"""Driving a Domain run with a Strategy attached.

The dependency direction is the point. Strategy calls Domain; Domain knows
nothing about Strategy and needs no change to be driven by it. A run without a
Strategy is still a complete Level 0 run -- `domain.run.run` is unchanged and
still emits no `exception/respond`.

What this adds to a fold: after Domain has verified and folded, if the deviation
still stands, Strategy responds and appends one addressed write to the same log.
The `prev` chain runs unbroken across both layers' writes, so the response is
part of the record rather than a side note about it.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD
from domain.model import DomainModel
from domain.emit import emit
from domain.run import (
    initial_state,
    step_with_writes,
    converged,
    snapshot,
    make_result,
)
from address.write import last_id
from strategy.respond import (
    respond_props,
    respond,
    exhausted,
    escalation,
    is_search,
    max_depth,
    has_progress_test,
    progress,
    progress_props,
    ineffective,
)
from strategy.search import search


comptime E_STRATEGY_RUN = "strategy_error"


fn respond_frame(response: Value, verdict: Value, result: Value) -> Value:
    """The frame a strategy's slots resolve against.

    `response` is what this layer produced; the rest is context, so a slot such
    as `verdict.finding` can be addressed as readily as `response.action`.
    """
    var d = Dict[String, Value]()
    d[String("response")] = response.copy()
    d[String("verdict")] = verdict.copy()
    d[String("result")] = result.copy()
    return Value.record(d^)


fn respond_write_props(
    state: Value,
    next: Value,
    result: Value,
    verdict: Value,
    response: Value,
    step: Int,
    futile: Bool,
) -> Value:
    """Props for a strategy's write policy.

    Domain's shape plus `response`, so a policy can gate on what the strategy
    actually decided -- which is how an escalation's `authority` write knows to
    fire and an ordinary retry's does not -- plus `ineffective`, which is how the
    detect/respond pair knows to fire.
    """
    var ev = Dict[String, Value]()
    ev[String("is_first")] = Value.bool(step == 0)
    ev[String("step")] = Value.int(step)

    var d = Dict[String, Value]()
    d[String("state")] = state.copy()
    d[String("next")] = next.copy()
    d[String("result")] = result.copy()
    d[String("output")] = verdict.copy()
    d[String("response")] = response.copy()
    d[String("ineffective")] = Value.bool(futile)
    d[String("event")] = Value.record(ev^)
    return Value.record(d^)


fn converge(
    model: DomainModel,
    strategy: Value,
    policy: Value,
    initial_result: Value,
) -> Value:
    """Let Strategy propose Results until Domain accepts one, or the boundary
    is crossed.

    This is the closed loop, and it is what makes rung 3 different in kind. In
    every earlier rung a Result came from outside and Strategy at most commented
    on it. Here Strategy searches from the current actual state, proposes the
    best candidate it found, and Domain verifies that proposal -- so the runtime
    can reach a contract on its own.

    The heuristic guides the search; it never decides the outcome. A proposal is
    still just a Result, and Domain still verifies it. A misleading heuristic
    costs attempts, not correctness.

    Returns the same shape as `run`, plus `proposals`.
    """
    if not model.is_valid():
        return model.error.copy()
    if strategy.is_error():
        return strategy.copy()
    if not is_search(strategy):
        return Value.error(
            String(E_STRATEGY_RUN),
            String("converge requires a strategy that declares operators and a goal"),
        )

    var state = initial_state(model)
    var result = initial_result.copy()
    var log = List[Value]()
    var classifications = List[Value]()
    var responses = List[Value]()
    var proposals = List[Value]()
    var prev = String("")
    var attempts = 0
    var gave_up = False
    var round = 0

    while True:
        if converged(state):
            break

        var folded = step_with_writes(model, policy, state, result, round, prev.copy())
        if folded.is_error():
            return folded^

        var writes = folded.get(String("writes"))
        for w in range(writes.len()):
            log.append(writes.at(w))
        var tail = last_id(writes)
        if len(tail) > 0:
            prev = tail^

        var next = folded.get(String("state"))
        classifications.append(
            next.get_or(String("classification"), Value.null())
        )
        state = next.copy()

        if converged(state):
            break

        # Search from the state that failed, for something closer to the goal.
        var verdict = next.get_or(String("verdict"), Value.null())
        var base = search_base(model, result, verdict, next)
        var found = search(
            strategy, base, result.get(String("actual")), max_depth(strategy)
        )
        if found.is_error():
            return found^

        var props = respond_props(
            model.contract, result, verdict, state, next
        )
        var with_search = _with(props, String("search"), found)

        # Nothing reachable within the bound, or too many rejected proposals:
        # either way this strategy is done and hands off.
        var over = not found.get(String("found")).truthy() or exhausted(
            strategy, attempts
        )
        var response: Value
        if over:
            response = escalation(strategy, with_search)
        else:
            response = respond(strategy, with_search)
        if response.is_error():
            return response^

        var frame = respond_frame(response, verdict, result)
        var wprops = respond_write_props(
            state, next, result, verdict, response, round, False
        )
        var rwrites = emit(
            strategy.get(String("writes")), model.name, wprops, frame, round, prev.copy()
        )
        if rwrites.is_error():
            return rwrites^
        if rwrites.len() > 0:
            for w in range(rwrites.len()):
                log.append(rwrites.at(w))
            var rtail = last_id(rwrites)
            if len(rtail) > 0:
                prev = rtail^
            responses.append(response.copy())
            attempts += 1

        if over:
            gave_up = True
            break

        # The proposal becomes the next Result. This is the loop closing.
        var proposed = response.get_or(String("proposes"), Value.null())
        if proposed.is_null() or proposed.is_error():
            gave_up = True
            break
        proposals.append(proposed.copy())
        result = make_result(proposed^, String("strategy"))
        round += 1

    var trace_value = Value.list(log^)
    var out = Dict[String, Value]()
    out[String("state")] = state.copy()
    out[String("trace")] = trace_value.copy()
    out[String("classifications")] = Value.list(classifications^)
    out[String("responses")] = Value.list(responses^)
    out[String("proposals")] = Value.list(proposals^)
    out[String("attempts")] = Value.int(attempts)
    out[String("exhausted")] = Value.bool(gave_up)
    out[String("converged")] = Value.bool(converged(state))
    if converged(state):
        out[String("snapshot")] = snapshot(model, state, trace_value)
    return Value.record(out^)


fn search_base(
    model: DomainModel, result: Value, verdict: Value, next: Value
) -> Value:
    """What a goal, heuristic, or operator effect may reference.

    `expected` is bound directly so a goal reads `ref: expected.count` rather
    than reaching through the contract -- the shape doc section 4.2 uses.
    """
    var d = Dict[String, Value]()
    d[String("expected")] = model.expected()
    d[String("contract")] = model.contract.copy()
    d[String("result")] = result.copy()
    d[String("verdict")] = verdict.copy()
    d[String("next")] = next.copy()
    return Value.record(d^)


fn _with(props: Value, var key: String, value: Value) -> Value:
    var d = Dict[String, Value]()
    if props.tag == RECORD:
        for k in props.fields[].keys():
            var kk = k.copy()
            d[kk] = props.fields[].get(kk).value()
    d[key^] = value.copy()
    return Value.record(d^)


fn run(
    model: DomainModel,
    strategy: Value,
    policy: Value,
    results: List[Value],
) -> Value:
    """Apply supplied Results, letting Strategy respond to each deviation.

    Returns `{state, trace, classifications, responses, converged, snapshot?}`.
    `trace` is one write log carrying both Domain's writes and Strategy's.
    """
    if not model.is_valid():
        return model.error.copy()
    if strategy.is_error():
        return strategy.copy()

    var state = initial_state(model)
    var log = List[Value]()
    var classifications = List[Value]()
    var responses = List[Value]()
    var prev = String("")
    var attempts = 0
    var gave_up = False
    var prev_verdict = Value.null()
    var prev_response = Value.null()
    var have_previous = False
    var stopped = String("results_consumed")

    for k in range(len(results)):
        if converged(state):
            break

        var folded = step_with_writes(model, policy, state, results[k], k, prev.copy())
        if folded.is_error():
            return folded^

        var writes = folded.get(String("writes"))
        for w in range(writes.len()):
            log.append(writes.at(w))
        var tail = last_id(writes)
        if len(tail) > 0:
            prev = tail^

        var next = folded.get(String("state"))
        classifications.append(
            next.get_or(String("classification"), Value.null())
        )

        # Strategy's turn. The write policy's `when` decides whether a response
        # is actually recorded, so the decision stays in the model rather than
        # in this loop.
        var verdict = next.get_or(String("verdict"), Value.null())
        var props = respond_props(
            model.contract, results[k], verdict, state, next
        )

        # Did the last response accomplish anything? Asked only once there has
        # been a response to judge, which is why nothing here reaches through a
        # null and why this needs no presence operator.
        var futile = False
        if has_progress_test(strategy) and have_previous and not converged(next):
            var moved = progress(
                strategy,
                progress_props(verdict, prev_verdict, prev_response),
            )
            # A broken predicate is a defect in the model. Reading it as "no
            # progress" would escalate for the wrong reason and hide the defect
            # behind plausible behaviour.
            if moved.is_error():
                return moved^
            futile = not moved.b

        # The boundary is consulted before the response, not after: once the
        # strategy has answered as many times as it is allowed to, it stops
        # choosing among candidates and escalates instead.
        var over_boundary = not converged(next) and exhausted(strategy, attempts)

        # Futility takes precedence. If both hold, "your response did not work"
        # is the more specific and more actionable conclusion, and escalating on
        # it immediately is what the boundary alone cannot express.
        var response: Value
        if futile:
            # An `ineffective` response sees the same environment every other
            # response form does -- `respond_props` -- so it can reach
            # `result.source` or `contract` exactly as a candidate beside it
            # could. It additionally gets `previous`, the verdict/response pair
            # this loop just judged progress against, since concluding
            # ineffectiveness is the one decision that reasons about the last
            # thing tried. The `previous` sub-record is sourced from
            # `progress_props` so its shape has a single definition.
            var prev_pair = progress_props(
                verdict, prev_verdict, prev_response
            ).get(String("previous"))
            response = ineffective(
                strategy, _with(props, String("previous"), prev_pair)
            )
        elif over_boundary:
            response = escalation(strategy, props)
        else:
            response = respond(strategy, props)
        if response.is_error():
            return response^

        var frame = respond_frame(response, verdict, results[k])
        var wprops = respond_write_props(
            state, next, results[k], verdict, response, k, futile
        )
        var rwrites = emit(
            strategy.get(String("writes")),
            model.name,
            wprops,
            frame,
            k,
            prev.copy(),
        )
        if rwrites.is_error():
            return rwrites^

        if rwrites.len() > 0:
            for w in range(rwrites.len()):
                log.append(rwrites.at(w))
            var rtail = last_id(rwrites)
            if len(rtail) > 0:
                prev = rtail^
            responses.append(response.copy())
            attempts += 1
            prev_verdict = verdict.copy()
            prev_response = response.copy()
            have_previous = True

        state = next^

        # Handing off ends this strategy's involvement. Continuing to verify
        # after escalating would be answering a question already given away.
        if futile:
            gave_up = True
            stopped = String("ineffective")
            break
        if over_boundary:
            gave_up = True
            stopped = String("exhausted")
            break

    if converged(state):
        stopped = String("converged")

    var trace_value = Value.list(log^)
    var out = Dict[String, Value]()
    out[String("state")] = state.copy()
    out[String("trace")] = trace_value.copy()
    out[String("classifications")] = Value.list(classifications^)
    out[String("responses")] = Value.list(responses^)
    out[String("attempts")] = Value.int(attempts)
    out[String("exhausted")] = Value.bool(gave_up)
    out[String("stopped")] = Value.symbol(stopped^)
    out[String("converged")] = Value.bool(converged(state))
    if converged(state):
        out[String("snapshot")] = snapshot(model, state, trace_value)
    return Value.record(out^)

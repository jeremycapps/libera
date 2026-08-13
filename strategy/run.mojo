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
)
from address.write import last_id
from strategy.respond import respond_props, respond


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
    state: Value, next: Value, result: Value, verdict: Value, step: Int
) -> Value:
    """Props for a strategy's write policy -- the same shape Domain's sees."""
    var ev = Dict[String, Value]()
    ev[String("is_first")] = Value.bool(step == 0)
    ev[String("step")] = Value.int(step)

    var d = Dict[String, Value]()
    d[String("state")] = state.copy()
    d[String("next")] = next.copy()
    d[String("result")] = result.copy()
    d[String("output")] = verdict.copy()
    d[String("event")] = Value.record(ev^)
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
        var response = respond(strategy, props)
        if response.is_error():
            return response^

        var frame = respond_frame(response, verdict, results[k])
        var wprops = respond_write_props(state, next, results[k], verdict, k)
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
            responses.append(response^)

        state = next^

    var trace_value = Value.list(log^)
    var out = Dict[String, Value]()
    out[String("state")] = state.copy()
    out[String("trace")] = trace_value.copy()
    out[String("classifications")] = Value.list(classifications^)
    out[String("responses")] = Value.list(responses^)
    out[String("converged")] = Value.bool(converged(state))
    if converged(state):
        out[String("snapshot")] = snapshot(model, state, trace_value)
    return Value.record(out^)

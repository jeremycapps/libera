"""Bounded search over composed operators.

This is the machinery rungs 1 and 2 did not need. Those chose among responses
that were written down; this generates states that nobody wrote down, by
applying operators to what exists and seeing what comes out.

Two operations, and the split matters:

  `expand`  apply every admissible operator once, score each result
  `search`  expand repeatedly to a bounded depth, stopping at the goal

`expand` is doc section 6's S0 and S1 together -- candidate generation and
heuristic choice -- and is testable without running a search at all. `search`
composes it.

The heuristic guides exploration; it does not decide truth. Whatever this
proposes, Domain still verifies. That separation is the reason a misleading
heuristic costs time rather than correctness.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, LIST
from kernel.eval import evaluate


comptime E_SEARCH = "search_error"


fn _merge_props(base: Value, var extra: Dict[String, Value]) -> Value:
    """`base` props plus bindings for this evaluation."""
    var d = extra^
    if base.tag == RECORD:
        for k in base.fields[].keys():
            var kk = k.copy()
            if kk not in d:
                d[kk] = base.fields[].get(kk).value()
    return Value.record(d^)


fn apply_operator(op: Value, base: Value, state: Value) -> Value:
    """The state that results from applying one operator, or null if its
    preconditions do not hold."""
    if op.is_error():
        return op.copy()

    var props = Dict[String, Value]()
    props[String("state")] = state.copy()
    var env = _merge_props(base, props^)

    if op.has(String("preconditions")):
        var ok = evaluate(op.get(String("preconditions")), env)
        if ok.is_error():
            return ok^
        if ok.tag != 1:  # BOOL
            return Value.error(
                String(E_SEARCH),
                String("preconditions must evaluate to a boolean, got ")
                + ok.to_string(),
            )
        if not ok.b:
            return Value.null()

    return evaluate(op.get(String("effect")), env)


fn expand(strategy: Value, base: Value, state: Value) -> Value:
    """Every candidate reachable in one step, scored.

    Returns a LIST of `{operator, state, score, satisfies}` in sorted operator
    order. Operators whose preconditions fail are absent rather than present
    with a null state -- an inapplicable operator produced no candidate.
    """
    if strategy.is_error():
        return strategy.copy()

    var operators = strategy.get_or(String("operators"), Value.null())
    if operators.tag != LIST:
        return Value.error(
            String(E_SEARCH), String("strategy declares no operators")
        )

    var goal = strategy.get_or(String("goal"), Value.null())
    var heuristic = strategy.get_or(String("heuristic"), Value.null())

    var out = List[Value]()
    for k in range(operators.len()):
        var op = operators.at(k)
        var next_state = apply_operator(op, base, state)
        if next_state.is_error():
            return next_state^
        if next_state.is_null():
            continue

        var cprops = Dict[String, Value]()
        cprops[String("candidate")] = next_state.copy()
        cprops[String("state")] = state.copy()
        var cenv = _merge_props(base, cprops^)

        var satisfies = Value.bool(False)
        if not goal.is_null():
            var g = evaluate(goal, cenv)
            if g.is_error():
                return g^
            satisfies = Value.bool(g.truthy())

        var score = Value.null()
        if not heuristic.is_null():
            score = evaluate(heuristic, cenv)
            if score.is_error():
                return score^

        var d = Dict[String, Value]()
        d[String("operator")] = op.get(String("id"))
        d[String("state")] = next_state^
        d[String("score")] = score^
        d[String("satisfies")] = satisfies^
        out.append(Value.record(d^))

    return Value.list(out^)


fn lowest_score(candidates: Value) -> Value:
    """The candidate with the lowest score, or null for an empty list.

    Ties go to the earlier candidate, which with sorted operator order makes the
    choice deterministic.
    """
    if candidates.tag != LIST or candidates.len() == 0:
        return Value.null()

    var best = candidates.at(0)
    for k in range(1, candidates.len()):
        var c = candidates.at(k)
        var cs = c.get(String("score"))
        var bs = best.get(String("score"))
        if cs.is_number() and bs.is_number() and cs.as_float() < bs.as_float():
            best = c^
    return best^


fn _result(
    found: Bool,
    best: Value,
    score: Value,
    var path: List[Value],
    explored: Int,
    depth: Int,
) -> Value:
    var d = Dict[String, Value]()
    d[String("found")] = Value.bool(found)
    d[String("best")] = best.copy()
    d[String("score")] = score.copy()
    d[String("path")] = Value.list(path^)
    d[String("explored")] = Value.int(explored)
    d[String("depth")] = Value.int(depth)
    return Value.record(d^)


fn search(strategy: Value, base: Value, start: Value, max_depth: Int) -> Value:
    """Expand to `max_depth`, stopping as soon as a candidate satisfies the goal.

    Returns `{found, best, score, path, explored, depth}`. `path` is the operator
    ids applied, so a proposal can say how it was reached and not merely what it
    is.

    Bounded rather than complete: nothing beyond `max_depth` is examined, so a
    solution deeper than the bound reports `found: false` rather than being
    searched for indefinitely. That is the boundary doing its job.
    """
    if strategy.is_error():
        return strategy.copy()

    # A frontier node is {state, path}.
    var frontier = List[Value]()
    var head = Dict[String, Value]()
    head[String("state")] = start.copy()
    head[String("path")] = Value.list(List[Value]())
    frontier.append(Value.record(head^))

    var explored = 0
    var best_overall = Value.null()
    var best_score = Value.null()
    var best_path = List[Value]()

    for depth in range(1, max_depth + 1):
        var next_frontier = List[Value]()

        for f in range(len(frontier)):
            var node = frontier[f]
            var node_state = node.get(String("state"))
            var node_path = node.get(String("path"))

            var candidates = expand(strategy, base, node_state)
            if candidates.is_error():
                return candidates^

            for c in range(candidates.len()):
                var cand = candidates.at(c)
                explored += 1

                var path = List[Value]()
                for p in range(node_path.len()):
                    path.append(node_path.at(p))
                path.append(cand.get(String("operator")))

                if cand.get(String("satisfies")).truthy():
                    return _result(
                        True,
                        cand.get(String("state")),
                        cand.get(String("score")),
                        path^,
                        explored,
                        depth,
                    )

                # Track the closest thing seen, so an exhausted search can still
                # report how near it got.
                var cs = cand.get(String("score"))
                if cs.is_number():
                    if not best_score.is_number() or cs.as_float() < best_score.as_float():
                        best_overall = cand.get(String("state"))
                        best_score = cs^
                        best_path = path.copy()

                var nn = Dict[String, Value]()
                nn[String("state")] = cand.get(String("state"))
                nn[String("path")] = Value.list(path^)
                next_frontier.append(Value.record(nn^))

        frontier = next_frontier^

    return _result(
        False, best_overall, best_score, best_path^, explored, max_depth
    )

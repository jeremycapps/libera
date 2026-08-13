"""Strategy: deciding what to do about a deviation.

Domain decides whether a Result conforms. Strategy decides what to do when it
does not. That is the whole division, and it is why this layer -- not Domain --
owns `exception/respond`.

Two forms are supported, and they are rungs of the same ladder:

  rung 1  `expressions.respond`     one response, always the same
  rung 2  `expressions.candidates`  several, the first whose `when` holds
          `boundary.max_attempts`   how many answers before giving up
          `expressions.exhausted`   the response on crossing that boundary

Neither searches. Ranking candidates by estimated proximity to a goal, and
composing operators into multi-step paths, are a further rung and are not built.

Strategy sits above Domain: it may name Contract, Result, and Verdict. Domain
may not name Strategy, and the layering test enforces that direction.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, LIST, BOOL, INT
from kernel.eval import evaluate
from modelir.yaml import parse_yaml_file
from modelir.compile import compile_expression


comptime E_STRATEGY = "strategy_error"


fn load_strategy(path: String) raises -> Value:
    """Load a strategy document into compiled IR.

    Returns `{respond?, candidates?, exhausted?, writes, max_attempts}`. A
    strategy declares no contract -- it does not verify anything -- so it does
    not load through `DomainModel`.
    """
    var root = parse_yaml_file(path)
    if root.is_error():
        return root^
    if root.tag != RECORD or not root.has(String("expressions")):
        return Value.error(
            String(E_STRATEGY), String("strategy document has no 'expressions'")
        )

    var exprs = root.get(String("expressions"))
    var d = Dict[String, Value]()

    var has_respond = exprs.has(String("respond"))
    var has_candidates = exprs.has(String("candidates"))
    if not has_respond and not has_candidates:
        return Value.error(
            String(E_STRATEGY),
            String(
                "strategy declares neither 'expressions.respond' nor"
                " 'expressions.candidates'"
            ),
        )
    if has_respond and has_candidates:
        # Two ways to pick a response is two sources of truth for the same
        # decision. Refuse rather than silently preferring one.
        return Value.error(
            String(E_STRATEGY),
            String(
                "strategy declares both 'respond' and 'candidates'; it must"
                " declare exactly one"
            ),
        )

    if has_respond:
        var ir = compile_expression(exprs.get(String("respond")))
        if ir.is_error():
            return ir^
        d[String("respond")] = ir^
    else:
        var ir = compile_expression(exprs.get(String("candidates")))
        if ir.is_error():
            return ir^
        d[String("candidates")] = ir^

    if not exprs.has(String("writes")):
        return Value.error(
            String(E_STRATEGY),
            String("strategy document has no 'expressions.writes'"),
        )
    var writes_ir = compile_expression(exprs.get(String("writes")))
    if writes_ir.is_error():
        return writes_ir^
    d[String("writes")] = writes_ir^

    if exprs.has(String("exhausted")):
        var ir = compile_expression(exprs.get(String("exhausted")))
        if ir.is_error():
            return ir^
        d[String("exhausted")] = ir^

    # Search machinery (rung 3). Absent for strategies that only respond.
    if root.has(String("goal")):
        var goal = root.get(String("goal"))
        if not goal.has(String("satisfy")):
            return Value.error(
                String(E_STRATEGY), String("goal must declare 'satisfy'")
            )
        var ir = compile_expression(goal.get(String("satisfy")))
        if ir.is_error():
            return ir^
        d[String("goal")] = ir^

    if root.has(String("operators")):
        var ops = root.get(String("operators"))
        if ops.tag != RECORD:
            return Value.error(
                String(E_STRATEGY),
                String("operators must be a mapping of id to operator, got ")
                + ops.to_string(),
            )
        # Sorted so candidate generation is reproducible: a mapping has no
        # inherent order, and a search whose results depend on hash iteration
        # is not a search anyone can rely on.
        var ids = List[String]()
        for key in ops.fields[].keys():
            ids.append(key.copy())
        for a in range(1, len(ids)):
            var cur = ids[a].copy()
            var b = a - 1
            while b >= 0 and ids[b] > cur:
                ids[b + 1] = ids[b].copy()
                b -= 1
            ids[b + 1] = cur^

        var built = List[Value]()
        for a in range(len(ids)):
            var id = ids[a].copy()
            var op = ops.fields[].get(id).value()
            if not op.has(String("effect")):
                return Value.error(
                    String(E_STRATEGY),
                    String("operator '") + id + String("' declares no effect"),
                )
            var od = Dict[String, Value]()
            od[String("id")] = Value.symbol(id.copy())
            var eff = compile_expression(op.get(String("effect")))
            if eff.is_error():
                return eff^
            od[String("effect")] = eff^
            if op.has(String("preconditions")):
                var pre = compile_expression(op.get(String("preconditions")))
                if pre.is_error():
                    return pre^
                od[String("preconditions")] = pre^
            built.append(Value.record(od^))
        d[String("operators")] = Value.list(built^)

    if exprs.has(String("heuristic")):
        var ir = compile_expression(exprs.get(String("heuristic")))
        if ir.is_error():
            return ir^
        d[String("heuristic")] = ir^

    # The boundary is data, not an expression: counts and depths, not judgments.
    var limit = Value.null()
    var depth = Value.null()
    if root.has(String("boundary")):
        var boundary = root.get(String("boundary"))
        if boundary.tag != RECORD:
            return Value.error(
                String(E_STRATEGY),
                String("boundary must be a mapping, got ")
                + boundary.to_string(),
            )
        if boundary.has(String("max_attempts")):
            limit = boundary.get(String("max_attempts"))
            if limit.tag != INT:
                return Value.error(
                    String(E_STRATEGY),
                    String("boundary.max_attempts must be an integer, got ")
                    + limit.to_string(),
                )
        if boundary.has(String("max_depth")):
            depth = boundary.get(String("max_depth"))
            if depth.tag != INT:
                return Value.error(
                    String(E_STRATEGY),
                    String("boundary.max_depth must be an integer, got ")
                    + depth.to_string(),
                )
    d[String("max_attempts")] = limit^
    d[String("max_depth")] = depth^

    # Operators with nothing to aim at, or a goal with nothing to reach it,
    # are each half a search.
    var has_ops = d.__contains__(String("operators"))
    var has_goal = d.__contains__(String("goal"))
    if has_ops != has_goal:
        return Value.error(
            String(E_STRATEGY),
            String(
                "a search needs both 'operators' and 'goal'; this declares"
                " only one"
            ),
        )
    if has_ops and d[String("max_depth")].tag != INT:
        return Value.error(
            String(E_STRATEGY),
            String(
                "a search needs 'boundary.max_depth': without a bound it may"
                " never stop"
            ),
        )

    # A boundary that can be crossed with nothing to do about it is a trap.
    var has_limit = d[String("max_attempts")].tag == INT
    if has_limit and not d.__contains__(String("exhausted")):
        return Value.error(
            String(E_STRATEGY),
            String(
                "boundary.max_attempts is declared but 'expressions.exhausted'"
                " is not: crossing the boundary would have no response"
            ),
        )

    return Value.record(d^)


fn respond_props(
    contract: Value,
    result: Value,
    verdict: Value,
    state: Value,
    next: Value,
) -> Value:
    """What a response expression may reference.

    Deliberately the same shape a verifier sees, plus the folded state: a
    response is a judgment about the same material, made after the verdict
    rather than instead of it.
    """
    var d = Dict[String, Value]()
    d[String("contract")] = contract.copy()
    d[String("result")] = result.copy()
    d[String("verdict")] = verdict.copy()
    d[String("state")] = state.copy()
    d[String("next")] = next.copy()
    return Value.record(d^)


fn is_search(strategy: Value) -> Bool:
    """Whether this strategy generates candidates rather than choosing among
    written-down responses."""
    if strategy.is_error():
        return False
    return strategy.has(String("operators")) and strategy.has(String("goal"))


fn max_depth(strategy: Value) -> Int:
    """The search depth bound. Zero when this strategy does not search."""
    if not is_search(strategy):
        return 0
    return strategy.get(String("max_depth")).i


fn has_boundary(strategy: Value) -> Bool:
    """Whether this strategy can stop itself."""
    if strategy.is_error():
        return False
    return strategy.get_or(String("max_attempts"), Value.null()).tag == INT


fn exhausted(strategy: Value, attempts: Int) -> Bool:
    """Whether the strategy has answered as many times as it is allowed to.

    A strategy with no boundary is never exhausted -- it will answer forever,
    which is the rung 1 behaviour and is why rung 2 exists.
    """
    if not has_boundary(strategy):
        return False
    return attempts >= strategy.get(String("max_attempts")).i


fn respond(strategy: Value, props: Value) -> Value:
    """The response to this deviation, before any boundary is considered.

    For a single-response strategy this evaluates the one expression. For a
    candidate list it takes the first whose `when` holds -- selection over
    declared conditions, not a search.
    """
    if strategy.is_error():
        return strategy.copy()

    if strategy.has(String("respond")):
        return evaluate(strategy.get(String("respond")), props)

    var candidates = evaluate(strategy.get(String("candidates")), props)
    if candidates.is_error():
        return candidates^
    if candidates.tag != LIST:
        return Value.error(
            String(E_STRATEGY),
            String("candidates must evaluate to a list, got ")
            + candidates.to_string(),
        )

    for k in range(candidates.len()):
        var c = candidates.at(k)
        if c.tag != RECORD:
            return Value.error(
                String(E_STRATEGY),
                String("each candidate must be a record, got ") + c.to_string(),
            )
        var when = c.get_or(String("when"), Value.bool(True))
        if when.is_error():
            return when^
        if when.tag != BOOL:
            return Value.error(
                String(E_STRATEGY),
                String("a candidate's 'when' must be a boolean, got ")
                + when.to_string(),
            )
        if when.b:
            return c^

    # Falling off the end means a deviation arrived that nothing answers. That
    # is a gap in the model, not a reason to do nothing quietly.
    return Value.error(
        String(E_STRATEGY),
        String("no candidate response applies; the last should be unconditional"),
    )


fn escalation(strategy: Value, props: Value) -> Value:
    """The response for crossing the boundary."""
    if strategy.is_error():
        return strategy.copy()
    if not strategy.has(String("exhausted")):
        return Value.error(
            String(E_STRATEGY),
            String("strategy has no 'exhausted' response"),
        )
    return evaluate(strategy.get(String("exhausted")), props)

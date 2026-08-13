"""Strategy: deciding what to do about a deviation.

Domain decides whether a Result conforms. Strategy decides what to do when it
does not. That is the whole division, and it is why this layer -- not Domain --
owns `exception/respond`.

This module holds the smallest form of that decision: evaluate one declared
expression and get back a Response. There are no candidates to rank and nothing
to search, because a fixed response has one option. The machinery for choosing
among several belongs to a later rung and is not built.

Strategy sits above Domain: it may name Contract, Result, and Verdict. Domain
may not name Strategy, and the layering test enforces that direction.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD
from kernel.eval import evaluate
from modelir.yaml import parse_yaml_file
from modelir.compile import compile_expression


comptime E_STRATEGY = "strategy_error"


fn load_strategy(path: String) raises -> Value:
    """Load a strategy document into `{respond, writes}` of compiled IR.

    A strategy declares no contract -- it does not verify anything -- so it does
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
    if not exprs.has(String("respond")):
        return Value.error(
            String(E_STRATEGY),
            String("strategy document has no 'expressions.respond'"),
        )
    if not exprs.has(String("writes")):
        return Value.error(
            String(E_STRATEGY),
            String("strategy document has no 'expressions.writes'"),
        )

    var respond_ir = compile_expression(exprs.get(String("respond")))
    if respond_ir.is_error():
        return respond_ir^
    var writes_ir = compile_expression(exprs.get(String("writes")))
    if writes_ir.is_error():
        return writes_ir^

    var d = Dict[String, Value]()
    d[String("respond")] = respond_ir^
    d[String("writes")] = writes_ir^
    return Value.record(d^)


fn respond_props(
    contract: Value,
    result: Value,
    verdict: Value,
    state: Value,
    next: Value,
) -> Value:
    """What a `respond` expression may reference.

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


fn respond(strategy: Value, props: Value) -> Value:
    """Evaluate the declared response. Returns a Response record, or an Error."""
    if strategy.is_error():
        return strategy.copy()
    var expr = strategy.get(String("respond"))
    if expr.is_error():
        return expr^
    return evaluate(expr, props)

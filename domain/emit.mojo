"""Evaluate a write policy and emit addressed Writes.

This is the seam between Domain and the address layer. It binds Domain props
(`output`, `verdict`) and so must live here rather than in `address/` -- the address
layer may not name Domain vocabulary.

The runtime decides nothing semantic. It evaluates a declared expression, drops
candidates whose declared `when` is false, and resolves each slot against a frame.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, LIST, SYMBOL, STRING
from kernel.eval import evaluate, resolve
from modelir.yaml import parse_yaml_file
from modelir.compile import compile_expression
from address.grammar import address
from address.write import write


comptime E_EMIT = "emit_error"


fn load_policy(path: String) raises -> Value:
    """Load and compile `expressions.writes` from a policy document.

    Policy documents have no `contract:`, so they do not go through `DomainModel`.
    """
    var root = parse_yaml_file(path)
    if root.is_error():
        return root^
    if root.tag != RECORD or not root.has(String("expressions")):
        return Value.error(
            String(E_EMIT), String("policy document has no 'expressions'")
        )
    var exprs = root.get(String("expressions"))
    if not exprs.has(String("writes")):
        return Value.error(
            String(E_EMIT), String("policy document has no 'expressions.writes'")
        )
    return compile_expression(exprs.get(String("writes")))


fn policy_props(
    state: Value,
    next: Value,
    result: Value,
    output: Value,
    is_first: Bool,
    step: Int,
) -> Value:
    """The environment a write policy may reference."""
    var ev = Dict[String, Value]()
    ev[String("is_first")] = Value.bool(is_first)
    ev[String("step")] = Value.int(step)

    var d = Dict[String, Value]()
    d[String("state")] = state.copy()
    d[String("next")] = next.copy()
    d[String("result")] = result.copy()
    d[String("output")] = output.copy()
    d[String("event")] = Value.record(ev^)
    return Value.record(d^)


fn slot_frame(
    contract: Value,
    result: Value,
    verdict: Value,
    state: Value,
    next: Value,
    snapshot: Value,
) -> Value:
    """The environment a slot resolves against to obtain its value."""
    var d = Dict[String, Value]()
    d[String("contract")] = contract.copy()
    d[String("result")] = result.copy()
    d[String("verdict")] = verdict.copy()
    d[String("state")] = state.copy()
    d[String("next")] = next.copy()
    d[String("snapshot")] = snapshot.copy()
    return Value.record(d^)


fn emit(
    policy: Value,
    program: String,
    props: Value,
    frame: Value,
    step: Int,
    var prev: String,
) -> Value:
    """Evaluate the policy and return a LIST Value of Writes, or an Error."""
    var candidates = evaluate(policy, props)
    if candidates.is_error():
        return candidates^
    if candidates.tag != LIST:
        return Value.error(
            String(E_EMIT),
            String("write policy must return a list, got ")
            + candidates.to_string(),
        )

    var out = List[Value]()
    var last = prev^

    for k in range(candidates.len()):
        var c = candidates.at(k)
        if c.tag != RECORD:
            return Value.error(
                String(E_EMIT),
                String("write candidate must be a record, got ") + c.to_string(),
            )

        var when = c.get_or(String("when"), Value.bool(True))
        if when.is_error():
            return when^
        if not when.truthy():
            continue

        var pressure = c.get(String("pressure"))
        if pressure.is_error():
            return pressure^
        var operation = c.get(String("operation"))
        if operation.is_error():
            return operation^
        var slot = c.get(String("slot"))
        if slot.is_error():
            return slot^

        if not pressure.is_text() or not operation.is_text() or not slot.is_text():
            return Value.error(
                String(E_EMIT),
                String("pressure, operation and slot must be names, got ")
                + c.to_string(),
            )

        var addr = address(
            program.copy(),
            pressure.s.copy(),
            operation.s.copy(),
            slot.s.copy(),
        )
        if addr.is_error():
            return addr^

        # A slot that does not resolve is a policy error, not a silent null.
        var value = resolve(addr.get(String("slot")), frame)
        if value.is_error():
            return value^

        var w = write(addr, value, step, last.copy())
        if w.is_error():
            return w^
        last = w.get(String("id")).s.copy()
        out.append(w^)

    return Value.list(out^)


fn derive_classification(writes: Value) -> Value:
    """Classification follows from the pressures emitted, not from a hand-written
    expression: any exception pressure makes the fold an exception."""
    if writes.tag != LIST:
        return Value.symbol(String("confirmed"))
    for k in range(writes.len()):
        var p = writes.at(k).get(String("address")).get(String("pressure"))
        if p.is_text() and p.s == "exception":
            return Value.symbol(String("exception"))
    return Value.symbol(String("confirmed"))

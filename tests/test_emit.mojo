"""Tests for write policy evaluation.

These build the props and frame directly rather than running a full Domain cycle, so a
failure here points at emission rather than at orchestration.
"""

from std.collections import List, Dict

from kernel.value import Value, LIST, RECORD, SYMBOL
from kernel.ir import kv, rec, sym, r, lst
from domain.emit import (
    load_policy,
    policy_props,
    slot_frame,
    emit,
    derive_classification,
    E_EMIT,
)
from address.grammar import render
from address.write import chain_is_intact
from testkit.harness import TestSuite


comptime POLICY_PATH = "models/writes-default.yaml"


fn _contract() -> Value:
    return rec(kv(String("expected"), rec(kv(String("count"), Value.int(3)))))


fn _result(n: Int) -> Value:
    return rec(kv(String("actual"), rec(kv(String("count"), Value.int(n)))))


fn _verdict(conforms: Bool) -> Value:
    return rec(
        kv(String("conforms"), Value.bool(conforms)),
        kv(String("expected"), Value.int(3)),
        kv(String("actual"), Value.int(2)),
    )


fn _state(converged: Bool) -> Value:
    return rec(
        kv(String("contract"), _contract()),
        kv(String("converged"), Value.bool(converged)),
    )


fn run(mut t: TestSuite) raises:
    var policy = load_policy(String(POLICY_PATH))
    _loading(t, policy)
    _trace_a(t, policy)
    _trace_b(t, policy)
    _classification(t)
    _failures(t, policy)
    _non_boolean_when(t)
    _duplicate_ids(t)


fn _loading(mut t: TestSuite, policy: Value):
    t.section(String("emit / policy loading"))
    t.not_error(String("default policy loads"), policy)


fn _trace_a(mut t: TestSuite, policy: Value):
    t.section(String("emit / trace A -- first fold, non-conforming"))

    var result = _result(2)
    var verdict = _verdict(False)
    var next = _state(False)
    var props = policy_props(_state(False), next, result, verdict, True, 0)
    var frame = slot_frame(
        _contract(), result, verdict, _state(False), next, Value.null()
    )
    var writes = emit(policy, String("prog"), props, frame, 0, String(""))

    t.not_error(String("emission succeeds"), writes)
    t.eq_int(String("three writes on the first fold"), writes.len(), 3)

    t.eq_str(
        String("contract enters scope"),
        render(writes.at(0).get(String("address"))),
        String("boundary/enter/contract.expected"),
    )
    t.eq_str(
        String("result changes state"),
        render(writes.at(1).get(String("address"))),
        String("movement/change/result.actual"),
    )
    t.eq_str(
        String("deviation is detected"),
        render(writes.at(2).get(String("address"))),
        String("exception/detect/verdict.conforms"),
    )

    # Values are resolved from the frame, not declared in the policy.
    t.eq_value(
        String("enter carries the expected count"),
        writes.at(0).get(String("value")),
        rec(kv(String("count"), Value.int(3))),
    )
    t.eq_value(
        String("change carries the actual count"),
        writes.at(1).get(String("value")),
        rec(kv(String("count"), Value.int(2))),
    )
    t.eq_value(
        String("detect carries the conformance"),
        writes.at(2).get(String("value")),
        Value.bool(False),
    )

    t.check(
        String("the emitted chain is intact"),
        chain_is_intact(writes, String("")),
        String("chain broken: ") + writes.to_string(),
    )
    # An address renders as a record, so `to_string()` never contains the slash form.
    # Match on the bare operation symbol instead.
    t.check(
        String("no snapshot write before convergence"),
        writes.to_string().find("exit") == -1,
        String("exit emitted early"),
    )


fn _trace_b(mut t: TestSuite, policy: Value):
    t.section(String("emit / trace B -- later fold, conforming"))

    var result = _result(3)
    var verdict = _verdict(True)
    var next = _state(True)
    var snapshot = rec(kv(String("final_verdict"), verdict))
    var props = policy_props(_state(False), next, result, verdict, False, 1)
    var frame = slot_frame(
        _contract(), result, verdict, _state(False), next, snapshot
    )
    var writes = emit(
        policy, String("prog"), props, frame, 1, String("path.earlier#0")
    )

    t.not_error(String("emission succeeds"), writes)
    # Not the first fold, so no enter; converged, so an exit. Candidates 2, 3 and 4
    # all fire.
    t.eq_int(String("three writes on a converging fold"), writes.len(), 3)
    t.eq_str(
        String("result changes state"),
        render(writes.at(0).get(String("address"))),
        String("movement/change/result.actual"),
    )
    t.eq_str(
        String("conformance advances"),
        render(writes.at(1).get(String("address"))),
        String("movement/advance/verdict.conforms"),
    )
    t.eq_str(
        String("work leaves scope"),
        render(writes.at(2).get(String("address"))),
        String("boundary/exit/snapshot"),
    )
    t.eq_value(
        String("advance carries a true conformance"),
        writes.at(1).get(String("value")),
        Value.bool(True),
    )

    t.check(
        String("continuation chain is intact"),
        chain_is_intact(writes, String("path.earlier#0")),
        String("chain broken: ") + writes.to_string(),
    )
    t.check(
        String("step is carried onto each write"),
        writes.at(0).get(String("step")).equals(Value.int(1)),
        String("wrong step"),
    )


fn _classification(mut t: TestSuite):
    t.section(String("emit / classification is derived"))

    var exceptional = List[Value]()
    exceptional.append(
        rec(
            kv(
                String("address"),
                rec(kv(String("pressure"), sym(String("exception")))),
            )
        )
    )
    t.eq_value(
        String("an exception pressure yields exception"),
        derive_classification(Value.list(exceptional^)),
        sym(String("exception")),
    )

    var clean = List[Value]()
    clean.append(
        rec(
            kv(
                String("address"),
                rec(kv(String("pressure"), sym(String("movement")))),
            )
        )
    )
    clean.append(
        rec(
            kv(
                String("address"),
                rec(kv(String("pressure"), sym(String("boundary")))),
            )
        )
    )
    t.eq_value(
        String("no exception pressure yields confirmed"),
        derive_classification(Value.list(clean^)),
        sym(String("confirmed")),
    )
    t.eq_value(
        String("an empty log is confirmed"),
        derive_classification(Value.list(List[Value]())),
        sym(String("confirmed")),
    )


fn _failures(mut t: TestSuite, policy: Value):
    t.section(String("emit / failures"))

    # A slot that does not resolve is a policy error, caught at emission. This is
    # what makes a slot a Ref rather than a decorative string.
    var props = policy_props(
        _state(False), _state(False), _result(2), _verdict(False), True, 0
    )
    var bare = slot_frame(
        Value.empty_record(),
        _result(2),
        _verdict(False),
        _state(False),
        _state(False),
        Value.null(),
    )
    t.is_error(
        String("an unresolvable slot fails emission"),
        emit(policy, String("prog"), props, bare, 0, String("")),
        String("unresolved_ref"),
    )

    t.is_error(
        String("a policy returning a non-list is rejected"),
        emit(_not_a_policy(), String("prog"), props, bare, 0, String("")),
        String(E_EMIT),
    )


fn _not_a_policy() -> Value:
    """A 'policy' that evaluates to a scalar rather than a list of candidates."""
    return Value.int(1)


fn _non_boolean_when(mut t: TestSuite):
    t.section(String("emit / a non-boolean when is a type error"))

    # `when: "true"` looks like it should pass, but the kernel never coerces
    # strings to booleans -- a malformed condition must surface as an error,
    # not silently take (or drop) the branch.
    var policy = lst(
        rec(
            kv(String("when"), Value.string(String("true"))),
            kv(String("pressure"), sym(String("movement"))),
            kv(String("operation"), sym(String("change"))),
            kv(String("slot"), r(String("result.actual"))),
        )
    )
    var props = policy_props(
        _state(False), _state(False), _result(2), _verdict(False), True, 0
    )
    var frame = slot_frame(
        _contract(), _result(2), _verdict(False), _state(False), _state(False),
        Value.null(),
    )
    t.is_error(
        String("a string 'when' is rejected rather than dropped"),
        emit(policy, String("prog"), props, frame, 0, String("")),
        String(E_EMIT),
    )


fn _duplicate_ids(mut t: TestSuite):
    t.section(String("emit / duplicate write ids are rejected"))

    # Two candidates with the same slot and operation produce the same
    # write id within one fold -- the address grammar does not distinguish
    # them, so `emit` must catch it rather than let the trace go ambiguous.
    var candidate = rec(
        kv(String("when"), Value.bool(True)),
        kv(String("pressure"), sym(String("movement"))),
        kv(String("operation"), sym(String("change"))),
        kv(String("slot"), sym(String("result.actual"))),
    )
    var policy = lst(candidate, candidate)
    var props = policy_props(
        _state(False), _state(False), _result(2), _verdict(False), True, 0
    )
    var frame = slot_frame(
        _contract(), _result(2), _verdict(False), _state(False), _state(False),
        Value.null(),
    )
    t.is_error(
        String("a repeated slot/operation pair yields a duplicate id error"),
        emit(policy, String("prog"), props, frame, 0, String("")),
        String(E_EMIT),
    )

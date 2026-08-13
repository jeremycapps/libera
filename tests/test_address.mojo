"""Tests for the Libera address grammar.

Nothing here may mention Contract, Verdict, or conformance -- the address layer
knows where a write landed, never what it meant.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, REF, SYMBOL
from address.grammar import (
    is_pressure,
    is_operation,
    valid_pair,
    default_id,
    address,
    render,
    parse,
    E_ADDRESS,
)
from testkit.harness import TestSuite


fn run(mut t: TestSuite):
    _vocabulary(t)
    _pairing(t)
    _construction(t)
    _render_parse(t)
    _failures(t)


fn _vocabulary(mut t: TestSuite):
    t.section(String("address / vocabulary"))
    t.check(String("boundary is a pressure"), is_pressure(String("boundary")), String("x"))
    t.check(String("movement is a pressure"), is_pressure(String("movement")), String("x"))
    t.check(String("exception is a pressure"), is_pressure(String("exception")), String("x"))
    t.check(
        String("motion is not a pressure"),
        not is_pressure(String("motion")),
        String("only three pressures exist"),
    )
    var ops = List[String]()
    ops.append(String("enter"))
    ops.append(String("exit"))
    ops.append(String("advance"))
    ops.append(String("change"))
    ops.append(String("detect"))
    ops.append(String("respond"))
    for k in range(len(ops)):
        t.check(
            String("operation ") + ops[k],
            is_operation(ops[k]),
            String("expected an operation"),
        )
    t.check(
        String("escalate is not an operation"),
        not is_operation(String("escalate")),
        String("escalation is a species of respond, not its own operation"),
    )


fn _pairing(mut t: TestSuite):
    t.section(String("address / pressure-operation pairing"))
    t.check(String("boundary/enter"), valid_pair(String("boundary"), String("enter")), String("x"))
    t.check(String("boundary/exit"), valid_pair(String("boundary"), String("exit")), String("x"))
    t.check(String("movement/advance"), valid_pair(String("movement"), String("advance")), String("x"))
    t.check(String("movement/change"), valid_pair(String("movement"), String("change")), String("x"))
    t.check(String("exception/detect"), valid_pair(String("exception"), String("detect")), String("x"))
    t.check(String("exception/respond"), valid_pair(String("exception"), String("respond")), String("x"))

    # Operations belong to exactly one pressure.
    t.check(
        String("boundary/advance is invalid"),
        not valid_pair(String("boundary"), String("advance")),
        String("advance belongs to movement"),
    )
    t.check(
        String("movement/detect is invalid"),
        not valid_pair(String("movement"), String("detect")),
        String("detect belongs to exception"),
    )
    t.check(
        String("exception/enter is invalid"),
        not valid_pair(String("exception"), String("enter")),
        String("enter belongs to boundary"),
    )


fn _construction(mut t: TestSuite):
    t.section(String("address / construction"))
    var a = address(
        String("domain-count-level-0"),
        String("exception"),
        String("detect"),
        String("verdict.conforms"),
    )
    t.not_error(String("valid address builds"), a)
    t.eq_str(
        String("program is carried"),
        a.get(String("program")).s,
        String("domain-count-level-0"),
    )
    t.eq_value(
        String("pressure is a symbol"),
        a.get(String("pressure")),
        Value.symbol(String("exception")),
    )
    t.eq_value(
        String("operation is a symbol"),
        a.get(String("operation")),
        Value.symbol(String("detect")),
    )

    # The slot is a kernel Ref, not a string. This is the whole convergence.
    t.check(
        String("slot is a REF value"),
        a.get(String("slot")).tag == REF,
        String("got ") + a.get(String("slot")).to_string(),
    )
    t.eq_value(
        String("slot ref path"),
        a.get(String("slot")),
        Value.ref(String("verdict.conforms")),
    )

    t.eq_str(
        String("id is derived from slot and operation"),
        a.get(String("id")).s,
        String("path.verdict_conforms_detect"),
    )
    t.eq_str(
        String("default_id flattens dots"),
        default_id(String("contract.expected"), String("enter")),
        String("path.contract_expected_enter"),
    )
    t.eq_str(
        String("default_id on a single segment"),
        default_id(String("snapshot"), String("exit")),
        String("path.snapshot_exit"),
    )


fn _render_parse(mut t: TestSuite):
    t.section(String("address / render and parse"))
    var a = address(
        String("p"), String("movement"), String("change"), String("result.actual")
    )
    t.eq_str(
        String("renders as pressure/operation/slot"),
        render(a),
        String("movement/change/result.actual"),
    )

    var back = parse(String("movement/change/result.actual"), String("p"))
    t.not_error(String("parses a rendered address"), back)
    t.eq_value(String("round-trip is lossless"), back, a)

    t.eq_str(
        String("round-trip renders identically"),
        render(parse(render(a), String("p"))),
        render(a),
    )


fn _failures(mut t: TestSuite):
    t.section(String("address / failures are Values"))
    t.is_error(
        String("unknown pressure"),
        address(String("p"), String("motion"), String("change"), String("a.b")),
        String(E_ADDRESS),
    )
    t.is_error(
        String("unknown operation"),
        address(String("p"), String("movement"), String("escalate"), String("a.b")),
        String(E_ADDRESS),
    )
    t.is_error(
        String("mismatched pair"),
        address(String("p"), String("boundary"), String("detect"), String("a.b")),
        String(E_ADDRESS),
    )
    # `program` is required by the v2 schema; the finding's 3-part grammar dropped it.
    t.is_error(
        String("missing program"),
        address(String(""), String("movement"), String("change"), String("a.b")),
        String(E_ADDRESS),
    )
    t.is_error(
        String("missing slot"),
        address(String("p"), String("movement"), String("change"), String("")),
        String(E_ADDRESS),
    )
    t.is_error(
        String("parse rejects a two-part path"),
        parse(String("movement/change"), String("p")),
        String(E_ADDRESS),
    )
    t.is_error(
        String("parse rejects a four-part path"),
        parse(String("a/b/c/d"), String("p")),
        String(E_ADDRESS),
    )

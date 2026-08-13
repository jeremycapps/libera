"""Tests for Write records and the prev chain.

The chain is what upgrades a positional trace into a replayable log. It is Timpos's
Moment minus the timestamp -- structure without observation.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, STRING
from address.grammar import address
from address.write import write, last_id, chain_is_intact, E_WRITE
from testkit.harness import TestSuite


fn _addr(var slot: String, var op: String, var pressure: String) -> Value:
    return address(String("prog"), pressure^, op^, slot^)


fn run(mut t: TestSuite):
    _construction(t)
    _chaining(t)
    _integrity(t)


fn _construction(mut t: TestSuite):
    t.section(String("write / construction"))
    var a = _addr(String("result.actual"), String("change"), String("movement"))
    var w = write(a, Value.int(2), 0, String(""))

    t.not_error(String("write builds"), w)
    t.eq_value(String("carries its value"), w.get(String("value")), Value.int(2))
    t.eq_value(String("carries its step"), w.get(String("step")), Value.int(0))
    t.eq_value(String("address is nested"), w.get(String("address")), a)
    t.eq_value(
        String("head write has a null prev"), w.get(String("prev")), Value.null()
    )

    # The write id is address identity plus step -- identified, not merely positional.
    t.eq_str(
        String("write id combines address and step"),
        w.get(String("id")).s,
        String("path.result_actual_change#0"),
    )
    var w1 = write(a, Value.int(3), 1, String("path.result_actual_change#0"))
    t.eq_str(
        String("same address at a later step differs"),
        w1.get(String("id")).s,
        String("path.result_actual_change#1"),
    )

    # An Error address propagates rather than producing a malformed write.
    t.is_error(
        String("bad address propagates"),
        write(
            address(String("prog"), String("boundary"), String("detect"), String("a")),
            Value.int(1),
            0,
            String(""),
        ),
        String("address_error"),
    )


fn _chaining(mut t: TestSuite):
    t.section(String("write / chaining"))
    var a = _addr(String("result.actual"), String("change"), String("movement"))
    var b = _addr(String("verdict.conforms"), String("detect"), String("exception"))

    var w0 = write(a, Value.int(2), 0, String(""))
    var w1 = write(b, Value.bool(False), 0, w0.get(String("id")).s.copy())

    t.eq_str(
        String("second write points at the first"),
        w1.get(String("prev")).s,
        String("path.result_actual_change#0"),
    )

    var items = List[Value]()
    items.append(w0)
    items.append(w1)
    var log = Value.list(items^)

    t.eq_str(
        String("last_id returns the tail"),
        last_id(log),
        String("path.verdict_conforms_detect#0"),
    )
    t.eq_str(
        String("last_id of an empty log is empty"),
        last_id(Value.list(List[Value]())),
        String(""),
    )


fn _integrity(mut t: TestSuite):
    t.section(String("write / chain integrity"))
    var a = _addr(String("result.actual"), String("change"), String("movement"))
    var b = _addr(String("verdict.conforms"), String("detect"), String("exception"))

    var good = List[Value]()
    var w0 = write(a, Value.int(2), 0, String(""))
    good.append(w0)
    good.append(write(b, Value.bool(False), 0, w0.get(String("id")).s.copy()))
    t.check(
        String("a well-formed chain is intact"),
        chain_is_intact(Value.list(good^), String("")),
        String("expected an intact chain"),
    )

    # A broken link must be detected, not tolerated.
    var broken = List[Value]()
    broken.append(write(a, Value.int(2), 0, String("")))
    broken.append(write(b, Value.bool(False), 0, String("path.wrong#0")))
    t.check(
        String("a wrong prev is detected"),
        not chain_is_intact(Value.list(broken^), String("")),
        String("expected a broken chain"),
    )

    # An orphan head -- a non-null prev where none was expected.
    var orphan = List[Value]()
    orphan.append(write(a, Value.int(2), 0, String("path.ghost#0")))
    t.check(
        String("an orphan head is detected"),
        not chain_is_intact(Value.list(orphan^), String("")),
        String("expected a broken chain"),
    )

    # Continuing an existing chain: the head's prev must match head_prev.
    var cont = List[Value]()
    cont.append(write(a, Value.int(2), 1, String("path.earlier#0")))
    t.check(
        String("a continuation chain is intact"),
        chain_is_intact(Value.list(cont^), String("path.earlier#0")),
        String("expected an intact continuation"),
    )

    t.check(
        String("an empty log is intact"),
        chain_is_intact(Value.list(List[Value]()), String("")),
        String("empty is vacuously intact"),
    )

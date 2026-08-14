"""Tests for `replay()` -- folding a write log back into its settled snapshot.

Traces are hand-built from `address.write.write` and `address.grammar.address`.
No model runs here; that end-to-end path is Task 2's concern.
"""

from std.collections import List

from kernel.value import Value, RECORD
from address.grammar import address, render
from address.write import write
from domain.replay import replay, E_REPLAY
from testkit.harness import TestSuite


fn _addr(var slot: String, var op: String, var pressure: String) -> Value:
    return address(String("prog"), pressure^, op^, slot^)


fn run(mut t: TestSuite):
    _well_formed(t)
    _last_write_wins(t)
    _malformed_input(t)
    _broken_chain(t)
    _unterminated(t)


fn _well_formed(mut t: TestSuite):
    t.section(String("replay / well-formed log"))

    var a0 = _addr(String("result.actual"), String("change"), String("movement"))
    var a1 = _addr(String("state.cursor"), String("advance"), String("movement"))
    var a2 = _addr(String("output.final"), String("exit"), String("boundary"))

    var w0 = write(a0, Value.int(1), 0, String(""))
    var w1 = write(a1, Value.int(2), 1, w0.get(String("id")).s.copy())
    var w2 = write(a2, Value.int(3), 2, w1.get(String("id")).s.copy())

    var items = List[Value]()
    items.append(w0)
    items.append(w1)
    items.append(w2)
    var trace = Value.list(items^)

    var result = replay(trace)
    t.not_error(String("a well-formed three-write log replays"), result)
    t.eq_value(
        String("reconstructed is the terminal write's value"),
        result.get(String("reconstructed")),
        Value.int(3),
    )
    t.eq_str(
        String("final_address is the terminal write's rendered address"),
        result.get(String("final_address")).s,
        render(a2),
    )
    t.eq_int(
        String("steps equals the number of writes folded"),
        result.get(String("steps")).i,
        3,
    )


fn _last_write_wins(mut t: TestSuite):
    t.section(String("replay / last write wins"))

    # Two writes at the very same address -- the later value must win the fold,
    # not the earlier one.
    var a = _addr(String("output.final"), String("exit"), String("boundary"))
    var w0 = write(a, Value.int(100), 0, String(""))
    var w1 = write(a.copy(), Value.int(200), 1, w0.get(String("id")).s.copy())

    var items = List[Value]()
    items.append(w0)
    items.append(w1)
    var trace = Value.list(items^)

    var result = replay(trace)
    t.not_error(String("a repeated-address log still replays"), result)
    t.eq_value(
        String("the later value at a shared address wins"),
        result.get(String("reconstructed")),
        Value.int(200),
    )
    t.eq_int(
        String("steps still counts every write folded"),
        result.get(String("steps")).i,
        2,
    )


fn _malformed_input(mut t: TestSuite):
    t.section(String("replay / malformed input"))

    t.is_error(
        String("a non-list trace errors"),
        replay(Value.int(5)),
        String(E_REPLAY),
    )
    t.is_error(
        String("an empty trace errors"),
        replay(Value.list(List[Value]())),
        String(E_REPLAY),
    )


fn _broken_chain(mut t: TestSuite):
    t.section(String("replay / broken chain"))

    var a0 = _addr(String("result.actual"), String("change"), String("movement"))
    var a1 = _addr(String("output.final"), String("exit"), String("boundary"))

    # The second write's prev does not point at the first.
    var w0 = write(a0, Value.int(1), 0, String(""))
    var w1 = write(a1, Value.int(2), 1, String("path.nowhere#0"))
    var items = List[Value]()
    items.append(w0)
    items.append(w1)
    t.is_error(
        String("a wrong prev breaks the chain"),
        replay(Value.list(items^)),
        String(E_REPLAY),
    )

    # A head whose prev is non-null is an orphan -- there is no predecessor to
    # continue from.
    var orphan = write(a0.copy(), Value.int(1), 0, String("path.ghost#0"))
    var orphan_items = List[Value]()
    orphan_items.append(orphan)
    t.is_error(
        String("an orphan head errors"),
        replay(Value.list(orphan_items^)),
        String(E_REPLAY),
    )


fn _unterminated(mut t: TestSuite):
    t.section(String("replay / unterminated log"))

    var a = _addr(String("result.actual"), String("change"), String("movement"))
    var w0 = write(a, Value.int(1), 0, String(""))
    var items = List[Value]()
    items.append(w0)

    t.is_error(
        String("a log not ending at boundary/exit errors"),
        replay(Value.list(items^)),
        String(E_REPLAY),
    )

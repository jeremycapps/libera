"""Tests for `replay()` -- folding a write log back into its settled snapshot.

Traces are hand-built from `address.write.write` and `address.grammar.address`.
No model runs here; that end-to-end path is Task 2's concern.
"""

from std.collections import List

from kernel.value import Value, RECORD
from kernel.ir import kv, rec
from address.grammar import address, render
from address.write import write, chain_is_intact
from domain.model import load_domain_model
from domain.run import run as run_domain, settled, make_result
from domain.emit import load_policy
from domain.replay import replay, E_REPLAY
from testkit.harness import TestSuite


fn _addr(var slot: String, var op: String, var pressure: String) -> Value:
    return address(String("prog"), pressure^, op^, slot^)


fn run(mut t: TestSuite):
    _well_formed(t)
    _last_write_wins(t)
    _fold_is_keyed_by_slot(t)
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

    # The fold is part of the contract, not an internal detail: every slot the
    # log wrote is readable back out of it, including the non-terminal ones.
    var slots = result.get(String("slots"))
    t.check(
        String("slots is a record"),
        slots.tag == RECORD,
        String("expected a record, got ") + slots.to_string(),
    )
    t.eq_int(String("slots holds one entry per slot written"), slots.len(), 3)
    t.eq_value(
        String("the non-terminal result.actual slot survives the fold"),
        slots.get(String("result.actual")),
        Value.int(1),
    )
    t.eq_value(
        String("the non-terminal state.cursor slot survives the fold"),
        slots.get(String("state.cursor")),
        Value.int(2),
    )
    t.eq_value(
        String("the terminal slot holds what reconstructed holds"),
        slots.get(String("output.final")),
        Value.int(3),
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


fn _fold_is_keyed_by_slot(mut t: TestSuite):
    t.section(String("replay / the fold keys on slot, not rendered address"))

    # One slot, written twice under two different pressure/operation pairs --
    # exactly what a real run does to `verdict.conforms` when a deviation is
    # detected and then resolved. Rendered addresses differ; the destination
    # does not. Keyed by rendered address the stale `false` would survive
    # alongside the `true` that replaced it.
    var detected = _addr(
        String("verdict.conforms"), String("detect"), String("exception")
    )
    var advanced = _addr(
        String("verdict.conforms"), String("advance"), String("movement")
    )
    var exited = _addr(
        String("snapshot"), String("exit"), String("boundary")
    )

    var w0 = write(detected, Value.bool(False), 0, String(""))
    var w1 = write(advanced, Value.bool(True), 1, w0.get(String("id")).s.copy())
    var w2 = write(exited, Value.int(7), 2, w1.get(String("id")).s.copy())

    var items = List[Value]()
    items.append(w0)
    items.append(w1)
    items.append(w2)

    var result = replay(Value.list(items^))
    t.not_error(String("a re-addressed slot still replays"), result)

    var slots = result.get(String("slots"))
    t.eq_int(
        String("one slot written twice folds to one entry, not two"),
        slots.len(),
        2,
    )
    t.eq_value(
        String("the later write to the slot wins across a pressure change"),
        slots.get(String("verdict.conforms")),
        Value.bool(True),
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


# --- §10 acceptance: a real run's write log is reconstructable -------------
#
# Everything above hand-builds its trace. This suite drives an actual model
# through `run()` and proves the write log that comes out the other end is
# not merely emitted -- it is reconstructable by `replay`, and what it
# reconstructs to is exactly what `settled()` would have produced directly
# from the converged state.

comptime MODEL_PATH = "models/domain-count-level-0.yaml"


fn _count_result(n: Int) -> Value:
    """A supplied Result -- Level 0 does not discover one."""
    return make_result(rec(kv(String("count"), Value.int(n))), String("manual"))


fn run_acceptance(mut t: TestSuite) raises:
    t.section(String("replay / §10 acceptance: a real run's log replays"))

    var model = load_domain_model(String(MODEL_PATH))
    var policy = load_policy(String("models/writes-default.yaml"))

    var results = List[Value]()
    results.append(_count_result(2))
    results.append(_count_result(3))
    var out = run_domain(model, policy, results)
    t.not_error(String("the run converges"), out)
    t.eq_value(
        String("the run reports converged"),
        out.get(String("converged")),
        Value.bool(True),
    )

    var trace = out.get(String("snapshot")).get(String("trace"))
    var result = replay(trace)

    t.check(
        String("replay of a real run's trace returns a record, not an error"),
        result.tag == RECORD,
        String("expected a record, got ") + result.to_string(),
    )

    t.eq_str(
        String("final_address is boundary/exit/snapshot"),
        result.get(String("final_address")).s,
        String("boundary/exit/snapshot"),
    )

    var want = settled(model, out.get(String("state")))
    t.not_error(String("settled(model, out.state) itself succeeds"), want)
    var reconstructed = result.get(String("reconstructed"))
    t.eq_value(
        String("reconstructed.contract matches settled(model, state).contract"),
        reconstructed.get(String("contract")),
        want.get(String("contract")),
    )
    t.eq_value(
        String(
            "reconstructed.final_result matches settled(model,"
            " state).final_result"
        ),
        reconstructed.get(String("final_result")),
        want.get(String("final_result")),
    )
    t.eq_value(
        String(
            "reconstructed.final_verdict matches settled(model,"
            " state).final_verdict"
        ),
        reconstructed.get(String("final_verdict")),
        want.get(String("final_verdict")),
    )

    t.check(
        String("reconstructed carries no trace field"),
        not reconstructed.has(String("trace")),
        String("a settled value inside the log must not carry a trace: ")
        + reconstructed.to_string(),
    )

    # --- Reconstruction from the NON-terminal writes -----------------------
    #
    # Everything above reads the terminal write. On its own that proves the run
    # terminated correctly, not that the log is reconstructable: a `replay` that
    # discarded every write but the last would satisfy all of it. What follows
    # rebuilds the settled snapshot out of the slots the earlier writes landed
    # in, and never touches the `snapshot` slot the terminal write occupies.
    #
    # The slot -> settled-field mapping lives HERE, in the test. `replay` must
    # never learn that `result.actual` means `final_result`; the test may know
    # the model, the fold may not.

    var slots = result.get(String("slots"))
    t.check(
        String("replay exposes its fold as a record of slots"),
        slots.tag == RECORD,
        String("expected a record, got ") + slots.to_string(),
    )
    t.check(
        String("the fold holds the non-terminal contract.expected slot"),
        slots.has(String("contract.expected")),
        String("fold: ") + slots.to_string(),
    )
    t.check(
        String("the fold holds the non-terminal result.actual slot"),
        slots.has(String("result.actual")),
        String("fold: ") + slots.to_string(),
    )
    t.check(
        String("the fold holds the non-terminal verdict.conforms slot"),
        slots.has(String("verdict.conforms")),
        String("fold: ") + slots.to_string(),
    )
    t.eq_int(
        String("the fold holds exactly the four slots the policy declares"),
        slots.len(),
        4,
    )

    # This run writes `verdict.conforms` twice: once under exception/detect
    # (count=2 deviates) and once under movement/advance (count=3 conforms).
    # Two rendered addresses, one destination -- which is why the fold keys on
    # the slot. Keyed by rendered address the stale `false` would still be
    # standing here beside the `true` that replaced it.
    var saw_detect = False
    var saw_advance = False
    for k in range(trace.len()):
        var rendered = render(trace.at(k).get(String("address")))
        if rendered == "exception/detect/verdict.conforms":
            saw_detect = True
        if rendered == "movement/advance/verdict.conforms":
            saw_advance = True
    t.check(
        String("the run writes verdict.conforms under two different pressures"),
        saw_detect and saw_advance,
        String("expected both an exception/detect and a movement/advance write"),
    )
    t.eq_value(
        String("the folded verdict.conforms is the later, conforming write"),
        slots.get(String("verdict.conforms")),
        Value.bool(True),
    )

    # Rebuild the settled snapshot from those non-terminal slots alone. The
    # comparison is against a projection of `settled()` rather than the whole
    # record because the policy records `verdict.conforms`, not the whole
    # Verdict -- the log cannot be asked to give back more than it wrote
    # (`models/writes-default.yaml` declares exactly four slots).
    var rebuilt = rec(
        kv(
            String("contract"),
            rec(kv(String("expected"), slots.get(String("contract.expected")))),
        ),
        kv(
            String("final_result"),
            make_result(slots.get(String("result.actual")), String("manual")),
        ),
        kv(
            String("final_verdict.conforms"),
            slots.get(String("verdict.conforms")),
        ),
    )
    var want_projection = rec(
        kv(String("contract"), want.get(String("contract"))),
        kv(String("final_result"), want.get(String("final_result"))),
        kv(
            String("final_verdict.conforms"),
            want.get(String("final_verdict")).get(String("conforms")),
        ),
    )
    t.eq_value(
        String(
            "the settled snapshot rebuilds from the non-terminal writes alone"
        ),
        rebuilt,
        want_projection,
    )

    t.eq_int(
        String("steps equals the number of writes in the real trace"),
        result.get(String("steps")).i,
        trace.len(),
    )

    t.check(
        String("the whole real trace is one intact chain"),
        chain_is_intact(trace, String("")),
        String("chain broken"),
    )

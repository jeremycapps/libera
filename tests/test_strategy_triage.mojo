"""Rung 2: several responses, a rule for choosing, and a boundary that stops.

Rung 1 could decide but not stop. It answered every deviation identically and
forever. This adds the two missing pieces:

  selection  several candidates, the first whose `when` holds
  boundary   how many answers before giving up, and what to do then

The boundary is the part that matters. A strategy that cannot stop is not a
strategy, it is a loop -- and doc section 5 says so plainly about fixed
transforms. Crossing the boundary does not fail quietly: it escalates, and the
escalation names an `authority`, which is exactly what distinguishes handing a
problem up from trying again.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, LIST
from kernel.ir import kv, rec, sym, record_of, list_of
from domain.model import DomainModel, load_domain_model
from domain.emit import load_policy
from domain.run import make_result, verify
from strategy.respond import (
    load_strategy,
    respond_props,
    respond,
    exhausted,
    has_boundary,
    escalation,
    E_STRATEGY,
)
from strategy.run import run as run_with_strategy
from address.grammar import render
from address.write import chain_is_intact
from testkit.harness import TestSuite


comptime MODEL_PATH = "models/issue-completeness.yaml"
comptime POLICY_PATH = "models/writes-default.yaml"
comptime TRIAGE_PATH = "models/strategy-issue-triage.yaml"
comptime RUNG1_PATH = "models/strategy-route-back.yaml"


fn _text(var s: String) -> Value:
    return Value.string(s^)


fn _issue(var root_cause: Value, var owner: Value, var path: Value) -> Value:
    return make_result(
        rec(
            kv(String("root_cause"), root_cause^),
            kv(String("owner"), owner^),
            kv(String("resolution_path"), path^),
        ),
        String("support"),
    )


fn _no_root_cause() -> Value:
    return _issue(
        Value.null(), _text(String("alice")), _text(String("rollback"))
    )


fn _no_owner() -> Value:
    return _issue(
        _text(String("bad deploy")), Value.null(), _text(String("rollback"))
    )


fn _no_path() -> Value:
    return _issue(
        _text(String("bad deploy")), _text(String("alice")), Value.null()
    )


fn _complete() -> Value:
    return _issue(
        _text(String("bad deploy")),
        _text(String("alice")),
        _text(String("rollback")),
    )


fn _count_operation(trace: Value, var op: String) -> Int:
    var n = 0
    for k in range(trace.len()):
        var o = trace.at(k).get(String("address")).get(String("operation"))
        if o.is_text() and o.s == op:
            n += 1
    return n


fn _action_for(model: DomainModel, strategy: Value, result: Value) -> Value:
    """The action this strategy picks for a given Result."""
    var verdict = verify(model, result)
    var props = respond_props(
        model.contract,
        result,
        verdict,
        Value.empty_record(),
        Value.empty_record(),
    )
    return respond(strategy, props).get(String("action"))


fn run(mut t: TestSuite) raises:
    var model = load_domain_model(String(MODEL_PATH))
    var policy = load_policy(String(POLICY_PATH))
    var triage = load_strategy(String(TRIAGE_PATH))

    _loading(t, triage)
    _selection(t, model, triage)
    _boundary_arithmetic(t, triage)
    _escalation_on_crossing(t, model, triage, policy)
    _converging_never_escalates(t, model, triage, policy)
    _rung_one_still_works(t)
    _validation(t)


fn _loading(mut t: TestSuite, triage: Value):
    t.section(String("triage / loading"))

    t.not_error(String("strategy loads"), triage)
    t.check(
        String("declares candidates, not a single response"),
        triage.has(String("candidates")) and not triage.has(String("respond")),
        String("wrong shape"),
    )
    t.check(
        String("declares a boundary"),
        has_boundary(triage),
        String("no max_attempts"),
    )
    t.eq_value(
        String("the boundary is two attempts"),
        triage.get(String("max_attempts")),
        Value.int(2),
    )
    t.check(
        String("and a response for crossing it"),
        triage.has(String("exhausted")),
        String("no exhausted response"),
    )


fn _selection(mut t: TestSuite, model: DomainModel, triage: Value):
    t.section(String("triage / the finding selects the response"))

    # This is the whole of rung 2's choosing: different deviations get
    # different answers, decided by a declared condition rather than a score.
    t.eq_value(
        String("a missing root cause asks engineering for logs"),
        _action_for(model, triage, _no_root_cause()),
        sym(String("ask_for_logs")),
    )
    t.eq_value(
        String("a missing owner is an assignment"),
        _action_for(model, triage, _no_owner()),
        sym(String("assign_owner")),
    )
    t.eq_value(
        String("anything else goes back to the supplier"),
        _action_for(model, triage, _no_path()),
        sym(String("route_back")),
    )

    # The chosen candidate still quotes the verdict, as rung 1 did.
    var verdict = verify(model, _no_owner())
    var props = respond_props(
        model.contract,
        _no_owner(),
        verdict,
        Value.empty_record(),
        Value.empty_record(),
    )
    var chosen = respond(triage, props)
    t.eq_value(
        String("and says why in the verdict's own words"),
        chosen.get(String("because")),
        verdict.get(String("finding")),
    )
    t.eq_value(
        String("an ordinary response names no authority"),
        chosen.get(String("authority")),
        Value.null(),
    )
    t.eq_value(
        String("it is routed to whoever can act on it"),
        chosen.get(String("to")),
        sym(String("support_lead")),
    )

    # A candidate list with nothing applicable is a gap in the model, not a
    # reason to do nothing quietly.
    var nothing_applies = rec(
        kv(
            String("candidates"),
            list_of(
                record_of(
                    kv(String("when"), Value.bool(False)),
                    kv(String("action"), sym(String("never"))),
                )
            ),
        ),
        kv(String("writes"), list_of()),
        kv(String("max_attempts"), Value.null()),
    )
    t.is_error(
        String("no applicable candidate is an error"),
        respond(nothing_applies, Value.empty_record()),
        String(E_STRATEGY),
    )


fn _boundary_arithmetic(mut t: TestSuite, triage: Value):
    t.section(String("triage / the boundary counts answers"))

    t.check(
        String("not exhausted before answering"),
        not exhausted(triage, 0),
        String("exhausted too early"),
    )
    t.check(
        String("not exhausted after one answer"),
        not exhausted(triage, 1),
        String("exhausted too early"),
    )
    t.check(
        String("exhausted at the limit"),
        exhausted(triage, 2),
        String("should be exhausted at 2"),
    )
    t.check(
        String("still exhausted past it"),
        exhausted(triage, 3),
        String("should stay exhausted"),
    )

    # A strategy with no boundary never exhausts. That is rung 1's behaviour,
    # and it is precisely the thing rung 2 exists to fix.
    var unbounded = rec(
        kv(String("respond"), record_of(kv(String("action"), sym(String("x"))))),
        kv(String("writes"), list_of()),
        kv(String("max_attempts"), Value.null()),
    )
    t.check(
        String("a strategy with no boundary has none"),
        not has_boundary(unbounded),
        String("unexpected boundary"),
    )
    t.check(
        String("and is never exhausted, however many times it answers"),
        not exhausted(unbounded, 9999),
        String("unbounded strategy claimed exhaustion"),
    )


fn _escalation_on_crossing(
    mut t: TestSuite, model: DomainModel, triage: Value, policy: Value
):
    t.section(String("triage / crossing the boundary escalates"))

    # Five identical unfixable issues. The strategy answers twice, then hands
    # the problem up rather than answering a third time.
    var results = List[Value]()
    for _ in range(5):
        results.append(_no_root_cause())
    var outcome = run_with_strategy(model, triage, policy, results)

    t.not_error(String("run completes"), outcome)
    t.eq_value(
        String("it does not converge"),
        outcome.get(String("converged")),
        Value.bool(False),
    )
    t.eq_value(
        String("it reports that it gave up"),
        outcome.get(String("exhausted")),
        Value.bool(True),
    )

    # The run stops at the handoff. Continuing to verify after escalating would
    # be answering a question already given away.
    t.eq_int(
        String("only three folds ran, not five"),
        outcome.get(String("classifications")).len(),
        3,
    )
    t.eq_int(
        String("two retries plus one escalation"),
        outcome.get(String("attempts")).i,
        3,
    )

    var responses = outcome.get(String("responses"))
    t.eq_value(
        String("the first answer is a retry"),
        responses.at(0).get(String("action")),
        sym(String("ask_for_logs")),
    )
    t.eq_value(
        String("so is the second"),
        responses.at(1).get(String("action")),
        sym(String("ask_for_logs")),
    )
    t.eq_value(
        String("the third escalates"),
        responses.at(2).get(String("action")),
        sym(String("escalate")),
    )

    # The distinction that makes it an escalation rather than a third retry.
    t.eq_value(
        String("retries name no authority"),
        responses.at(0).get(String("authority")),
        Value.null(),
    )
    t.eq_value(
        String("the escalation names one"),
        responses.at(2).get(String("authority")),
        sym(String("product_owner")),
    )

    # And that authority reaches the log, which is the governance half of the
    # write record: `authority` answers who can make this count.
    var trace = outcome.get(String("trace"))
    var last = trace.at(trace.len() - 1)
    t.eq_str(
        String("the final write records who it was handed to"),
        render(last.get(String("address"))),
        String("exception/respond/response.authority"),
    )
    t.eq_value(
        String("naming them"),
        last.get(String("value")),
        sym(String("product_owner")),
    )
    t.eq_str(
        String("preceded by the escalation itself"),
        render(trace.at(trace.len() - 2).get(String("address"))),
        String("exception/respond/response.action"),
    )
    t.eq_value(
        String("whose action is escalate"),
        trace.at(trace.len() - 2).get(String("value")),
        sym(String("escalate")),
    )

    # Four responses' worth of writes: three actions plus one authority.
    t.eq_int(
        String("four response writes in all"),
        _count_operation(trace, String("respond")),
        4,
    )
    t.eq_int(
        String("three detections, one per fold"),
        _count_operation(trace, String("detect")),
        3,
    )
    t.check(
        String("nothing advanced and nothing exited"),
        _count_operation(trace, String("advance")) == 0
        and _count_operation(trace, String("exit")) == 0,
        String("an unconverged run should not advance or exit"),
    )
    t.check(
        String("the log is one intact chain across both layers"),
        chain_is_intact(trace, String("")),
        String("chain broken"),
    )
    t.check(
        String("and carries no snapshot, having settled nothing"),
        not outcome.has(String("snapshot")),
        String("unexpected snapshot on an escalated run"),
    )


fn _converging_never_escalates(
    mut t: TestSuite, model: DomainModel, triage: Value, policy: Value
):
    t.section(String("triage / fixing it in time avoids the boundary"))

    # Two deviations then a fix. The boundary allows two answers, so the
    # escalation is never reached -- the limit is on fruitless answers, not on
    # folds.
    var results = List[Value]()
    results.append(_no_root_cause())
    results.append(_no_owner())
    results.append(_complete())
    var outcome = run_with_strategy(model, triage, policy, results)

    t.eq_value(
        String("it converges"),
        outcome.get(String("converged")),
        Value.bool(True),
    )
    t.eq_value(
        String("without giving up"),
        outcome.get(String("exhausted")),
        Value.bool(False),
    )
    t.eq_int(String("two answers, both retries"), outcome.get(String("attempts")).i, 2)
    t.eq_int(
        String("no escalation write"),
        _count_operation(outcome.get(String("trace")), String("respond")),
        2,
    )
    t.check(
        String("nothing named an authority"),
        outcome.get(String("trace")).to_string().find("product_owner") == -1,
        String("escalated when it should not have"),
    )
    t.check(
        String("and it settled, so a snapshot was emitted"),
        outcome.has(String("snapshot")),
        String("missing snapshot on a converged run"),
    )


fn _rung_one_still_works(mut t: TestSuite) raises:
    t.section(String("triage / rung 1 is unchanged"))

    # Adding candidates and boundaries must not break the single-response form.
    var rung1 = load_strategy(String(RUNG1_PATH))
    t.not_error(String("the fixed-response strategy still loads"), rung1)
    t.check(
        String("it declares a single response"),
        rung1.has(String("respond")),
        String("missing respond"),
    )
    t.check(
        String("and still has no boundary"),
        not has_boundary(rung1),
        String("unexpected boundary"),
    )
    t.is_error(
        String("so asking it to escalate is an error"),
        escalation(rung1, Value.empty_record()),
        String(E_STRATEGY),
    )


fn _validation(mut t: TestSuite) raises:
    t.section(String("triage / malformed strategies are rejected"))

    t.is_error(
        String("declaring both respond and candidates"),
        load_strategy(String("tests/fixtures/strategy-both.yaml")),
        String(E_STRATEGY),
    )
    # A boundary with no response for crossing it is a trap: the run would
    # reach the limit and have nothing to do.
    t.is_error(
        String("a boundary with no exhausted response"),
        load_strategy(
            String("tests/fixtures/strategy-limit-without-exhausted.yaml")
        ),
        String(E_STRATEGY),
    )
    t.is_error(
        String("a non-integer max_attempts"),
        load_strategy(String("tests/fixtures/strategy-bad-limit.yaml")),
        String(E_STRATEGY),
    )

"""Domain Level 0: D0 and D1 from the bootstrap table (doc 6).

    Level  Purpose               Test                              Pass condition
    D0     Domain verification   Contract expected 3, Result 2/3.  Verdict and
                                                                   CurrentState
                                                                   update correctly.
    D1     Domain orchestration  Fold Contract, Result, Verdict     Classification
                                 into state.                       becomes exception
                                                                   or confirmed.

Traces A and B are given verbatim in doc 3.3 and are asserted here field by
field. The model under test is `models/domain-count-level-0.yaml`, loaded from
disk -- so these tests exercise the whole path the architecture describes:
YAML -> Model IR -> kernel evaluation.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, SYMBOL
from kernel.ir import kv, rec, lst, sym
from domain.model import (
    DomainModel,
    load_domain_model,
    domain_model_from_text,
)
from domain.run import (
    initial_state,
    make_result,
    verify,
    orchestrate,
    step,
    step_with_writes,
    run as run_domain,
    snapshot,
    converged,
)
from domain.emit import load_policy
from address.grammar import render
from address.write import chain_is_intact
from testkit.harness import TestSuite


comptime MODEL_PATH = "models/domain-count-level-0.yaml"


fn _count_result(n: Int) -> Value:
    """A supplied Result -- Level 0 does not discover one."""
    return make_result(rec(kv(String("count"), Value.int(n))), String("manual"))


fn run(mut t: TestSuite) raises:
    var model = load_domain_model(String(MODEL_PATH))
    _loading(t, model)
    _d0_verification(t, model)
    _d1_orchestration(t, model)
    _trace_a(t, model)
    _trace_b(t, model)
    _convergence_and_snapshot(t, model)
    _no_planning(t, model)
    _addressed_writes(t, model)
    _model_errors(t)


fn _loading(mut t: TestSuite, model: DomainModel):
    t.section(String("domain / model loading"))

    t.check(
        String("model loads from disk"),
        model.is_valid(),
        String("load failed: ") + model.error.to_string(),
    )
    t.eq_str(
        String("model name"), model.name, String("domain-count-level-0")
    )
    t.eq_value(String("model version"), model.version, Value.float(0.1))
    t.eq_value(
        String("contract is data, not an expression"),
        model.contract,
        rec(kv(String("expected"), rec(kv(String("count"), Value.int(3))))),
    )
    t.eq_value(
        String("contract expected"),
        model.expected(),
        rec(kv(String("count"), Value.int(3))),
    )
    t.not_error(String("model declares a verifier"), model.verifier())
    t.not_error(String("model declares an orchestrator"), model.orchestrator())

    var state = initial_state(model)
    t.eq_value(
        String("initial state seeds the contract"),
        state.get(String("contract")),
        model.contract,
    )
    t.eq_value(
        String("initial state has no result"),
        state.get(String("result")),
        Value.null(),
    )
    t.eq_value(
        String("initial state has no verdict"),
        state.get(String("verdict")),
        Value.null(),
    )
    t.eq_value(
        String("initial state is not converged"),
        state.get(String("converged")),
        Value.bool(False),
    )


fn _d0_verification(mut t: TestSuite, model: DomainModel):
    t.section(String("D0 / domain verification"))

    # Verdict shape per doc 3.1: { conforms, expected, actual, finding? }.
    var v2 = verify(model, _count_result(2))
    t.not_error(String("verify returns a Verdict"), v2)
    t.eq_value(
        String("actual 2 does not conform"),
        v2.get(String("conforms")),
        Value.bool(False),
    )
    t.eq_value(
        String("verdict finding is not_confirmed"),
        v2.get(String("finding")),
        sym(String("not_confirmed")),
    )
    t.eq_value(
        String("verdict carries expected"),
        v2.get(String("expected")),
        Value.int(3),
    )
    t.eq_value(
        String("verdict carries actual"), v2.get(String("actual")), Value.int(2)
    )
    t.eq_value(
        String("verdict is typed"), v2.get(String("type")), sym(String("Verdict"))
    )

    var v3 = verify(model, _count_result(3))
    t.eq_value(
        String("actual 3 conforms"),
        v3.get(String("conforms")),
        Value.bool(True),
    )
    t.eq_value(
        String("verdict finding is confirmed"),
        v3.get(String("finding")),
        sym(String("confirmed")),
    )

    # Verification is comparison, not coercion: an actual above expected fails
    # just as an actual below it does.
    t.eq_value(
        String("actual 4 does not conform"),
        verify(model, _count_result(4)).get(String("conforms")),
        Value.bool(False),
    )

    t.is_error(
        String("a Result without 'actual' is an error"),
        verify(model, rec(kv(String("wrong"), Value.int(3)))),
        String("domain_error"),
    )
    t.is_error(
        String("a non-record Result is an error"),
        verify(model, Value.int(3)),
        String("domain_error"),
    )


fn _d1_orchestration(mut t: TestSuite, model: DomainModel) raises:
    t.section(String("D1 / domain orchestration"))

    var policy = load_policy(String("models/writes-default.yaml"))

    var state = initial_state(model)
    var verdict = verify(model, _count_result(2))
    var folded = orchestrate(model, state, verdict)

    t.not_error(String("orchestrate returns a state"), folded)
    var derived_bad = step_with_writes(
        model, policy, state, _count_result(2), 0, String("")
    )
    t.eq_value(
        String("classification becomes exception"),
        derived_bad.get(String("state")).get(String("classification")),
        sym(String("exception")),
    )
    t.eq_value(
        String("verdict is folded into state"),
        folded.get(String("verdict")),
        verdict,
    )
    t.eq_value(
        String("contract is preserved through the fold"),
        folded.get(String("contract")),
        model.contract,
    )

    var good = orchestrate(model, state, verify(model, _count_result(3)))
    var derived_good = step_with_writes(
        model, policy, state, _count_result(3), 0, String("")
    )
    t.eq_value(
        String("classification becomes confirmed"),
        derived_good.get(String("state")).get(String("classification")),
        sym(String("confirmed")),
    )
    t.eq_value(
        String("converged tracks conformance"),
        good.get(String("converged")),
        Value.bool(True),
    )

    # `step` stages the Result into state before orchestrating, so the
    # orchestrator's `ref: state.result` sees this observation.
    var stepped = step(model, state, _count_result(2))
    t.eq_value(
        String("step records the result in state"),
        stepped.get(String("result")),
        _count_result(2),
    )


fn _trace_a(mut t: TestSuite, model: DomainModel) raises:
    t.section(String("domain / trace A (doc 3.3): expected 3, actual 2"))

    var policy = load_policy(String("models/writes-default.yaml"))

    var verdict = verify(model, _count_result(2))
    t.eq_value(
        String("Verdict = { conforms: false, finding: not_confirmed }"),
        rec(
            kv(String("conforms"), verdict.get(String("conforms"))),
            kv(String("finding"), verdict.get(String("finding"))),
        ),
        rec(
            kv(String("conforms"), Value.bool(False)),
            kv(String("finding"), sym(String("not_confirmed"))),
        ),
    )

    var next = step_with_writes(
        model, policy, initial_state(model), _count_result(2), 0, String("")
    ).get(String("state"))
    t.eq_value(
        String("CurrentState' = { classification: exception, converged: false }"),
        rec(
            kv(String("classification"), next.get(String("classification"))),
            kv(String("converged"), next.get(String("converged"))),
        ),
        rec(
            kv(String("classification"), sym(String("exception"))),
            kv(String("converged"), Value.bool(False)),
        ),
    )
    t.check(
        String("trace A has not converged"),
        not converged(next),
        String("state: ") + next.to_string(),
    )


fn _trace_b(mut t: TestSuite, model: DomainModel) raises:
    t.section(String("domain / trace B (doc 3.3): expected 3, actual 3"))

    var policy = load_policy(String("models/writes-default.yaml"))

    var verdict = verify(model, _count_result(3))
    t.eq_value(
        String("Verdict = { conforms: true, finding: confirmed }"),
        rec(
            kv(String("conforms"), verdict.get(String("conforms"))),
            kv(String("finding"), verdict.get(String("finding"))),
        ),
        rec(
            kv(String("conforms"), Value.bool(True)),
            kv(String("finding"), sym(String("confirmed"))),
        ),
    )

    var next = step_with_writes(
        model, policy, initial_state(model), _count_result(3), 0, String("")
    ).get(String("state"))
    t.eq_value(
        String("CurrentState' = { classification: confirmed, converged: true }"),
        rec(
            kv(String("classification"), next.get(String("classification"))),
            kv(String("converged"), next.get(String("converged"))),
        ),
        rec(
            kv(String("classification"), sym(String("confirmed"))),
            kv(String("converged"), Value.bool(True)),
        ),
    )
    t.check(
        String("trace B has converged"),
        converged(next),
        String("state: ") + next.to_string(),
    )


fn _convergence_and_snapshot(mut t: TestSuite, model: DomainModel) raises:
    t.section(String("domain / convergence and snapshot"))

    var policy = load_policy(String("models/writes-default.yaml"))

    # A run of supplied Results: the first fails, the second converges.
    var results = List[Value]()
    results.append(_count_result(2))
    results.append(_count_result(3))
    var outcome = run_domain(model, policy, results)

    t.not_error(String("run completes"), outcome)
    t.eq_value(
        String("run converges"),
        outcome.get(String("converged")),
        Value.bool(True),
    )
    t.eq_int(String("trace holds six writes"), outcome.get(String("trace")).len(), 6)
    t.eq_value(
        String("first fold classifies as exception"),
        outcome.get(String("classifications")).at(0),
        sym(String("exception")),
    )
    t.eq_value(
        String("second fold classifies as confirmed"),
        outcome.get(String("classifications")).at(1),
        sym(String("confirmed")),
    )

    # Snapshot shape per doc 3.1: { contract, final_result, final_verdict, trace }.
    var snap = outcome.get(String("snapshot"))
    t.not_error(String("snapshot emitted on convergence"), snap)
    t.eq_value(
        String("snapshot carries the contract"),
        snap.get(String("contract")),
        model.contract,
    )
    t.eq_value(
        String("snapshot final_result is the converging result"),
        snap.get(String("final_result")),
        _count_result(3),
    )
    t.eq_value(
        String("snapshot final_verdict conforms"),
        snap.get(String("final_verdict")).get(String("conforms")),
        Value.bool(True),
    )
    t.eq_int(String("snapshot carries the trace"), snap.get(String("trace")).len(), 6)

    # Once converged the run stops -- later results are not consumed.
    var early = List[Value]()
    early.append(_count_result(3))
    early.append(_count_result(2))
    var stopped = run_domain(model, policy, early)
    t.eq_value(
        String("run stops at convergence"),
        stopped.get(String("converged")),
        Value.bool(True),
    )
    t.eq_int(
        String("trailing results are not consumed"),
        stopped.get(String("classifications")).len(),
        1,
    )

    # A run that never conforms neither converges nor snapshots.
    var never = List[Value]()
    never.append(_count_result(1))
    never.append(_count_result(2))
    var unconverged = run_domain(model, policy, never)
    t.eq_value(
        String("non-conforming run does not converge"),
        unconverged.get(String("converged")),
        Value.bool(False),
    )
    t.check(
        String("no snapshot without convergence"),
        not unconverged.has(String("snapshot")),
        String("unexpected snapshot: ") + unconverged.to_string(),
    )
    t.is_error(
        String("snapshotting an unconverged state is an error"),
        snapshot(model, unconverged.get(String("state")), lst()),
        String("domain_error"),
    )

    var empty = List[Value]()
    var no_results = run_domain(model, policy, empty)
    t.eq_value(
        String("a run with no results does not converge"),
        no_results.get(String("converged")),
        Value.bool(False),
    )


fn _no_planning(mut t: TestSuite, model: DomainModel) raises:
    t.section(String("domain / Level 0 does not plan"))

    var policy = load_policy(String("models/writes-default.yaml"))

    # The doc is explicit that Level 0 must not solve planning or repair. The
    # observable consequence: Domain never improves a Result on its own. Given
    # only non-conforming results, it stays unconverged rather than deriving 3.
    var wrong = List[Value]()
    wrong.append(_count_result(0))
    wrong.append(_count_result(1))
    wrong.append(_count_result(2))
    var outcome = run_domain(model, policy, wrong)

    t.eq_value(
        String("Domain does not derive a conforming result"),
        outcome.get(String("converged")),
        Value.bool(False),
    )
    t.eq_int(
        String("every supplied result was verified"),
        outcome.get(String("classifications")).len(),
        3,
    )
    t.eq_value(
        String("final result is the last one supplied, unmodified"),
        outcome.get(String("state")).get(String("result")),
        _count_result(2),
    )
    t.eq_value(
        String("every step classified as exception"),
        outcome.get(String("classifications")).at(2),
        sym(String("exception")),
    )


fn _model_errors(mut t: TestSuite):
    t.section(String("domain / model validation"))

    t.check(
        String("a document without a contract is rejected"),
        not domain_model_from_text(String("model: x\n")).is_valid(),
        String("expected an invalid model"),
    )
    t.check(
        String("a non-mapping document is rejected"),
        not domain_model_from_text(String("- 1\n- 2\n")).is_valid(),
        String("expected an invalid model"),
    )
    t.check(
        String("a parse error surfaces as an invalid model"),
        not domain_model_from_text(String("contract: {a: 1\n")).is_valid(),
        String("expected an invalid model"),
    )

    # Missing expressions are reported when asked for, not at load time -- D0
    # needs only a verifier, so a model without an orchestrator is still usable.
    var verify_only = domain_model_from_text(
        String(
            """
model: verify-only
contract:
  expected:
    count: 1
expressions:
  verify:
    record:
      conforms:
        eq:
          - ref: actual.count
          - ref: expected.count
"""
        )
    )
    t.check(
        String("a model with only a verifier still loads"),
        verify_only.is_valid(),
        String("load failed: ") + verify_only.error.to_string(),
    )
    t.not_error(String("its verifier resolves"), verify_only.verifier())
    t.is_error(
        String("its missing orchestrator is reported"),
        verify_only.orchestrator(),
        String("model_error"),
    )
    t.eq_value(
        String("it can still verify"),
        verify(verify_only, _count_result(1)).get(String("conforms")),
        Value.bool(True),
    )

    var no_verifier = domain_model_from_text(
        String("model: bare\ncontract:\n  expected:\n    count: 1\n")
    )
    t.check(
        String("a model without expressions loads"),
        no_verifier.is_valid(),
        String("load failed"),
    )
    t.is_error(
        String("its missing verifier is reported"),
        no_verifier.verifier(),
        String("model_error"),
    )

    # Doc 3.1 allows the verifier to live on the Contract instead; both spellings
    # work, and contract.verifier takes precedence.
    var on_contract = domain_model_from_text(
        String(
            """
model: verifier-on-contract
contract:
  expected:
    count: 2
  verifier:
    record:
      conforms:
        eq:
          - ref: actual.count
          - ref: expected.count
"""
        )
    )
    t.check(
        String("verifier on the contract loads"),
        on_contract.is_valid(),
        String("load failed: ") + on_contract.error.to_string(),
    )
    t.eq_value(
        String("contract.verifier is used"),
        verify(on_contract, _count_result(2)).get(String("conforms")),
        Value.bool(True),
    )
    t.eq_value(
        String("contract.verifier rejects a mismatch"),
        verify(on_contract, _count_result(5)).get(String("conforms")),
        Value.bool(False),
    )


fn _count_operation(trace: Value, var op: String) -> Int:
    """How many writes in the log carry this operation."""
    var n = 0
    for k in range(trace.len()):
        var o = trace.at(k).get(String("address")).get(String("operation"))
        if o.is_text() and o.s == op:
            n += 1
    return n


fn _addressed_writes(mut t: TestSuite, model: DomainModel) raises:
    t.section(String("domain / writes carry addresses"))

    var policy = load_policy(String("models/writes-default.yaml"))
    var results = List[Value]()
    results.append(_count_result(2))
    results.append(_count_result(3))
    var outcome = run_domain(model, policy, results)

    t.not_error(String("run completes"), outcome)
    t.eq_value(
        String("run converges"),
        outcome.get(String("converged")),
        Value.bool(True),
    )

    # Three writes per fold. Fold 0: enter (first fold), change, detect. Fold 1: no
    # enter, change, advance, exit (converged). Six in total.
    var trace = outcome.get(String("trace"))
    t.eq_int(String("six writes across two folds"), trace.len(), 6)
    t.eq_str(
        String("write 0 -- contract enters"),
        render(trace.at(0).get(String("address"))),
        String("boundary/enter/contract.expected"),
    )
    t.eq_str(
        String("write 1 -- result changes"),
        render(trace.at(1).get(String("address"))),
        String("movement/change/result.actual"),
    )
    t.eq_str(
        String("write 2 -- deviation detected"),
        render(trace.at(2).get(String("address"))),
        String("exception/detect/verdict.conforms"),
    )
    t.eq_str(
        String("write 3 -- result changes again"),
        render(trace.at(3).get(String("address"))),
        String("movement/change/result.actual"),
    )
    t.eq_str(
        String("write 4 -- conformance advances"),
        render(trace.at(4).get(String("address"))),
        String("movement/advance/verdict.conforms"),
    )
    t.eq_str(
        String("write 5 -- work leaves scope"),
        render(trace.at(5).get(String("address"))),
        String("boundary/exit/snapshot"),
    )

    # `enter` fires exactly once even though two folds run.
    t.eq_int(
        String("contract enters scope only once"),
        _count_operation(trace, String("enter")),
        1,
    )
    t.eq_int(
        String("result changes once per fold"),
        _count_operation(trace, String("change")),
        2,
    )

    t.check(
        String("the whole log is one intact chain"),
        chain_is_intact(trace, String("")),
        String("chain broken"),
    )

    # Level 0 discipline, now assertable by address.
    t.check(
        String("no exception/respond is ever emitted"),
        trace.to_string().find("respond") == -1,
        String("planning has leaked into Domain"),
    )

    # Classification is derived, and still agrees with what the doc's traces say.
    t.eq_value(
        String("first fold classifies as exception"),
        outcome.get(String("classifications")).at(0),
        sym(String("exception")),
    )
    t.eq_value(
        String("second fold classifies as confirmed"),
        outcome.get(String("classifications")).at(1),
        sym(String("confirmed")),
    )

    # A conforming-only run never emits an exception pressure.
    var quick = List[Value]()
    quick.append(_count_result(3))
    var fast = run_domain(model, policy, quick)
    t.check(
        String("a conforming run emits no exception pressure"),
        fast.get(String("trace")).to_string().find("exception") == -1,
        String("unexpected exception pressure"),
    )

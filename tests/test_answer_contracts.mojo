"""Versioned Verdict and Transform compatibility above the kernel."""

from kernel.value import Value
from kernel.ir import kv, rec, lst, sym
from domain.model import load_domain_model, domain_model_from_text
from domain.run import initial_state, make_result, verify, step_with_writes, converged
from domain.emit import load_policy
from domain.answer import transform_v1, validate_transform, validate_model_policy
from testkit.harness import TestSuite


fn run(mut t: TestSuite) raises:
    t.section(String("domain answers / versioned Verdict compatibility"))

    var legacy = load_domain_model(String("models/domain-count-level-0.yaml"))
    t.eq_str(String("existing models default to legacy contract"), legacy.answer_contract, String("LegacyBooleanVerdictV0"))
    t.eq_value(
        String("legacy false remains compatible"),
        verify(legacy, make_result(rec(kv(String("count"), Value.int(2))), String("test"))).get(String("conforms")),
        Value.bool(False),
    )
    t.eq_value(
        String("legacy true remains compatible"),
        verify(legacy, make_result(rec(kv(String("count"), Value.int(3))), String("test"))).get(String("conforms")),
        Value.bool(True),
    )

    var bounded = load_domain_model(String("models/mercury-incident-handoff.yaml"))
    t.eq_str(String("bounded contract is explicit"), bounded.answer_contract, String("BoundedVerdictV1"))
    t.check(String("bounded conformance is optional"), bounded.conformance_optional, String("expected optional"))

    var actual = rec(
        kv(String("incidentId"), Value.string(String("INC-1842"))),
        kv(String("owner"), Value.string(String("Support"))),
        kv(String("targetContext"), Value.string(String("Engineering"))),
        kv(String("missing"), lst(sym(String("root_cause")), sym(String("reproduction_steps")))),
        kv(String("evidence"), lst(sym(String("customer_report")), sym(String("application_logs")), sym(String("prior_support_notes")))),
    )
    var answer = verify(bounded, make_result(actual, String("fixture")))
    t.not_error(String("bounded verdict validates"), answer)
    t.eq_value(String("bounded state is preserved"), answer.get(String("state")), sym(String("blocked")))
    t.eq_value(String("optional projection may be present"), answer.get(String("conforms")), Value.bool(False))

    var bounded_policy = load_policy(String("models/writes-bounded.yaml"))
    t.not_error(String("explicit bounded policy is compatible"), validate_model_policy(bounded, bounded_policy))
    t.not_error(
        String("compatible bounded fold emits writes"),
        step_with_writes(bounded, bounded_policy, initial_state(bounded), make_result(actual, String("fixture")), 0, String("")),
    )
    var default_policy = load_policy(String("models/writes-default.yaml"))
    t.is_error(
        String("incompatible default policy fails before writes"),
        step_with_writes(bounded, default_policy, initial_state(bounded), make_result(actual, String("fixture")), 0, String("")),
        String("INCOMPATIBLE_VERDICT_POLICY"),
    )

    var no_projection = domain_model_from_text(String("""
model: bounded-without-projection
answer_contract: BoundedVerdictV1
conformance: optional
write_policy: models/writes-bounded.yaml
contract:
  expected: ready
expressions:
  verify:
    record:
      type: Verdict
      state: needs_review
  orchestrate:
    record:
      verdict:
        ref: output
      converged: false
"""))
    var bounded_without = verify(no_projection, make_result(Value.int(1), String("test")))
    t.not_error(String("bounded verdict may omit conforms"), bounded_without)
    t.check(String("omitted conforms stays omitted"), not bounded_without.has(String("conforms")), String("projection was invented"))
    t.check(
        String("state name never implies convergence"),
        not converged(rec(kv(String("converged"), Value.bool(False)), kv(String("verdict"), bounded_without))),
        String("bounded state was treated as Boolean convergence"),
    )

    t.section(String("domain answers / TransformV1"))
    var transform = transform_v1(
        String("mercury.handoff"), String("Support to Engineering handoff"),
        rec(kv(String("owner"), sym(String("Support")))),
        rec(kv(String("owner"), sym(String("Engineering")))),
        rec(kv(String("status"), sym(String("triaged")))),
        rec(kv(String("status"), sym(String("accepted")))),
        lst(sym(String("approval:ENG-22"))),
    )
    t.not_error(String("TransformV1 validates"), validate_transform(transform))
    t.eq_str(String("operation identity survives"), transform.get(String("operation")).get(String("id")).s, String("mercury.handoff"))
    t.eq_value(String("input survives"), transform.get(String("input")).get(String("owner")), sym(String("Support")))
    t.eq_value(String("output survives"), transform.get(String("output")).get(String("owner")), sym(String("Engineering")))
    t.eq_value(String("before survives"), transform.get(String("before")).get(String("status")), sym(String("triaged")))
    t.eq_value(String("after survives"), transform.get(String("after")).get(String("status")), sym(String("accepted")))
    t.eq_int(String("evidence survives"), transform.get(String("evidence")).len(), 1)
    t.is_error(
        String("empty Transform operation is rejected"),
        transform_v1(String(""), String("bad"), Value.int(1), Value.int(2), Value.null(), Value.null(), Value.null()),
        String("INVALID_DOMAIN_ANSWER"),
    )

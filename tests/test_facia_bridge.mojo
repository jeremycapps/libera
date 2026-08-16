"""Schema-pinned question-to-AnswerSet normalization proof."""

from kernel.value import Value
from kernel.ir import kv, rec, lst, sym
from modelir.yaml import parse_yaml_file
from domain.model import load_domain_model
from domain.run import make_result, verify
from domain.answer import transform_v1
from facia_bridge.schema_pin import FACIA_SCHEMA_ID, FACIA_SCHEMA_SHA256
from facia_bridge.bridge import load_question, verify_schema_pin, normalize
from testkit.harness import TestSuite


fn run(mut t: TestSuite) raises:
    t.section(String("facia bridge / release pin and Mercury flow"))
    var manifest = parse_yaml_file(String("facia_bridge/fixtures/manifest.yaml"))
    t.eq_str(String("consumer manifest schema id"), manifest.get(String("schema")).s, String(FACIA_SCHEMA_ID))
    t.eq_str(String("consumer manifest schema hash"), manifest.get(String("schema_sha256")).s, String(FACIA_SCHEMA_SHA256))
    t.not_error(String("matching pin is accepted"), verify_schema_pin(String(FACIA_SCHEMA_ID), String(FACIA_SCHEMA_SHA256)))
    t.is_error(String("schema id mismatch is structured"), verify_schema_pin(String("facia.answer-set/2"), String(FACIA_SCHEMA_SHA256)), String("FACIA_SCHEMA_ID_MISMATCH"))
    t.is_error(String("schema hash mismatch is structured"), verify_schema_pin(String(FACIA_SCHEMA_ID), String("bad")), String("FACIA_SCHEMA_HASH_MISMATCH"))

    var question = load_question(String("questions/mercury-incident-handoff.yaml"))
    t.not_error(String("declared Mercury question loads"), question)
    t.eq_str(String("question selection is explicit"), question.get(String("id")).s, String("mercury.incident_handoff"))
    t.eq_str(String("question selects the Domain model"), question.get(String("domain_model")).s, String("models/mercury-incident-handoff.yaml"))

    var actual = rec(
        kv(String("incidentId"), Value.string(String("INC-1842"))),
        kv(String("owner"), Value.string(String("Support"))),
        kv(String("targetContext"), Value.string(String("Engineering"))),
        kv(String("missing"), lst(Value.string(String("root_cause")), Value.string(String("reproduction_steps")))),
        kv(String("evidence"), lst(Value.string(String("customer_report")), Value.string(String("application_logs")), Value.string(String("prior_support_notes")))),
    )
    var model = load_domain_model(question.get(String("domain_model")).s)
    var verdict = verify(model, make_result(actual, String("mercury-fixture")))
    var trace = lst(Value.string(String("question.selected")), Value.string(String("domain.completed")), Value.string(String("bridge.normalized")))
    var answer_set = normalize(question, verdict, String(FACIA_SCHEMA_ID), String(FACIA_SCHEMA_SHA256), trace)
    t.not_error(String("Mercury normalizes"), answer_set)
    t.eq_str(String("schema id is pinned"), answer_set.get(String("schema")).s, String(FACIA_SCHEMA_ID))
    t.eq_str(String("answer kind is verdict"), answer_set.get(String("answerType")).s, String("verdict"))
    t.eq_str(String("semantic path is execution"), answer_set.get(String("path")).s, String("execution"))
    t.eq_int(String("one singular item"), answer_set.get(String("items")).len(), 1)
    var item = answer_set.get(String("items")).at(0)
    t.eq_str(String("bounded contract is explicit on wire"), item.get(String("contract")).s, String("BoundedVerdictV1"))
    t.eq_str(String("blocked state survives"), item.get(String("state")).s, String("blocked"))
    t.eq_value(String("conformance survives without derivation"), item.get(String("conforms")), Value.bool(False))
    t.eq_value(
        String("actual incident data survives losslessly"),
        item.get(String("actual")),
        rec(
            kv(String("incidentId"), Value.string(String("INC-1842"))),
            kv(String("owner"), Value.string(String("Support"))),
            kv(String("targetContext"), Value.string(String("Engineering"))),
            kv(String("missing"), lst(Value.string(String("root_cause")), Value.string(String("reproduction_steps")))),
        ),
    )
    t.eq_int(String("evidence survives"), item.get(String("evidence")).len(), 3)
    t.eq_int(String("exactly three operations"), answer_set.get(String("operations")).len(), 3)
    t.eq_str(String("assign reference"), answer_set.get(String("operations")).at(0).get(String("reference")).s, String("mercury.assign_owner"))
    t.eq_str(String("escalate reference"), answer_set.get(String("operations")).at(1).get(String("reference")).s, String("mercury.escalate"))
    t.eq_str(String("comment reference"), answer_set.get(String("operations")).at(2).get(String("reference")).s, String("mercury.add_comment"))
    t.eq_value(String("trace survives"), answer_set.get(String("trace")), trace)
    t.eq_value(
        String("generated consumer golden record matches exactly"),
        answer_set,
        parse_yaml_file(String("facia_bridge/fixtures/mercury-handoff.yaml")),
    )
    t.eq_value(
        String("normalization is deterministic"), answer_set,
        normalize(question, verdict, String(FACIA_SCHEMA_ID), String(FACIA_SCHEMA_SHA256), trace),
    )

    t.section(String("facia bridge / Value and Transform dispatch"))
    var read_only_question = rec(
        kv(String("id"), sym(String("q.value"))),
        kv(String("prompt"), Value.string(String("What is the count?"))),
        kv(String("expected_answer"), sym(String("Value"))),
        kv(String("path"), sym(String("meaning"))),
        kv(String("density"), Value.int(1)),
        kv(String("inspection"), sym(String("available"))),
        kv(String("operations"), lst()),
    )
    var value_set = normalize(read_only_question, Value.int(7), String(FACIA_SCHEMA_ID), String(FACIA_SCHEMA_SHA256), Value.null())
    t.eq_str(String("raw Value dispatch"), value_set.get(String("answerType")).s, String("value"))
    t.eq_value(String("raw Value is preserved"), value_set.get(String("items")).at(0).get(String("value")), Value.int(7))
    t.eq_value(String("read-only answer has no actions"), value_set.get(String("actionable")), Value.bool(False))

    var transform = transform_v1(String("handoff"), String("Handoff"), Value.int(1), Value.int(2), Value.int(0), Value.int(3), lst(sym(String("trace"))))
    var transform_set = normalize(read_only_question, transform, String(FACIA_SCHEMA_ID), String(FACIA_SCHEMA_SHA256), Value.null())
    t.eq_str(String("Transform dispatch"), transform_set.get(String("answerType")).s, String("transform"))
    var transform_item = transform_set.get(String("items")).at(0)
    t.check(String("Domain-only contract marker is not copied"), not transform_item.has(String("contract")), String("wire shape drifted"))
    t.eq_value(String("Transform before survives"), transform_item.get(String("before")), Value.int(0))
    t.eq_value(String("Transform after survives"), transform_item.get(String("after")), Value.int(3))
    t.eq_int(String("Transform evidence survives"), transform_item.get(String("evidence")).len(), 1)

    t.is_error(
        String("unsupported typed output is structured"),
        normalize(question, rec(kv(String("type"), sym(String("Mystery")))), String(FACIA_SCHEMA_ID), String(FACIA_SCHEMA_SHA256), Value.null()),
        String("FACIA_UNSUPPORTED_ANSWER"),
    )

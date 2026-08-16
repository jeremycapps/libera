"""Versioned Domain answer contracts and write-policy compatibility.

These are Domain records built from kernel Values. The kernel remains unaware of
Verdict or Transform semantics. State and conformance are never derived from each
other, and a completed Transform grants no execution authority.
"""

from std.collections import Dict

from kernel.value import Value, BOOL, RECORD, REF, EXPR, LIST
from domain.model import DomainModel


comptime LEGACY_VERDICT = "LegacyBooleanVerdictV0"
comptime BOUNDED_VERDICT = "BoundedVerdictV1"
comptime TRANSFORM_V1 = "TransformV1"
comptime E_ANSWER = "INVALID_DOMAIN_ANSWER"
comptime E_POLICY = "INCOMPATIBLE_VERDICT_POLICY"


fn validate_declared_answer(model: DomainModel, answer: Value) -> Value:
    """Return the original answer when it matches the model's declared contract."""
    # Historical/ad-hoc models may use a verifier as a plain Boolean expression.
    # Only typed Verdict records, or models that explicitly opt into an answer
    # contract, are subject to the versioned wire-shape checks.
    if not model.answer_contract_declared:
        if answer.tag != RECORD or answer.get_or(String("type"), Value.null()).s != String("Verdict"):
            return answer
    if answer.tag != RECORD:
        return Value.error(String(E_ANSWER), String("Domain answer must be a record"))

    if model.answer_contract == String(LEGACY_VERDICT):
        if answer.get_or(String("type"), Value.null()).s != String("Verdict"):
            return Value.error(String(E_ANSWER), String("legacy answer must have type Verdict"))
        if not answer.has(String("conforms")) or answer.get(String("conforms")).tag != BOOL:
            return Value.error(String(E_ANSWER), String("LegacyBooleanVerdictV0 requires conforms: Bool"))
        if answer.has(String("state")):
            return Value.error(String(E_ANSWER), String("LegacyBooleanVerdictV0 forbids state"))
        return answer

    if model.answer_contract == String(BOUNDED_VERDICT):
        if answer.get_or(String("type"), Value.null()).s != String("Verdict"):
            return Value.error(String(E_ANSWER), String("bounded answer must have type Verdict"))
        if not answer.has(String("state")) or not answer.get(String("state")).is_text() or len(answer.get(String("state")).s) == 0:
            return Value.error(String(E_ANSWER), String("BoundedVerdictV1 requires non-empty state"))
        if answer.has(String("conforms")) and answer.get(String("conforms")).tag != BOOL:
            return Value.error(String(E_ANSWER), String("BoundedVerdictV1 conforms must be Bool when present"))
        if not model.conformance_optional and not answer.has(String("conforms")):
            return Value.error(String(E_ANSWER), String("this BoundedVerdictV1 model requires conforms"))
        return answer

    return Value.error(
        String(E_ANSWER),
        String("unknown declared answer contract '") + model.answer_contract + String("'"),
    )


fn transform_v1(
    var operation_id: String,
    var operation_name: String,
    input: Value,
    output: Value,
    before: Value,
    after: Value,
    evidence: Value,
) -> Value:
    if len(operation_id) == 0 or len(operation_name) == 0:
        return Value.error(String(E_ANSWER), String("TransformV1 operation id and name must be non-empty"))
    var operation = Dict[String, Value]()
    operation[String("id")] = Value.string(operation_id^)
    operation[String("name")] = Value.string(operation_name^)
    var d = Dict[String, Value]()
    d[String("type")] = Value.symbol(String("Transform"))
    d[String("contract")] = Value.symbol(String(TRANSFORM_V1))
    d[String("operation")] = Value.record(operation^)
    d[String("input")] = input.copy()
    d[String("output")] = output.copy()
    if not before.is_null():
        d[String("before")] = before.copy()
    if not after.is_null():
        d[String("after")] = after.copy()
    if not evidence.is_null():
        d[String("evidence")] = evidence.copy()
    return Value.record(d^)


fn validate_transform(answer: Value) -> Value:
    if answer.tag != RECORD or answer.get_or(String("type"), Value.null()).s != String("Transform"):
        return Value.error(String(E_ANSWER), String("TransformV1 requires type Transform"))
    if not answer.has(String("operation")) or not answer.has(String("input")) or not answer.has(String("output")):
        return Value.error(String(E_ANSWER), String("TransformV1 requires operation, input, and output"))
    var operation = answer.get(String("operation"))
    if operation.tag != RECORD or not operation.has(String("id")) or not operation.has(String("name")):
        return Value.error(String(E_ANSWER), String("TransformV1 operation requires id and name"))
    if not operation.get(String("id")).is_text() or len(operation.get(String("id")).s) == 0:
        return Value.error(String(E_ANSWER), String("TransformV1 operation id must be non-empty"))
    if not operation.get(String("name")).is_text() or len(operation.get(String("name")).s) == 0:
        return Value.error(String(E_ANSWER), String("TransformV1 operation name must be non-empty"))
    return answer


fn _mentions_conformance(value: Value) -> Bool:
    if value.tag == REF:
        return value.s == String("output.conforms") or value.s == String("verdict.conforms")
    if value.tag == LIST or value.tag == EXPR or value.tag == REF:
        for i in range(value.len()):
            if _mentions_conformance(value.at(i)):
                return True
    if value.tag == RECORD or value.tag == EXPR:
        for key in value.fields[].keys():
            var k = key.copy()
            if _mentions_conformance(value.fields[].get(k).value()):
                return True
    return False


fn validate_model_policy(model: DomainModel, policy: Value) -> Value:
    """Reject an optional-conformance model before its first fold can emit writes."""
    if model.answer_contract == String(BOUNDED_VERDICT) and model.conformance_optional and _mentions_conformance(policy):
        var detail = Dict[String, Value]()
        detail[String("model")] = Value.string(model.name.copy())
        detail[String("policy")] = Value.string(model.write_policy.copy())
        return Value.error_with(
            String(E_POLICY),
            String("bounded verdict model may omit conforms, but its policy dereferences conforms"),
            detail^,
        )
    return Value.bool(True)

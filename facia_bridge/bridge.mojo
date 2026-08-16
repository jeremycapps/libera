"""Normalize completed Libera answers into the schema-pinned Facia wire record.

This top layer may import Domain. It contains no shape, pattern, affordance, or
renderer decisions; those remain owned by Facia after validation.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, LIST
from modelir.yaml import parse_yaml_file
from facia_bridge.schema_pin import FACIA_SCHEMA_ID, FACIA_SCHEMA_SHA256


comptime E_SCHEMA_ID = "FACIA_SCHEMA_ID_MISMATCH"
comptime E_SCHEMA_HASH = "FACIA_SCHEMA_HASH_MISMATCH"
comptime E_NORMALIZE = "FACIA_NORMALIZATION_ERROR"
comptime E_UNSUPPORTED = "FACIA_UNSUPPORTED_ANSWER"


fn load_question(path: String) raises -> Value:
    var question = parse_yaml_file(path)
    if question.is_error():
        return question^
    if question.tag != RECORD or not question.has(String("id")) or not question.has(String("prompt")):
        return Value.error(String(E_NORMALIZE), String("question declaration requires id and prompt"))
    return question^


fn verify_schema_pin(var schema_id: String, var schema_hash: String) -> Value:
    if schema_id != String(FACIA_SCHEMA_ID):
        return Value.error(
            String(E_SCHEMA_ID),
            String("expected ") + String(FACIA_SCHEMA_ID) + String(", got ") + schema_id,
        )
    if schema_hash != String(FACIA_SCHEMA_SHA256):
        return Value.error(
            String(E_SCHEMA_HASH),
            String("expected ") + String(FACIA_SCHEMA_SHA256) + String(", got ") + schema_hash,
        )
    return Value.bool(True)


fn _wire_text(value: Value, var field: String) -> Value:
    if not value.is_text() or len(value.s) == 0:
        var name = field^
        return Value.error(String(E_NORMALIZE), name + String(" must be non-empty text"))
    return Value.string(value.s.copy())


fn _copy_optional(answer: Value, mut out: Dict[String, Value], var key: String):
    if answer.has(key):
        out[key.copy()] = answer.get(key)


fn _verdict_item(question: Value, answer: Value) -> Value:
    if not answer.has(String("conforms")) and not answer.has(String("state")):
        return Value.error(String(E_NORMALIZE), String("Verdict requires conforms or state"))
    var contract = question.get(String("expected_answer"))
    if contract.is_error() or not contract.is_text():
        return Value.error(String(E_NORMALIZE), String("question must declare expected_answer"))
    var out = Dict[String, Value]()
    out[String("type")] = Value.string(String("Verdict"))
    out[String("contract")] = Value.string(contract.s.copy())
    if answer.has(String("state")):
        var state = _wire_text(answer.get(String("state")), String("Verdict state"))
        if state.is_error():
            return state^
        out[String("state")] = state^
    _copy_optional(answer, out, String("conforms"))
    _copy_optional(answer, out, String("finding"))
    _copy_optional(answer, out, String("reason"))
    _copy_optional(answer, out, String("expected"))
    _copy_optional(answer, out, String("actual"))
    _copy_optional(answer, out, String("evidence"))
    return Value.record(out^)


fn _transform_item(answer: Value) -> Value:
    if not answer.has(String("operation")) or not answer.has(String("input")) or not answer.has(String("output")):
        return Value.error(String(E_NORMALIZE), String("Transform requires operation, input, and output"))
    var out = Dict[String, Value]()
    out[String("type")] = Value.string(String("Transform"))
    out[String("operation")] = answer.get(String("operation"))
    out[String("input")] = answer.get(String("input"))
    out[String("output")] = answer.get(String("output"))
    _copy_optional(answer, out, String("before"))
    _copy_optional(answer, out, String("after"))
    _copy_optional(answer, out, String("evidence"))
    return Value.record(out^)


fn _wire_operations(operations: Value) -> Value:
    if operations.tag != LIST:
        return Value.error(String(E_NORMALIZE), String("question operations must be a list"))
    var items = List[Value]()
    for i in range(operations.len()):
        var operation = operations.at(i)
        if operation.tag != RECORD:
            return Value.error(String(E_NORMALIZE), String("operation descriptor must be a record"))
        var out = Dict[String, Value]()
        var required = List[String]()
        required.append(String("id"))
        required.append(String("label"))
        required.append(String("invocation"))
        required.append(String("reference"))
        for j in range(len(required)):
            var key = required[j]
            if not operation.has(key):
                return Value.error(String(E_NORMALIZE), String("operation descriptor missing ") + key)
            var text = _wire_text(operation.get(key), key)
            if text.is_error():
                return text^
            out[key.copy()] = text^
        _copy_optional(operation, out, String("inputSchema"))
        if operation.has(String("confirmation")):
            var confirmation = _wire_text(operation.get(String("confirmation")), String("confirmation"))
            if confirmation.is_error():
                return confirmation^
            out[String("confirmation")] = confirmation^
        items.append(Value.record(out^))
    return Value.list(items^)


fn normalize(
    question: Value,
    answer: Value,
    var schema_id: String,
    var schema_hash: String,
    trace: Value,
) -> Value:
    var pin = verify_schema_pin(schema_id^, schema_hash^)
    if pin.is_error():
        return pin^
    if question.tag != RECORD:
        return Value.error(String(E_NORMALIZE), String("question must be a record"))

    var answer_type = String("value")
    var item: Value
    if answer.tag == RECORD and answer.get_or(String("type"), Value.null()).is_text():
        var kind = answer.get(String("type")).s
        if kind == String("Verdict"):
            answer_type = String("verdict")
            item = _verdict_item(question, answer)
        elif kind == String("Transform"):
            answer_type = String("transform")
            item = _transform_item(answer)
        elif kind == String("Value") and answer.has(String("value")):
            var wrapped = Dict[String, Value]()
            wrapped[String("type")] = Value.string(String("Value"))
            wrapped[String("value")] = answer.get(String("value"))
            _copy_optional(answer, wrapped, String("evidence"))
            item = Value.record(wrapped^)
        else:
            return Value.error(String(E_UNSUPPORTED), String("unsupported typed Domain answer"))
    else:
        var wrapped = Dict[String, Value]()
        wrapped[String("type")] = Value.string(String("Value"))
        wrapped[String("value")] = answer.copy()
        item = Value.record(wrapped^)
    if item.is_error():
        return item^

    var items = List[Value]()
    items.append(item^)
    var operations = _wire_operations(question.get_or(String("operations"), Value.list(List[Value]())))
    if operations.is_error():
        return operations^

    var prompt = _wire_text(question.get(String("prompt")), String("question prompt"))
    if prompt.is_error():
        return prompt^
    var path = _wire_text(question.get_or(String("path"), Value.string(String("meaning"))), String("path"))
    if path.is_error():
        return path^
    var inspection = _wire_text(question.get_or(String("inspection"), Value.string(String("none"))), String("inspection"))
    if inspection.is_error():
        return inspection^

    var out = Dict[String, Value]()
    out[String("schema")] = Value.string(String(FACIA_SCHEMA_ID))
    out[String("question")] = prompt^
    out[String("answerType")] = Value.string(answer_type^)
    out[String("path")] = path^
    out[String("density")] = question.get_or(String("density"), Value.int(1))
    out[String("inspection")] = inspection^
    out[String("actionable")] = Value.bool(operations.len() > 0)
    out[String("items")] = Value.list(items^)
    out[String("operations")] = operations^
    if not trace.is_null():
        out[String("trace")] = trace.copy()
    return Value.record(out^)

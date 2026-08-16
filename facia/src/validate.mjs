const ERROR = (code, path, message) => ({ code, path, message });

const ITEM_TYPE = { value: "Value", verdict: "Verdict", transform: "Transform" };

function validOperation(operation) {
  return operation && typeof operation === "object" && !Array.isArray(operation)
    && typeof operation.id === "string" && operation.id.length > 0
    && typeof operation.label === "string" && operation.label.length > 0
    && ["model-operation", "host-callback"].includes(operation.invocation)
    && typeof operation.reference === "string" && operation.reference.length > 0
    && (operation.inputSchema === undefined || (operation.inputSchema && typeof operation.inputSchema === "object" && !Array.isArray(operation.inputSchema)))
    && (operation.confirmation === undefined || (typeof operation.confirmation === "string" && operation.confirmation.length > 0));
}

function validItem(item, answerType) {
  if (!item || typeof item !== "object" || Array.isArray(item) || item.type !== ITEM_TYPE[answerType]) return false;
  if (answerType === "value") return Object.hasOwn(item, "value");
  if (answerType === "verdict") {
    if (item.contract === "LegacyBooleanVerdictV0") return typeof item.conforms === "boolean" && !Object.hasOwn(item, "state");
    if (item.contract === "BoundedVerdictV1") return typeof item.state === "string" && item.state.length > 0 && (item.conforms === undefined || typeof item.conforms === "boolean");
    return false;
  }
  return item.operation && typeof item.operation.id === "string" && item.operation.id.length > 0
    && typeof item.operation.name === "string" && item.operation.name.length > 0
    && Object.hasOwn(item, "input") && Object.hasOwn(item, "output");
}

export function validateAnswerSet(value) {
  const errors = [];
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { valid: false, errors: [ERROR("INVALID_ANSWER_SET", "$", "answer set must be an object")] };
  }
  if (value.schema !== "facia.answer-set/1") errors.push(ERROR("ANSWER_SET_SCHEMA_UNSUPPORTED", "$.schema", "expected facia.answer-set/1"));
  if (!Array.isArray(value.items) || value.items.length === 0) errors.push(ERROR("ANSWER_SET_EMPTY_ITEMS", "$.items", "items must be non-empty"));
  if (![1, 2, 3].includes(value.density)) errors.push(ERROR("INVALID_DENSITY", "$.density", "density must be 1, 2, or 3"));

  if (Array.isArray(value.items) && value.items.length > 0) {
    if (!["value", "verdict", "transform"].includes(value.answerType) || value.items.some(item => !validItem(item, value.answerType))) {
      errors.push(ERROR("ANSWER_KIND_MISMATCH", "$.items", "every item must match answerType and its versioned contract"));
    }
    if (value.items.length === 1 && (value.structure !== undefined || value.sequenceKind !== undefined)) {
      errors.push(ERROR("SINGULAR_STRUCTURE_FORBIDDEN", "$.structure", "singular records forbid structure and sequenceKind"));
    }
  }

  if (value.structure === "sequence" && !["temporal", "dependency", "trace"].includes(value.sequenceKind)) {
    errors.push(ERROR("SEQUENCE_KIND_REQUIRED", "$.sequenceKind", "sequence structure requires sequenceKind"));
  } else if (value.structure !== "sequence" && value.sequenceKind !== undefined) {
    errors.push(ERROR("SEQUENCE_KIND_FORBIDDEN", "$.sequenceKind", "sequenceKind is only valid for sequence structure"));
  }

  const operations = Array.isArray(value.operations) ? value.operations : [];
  if (!Array.isArray(value.operations) || operations.some(op => !validOperation(op))) {
    errors.push(ERROR("INVALID_OPERATION_DESCRIPTOR", "$.operations", "operations must contain complete v1 descriptors"));
  }
  const ids = operations.map(op => op && op.id);
  if (new Set(ids).size !== ids.length) errors.push(ERROR("DUPLICATE_OPERATION_ID", "$.operations", "operation ids must be unique"));
  if (typeof value.actionable !== "boolean" || value.actionable !== (operations.length > 0)) {
    errors.push(ERROR("ACTIONABILITY_MISMATCH", "$.actionable", "actionable must equal operations.length > 0"));
  }

  if (typeof value.question !== "string" || value.question.length === 0
      || !["meaning", "execution"].includes(value.path)
      || !["none", "available"].includes(value.inspection)
      || (value.structure !== undefined && !["dimension", "group", "sequence"].includes(value.structure))) {
    errors.push(ERROR("INVALID_ANSWER_SET", "$", "required fields or enums are invalid"));
  }
  return errors.length ? { valid: false, errors } : { valid: true, value };
}

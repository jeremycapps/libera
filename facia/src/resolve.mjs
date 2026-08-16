import { validateAnswerSet } from "./validate.mjs";

const SHAPE_REASONS = {
  "singular-value": "SHAPE_SINGULAR_VALUE",
  "singular-verdict": "SHAPE_SINGULAR_VERDICT",
  "singular-transform": "SHAPE_SINGULAR_TRANSFORM",
  collection: "SHAPE_COLLECTION",
  dimension: "SHAPE_DIMENSION",
  group: "SHAPE_GROUP",
  "temporal-sequence": "SHAPE_TEMPORAL_SEQUENCE",
  "dependency-sequence": "SHAPE_DEPENDENCY_SEQUENCE",
  "trace-sequence": "SHAPE_TRACE_SEQUENCE"
};

export function resolveShape(answerSet) {
  const validation = validateAnswerSet(answerSet);
  if (!validation.valid) return { ok: false, code: "INVALID_ANSWER_SET", errors: validation.errors };
  let shape;
  if (answerSet.items.length === 1) shape = `singular-${answerSet.answerType}`;
  else if (!answerSet.structure) shape = "collection";
  else if (answerSet.structure === "sequence") shape = `${answerSet.sequenceKind}-sequence`;
  else shape = answerSet.structure;
  return { ok: true, shape, reasonCode: SHAPE_REASONS[shape], explanation: `Item count and declared structure resolve deterministically to ${shape}.` };
}

const result = (family, variant, reasonCode) => ({
  ok: true, family, variant, reasonCode,
  explanation: `${reasonCode} selects the renderer-independent ${variant} pattern.`
});

export function resolvePattern(shapeResult, answerSet) {
  const validation = validateAnswerSet(answerSet);
  if (!validation.valid) return { ok: false, code: "VALIDATION_REQUIRED", errors: validation.errors };
  const shape = shapeResult?.ok ? shapeResult.shape : shapeResult?.shape;
  if (!shape) return { ok: false, code: "SHAPE_REQUIRED", explanation: "resolveShape must succeed before resolvePattern" };
  const actionable = answerSet.actionable;
  const density = answerSet.density;
  const kind = answerSet.answerType;

  if (shape === "singular-verdict" && actionable) return result("detail", "review-panel", "PATTERN_ACTIONABLE_VERDICT");
  if (shape === "singular-transform" && actionable) return result("detail", "action-panel", "PATTERN_ACTIONABLE_TRANSFORM");
  if (shape === "singular-value" && actionable) return result("form", "edit-form", "PATTERN_ACTIONABLE_VALUE");
  if (shape === "singular-transform") return result("detail", "transition-detail", "PATTERN_TRANSFORM_DETAIL");
  if (shape === "singular-verdict" && density === 1) return result("status", "badge", "PATTERN_COMPACT_VERDICT");
  if (shape === "singular-verdict") return result("detail", "detail", "PATTERN_DENSE_VERDICT");
  if (shape === "singular-value" && density === 1 && ["string", "number", "boolean"].includes(typeof answerSet.items[0].value)) return result("metric", "stat", "PATTERN_COMPACT_SCALAR");
  if (shape === "singular-value" && density === 1) return result("detail", "compact-card", "PATTERN_COMPACT_OBJECT");
  if (shape === "singular-value") return result("detail", "detail", "PATTERN_DENSE_VALUE");
  if (shape === "collection" && density <= 2) return result("collection", "list", "PATTERN_COLLECTION_LIST");
  if (shape === "collection") return result("collection", "grid", "PATTERN_COLLECTION_GRID");
  if (shape === "dimension" && density <= 2) return result("comparison", "table", "PATTERN_DIMENSION_TABLE");
  if (shape === "dimension") return result("comparison", "comparison-matrix", "PATTERN_DIMENSION_MATRIX");
  if (shape === "group" && kind === "transform") return result("workflow", "board", "PATTERN_TRANSFORM_BOARD");
  if (shape === "group" && actionable && answerSet.path === "execution") return result("workflow", "queue", "PATTERN_ACTION_QUEUE");
  if (shape === "group") return result("collection", "grouped-list", "PATTERN_GROUPED_LIST");
  if (shape === "temporal-sequence") return result("sequence", "timeline", "PATTERN_TEMPORAL_TIMELINE");
  if (shape === "dependency-sequence" && density === 1) return result("sequence", "dependency-list", "PATTERN_DEPENDENCY_LIST");
  if (shape === "dependency-sequence") return result("sequence", "dependency-tree", "PATTERN_DEPENDENCY_TREE");
  if (shape === "trace-sequence" && actionable && kind === "transform") return result("sequence", "replay-panel", "PATTERN_ACTIONABLE_REPLAY");
  if (shape === "trace-sequence") return result("sequence", "audit-trail", "PATTERN_TRACE_AUDIT");
  return { ok: false, code: "PATTERN_UNSUPPORTED", explanation: `No PatternSpec v1 rule matches ${shape}.` };
}

import { validateAnswerSet } from "./validate.mjs";

export function resolveAffordances(answerSet, shapeResult = undefined) {
  const validation = validateAnswerSet(answerSet);
  if (!validation.valid) return { ok: false, code: "VALIDATION_REQUIRED", errors: validation.errors };
  const shape = shapeResult?.shape ?? "";
  const inspection = [];
  if (answerSet.inspection === "available") {
    inspection.push("inspect", "expand");
    if (answerSet.items.length > 1) inspection.push("filter", "sort");
    if (answerSet.structure === "dimension") inspection.push("compare", "drill-down");
    if (answerSet.items.some(item => item.evidence !== undefined)) inspection.push("view-evidence");
    if (shape === "trace-sequence" || answerSet.trace !== undefined) inspection.push("view-trace");
  }
  const actions = answerSet.actionable ? answerSet.operations.map(operation => ({
    id: operation.id,
    label: operation.label,
    invocation: operation.invocation,
    reference: operation.reference,
    inputSchema: operation.inputSchema,
    confirmation: operation.confirmation
  })) : [];
  return { ok: true, inspection: [...new Set(inspection)], actions };
}

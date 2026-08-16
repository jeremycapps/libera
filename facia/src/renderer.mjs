const RECIPE = {
  "review-panel": ["Card", "StateBadge", "DetailList", "EvidenceDisclosure", "OperationControls"],
  table: ["DataTable", "InspectionToolbar"],
  queue: ["QueueList", "InspectionToolbar", "OperationControls"],
  board: ["Board", "InspectionToolbar", "OperationControls"],
  timeline: ["Timeline", "InspectionToolbar"],
  "audit-trail": ["AuditTrail", "EvidenceDisclosure"],
  "replay-panel": ["ReplayPanel", "EvidenceDisclosure", "OperationControls"],
  "action-panel": ["Card", "TransitionDetail", "EvidenceDisclosure", "OperationControls"],
  "edit-form": ["Form", "OperationControls"]
};

export function toComponentRecipe(pattern, affordances, answerSet) {
  if (!pattern?.ok || !affordances?.ok) return { ok: false, code: "SEMANTIC_SPEC_REQUIRED" };
  const components = RECIPE[pattern.variant] ?? ["SemanticSurface"];
  return {
    ok: true,
    recipe: pattern.variant,
    components,
    inspectionControls: affordances.inspection,
    actionControls: affordances.actions.map(action => ({
      id: action.id,
      label: action.label,
      registryReference: action.reference,
      invocation: action.invocation
    })),
    answer: answerSet,
    boundary: "Renderer consumes semantic specs; it does not evaluate Domain truth."
  };
}

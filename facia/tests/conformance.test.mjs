import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { validateAnswerSet, resolveShape, resolvePattern, resolveAffordances, toComponentRecipe } from "../src/index.mjs";

const fixture = async name => JSON.parse(await readFile(new URL(`../fixtures/${name}`, import.meta.url), "utf8"));
const operation = { id: "go", label: "Go", invocation: "model-operation", reference: "test.go" };
const valueItem = { type: "Value", value: 1 };
const verdictItem = { type: "Verdict", contract: "BoundedVerdictV1", state: "ready" };
const transformItem = { type: "Transform", operation: { id: "t", name: "Transform" }, input: 1, output: 2 };

function answer(overrides = {}) {
  return {
    schema: "facia.answer-set/1", question: "Q?", answerType: "value", path: "meaning",
    density: 1, inspection: "available", actionable: false, items: [valueItem], operations: [],
    ...overrides
  };
}

test("manifest pins the exact canonical schema hash", async () => {
  const manifest = await fixture("manifest.json");
  const schema = await readFile(new URL("../schemas/facia-answer-set.v1.schema.json", import.meta.url));
  assert.equal(JSON.parse(schema).$id, "facia.answer-set/1");
  assert.equal(manifest.schema, "facia.answer-set/1");
  assert.equal(manifest.schemaSha256, createHash("sha256").update(schema).digest("hex"));
});

test("golden fixtures validate and round-trip without semantic change", async () => {
  const manifest = await fixture("manifest.json");
  for (const name of manifest.fixtures) {
    const record = await fixture(name);
    assert.deepEqual(validateAnswerSet(record), { valid: true, value: record });
    assert.deepEqual(JSON.parse(JSON.stringify(record)), record);
  }
});

test("validation covers every stable invalid-case code", () => {
  const cases = [
    ["ANSWER_SET_SCHEMA_UNSUPPORTED", { schema: "facia.answer-set/2" }],
    ["ANSWER_SET_EMPTY_ITEMS", { items: [] }],
    ["ANSWER_KIND_MISMATCH", { answerType: "verdict" }],
    ["INVALID_DENSITY", { density: 4 }],
    ["SINGULAR_STRUCTURE_FORBIDDEN", { structure: "group" }],
    ["SEQUENCE_KIND_REQUIRED", { items: [valueItem, valueItem], structure: "sequence" }],
    ["SEQUENCE_KIND_FORBIDDEN", { items: [valueItem, valueItem], structure: "group", sequenceKind: "trace" }],
    ["ACTIONABILITY_MISMATCH", { actionable: true }],
    ["DUPLICATE_OPERATION_ID", { actionable: true, operations: [operation, operation] }],
    ["INVALID_OPERATION_DESCRIPTOR", { actionable: true, operations: [{ id: "bad" }] }]
  ];
  for (const [code, overrides] of cases) {
    const result = validateAnswerSet(answer(overrides));
    assert.equal(result.valid, false, code);
    assert.ok(result.errors.some(error => error.code === code), code);
  }
});

test("valid structural combinations resolve to all nine shapes", () => {
  const cases = [
    ["singular-value", answer()],
    ["singular-verdict", answer({ answerType: "verdict", items: [verdictItem] })],
    ["singular-transform", answer({ answerType: "transform", items: [transformItem] })],
    ["collection", answer({ items: [valueItem, valueItem] })],
    ["dimension", answer({ items: [valueItem, valueItem], structure: "dimension" })],
    ["group", answer({ items: [valueItem, valueItem], structure: "group" })],
    ["temporal-sequence", answer({ items: [valueItem, valueItem], structure: "sequence", sequenceKind: "temporal" })],
    ["dependency-sequence", answer({ items: [valueItem, valueItem], structure: "sequence", sequenceKind: "dependency" })],
    ["trace-sequence", answer({ items: [valueItem, valueItem], structure: "sequence", sequenceKind: "trace" })]
  ];
  for (const [expected, record] of cases) assert.equal(resolveShape(record).shape, expected);
});

function expectedPattern(shape, kind, path, density, actionable, scalar = true) {
  if (shape === "singular-verdict" && actionable) return ["review-panel", "PATTERN_ACTIONABLE_VERDICT"];
  if (shape === "singular-transform" && actionable) return ["action-panel", "PATTERN_ACTIONABLE_TRANSFORM"];
  if (shape === "singular-value" && actionable) return ["edit-form", "PATTERN_ACTIONABLE_VALUE"];
  if (shape === "singular-transform") return ["transition-detail", "PATTERN_TRANSFORM_DETAIL"];
  if (shape === "singular-verdict" && density === 1) return ["badge", "PATTERN_COMPACT_VERDICT"];
  if (shape === "singular-verdict") return ["detail", "PATTERN_DENSE_VERDICT"];
  if (shape === "singular-value" && density === 1 && scalar) return ["stat", "PATTERN_COMPACT_SCALAR"];
  if (shape === "singular-value" && density === 1) return ["compact-card", "PATTERN_COMPACT_OBJECT"];
  if (shape === "singular-value") return ["detail", "PATTERN_DENSE_VALUE"];
  if (shape === "collection") return density <= 2 ? ["list", "PATTERN_COLLECTION_LIST"] : ["grid", "PATTERN_COLLECTION_GRID"];
  if (shape === "dimension") return density <= 2 ? ["table", "PATTERN_DIMENSION_TABLE"] : ["comparison-matrix", "PATTERN_DIMENSION_MATRIX"];
  if (shape === "group" && kind === "transform") return ["board", "PATTERN_TRANSFORM_BOARD"];
  if (shape === "group" && actionable && path === "execution") return ["queue", "PATTERN_ACTION_QUEUE"];
  if (shape === "group") return ["grouped-list", "PATTERN_GROUPED_LIST"];
  if (shape === "temporal-sequence") return ["timeline", "PATTERN_TEMPORAL_TIMELINE"];
  if (shape === "dependency-sequence") return density === 1 ? ["dependency-list", "PATTERN_DEPENDENCY_LIST"] : ["dependency-tree", "PATTERN_DEPENDENCY_TREE"];
  if (shape === "trace-sequence" && actionable && kind === "transform") return ["replay-panel", "PATTERN_ACTIONABLE_REPLAY"];
  return ["audit-trail", "PATTERN_TRACE_AUDIT"];
}

test("decision table is exhaustive and deterministic across valid metadata combinations", () => {
  const shapeInputs = [
    ["singular-value", "value", [valueItem], {}],
    ["singular-verdict", "verdict", [verdictItem], {}],
    ["singular-transform", "transform", [transformItem], {}],
    ["collection", "value", [valueItem, valueItem], {}],
    ["dimension", "value", [valueItem, valueItem], { structure: "dimension" }],
    ["group", "value", [valueItem, valueItem], { structure: "group" }],
    ["group", "transform", [transformItem, transformItem], { structure: "group" }],
    ["temporal-sequence", "value", [valueItem, valueItem], { structure: "sequence", sequenceKind: "temporal" }],
    ["dependency-sequence", "value", [valueItem, valueItem], { structure: "sequence", sequenceKind: "dependency" }],
    ["trace-sequence", "value", [valueItem, valueItem], { structure: "sequence", sequenceKind: "trace" }],
    ["trace-sequence", "transform", [transformItem, transformItem], { structure: "sequence", sequenceKind: "trace" }]
  ];
  let rows = 0;
  for (const [expectedShape, kind, items, structure] of shapeInputs) for (const path of ["meaning", "execution"]) for (const density of [1, 2, 3]) for (const actionable of [false, true]) {
    const record = answer({ answerType: kind, items, path, density, ...structure, actionable, operations: actionable ? [operation] : [] });
    const shape = resolveShape(record);
    assert.equal(shape.shape, expectedShape);
    const first = resolvePattern(shape, record);
    const second = resolvePattern(shape, record);
    assert.deepEqual(first, second);
    const [variant, reasonCode] = expectedPattern(expectedShape, kind, path, density, actionable);
    assert.equal(first.variant, variant, `${expectedShape}/${kind}/${path}/${density}/${actionable}`);
    assert.equal(first.reasonCode, reasonCode);
    assert.ok(!["calendar", "schedule"].includes(first.variant));
    rows += 1;
  }
  assert.equal(rows, 132);
});

test("inspection and actions are separate and operations map one-to-one", async () => {
  const mercury = await fixture("mercury-handoff.json");
  const shape = resolveShape(mercury);
  const affordances = resolveAffordances(mercury, shape);
  assert.deepEqual(affordances.inspection, ["inspect", "expand", "view-evidence", "view-trace"]);
  assert.deepEqual(affordances.actions.map(action => action.reference), ["mercury.assign_owner", "mercury.escalate", "mercury.add_comment"]);
  const readOnly = resolveAffordances(answer({ items: [valueItem, valueItem] }), { shape: "collection" });
  assert.deepEqual(readOnly.actions, []);
  assert.deepEqual(readOnly.inspection, ["inspect", "expand", "filter", "sort"]);
});

test("Mercury resolves end to end to a review-panel recipe", async () => {
  const mercury = await fixture("mercury-handoff.json");
  const shape = resolveShape(mercury);
  const pattern = resolvePattern(shape, mercury);
  const affordances = resolveAffordances(mercury, shape);
  const recipe = toComponentRecipe(pattern, affordances, mercury);
  assert.equal(shape.shape, "singular-verdict");
  assert.equal(pattern.variant, "review-panel");
  assert.equal(pattern.reasonCode, "PATTERN_ACTIONABLE_VERDICT");
  assert.equal(recipe.actionControls.length, 3);
  assert.deepEqual(recipe.actionControls.map(control => control.registryReference), ["mercury.assign_owner", "mercury.escalate", "mercury.add_comment"]);
});

test("static fixtures expose representative surfaces, states, and accessibility hooks", async () => {
  const html = await readFile(new URL("../prototype/index.html", import.meta.url), "utf8");
  for (const surface of ["review-panel", "table", "queue", "board", "timeline", "audit-trail", "replay-panel"]) assert.match(html, new RegExp(surface));
  for (const state of ["Loading", "Empty", "Validation error", "Operation unavailable"]) assert.match(html, new RegExp(state));
  for (const reference of ["mercury.assign_owner", "mercury.escalate", "mercury.add_comment"]) assert.match(html, new RegExp(reference));
  assert.match(html, /aria-live="polite"/);
  assert.match(html, /focus-visible/);
  assert.match(html, /@media \(max-width:800px\)/);
});

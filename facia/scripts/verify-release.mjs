import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { validateAnswerSet, resolveShape, resolvePattern, resolveAffordances, toComponentRecipe } from "../src/index.mjs";

const root = new URL("../", import.meta.url);
const manifest = JSON.parse(await readFile(new URL("fixtures/manifest.json", root), "utf8"));
const schema = await readFile(new URL("schemas/facia-answer-set.v1.schema.json", root));
const hash = createHash("sha256").update(schema).digest("hex");
if (hash !== manifest.schemaSha256) throw new Error(`SCHEMA_HASH_MISMATCH: expected ${manifest.schemaSha256}, got ${hash}`);
for (const name of manifest.fixtures) {
  const record = JSON.parse(await readFile(new URL(`fixtures/${name}`, root), "utf8"));
  const validation = validateAnswerSet(record);
  if (!validation.valid) throw new Error(`${name}: ${JSON.stringify(validation.errors)}`);
  const shape = resolveShape(record);
  const pattern = resolvePattern(shape, record);
  const affordances = resolveAffordances(record, shape);
  if (!toComponentRecipe(pattern, affordances, record).ok) throw new Error(`${name}: renderer recipe failed`);
}
console.log(`Facia release verified: ${manifest.schema} sha256:${hash} (${manifest.fixtures.length} golden fixtures)`);

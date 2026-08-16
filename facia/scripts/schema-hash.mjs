import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const bytes = await readFile(new URL("../schemas/facia-answer-set.v1.schema.json", import.meta.url));
console.log(createHash("sha256").update(bytes).digest("hex"));

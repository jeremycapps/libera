# Libera–Facia AnswerSet v1 release seam

The question-to-interface contract has one canonical serialized boundary. Facia owns
`facia/schemas/facia-answer-set.v1.schema.json`, the TypeScript contract and validator,
the shape/pattern/affordance resolvers, renderer recipes, and golden surface fixtures.
Libera owns declared question models, Domain and Strategy execution, the top-layer
`facia_bridge/` normalizer, and its consumer-side conformance copies.

Libera must not copy Facia resolver or renderer behavior. The bridge only normalizes a
completed answer into a renderer-neutral record. Facia must not evaluate Domain models,
infer a business verdict, or invent executable operations.

## Version pin

Every bridge invocation supplies both:

- schema id `facia.answer-set/1`; and
- the SHA-256 of the exact canonical schema bytes.

The current pin is recorded in `facia/fixtures/manifest.json` and
`facia_bridge/schema_pin.mojo`. A schema-id mismatch returns
`FACIA_SCHEMA_ID_MISMATCH`; a content-hash mismatch returns
`FACIA_SCHEMA_HASH_MISMATCH`. Neither side attempts best-effort conversion.

## Answer contracts

`LegacyBooleanVerdictV0` requires `conforms: Bool` and forbids `state`.
`BoundedVerdictV1` requires a non-empty `state` and permits, but does not require,
`conforms`. Neither field is derived from the other, and state names never imply
convergence. Optional `finding`, `reason`, `expected`, `actual`, and `evidence` values
remain lossless.

`TransformV1` requires an operation id/name plus input and output. Optional before,
after, and evidence values remain lossless. A Transform is an answer record, not
execution authority; Strategy still owns selection, retry, repair, search, and
escalation.

## Deterministic update procedure

1. Change the canonical JSON Schema in Facia.
2. Run `node facia/scripts/schema-hash.mjs` and update the manifest and Libera pin to the
   printed SHA-256 in the same release change.
3. Regenerate or edit Facia golden records, then run `npm test` and `npm run verify` in
   `facia/`.
4. Copy only released schema metadata and golden records required for consumer
   conformance into `facia_bridge/fixtures/`; never copy resolvers or renderer code.
5. Run `./run_tests.sh` and `./verify_release.sh`. A schema change without a matching pin
   fails deterministically.

Release order is Facia schema/types/fixtures first, followed by the Libera pin and bridge.
Consumers verify metadata before deserializing any record.

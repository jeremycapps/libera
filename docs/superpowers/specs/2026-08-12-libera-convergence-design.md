# Libera convergence: addressed writes in the model runtime

**Date:** 2026-08-12
**Status:** approved design, not yet implemented
**Scope:** folding `github.com/jeremycapps/libera` into the Mojo model runtime as a
write-addressing layer

## Problem

Two projects share a name and nothing else:

- `~/Dev/libera` — the Mojo runtime built from *Model Kernel, Domain, and Strategy
  Architecture*. Kernel (K0) and Domain (D0, D1) are complete; Strategy is not built.
- `github.com/jeremycapps/libera` — a published spec, *"a small open spec for defining
  replayable program state addresses."*

A proposal ("the finding") argued for importing Libera as an "addressed motion" layer.
This spec assesses that proposal against the actual repository, and defines how the two
converge into one runtime.

## Assessment of the finding

Verified correct against `protocol/libera.schema.yaml`:

- the `{pressure}/{operation}/{slot}` path format
- the six pairs: boundary enter/exit, movement advance/change, exception detect/respond
- the anti-domain-core discipline; `docs/migration_v1_to_v2.md` closes with
  *"Libera v2 defines motion. Domain defines meaning."*

Incorrect or omitted:

1. **`program` is required.** The v2 schema requires `[program, pressure, operation,
   slot]`, and real paths in `examples/protocol_design/paths.yaml` also carry an `id`.
   The finding's grammar is three-part and drops both. A Libera path is a record with
   identity, not a slash-string — and identity is what makes it replayable.
2. **The repo is mid-migration.** Only `protocol/` and `examples/protocol_design/` are
   v2. Root `libera.yaml`, both files in `schemas/`, `docs/logic.md`, and
   `docs/fields.md` are still v1.0.0 with the twelve domain types v2 claims to remove.
   "Libera removes business concepts" is true of one file and contradicted by five.
3. **`docs/fields.md` was omitted**, and it is the most valuable survivor. See §6.
4. **Replay is already owned by Timpos and Corus.** Per `docs/timpos_compatibility.md`,
   Timpos records Moments and Corus replays them over Libera paths. Building replay into
   the Domain runtime would duplicate two existing components.

The finding's load-bearing error was proposing Libera-style **refs**
(`movement/change/result.count`) and a layer stack the kernel evaluates *through*. That
would put pressure vocabulary in the substrate — the exact thing both projects were built
to avoid.

## Convergence analysis

Applying the Domain method to the convergence itself: a Contract for what a unified
runtime must preserve, both codebases as the Result, a Verdict per element.

**Contract.** One addressing scheme. Kernel stays semantically ignorant. Domain keeps
meaning. Writes are locatable and replayable. Nothing from either side is silently
dropped.

| Libera element | Runtime equivalent | Verdict |
|---|---|---|
| `program` | `model:` name | converged — rename |
| `slot` (`facia_surface_model.status`) | `Ref` (`contract.expected.count`) | **converged — identical shape** |
| `pressure` + `operation` | `classification: confirmed \| exception` | refines — 2 values vs 6 |
| path `id` | trace `step: 0, 1, 2` | Libera wins — stable vs positional |
| path as record | trace entry record | converged |
| v1 `evidence`, `authority` | Verdict `evidence?`, Result `evidence?` | partial — §3.1 already borrows `evidence` |
| `priority↔evidence`, `due↔authority` | absent | Libera wins — genuinely new |
| Timpos `prev` chain | absent | Libera wins |
| scope boundaries | kernel/Domain separation | converged — same discipline |
| v1's twelve domain types | absent | both reject |

### Three findings

**1. A slot *is* a Ref.** Both are dotted paths naming a state location. A Libera path is
a Ref plus an address prefix. Consequence: **CurrentState needs no rewrite**, and the
address grammar adds no kernel type and does not touch `Evaluate`.

**2. `classification` is a degenerate pressure.** The Level 0 model already computes
`if conforms then confirmed else exception` — we independently wrote a two-valued,
unaddressed version of Libera's six-valued grammar, and used the word `exception` for
one of its values.

**3. The governance symmetry has no home.** §4's Strategy Boundary is
`{invalid_when, exhausted_when, max_depth, max_cost}` — entirely execution pressure. The
governance half is missing, and Libera v1 already worked it out.

## §1 Architecture

```
kernel/     Value · Ref · Expression · Evaluate      knows nothing above it
modelir/    YAML → Model IR                          knows syntax, not meaning
address/    Address · Write                         knows addresses, not meaning
domain/     Contract · Result · Verdict · State      knows meaning
strategy/   Operator · Goal · Boundary · Heuristic   not built
```

Two distinct arrows, which the finding fused:

- **Dependency** (who may name whose vocabulary): `kernel ← address ← domain ← strategy`
- **Evaluation** (what runs): `domain → kernel`, directly and always

`address/` is a **vocabulary layer, not an evaluation stage.** It decorates writes after
a fold; it is never on the evaluation path.

`address/` depends on `kernel/` for exactly one thing: a slot is a kernel `Ref`. It sits
below `domain/` because it does not know what conformance means.

**Consequence for the write policy:** inference rules mention `conforms`, so the policy
lives in `domain/`, not `address/`. `address/` owns the grammar only — which operations
exist, how a path parses and renders, whether an address is well-formed.

### Replacing the lost repo boundary

Choosing one merged runtime gives up Libera's repo-level enforcement of its scope
boundaries. It is replaced by a **layering test** (§8) that fails if a module names
vocabulary from a layer above it.

## §2 Data shape

```
Address = {
  id:        path.contract_expected_enter     stable identity
  program:   domain-count-level-0             address space
  pressure:  boundary | movement | exception
  operation: enter|exit | advance|change | detect|respond
  slot:      ref(contract.expected)           a kernel Ref
}

Write = { id, address: Address, value: Value, prev: <id> | null,
          evidence?: Value, authority?: Value }
```

Every field is an existing kernel Value form. `slot` holds a `REF` inside a `RECORD`,
which is inert under evaluation. **Zero kernel changes.**

## §3 Write policy

Writes are inferred by the runtime and overridable — but the inference is a **declared
expression**, not Mojo logic, so the runtime makes no semantic judgments of its own.

At each fold the runtime binds props and evaluates `expressions.writes`, which returns
candidate writes. Entries whose `when` is false are dropped; filtering on a declared
boolean is mechanical, not semantic.

**Policy props** — what a write policy may reference:

| name | meaning |
|---|---|
| `state` | CurrentState before the fold |
| `next` | CurrentState after the fold |
| `output` | the Verdict being folded in |
| `result` | the Result being verified |
| `event` | `{is_first, step}` — position in the run |

**Where a write's value comes from.** The policy declares no `value:` field. The runtime
builds a **slot frame** and resolves each slot against it:

```
frame = { contract, result, verdict, state, next, snapshot }
value = Resolve(slot, frame)
```

So `contract.expected`, `result.actual`, and `verdict.conforms` each resolve to the value
at that address after the fold. This is what makes a slot genuinely a `Ref` rather than a
decorative string — it must resolve, and a slot that does not is a policy error caught at
emission.

`models/writes-default.yaml` ships as the default. A model overrides by declaring its own
`expressions.writes`.

```yaml
model: writes-default
expressions:
  writes:
    list:
      - record:
          when:      {ref: event.is_first}
          pressure:  boundary
          operation: enter
          slot:      contract.expected

      - record:
          when:      true
          pressure:  movement
          operation: change
          slot:      result.actual

      - record:
          when:      true
          pressure:  {if: {condition: {ref: output.conforms}, then: movement, else: exception}}
          operation: {if: {condition: {ref: output.conforms}, then: advance,  else: detect}}
          slot:      verdict.conforms

      - record:
          when:      {ref: next.converged}
          pressure:  boundary
          operation: exit
          slot:      snapshot
```

`exception/respond` is absent by construction — the Level 0 discipline is visible in the
policy, not merely asserted in a test.

**Slot authoring.** Slots are written as bare symbols (`contract.expected`) and parsed
into kernel `Ref`s by `address/`. Writing `{ref: …}` would *resolve* the path; the address
must carry it unresolved.

### Expected emission for the doc §3.3 traces

```
trace A                                              trace B
boundary/enter    contract.expected      {count: 3}  movement/change   result.actual     {count: 3}
movement/change   result.actual          {count: 2}  movement/advance  verdict.conforms  true
exception/detect  verdict.conforms       false       boundary/exit     snapshot          {…}
```

## §4 Exception: detect versus respond

The detect/respond boundary lands on doc §8 open decision #2 — *whether orchestration
classifies exception/escalation directly, or delegates classification to strategy.*

**Decision: Strategy owns `respond`. Domain emits `detect` only.**

Separation test: **detect writes a fact about the deviation; respond writes a decision
that changes what happens next.** Operationally — does anything downstream branch on this
write?

Applied: `verdict.conforms = false` is a fact. `state.classification = exception` looks
like a response but is not — `domain/run.mojo` branches on `converged(state)`, which
reads `state.converged`. Nothing reads `classification`. It is therefore a second slot in
the same detection.

At Level 0, `exception/respond` never fires.

### Escalation

Escalation is not the counterpart of detect. It is a species of respond:

```
exception
├── detect                    deviation identified
└── respond                   deviation acted on
    ├── retry / repair        Strategy picks another operator
    └── escalate              Strategy exhausts its boundary, hands off
```

Escalation is distinguished by carrying an `authority`. This is independently derived by
the v1 material: `logic.md` says non-urgent exceptions map to validation and urgent ones
to escalation; urgency is `due`; and `fields.md` gives `due ↔ authority`,
`priority ↔ evidence`. So **validation** is a respond judged on evidence, **escalation**
a respond judged on authority. Two parts of the old spec agreeing is the strongest
argument for retaining `fields.md`.

### `classification` is derived, not computed

**Decision:** stop hand-computing `classification` in each model's `orchestrate`
expression; derive it from the emitted pressure/operation. `movement/advance` is
"confirmed"; `exception/detect` is "exception".

Doc §3.1's CurrentState shape is preserved, existing tests stay meaningful, and there is
one source of truth. The §3.3 model loses an entire `if` block.

## §5 Trace becomes a write log

```
{ id, program, pressure, operation, slot, value, prev }
```

This is Timpos's Moment **minus the timestamp**, and it stays that way. The `prev` chain
is structure; timestamps are observation, which is Timpos's concern.

**Decision:** the merged runtime keeps saying no to observation, truth-evaluation, and
surface rendering, even though the repo boundary that enforced that is gone.

## §6 Bill of materials: v1 versus v2

**From v2** (`protocol/libera.schema.yaml`): path format, the six pairs, required
`program`, path-as-record-with-`id`, the scope boundaries list.

**From v1** (`fields.md`, `logic.md`) — dropped by v2 without replacement: the field
vocabulary, the `priority↔evidence` / `due↔authority` symmetry, the execution/governance
duality.

**Rejected from v1**: the twelve domain types and `{type}/{id}/{field}`.

**Correction to note:** the v1 field vocabulary does *not* cleanly fit our slots.
`contract.expected` and `verdict.conforms` are not `status`/`owner`/`result`. Forcing
them would be domain-smuggling. The vocabulary is therefore a **reserved set with defined
meanings, not a constraint.** The four already present in doc §3.1's shapes — `result`,
`evidence`, `authority`, `owner` — carry over with Libera's definitions attached.

### Governance completes Strategy's Boundary

```
execution   max_depth · max_cost · exhausted_when     ← priority, due
governance  evidence_required · authority_required    ← evidence, authority
```

Recorded, not built.

## §7 Naming and publishing — OPEN DECISION

`~/Dev/libera` (Mojo runtime) and `github.com/jeremycapps/libera` (published spec) share
a name and no content.

**Recommendation:** keep the name; fold the spec in as `protocol/` **verbatim**; let the
merged repo be spec-plus-reference-runtime. Scope-boundary claims then attach to
`protocol/`, and the README must say so explicitly.

**This changes what a public repo is.** No remote will be modified without explicit
instruction.

## §8 Testing

- **Layering test** — fails if `kernel/` mentions "contract" or "pressure", or `address/`
  mentions "verdict"/"conforms"/"contract". Replaces the surrendered repo boundary.
- **Conformance test** — `Address` validates against the published
  `protocol/libera.schema.yaml`, so the runtime cannot drift from the spec it ships.
- **Level 0 discipline** — assert no `exception/respond` is ever emitted.
- **Mutation testing** on `writes-default.yaml`, as was done for the domain model, to
  prove the write tests are not vacuous.
- **Chain integrity** — `prev` links form one unbroken chain with no orphans.
- **Trace fidelity** — traces A and B emit exactly the writes listed in §3.
- **Derivation agreement** — derived `classification` matches the emitted pressure.

## §9 Build order

1. `address/grammar.mojo` — `Address`, the pressure/operation vocabulary, parse/render/validate
2. `address/write.mojo` — `Write` and `prev`-chain helpers
3. `models/writes-default.yaml` — the default policy
4. `domain/emit.mojo` — evaluate the write policy, build the slot frame, resolve slots
5. Wire into `domain/run.mojo` — emit writes, chain them, derive `classification`
6. Layering test
7. Fold in `protocol/` + conformance test
8. Fold in `fields.md` as the governance vocabulary reference

Steps 1–3 do not touch existing code.

Note the split forced by the layering rule: `address/` holds the grammar and the `Write`
record, but the *evaluation* of a write policy lives in `domain/emit.mojo`, because it
binds `output`/`verdict` props and so names Domain vocabulary. Keeping the evaluator in
`address/` would fail the layering test in step 6.

Strategy remains unbuilt throughout.

## Decisions recorded

| # | Decision |
|---|---|
| 1 | One merged runtime; the Mojo repo is the foundation, Libera folds in |
| 2 | Writes inferred by runtime, overridable — expressed as a declared policy model, not Mojo |
| 3 | Strategy owns `exception/respond`; Domain emits `detect` only (settles doc §8 #2) |
| 4 | `classification` derived from emitted writes, not hand-computed |
| 5 | Escalation is a species of respond, marked by `authority` |
| 6 | v1 field vocabulary retained as reserved meanings, not enforced on slots |
| 7 | Trace carries `prev` but no timestamps; observation stays Timpos's |
| 8 | Repo naming and publishing — OPEN, no remote changes without instruction |
| 9 | Layer named `address/`; types `Address` and `Write` (not `motion`/`Motion`) |

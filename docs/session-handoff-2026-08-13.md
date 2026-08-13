# Session Handoff — 2026-08-13

*Built the entire deterministic runtime under Libera — kernel through Strategy — and consolidated the published spec repo into it.*

---

## The Setup

**Who:** Jeremy Capps, building **Libera**: a page-based platform for composing, sharing, and deploying executable semantic models. "Notion plus Obsidian plus Vercel for semantic models." This session was about the technical spine underneath that product, not the product surface.

**Goal coming in:** A Word doc — *Model Kernel, Domain, and Strategy Architecture* — describing a three-layer design. The ask was narrow: *"build just the kernel for this and test suite."*

---

## What Happened

It started small and kept earning its way forward. The kernel came first — `Value`, `Ref`, `Expression`, `Evaluate` in Mojo, with two decisions that shaped everything after: values are immutable behind `ArcPointer`, and **errors are Values, not exceptions**, so the kernel law `Value_out = Evaluate(Expression, Props)` stays literally total. Then Domain as a YAML model object, reproducing the doc's traces A and B exactly.

The pivot came from a proposal ("the finding") about importing a *Libera* addressing spec from an existing GitHub repo. Assessing it against the actual repository turned up four errors in the proposal and one big one: it wanted the kernel to evaluate *through* an address layer, which would have put motion vocabulary in the substrate. The real finding was quieter and better — **a Libera slot *is* a kernel `Ref`** — so the whole address grammar dropped in with **zero kernel changes**. That claim held across 22 commits and was independently verified twice.

Two things then got corrected in the framing. First, the layer we'd called `motion/` was renamed `address/`, on the argument that "motion" collided with `movement` (one of three pressures) and the real subject was the address. Jeremy's own North Star doc, surfaced later, independently used *Address* for the same layer. Second — and this was the significant reframe — Libera is **not an open spec**. It's the product. The published repo's boundary claims ("Libera does not define execution or meaning") were false of Libera and true only of Address. That correction rippled through the README, the protocol docs, and the schema itself.

The session closed by building Strategy as a ladder rather than a leap. The architecture doc's `count +2/+3` example had made Strategy feel abstract, because it jumps straight to search. Breaking it into rungs — fixed response, then selection with a boundary, then search — made each step concrete and testable. All three are built. The doc's full bootstrap table (K0, D0, D1, S0, S1, Integration) now passes.

---

## Decisions Made

**Errors are Values, never exceptions** — keeps the kernel law total and lets failures be folded into state by layers above. Only filesystem reads may `raise`.

**A slot is a kernel `Ref`** — this is why the address layer needed no kernel type and no change to `Evaluate`. It's the load-bearing claim of the whole design; a verification step asserts `kernel/` has no commits since the address work began.

**The layer is `address/`, types `Address` and `Write`** — "motion" collided with `movement`; "Write" was already the operative noun in the design ("one address per write").

**Strategy owns `exception/respond`; Domain only detects** — settles doc §8 open decision #2. Separation test: *detect writes a fact; respond writes a decision that branches.*

**Escalation is a species of respond, marked by `authority`** — not a peer of detect. Independently derived from v1's `due ↔ authority` symmetry in `fields.md`.

**`trace` is a projection, not a stored field** — settles doc §8 #5. A snapshot inside the log can't contain the log; its position *is* its trace. The old code passed an empty list, which is worse than omission — a durable record asserting nothing happened.

**`classification` is derived from emitted pressures** — it was a two-valued, unaddressed version of Address's six-valued grammar. One source of truth.

**Layering enforced by import direction, not word search** — a grep for "contract" false-positives on `kernel/value.mojo`'s own docstring. The test enumerates package files via `listdir` so the guard can't rot as files are added.

**Consolidate under the upstream repo, preserving its history** — `--allow-unrelated-histories`, never a force-push. v1 preserved four ways: tags `v1-final` and `spec-only`, `archive/v1/`, and untouched history.

**The conformance test reads `protocol/address.schema.yaml` directly** — not a vendored copy. The old copy had silently drifted (missing the entire `path.fields` block). Drift is now structurally impossible.

---

## Still Open

**Rung 2 counts answers, not progress.** It knows it responded twice; it doesn't know that asking for logs didn't work. A strategy comparing verdicts across folds could conclude its response is *ineffective* rather than merely exhausted. Probably more useful for real triage than anything in rung 3.

**No `has` operator in the expression language.** `models/issue-completeness.yaml` spells out `not(eq(x, null))` twice per field because there's no presence test and no way to bind a helper into a verifier's props. Both would be kernel changes, which is why neither was made unasked. The repetition is commented in the file — and mutation testing already caught one bug caused by it (`conforms` and `finding` silently disagreeing).

**`max_depth` is only weakly exercised.** The count contract is reachable at depth 1, so narrowing the bound fails just one assertion. A contract needing genuine composition would test it properly.

**Operator `cost` and `max_cost` unimplemented.** Depth bounds the search adequately; cost without a reason to weigh operators differently would be ceremony.

**The frontier is bounded-exhaustive, not best-first.** It expands everything at each depth rather than pursuing the lowest score. Fine at depth 2 with two operators; it would matter with a real branching factor.

**No license.** The repo is public and now contains a product's runtime. Earlier advice about this was reasoned from "open spec" and no longer applies — it's a genuinely different question now.

**`filesystem/` is an empty placeholder** inherited from the spec repo. The README explains the intent (addresses mounting as file paths) but nothing implements it.

**Page → Package → Deployment are unbuilt.** The entire product surface. The README says so plainly rather than implying a platform that isn't there.

---

## Made This Session

**The runtime** (all new):
- `kernel/` — `value.mojo`, `eval.mojo`, `ir.mojo`
- `modelir/` — `text.mojo`, `yaml.mojo`, `compile.mojo` (a YAML subset reader and IR compiler, pure Mojo — Python interop can't load libpython in this environment)
- `address/` — `grammar.mojo`, `write.mojo`
- `domain/` — `model.mojo`, `emit.mojo`, `run.mojo`
- `strategy/` — `respond.mojo`, `search.mojo`, `run.mojo`
- `testkit/harness.mojo` — assertion harness (Mojo 0.26 has no `mojo test`)

**Models** (`models/`): `domain-count-level-0.yaml`, `issue-completeness.yaml`, `writes-default.yaml`, `strategy-route-back.yaml`, `strategy-issue-triage.yaml`, `strategy-count-search.yaml`

**Docs**: `docs/runtime.md`, `docs/north-star.md`, rewritten `README.md`, `protocol/README.md`, `docs/fields.md`, `docs/timpos_compatibility.md`, `archive/v1/README.md`

**Process artifacts**: `docs/superpowers/specs/2026-08-12-libera-convergence-design.md` (10 recorded decisions), `docs/superpowers/plans/2026-08-12-address-layer.md`

**Tests**: 18 suites, **815 assertions, 0 failures**. Every model document is mutation-tested.

---

## Next Actions

1. **Decide the license.** The repo is public with a real runtime in it. This blocks nothing technically but gets more awkward the longer it waits.

2. **Add a `has` operator to the kernel** (or expression binding into verifier props). It removes the duplicated presence logic in `issue-completeness.yaml` and closes the class of bug mutation testing already caught there. Small, well-scoped, and unblocks cleaner Domain models.

3. **Build "did the response work?"** — the rung-2 gap. Give Strategy access to the previous verdict so it can detect that its own response changed nothing. Likely more valuable than anything further in search.

4. **Write a second Domain model from real product work** — a project-manager or decision-feed contract from the North Star's package examples (`@domain/project-manager`, `@corus/candidate-evaluation`). Two models exist; both are still somewhat synthetic. A third from actual work would test whether the Contract/Result/Verdict shape holds up.

5. **Start the Page layer** — the first product-surface piece. A Page is "a markdown body plus executable metadata," which is exactly what `modelir/` already parses. The gap between a model document and a Page is smaller than it looks.

---

## To Load Next Time

- `README.md` — current framing (product, not spec)
- `docs/north-star.md` — the product vision the runtime serves
- `docs/runtime.md` — how the runtime works, all design decisions
- `docs/superpowers/specs/2026-08-12-libera-convergence-design.md` — the 10 recorded architecture decisions and why
- `protocol/address.schema.yaml` — the canonical Address protocol
- The original Word doc: `~/Downloads/Model_Kernel_Domain_Strategy_Architecture.docx` (§8's open decisions #2 and #5 are now settled; the rest remain)

Run `./run_tests.sh` first. It should print **815 assertions, 0 failures**.

---

> **Tone note:** Build-heavy session, high trust, minimal hand-holding. Jeremy pushes back when framing is off (the "not an open spec" correction, disliking "motion") and those pushbacks were consistently right — take them seriously rather than defending. He reasons out loud and values being told when he's already done the thing someone advised. Mutation testing caught real bugs three separate times, including two in tests written this session; keep doing it and keep reporting failures honestly rather than presenting green suites as proof.

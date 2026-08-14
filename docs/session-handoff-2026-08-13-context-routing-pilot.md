# Session handoff — context-routing experiment pilot (2026-08-13)

## Summary

The three-arm context-routing pilot **ran to completion**. All nine agents executed,
the deterministic gate returned an unambiguous verdict for every arm, and the labels
have been unsealed.

- **Verdict:** `evidence_insufficient` — as predicted before the run, and not a
  disappointment. One run per arm, Priority 5 unmeasured, Priority 2 compromised by a
  disclosed ceiling. The pilot's deliverable was a debugged protocol, and it produced one.
- **Nothing was merged into Libera.** The arms ran in three throwaway clones outside the
  repository. The only commits on this branch are the design spec and this handoff.
- **Design spec:** `docs/superpowers/specs/2026-08-13-context-routing-execution-design.md`
- **Experiment root:** `~/Dev/libera-experiments/ctxroute-pilot-001/` (outside the repo,
  deliberately — a source readable from inside a clone would defeat the minimal arm)

## Results

| Label | Arm | Gate | Files | Turns | Tokens |
|---|---|---|---|---|---|
| A | `arm-full` | **8/8 conforming** | 2 | 68 | 64,794 |
| C | `arm-packetized` | **8/8 conforming** | 2 | 66 | 59,851 |
| B | `arm-goal-output` | **3/8 nonconforming** | 4 | 106 | 51,852 |

`arm-goal-output` failed DC-1, DC-2, DC-3, DC-4, DC-7.

Turn counts are read directly from the agent transcripts and are the more trustworthy
number. Token totals are per-arm only, with no per-role breakdown, and are **not** a
Priority 5 input.

## What the pilot found

**1. Possessing the answer did not produce transcription.** The frozen source was taken
whole and unredacted, and contains a complete proposed manifest (lines 161–245). The
predicted failure was that every arm would copy it. Neither conforming arm did. The
proposed shape leaves `examples/`, `run_tests.sh`, `docs/fields.md`,
`docs/migration_v1_to_v2.md`, and `docs/timpos_compatibility.md` unclassified; **both**
conforming arms detected the gaps against the actual tree and added an explicit fallback
for the remainder. The leak was less fatal than the design assumed.

**2. Minimal context produced an unconstrained agent, not a worse one.**
`arm-goal-output` wrote a 263-line Mojo guard test that walks the manifest and enumerates
the repository root so no new directory can appear unrouted, taking the suite 858 → 925
assertions. It is arguably the most rigorous artifact of the three. It is also
nonconforming, because it named its file `context-routing.yaml` and modified `tests/` —
constraints it was never given. The failure is scope, not competence.

**3. Self-certification under minimal context is worthless.** That arm's validator, given
no acceptance criteria, derived nine of its own from the goal statement, judged them
satisfied, and returned `conforming` on a patch failing five of eight deterministic
checks. **The mechanical gate caught what the arm's own validator could not.** This is the
strongest argument the pilot produced for keeping Priority 1 outside the arm entirely.

**4. Withheld context reappears as retrieval turns, below the orchestrator.** Full and
packetized are effectively tied (68 vs 66 turns) with near-identical internal profiles —
withholding ~40% of the source cost the packetized arm nothing. The goal-output arm took
55% more turns, and **all of the increase landed below the orchestrator**: its
orchestrator was the cheapest of the three (20 turns, nothing to route) while its
implementer more than doubled everyone else's (51 vs 24–25) and its validator doubled
(35 vs 17–18). It used the fewest tokens and the most turns — many small reads,
rediscovering what the other arms were handed.

## Libera-layer audit (§23.1)

Asked and answered: **the experiment used Libera's vocabulary, not its runtime.**

- **Zero model documents.** No arm wrote anything under `models/`. The three context
  policies are a Python dict of section names; the domain contract is `gate.sh`, bash; the
  verdict is a string in a YAML file.
- **`Evaluate` was never called.** `arm-goal-output` is the only arm that touched the
  runtime at all, importing `kernel.value` (`Value`, `INT`, `RECORD`, `LIST`) and
  `modelir.yaml.parse_yaml_file` to read its manifest in a guard test. `Evaluate`: 0.
  `Expression`: 0. The kernel was used as a library, never as its execution surface.
- **Where they would land if modeled.** The context policies are fixed projections with no
  candidate selection, no boundary, no heuristic — **rung 1**, the degenerate case
  `models/strategy-route-back.yaml` documents. The genuinely strategy-shaped component was
  the **orchestrator** (dispatch, read verdict, choose repair vs escalate vs block, stop at
  a boundary) — **rung 2**, the shape of `strategy-issue-triage.yaml`. It ran as agent
  prose, unmodeled.
- **No Addresses were recorded**, though the run generated events that map cleanly:

  ```text
  dispatch implementer   -> boundary/enter
  validator finds defect -> exception/detect
  repair round           -> exception/respond
  commit convergence     -> movement/change
  arm terminates blocked -> boundary/exit
  ```

## Protocol findings

Two contamination bugs were caught in pre-flight, **before** launch. Both are the class of
defect §24 says a pilot exists to surface:

1. **`DC-10` named the coverage gaps** — it listed `examples/`, `run_tests.sh` and the rest
   verbatim, which would have handed arms 1 and 2 the answer to the discriminator the
   pilot rested on. Rewritten to state the requirement without naming what was missing.
2. **YAML file comments were reaching agents.** The projector emitted raw file text, so
   `goal.yaml`'s header — "§19.5", "the minimal arm", "smuggle the criteria" — landed
   inside arm 3's implementer packet, disclosing the experimental design to a subject. The
   projector now round-trips through the parser so commentary can never reach an arm.

Controls that held: topology (exactly two nested dispatches per orchestrator, no role
skipped), isolation (this session's design commit is provably absent from every clone),
and the no-new-context rule — **1 escalation across all three arms, 0 `additional_context`
events**. No orchestrator answered an escalation with information it had not been given.

Controls that did **not** hold: **the sealed verdict**. Labels were unsealed on request
before a verdict was written, so pre-registration is forfeited for this pilot. Recorded as
`verdict_written_before_unsealing: false` in `verdict/sealed-labels.yaml` rather than left
silent. Note also that Priority 1 partially de-anonymizes the minimal arm on its own — a
nonconforming four-file patch with an invented filename is unmistakable — so the seal only
ever protected the two conforming arms from each other.

## Where things are

```text
~/Dev/libera-experiments/ctxroute-pilot-001/
  canonical-source.yaml         provenance manifest: refs, integrity, section map, policies
  sources/original-handoff.md   frozen raw source, sha256 663d4d8f...
  goal.yaml                     arm 3's entire input
  domain-contract.yaml          13 conditions: 8 deterministic, 5 judgment
  candidate-result.schema.yaml  identical result shape across arms
  project.py                    deterministic projector; refuses to run on source drift
  templates/                    one per role, shared by all arms
  gate.sh                       8 mechanical checks, validated against a negative control
  results/<arm>/                result.yaml, trace.md
  verdict/                      sealed-labels.yaml (now unsealed), anonymized/{A,B,C}.diff
```

Clones and dispatch packets were written to the session scratchpad and are **not durable**.
Re-create them with `project.py` plus three `git clone --local --single-branch` calls; see
the design spec's *Isolation topology*.

## For the next agent

The pilot met most of §24. What it did not settle, in priority order:

1. **The scripted harness.** Per-role token accounting is confirmed to be unobtainable
   under subagents — only per-arm totals came back. Priority 5 cannot be evaluated until
   this exists. This is the main blocker on a real result.
2. **Repetition.** n=1 per arm. Full and packetized differ by 2 turns and 8% tokens, which
   is inside any plausible variance. §22.13 (how many runs) is still unanswerable, but the
   pilot now gives a variance estimate to design against.
3. **Model the orchestrator as a real strategy.** The highest-value Libera-side work: a
   `models/strategy-context-arm.yaml` at rung 2, emitting addressed writes, would turn the
   hand-written `trace.md` into runtime output and make the experiment's own execution the
   first non-toy consumer of the Address protocol.
4. **Decide whether a redacted-source arm is worth running.** Freezing the source whole was
   an explicit decision and its ceiling was disclosed in advance. Finding 1 suggests the
   ceiling bound less tightly than expected — which makes the redacted comparison more
   interesting, not less.

Do not read `verdict/sealed-labels.yaml` before writing a verdict if you re-run this. The
mapping for **this** pilot is already public: A = full, B = goal-output, C = packetized.

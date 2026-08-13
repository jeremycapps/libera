# Context-routing experiment: execution design

**Date:** 2026-08-13
**Status:** design — pilot not yet authorized to run
**Subject spec:** `libera-context-routing-strategy-experiment-spec.md` (external, `~/Downloads/`)
**Scope:** how the three-arm experiment is actually executed. Isolation topology, projection
mechanics, run protocol, deterministic gate, verdict procedure. No Libera repository changes.

The subject spec defines *what* the experiment compares. This document defines *how a run
happens* — and stops where the subject spec's §24 completion criteria are still unmet, rather
than papering over them.

## What this document settles

Four decisions, taken deliberately, each of which forecloses a contamination path:

| Decision | Choice | What it forecloses |
|---|---|---|
| Execution substrate | Pilot via subagents now; scripted harness after the protocol survives contact | Building a measurement rig around projections that have never run |
| Arm 3's packet | Goal + output contract only — no acceptance criteria | §19.5, the "minimal" arm being the handoff in disguise |
| Arm 2's packets | Deterministic projection from the canonical source | Arm 2 winning on free human judgment the others never got |
| Verdict | Deterministic gate + human judgment, sealed labels | An unvalidated agent-judge rubric being mistaken for a finding |

And one it deliberately does **not** settle: the contents of `canonical-source.yaml`. See
[Open items](#open-items).

## A contradiction in the subject spec, and its resolution

§6 lists "domain goal and evaluator reference contract" among the dimensions that must remain
fixed across arms. §10.3 gives arm 3's implementer only `goal` and an output contract — while
§10.2 gives the packetized arm `acceptance_criteria` in its base context.

Read literally, these conflict: either acceptance criteria are fixed across arms (and arm 3
gets them, making it not minimal), or they vary (and §6 is violated).

**Resolution: the *evaluator's* reference contract is fixed; what is *delivered to agents*
varies.** All three arms are judged against the same criteria. Only arm 2 is told them. This
is the coherent reading, and it must be stated explicitly, because the alternative failure
modes are both silent — arm 3 gets quietly upgraded to stay "fair," or arm 3 is judged against
a contract it was never given and its failure is misattributed to minimal context rather than
to the experimenter.

Arm 3 failing Priority 1 because it never ran the tests is a **result**. It is the falsifiable
content of the minimal-context hypothesis, and the protocol must not rescue it.

## Isolation topology: clones, not worktrees

The subject spec's §7 says `branch_or_worktree: isolated_per_arm`, and §12 requires "no access
to another arm's patch, trace, or verdict."

Worktrees cannot deliver the second. They share one `.git`; an arm can run `git log --all` or
`git branch -a` and read its siblings' commits. Under worktrees, §12 isolation is a matter of
agent goodwill — a mandate the agent may or may not honor, and whose violation leaves no trace.

**Three `git clone --local` clones instead.** An arm's object store contains no sibling refs,
so the isolation is structural rather than behavioral. The repository is 940K; a local clone is
hardlinked and effectively free. There is no cost being traded away here.

Two further properties, both load-bearing:

**The experiment root sits outside the repository.** If `canonical-source.yaml` lived inside a
clone, arm 3 would read the answer it was deliberately not given — §19.5 leakage through the
filesystem rather than through the packet. Every projection artifact lives outside every clone.

**Nothing is ever merged.** §21 does not authorize modifying Libera. The clones are evidence.
Each arm commits to a branch named `arm` *inside its own clone*; results leave as
`git diff 4937ce1..HEAD` written to `results/<arm>/patch.diff`. No branch is created in the
working repository, nothing is pushed, and no clone is ever added as a remote of another.

### Layout

```text
~/Dev/libera-experiments/ctxroute-pilot-001/
  freeze.yaml                 # baseline commit, source hash, assertion count, model, boundaries
  canonical-source.yaml       # §9 — single source all projections derive from
  project.py                  # deterministic projector: canonical-source -> projections/
  projections/
    arm-full/{orchestrator,implementer,validator}.yaml
    arm-packetized/{base,orchestrator,implementer,validator}.yaml
    arm-goal-output/{orchestrator,implementer,validator}.yaml
  templates/{orchestrator,implementer,validator}.md      # one per role, shared by all arms
  arms/
    arm-full/ arm-packetized/ arm-goal-output/           # clones, branch `arm` off baseline
  results/<arm>/{patch.diff,result.yaml,trace.md,gate.yaml}
  gate.sh
  verdict/{sealed-labels.yaml,anonymized/{A,B,C}.diff,verdict.md}
```

## The freeze

Recorded in `freeze.yaml` before any arm starts, and stamped into every result packet:

```yaml
baseline_commit: 4937ce1
baseline_assertions: 858        # verified: ./run_tests.sh, 0 failures, ~11s wall
source_context_hash: <sha256 of canonical-source.yaml>
toolchain:
  mojo: 0.26.2.0                # verified present
  pyyaml: 6.0.3                 # verified present
model: claude-opus-5           # one identifier, every role, every arm — §19.9
boundaries:
  max_repair_rounds: 2
  max_escalations: 3
  wall_clock_per_arm: 30m
  network: none
```

`docs/superpowers/packets/MANIFEST.yaml` records a baseline of 815 assertions. That figure is
stale; the current suite reports 858. The freeze uses the verified number, and the gate's
regression floor derives from it.

## Projection

One canonical source, three mechanical projections, no authored variation.

`project.py` reads `canonical-source.yaml` and emits the per-role projection files by selecting
named fields per §10. It performs no summarization, no rewriting, and no judgment — arm 2's
packets are **strict subsets** of arm 1's source. This is what makes the comparison between
those two arms an isolation of a single variable: the difference between them is exactly what
was withheld, and nothing else.

| Arm | Orchestrator | Implementer | Validator |
|---|---|---|---|
| `arm-full` | canonical source | canonical source + role instruction | canonical source + role instruction + candidate result |
| `arm-packetized` | base ref + routing contract + completion contract | base ref + implementation scope + permitted addresses + output | base ref + validation scope + candidate result + evidence contract |
| `arm-goal-output` | goal + orchestration output contract | goal + implementation output contract | goal + validation output contract + candidate result |

Arm 3's implementer packet in full — no paths, no constraints, no test command, no mention of
Mojo, no README guidance:

```yaml
goal:
  statement: >
    Add a lightweight repository-level context-routing manifest that makes default
    agent context deliberate while preserving explicit access to the full
    repository history.
output_contract:
  changed_files: []
  patch_ref: ""
  design_summary: ""
```

Everything else it needs, it recovers by inspecting the repository, or it does not recover.

## Run protocol

### Topology, fixed across arms

Three roles per arm — orchestrator, implementer, validator — with a bounded repair loop. Role
count, tool set, model, boundaries, and result schema are identical everywhere. §19.1 makes
topology drift the first contamination risk, and §6 fixes topology; so arm 3 gets an
orchestrator even if it barely uses one. **An idle role is data; a missing role is a confound.**

### How prompts are assembled

Not by authoring three prompts. There is **one template per role**, shared by all arms, and an
arm's prompt is that template with its projection file spliced in — three fills of one form.

This is the mechanism that forecloses §19.3 hidden expansion at the source rather than policing
it afterward. If the templates are identical and the fills are mechanical, the experimenter has
no channel through which to enrich an arm, whether intentionally or not.

The one legitimate cross-arm difference in content is arm 1's instruction not to summarize
before delegating (§10.1). That is not template drift — it *is* the routing contract, which is
the experimental variable.

### Repair versus escalation

§22.9 asks for the distinction. It is drawn on whether new context is required:

- **Repair loop** — the validator returns defects the implementer can fix using context it
  already holds. Capped at 2 rounds. No new context enters.
- **Escalation** — the implementer or validator returns to the orchestrator because it cannot
  proceed within its supplied context or authority. Capped at 3. Each is logged in `trace.md`
  with its cause.

And the rule that keeps escalation from becoming a leak:

> **An orchestrator may never answer an escalation with information it was not given.**

If the orchestrator's projection does not contain the answer, the arm terminates `blocked`.
Blocked is a legitimate outcome — plausibly *the* outcome for arm 3 — and the protocol does not
rescue it. Without this rule, every arm converges toward full context under pressure, and the
experiment measures nothing.

Any context the orchestrator does legitimately add is logged as an `additional_context` event
and charged to the strategy (§16: moving cost into the orchestrator must not make an arm look
efficient).

## The deterministic gate

`gate.sh` runs per arm inside its clone after the arm terminates. It contains no judgment; it
is §23.7's deterministic half, and its output is `results/<arm>/gate.yaml`.

| # | Check | Failure verdict |
|---|---|---|
| 1 | `context.manifest.yaml` exists at repository root | `required_artifact_missing` |
| 2 | It parses as YAML | `invalid_manifest` |
| 3 | Changed files ⊆ {`context.manifest.yaml`, `README.md`} | `non_negotiable_violation` |
| 4 | Diff empty across `kernel/ modelir/ address/ domain/ strategy/ protocol/ tests/ testkit/ models/ examples/` | `non_negotiable_violation` |
| 5 | `./run_tests.sh` exits 0 **and** reports ≥ 858 assertions | `repository_regression` |
| 6 | The README diff references the manifest | `required_artifact_missing` |

Check 5's assertion floor is not redundant with its exit code. Exit code alone would pass an
arm that deleted tests until the suite went green — the same mutation-check discipline the
existing MANIFEST already applies to its own escalation conditions.

Check 4 *is* implied by check 3: a diff confined to two root files cannot touch those
directories. It is kept because it fails with a more specific verdict, and because check 3 is
the one likely to be loosened if a later revision permits an arm to add, say, a schema file —
at which point check 4 stops being implied and starts being the only thing protecting the
runtime. The redundancy is deliberate and cheap.

A gate failure records the arm as nonconforming under Priority 1. It does not remove the arm
from the human reading: *why* an arm failed is evidence about its context policy.

## Verdict procedure

Priority 1 is settled mechanically by the gate. Priorities 2–4 are human judgment, taken under
pre-registration discipline because the judge designed the arms and cannot be made naive.

1. **Randomize and seal.** Labels A/B/C are assigned at random to the three arms and written to
   `verdict/sealed-labels.yaml`. The mapping is not displayed.
2. **Stage 1 — patches only.** `verdict/anonymized/{A,B,C}.diff` and nothing else. Rank
   Priority 2 (meaning preservation: does the manifest express the intended distinction between
   default context and explicitly addressable history?) and write it down.
3. **Stage 2 — evidence.** Anonymized `design_summary` and validation evidence are released.
   Rank Priority 3 (implementation and validation quality) and Priority 4 (convergence).
4. **Unseal.** Labels are revealed only after the verdict is written in full. The verdict is not
   editable afterward; a revision is a new dated entry stating what changed and why.

This two-stage release is the answer to §22.12 — anonymizing without destroying the evidence
evaluation needs. The artifact is judged before the narrative that could identify its author.

Permitted verdicts are §18's: `prefer_full_context`, `prefer_packetized_context`,
`prefer_goal_output_context`, `no_material_difference`, `evidence_insufficient`,
`experiment_invalid`.

## What the pilot cannot measure

**Priority 5 is out of scope for the pilot.** Per-role token accounting under subagents is
approximate at best, and §16 requires accounting that spans orchestrator, implementer,
validator, repair, and escalation traffic without displacement. The pilot does not attempt it;
whatever counts are available are recorded as indicative and marked as such.

This is consistent with the subject spec on both counts: §14 consults cost only after the
higher-priority gates are satisfied, and §17 already classifies a single run per candidate as a
harness pilot rather than evidence.

**Therefore `evidence_insufficient` is the correct verdict for anything short of a stark
difference.** The pilot's deliverable is a debugged protocol, a frozen contract, and three
projections that have survived contact — not a winner. A pilot that names a winner has almost
certainly mistaken variance for effect (§19.8).

## Contamination controls

How each §19 risk is addressed, and by what — architecture where possible, discipline only
where necessary.

| Risk | Control | Kind |
|---|---|---|
| 1. Topology drift | Three roles, one template set, identical boundaries | Architecture |
| 2. Hidden packetization | Arm 1's routing contract forbids pre-delegation summarization | Discipline |
| 3. Hidden expansion | Orchestrator may not answer escalations beyond its projection; arm blocks instead | Architecture |
| 4. Evaluator leakage | Sealed labels, verdict written before unsealing, no revision after | Discipline |
| 5. Acceptance leakage | Arm 3 receives goal + output contract only; canonical source lives outside every clone | Architecture |
| 6. Repository drift | One frozen commit, clones from it, no network | Architecture |
| 7. Cost displacement | Deferred with the rest of Priority 5; not faked in the pilot | Scope |
| 8. Single-run overclaim | `evidence_insufficient` is the stated expected verdict | Discipline |
| 9. Agent identity effects | One model identifier in the freeze, all roles, all arms | Architecture |
| 10. Subject/router confusion | §20 naming boundary observed throughout | Discipline |

Risks 2, 4, 8, and 10 remain matters of discipline. Each is a candidate for hardening once the
scripted harness exists — 2 and 8 in particular become mechanical there.

## Open items

**`canonical-source.yaml` is not drafted here, deliberately.** It is the most bias-sensitive
artifact in the experiment: arm 1 receives it whole, arm 2 receives mechanical subsets of it,
and its field decomposition therefore *determines the ceiling on how good arm 2 can look*.
Choosing its contents quietly would settle the outcome before the first agent ran, which is
precisely what §23.9 instructs the design agent not to do. It is work item 1, to be settled
with the human. `~/Downloads/libera-agent-context-manifest-handoff.md` is a plausible seed and
is superseded; whether it is the basis is a decision, not an inference.

Also still open, and not blocking the pilot:

- §22.2 — the smallest complete domain contract for the manifest, beyond the gate's six checks.
- §22.7 / §22.8 — what implementer and validator may exchange directly. The pilot uses the
  existing MANIFEST's `child_roles` asymmetry (the validator does not see the implementation)
  as its default; whether that holds under three different context policies is a pilot finding.
- §22.10 — judging semantic fidelity beyond YAML validity. The pilot's stage-1 reading is where
  this rubric gets discovered; writing it before running is premature per §18.
- §22.13 — repetition count after the pilot. Unanswerable until pilot variance is observed.

## Completion criteria for the pilot

The pilot has succeeded — regardless of which arm wins — when it has produced:

1. A frozen, hashed `canonical-source.yaml` that survived three arms without amendment.
2. Three projections that produced runnable prompts without manual repair.
3. A gate that returned an unambiguous Priority 1 verdict for every arm.
4. A written record of every escalation and every `additional_context` event.
5. Enough of a semantic-fidelity rubric, discovered in stage 1, to be written down.
6. A defensible answer on whether per-role token accounting requires the scripted harness.

Only then does harness implementation begin, per §24. Until then the proper output is continued
design, not repository implementation.

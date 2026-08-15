# Semantic reconstruction cost

An experiment comparing two ways of getting the same verification done: restating the
meaning in a prompt every time, or executing a model that already holds it.

The task is **issue completeness**. A customer issue must carry a root cause, an owner,
and a resolution path before it can move. Something has to check that, name what is
missing, and keep checking as the issue is revised round after round.

| | |
|---|---|
| **Method A** | A prompt-only agent. The contract is restated in the prompt on every round, and the agent produces the verdict. |
| **Method B** | The Libera pipeline. The contract lives in a model document; the kernel evaluates it and the write policy addresses the folds. |

Both methods run the same fixtures and are asked for the same answer, so the difference
between them is not accuracy — it is what each one has to reconstruct before it can
answer. That reconstruction is the cost this experiment measures.

## Layout

```text
experiments/semantic-reconstruction-cost/
  README.md                     this file: what the experiment is and how to run it
  fixtures/                     the shared inputs — both methods read these, unchanged
  prompt-only/                  Method A
    prompt-template.md          the fixed prompt, repeated verbatim on every round
    runs/                       hand-authored transcripts, one file per fixture run
  libera/                       Method B
    model-ref.md                what the pipeline reads and what it does not restate
    runner.mojo                 drives a fixture through the model and writes the trace
    snapshots/                  captured runner output, one .txt per fixture
  results.md                    the measurement table, the scorecard, and the verdict
```

| Path | Purpose |
|---|---|
| `fixtures/` | Five YAML fixtures, each a list of per-round `actual` issue records with `id`, `title`, `description`, `root_cause`, `owner`, and `resolution_path`. Absence is always an explicit `null`, never an omitted key — the model requires the supplier to say they looked. The set is `issue-complete.yaml` (1 round), `issue-missing-root-cause.yaml` (2 rounds), `issue-missing-owner.yaml` (2 rounds), `issue-missing-resolution-path.yaml` (2 rounds), and `issue-multiple-missing.yaml` (3 rounds). |
| `prompt-only/prompt-template.md` | The Method A prompt, held fixed across every round of every fixture. It asks for a `verdict`, a `finding`, a `next_action`, and an `explanation`. Token cost is estimated as the whitespace-split word count of what is sent. |
| `prompt-only/runs/` | The Method A transcripts — at least nine: one baseline per fixture, plus repeat runs of two fixtures so reproducibility and drift can be observed rather than assumed. Hand-authored rather than generated, so the record is auditable. |
| `libera/model-ref.md` | Names exactly which model documents Method B reads, and what it therefore never has to restate per round. |
| `libera/runner.mojo` | The Method B driver. Loads the model and the write policy, folds one fixture's rounds through the run, and writes the addressed write trace — with the converged snapshot, when the run converges — to `snapshots/<fixture>.txt`. |
| `libera/snapshots/` | One `<fixture>.txt` per fixture, holding that runner's output verbatim, so the comparison rests on a recorded artifact rather than a remembered one. |
| `results.md` | Where the experiment lands: the §6 measurement table, the §8 scorecard, and the §9/§10 go/no-go verdict. |

## The model under test

Method B adds no model. It executes two documents that already exist in this repository,
and reads them exactly as the test suite does:

- [`models/issue-completeness.yaml`](../../models/issue-completeness.yaml) — a Level 0
  Domain model. Its contract declares `root_cause`, `owner`, and `resolution_path` as
  required; `conforms` is true only when all three carry a value, and `finding` names the
  **first** gap in that declared order rather than reporting a bare false. Nothing in it
  responds to a deviation: routing an issue back, asking for logs, or escalating are
  responses, and responses belong to Strategy.
- [`models/writes-default.yaml`](../../models/writes-default.yaml) — the default write
  policy. It addresses the folds of a run: `boundary/enter` for the contract coming into
  scope, `movement/change` for the supplied result, `movement/advance` or
  `exception/detect` for conformance, and `boundary/exit` when the run converges. It names
  slots and pressures, never domain concepts, which is why it addresses this contract
  without modification.

Both are **read-only reference points for this experiment**. Neither is edited, copied, or
forked here. If a fixture cannot be verified without changing a model, that is a finding
for `results.md`, not a licence to change the model.

[`tests/test_issue_model.mojo`](../../tests/test_issue_model.mojo) is the precedent for
how a run is driven — see its `_addressed_run`, which is where the write-trace shape the
runner prints comes from.

## Reproducing Method B

From the repository root:

```bash
mojo run -I . experiments/semantic-reconstruction-cost/libera/runner.mojo experiments/semantic-reconstruction-cost/fixtures/<name>.yaml
```

The working directory matters. `-I .` puts the repository root on the import path, and the
model paths the runner loads are relative to it — the same `cd "$(dirname "$0")" && mojo
run -I .` pattern [`run_tests.sh`](../../run_tests.sh) uses.

**This runner is not part of the test suite.** It is not wired into
[`run_tests.sh`](../../run_tests.sh) or [`tests/run_all.mojo`](../../tests/run_all.mojo),
and `./run_tests.sh` neither builds nor executes it. It is invoked by hand, per fixture,
and its output is captured into `libera/snapshots/`.

Method A has no runner. Its transcripts under `prompt-only/runs/` are the record, and
`prompt-only/prompt-template.md` is what was sent to produce them.

## What this experiment touches

Everything under `experiments/semantic-reconstruction-cost/` is **additive only**. Nothing
under `models/`, `kernel/`, `modelir/`, `domain/`, or `address/write.mojo` is modified by
this experiment, and neither is `run_tests.sh` or the test suite. Deleting this directory
returns the repository to exactly its prior state.

## Where the verdict lands

[`results.md`](results.md) in this directory. It is written last, once both methods have
run every fixture: the measurement table in §6, the scorecard in §8, and the go/no-go
verdict in §9/§10. Until EPIC-004 populates it, the experiment has data but no conclusion,
and nothing else in this directory should be read as one.

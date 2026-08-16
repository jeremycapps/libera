# Results: semantic reconstruction cost

This synthesizes the two capture tracks — 9 hand-authored Method A
transcripts under [`prompt-only/runs/`](prompt-only/runs/) and 5 Method B
snapshots under [`libera/snapshots/`](libera/snapshots/) — into the spec's
§6 measurement table, §8 scorecard, and an explicit go/no-go call against
§9 and §10.

Two checks were run against this experiment's own artifacts specifically to
substantiate the claims below (not committed as new deliverables — the task
that produced them, TASK-007/008, only required `chain_is_intact`, not a
replay call):

- **Determinism.** Re-running `libera/runner.mojo` against
  `fixtures/issue-multiple-missing.yaml` a second time produced a `.txt`
  file byte-identical to the committed `libera/snapshots/issue-multiple-missing.txt`.
- **Replayability.** Calling `domain.replay.replay()` on that same run's
  trace reconstructed a `final_result`/`final_verdict` identical to the
  run's own `snapshot` — confirming the write log alone is sufficient to
  rebuild the settled state, without re-running the model.

## §6 Measurement table

| Measurement | Prompt-only agent (Method A) | Libera model (Method B) | Libera wins if | Observed result |
|---|---|---|---|---|
| Repeated instruction tokens | The full completeness contract is restated in every transcript's prompt. | `models/issue-completeness.yaml`'s `contract.expected` is declared once and read from the same fixed path by every invocation of `runner.mojo`. | The model workflow requires less repeated instruction context. | **Libera wins.** The 9 transcripts under `prompt-only/runs/` each restate the full contract block; their `token_estimate` values (`prompt-only/runs/*.md`) sum to 2028 tokens of repeated instruction text across 9 runs (219, 221×3, 234, 228, 228×3). `models/issue-completeness.yaml` contains that same contract exactly once, unmodified, regardless of how many fixtures or rounds it is run against (`libera/model-ref.md`). |
| Semantic drift | Agent may reinterpret completeness. | Verifier expression is fixed. | Meaning of complete stays stable across runs. | **Libera wins.** Across the 3 runs each of `issue-missing-root-cause` and `issue-multiple-missing`, Method A's `verdict`/`finding` held stable (`conforms`/`complete` in all 6 transcripts) but `next_action`/`explanation` wording differed every time (compare `issue-missing-root-cause-run1.md`, `-run2.md`, `-run3.md`). Method B has no wording to drift: re-running `runner.mojo` against the same fixture reproduced the committed snapshot byte-for-byte (see determinism check above). |
| Reproducibility | Outputs may vary. | Same input + same model gives same verdict. | Verdict is deterministic for identical inputs. | **Libera wins.** Method A's structured fields (verdict/finding) agreed 3/3 in this hand-authored capture, but that is not evidence of a live LLM's reproducibility — no LLM API was called, per the experiment's scope, so Method A's true reproducibility is untested here. Method B's reproducibility was directly demonstrated: identical fixture in, byte-identical trace out. |
| Inspectability | Reasoning buried in free-text `explanation`. | Contract, result, verdict, writes, snapshot are all visible as addressed writes. | A reviewer can point to where the rule and verdict happened. | **Libera wins, with a caveat.** Every file in `libera/snapshots/` states `chain_intact: true` and shows the addressed writes (`boundary/enter/contract.expected`, `movement/change/result.actual`, `exception/detect/verdict.conforms` or `movement/advance/verdict.conforms`, `boundary/exit/snapshot`) a reviewer can point to. The caveat, documented in `libera/model-ref.md`: the intermediate `finding` value (e.g. `missing_owner`) is computed and consumed by the fold but never itself addressed — only the bare `conforms` boolean is written at each `exception/detect`. A reviewer needs `model-ref.md`'s account of the model alongside the trace to know *which* field triggered a given deviation. Method A's `explanation` field states that in prose directly, with no second document required. |
| Reuse | Prompt copied or rewritten per fixture. | Same model runs against multiple issues. | The verification logic is reused without restating it. | **Libera wins.** `runner.mojo` reads `models/issue-completeness.yaml` and `models/writes-default.yaml` from the same fixed, unmodified paths (`MODEL_PATH`/`POLICY_PATH`) for all 5 fixtures — confirmed by every snapshot file sharing the identical `contract.expected` value. Method A's 9 transcripts each contain their own full copy of the prompt text; the rule was pasted into every file rather than referenced once. |

## §8 Scorecard

| Criterion | Pass threshold | Observed result |
|---|---|---|
| Reusable verification logic | Same model evaluates all five fixtures without rewriting the rule. | **Pass (B).** All 5 `libera/snapshots/*.txt` files carry the identical `contract.expected` from the one, unmodified `models/issue-completeness.yaml`. Method A's rule is re-pasted into all 9 transcripts, not referenced once. |
| Deterministic verdict | Same input + same model returns the same conforms/finding output. | **Pass (B).** Confirmed empirically: re-running `runner.mojo` on `issue-multiple-missing.yaml` reproduced the committed snapshot byte-for-byte. Method A's structured output agreed 3/3 across repeats in this capture, but the experiment cannot test a live prompt-only agent's determinism (no LLM API is called), so this is not a comparable pass for A. |
| Inspectable trace | Output includes contract/result/verdict and addressed writes. | **Pass (B).** Every snapshot file includes all four, chain-verified via `chain_is_intact`. Method A's output has no structured trace at all — see the Inspectability caveat above regarding `finding` specifically. |
| Reduced repeated context | Model workflow avoids restating the full rule in each evaluation request. | **Pass (B).** The rule lives once in `models/issue-completeness.yaml`. Method A restates the full contract in every one of the 9 transcripts (2028 estimated tokens of repetition, summed from `prompt-only/runs/*.md`'s `token_estimate` fields). |
| Clear explanation | A human can explain why the verdict happened by inspecting the model and trace. | **Tie.** Method A's `explanation` field is self-contained prose — no second document needed, but also not independently checkable against a rule definition. Method B's explanation is precise and reproducible once a reader also consults `libera/model-ref.md` for what `finding` values mean (since `finding` itself is never individually addressed in the trace — only `verdict.conforms` is). Neither method wins this one cleanly. |

## Go/no-go verdict

**Against §9** (worth continuing if Libera wins on at least 2 of the 5
listed dimensions): fewer repeated instructions (**won**), more consistent
verdicts (**won**), clearer trace of state changes (**won**), reusable
verification logic (**won**), easier explanation of why the verdict
happened (**tie**, not counted as a win). **4 of 5 dimensions won**, well
past the ≥2 threshold. **§9 verdict: continue.**

**Against §10** (continue building upward into Pages/Packages if Libera
wins on replayability, inspectability, or reduced repeated context,
addressed individually):

- **Replayability:** **Won.** All 5 committed snapshots report
  `chain_intact: true`. Calling `domain.replay.replay()` on the
  `issue-multiple-missing` trace reconstructed a `final_result` and
  `final_verdict` identical to the run's own snapshot — the log alone
  rebuilds the settled state. Method A produces no log; there is nothing to
  replay.
- **Inspectability:** **Won**, with the caveat above: the trace shows
  *that* a fold deviated (`exception/detect/verdict.conforms`) and, at
  `boundary/exit`, the final settled verdict — but a reader needs
  `model-ref.md`'s account of the model to know which field an
  intermediate deviation named, since `finding` itself is never addressed.
- **Reduced repeated context:** **Won.** The contract lives once in
  `models/issue-completeness.yaml`; Method A's 9 transcripts collectively
  restate it 9 times.

All three named dimensions won. **§10 verdict: continue building upward
into Pages and Packages** — a follow-on build this idea's scope
deliberately excludes (see `IDEA-001`'s "Out of scope").

Per §10's interpretation rules: this result does **not** claim Libera is
faster or cheaper in tokens than a real prompt-only agent — no runtime or
real API cost was measured, only a reproducible whitespace-token estimate
on hand-authored text. Nor does it treat the kernel itself as the product
value; the value demonstrated here is the reusable, verifiable, inspectable
*meaning* the model captures — the contract, the fixed verifier, and the
addressed write log — independent of what runs it.

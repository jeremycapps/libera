# Model reference: what Method B is actually running

This is a companion to the snapshot files in `snapshots/`. It says what model and
what write policy produced them, so a reader can interpret a snapshot without
re-deriving the semantics from YAML.

Method B runs against two files that already exist in the repository and are
**unmodified** for this experiment — no experiment-specific fields, no tuning, no
copies:

| File | Role |
|---|---|
| `models/issue-completeness.yaml` | The domain model: the contract, what conformance means, and what a verdict says |
| `models/writes-default.yaml` | The write policy: which state motions get addressed, and under what pressure |

Both are repo-root-relative. Nothing in `experiments/semantic-reconstruction-cost/`
writes to `models/`. The policy in particular is the repo's *default* policy — it is
shared with the counting model in `models/domain-count-level-0.yaml` and knows nothing
about issues, which is the point: it names slots and pressures, never domain concepts.

The behaviour described below is pinned by `tests/test_issue_model.mojo`; the
write-trace section mirrors `_addressed_run` in that file.

## The domain model

**Contract.** `contract.expected` declares three required fields:

```
root_cause: required
owner: required
resolution_path: required
```

**Result.** A Result is `{ actual, source? }`, supplied from outside. Absence is
explicit: a Result states a value or `null` for every declared field and does not omit
keys. Omitting `root_cause` is not "we looked and it is blank" — it is an
`unresolved_ref` error, because `ref: actual.root_cause` has nothing to resolve. The
fixtures therefore always carry all three keys.

**Verdict.** `Verdict = Evaluate(verify, { expected, actual })`, a record with
`type: Verdict`, `expected`, `actual`, `conforms`, and `finding`.

- `conforms` is true only when all three fields are non-null. Presence is what is
  checked, not usefulness: an empty string is present.
- `finding` names the **first** gap, in a fixed order: `root_cause`, then `owner`, then
  `resolution_path`. It is a nested `if`, so a Result missing all three reports
  `missing_root_cause`; missing owner and resolution path reports `missing_owner`. The
  possible values are `missing_root_cause`, `missing_owner`,
  `missing_resolution_path`, and `complete`.

Naming one gap at a time is the model's deliberate choice, not a runtime limit: a
supplier fixes one thing, and the next verify names the next. That is why the
single-gap fixtures converge in two rounds and the multi-gap fixture takes three.

**State fold.** `State_next = Evaluate(orchestrate, { state, output })` carries
`contract`, `result`, `verdict`, and `converged: ref output.conforms`. A run stops at
the first fold where `converged` is true; supplied Results after that are not consumed.

**What the model does not do.** It does not search, repair, or respond. Given only
incomplete Results it stays unconverged and emits no snapshot rather than inventing a
root cause. Deciding what to do about a deviation — route it back, ask for logs,
escalate — is a *response*, and responses belong to Strategy. This is stated in the
model's own header comment and is the reason nothing in the model writes to
`exception/respond`. The test asserts the string `respond` never appears in a trace.

## The write policy

`models/writes-default.yaml` declares four write candidates, each with a `when`, a
`pressure`, an `operation`, and a `slot`. Every fold evaluates all four and keeps the
ones whose `when` is true:

| When | Address | Value written |
|---|---|---|
| `event.is_first` | `boundary/enter/contract.expected` | the three required fields |
| always | `movement/change/result.actual` | the Result supplied this round |
| always | `movement/advance/verdict.conforms` if `output.conforms`, else `exception/detect/verdict.conforms` | the boolean `conforms` |
| `next.converged` | `boundary/exit/snapshot` | the settled snapshot |

The policy is contract-agnostic: nothing in it mentions `root_cause`, `owner`,
`resolution_path`, or `finding`. The one semantic-looking choice — advance versus
detect — is an `if` over `output.conforms`, evaluated by the kernel, not a decision made
in Mojo.

Note the consequence for a reader: **`finding` is never given its own address.** The
trace records `verdict.conforms` (a bare `true`/`false`). The named gap is visible only
inside the `boundary/exit` write's `final_verdict`, where it is always `complete`, and
in the run's returned snapshot. Intermediate findings such as `missing_owner` are
computed and consumed by the fold but do not appear in the log.

## What a converged run's write trace looks like

An address renders as `{pressure}/{operation}/{slot}`; the program name
(`issue-completeness`) is a sibling field, not part of the path. Each Write is
`{ id, step, address, value, prev }`, where `step` is the zero-based fold index, `id` is
derived from the slot and operation (`path.verdict_conforms_detect#0`), and `prev`
chains the whole run into one unbroken log — null only at the head.

### The two-round shape, as pinned by `_addressed_run`

Round 1 supplies an issue with `owner` and `resolution_path` but a null `root_cause`;
round 2 supplies a complete issue. That is **6 writes across 2 folds**:

```
fold 0   boundary/enter/contract.expected      the contract comes into scope
         movement/change/result.actual         the incomplete issue
         exception/detect/verdict.conforms     false — a deviation, named nowhere in the log
fold 1   movement/change/result.actual         the corrected issue
         movement/advance/verdict.conforms     true
         boundary/exit/snapshot                {contract, final_result, final_verdict}
```

`boundary/enter` appears once, on the fold that has not yet recorded a Result.
`boundary/exit` appears once, on the fold that converges. Everything between is one
`movement/change` plus one verdict write per round.

### Generalising to the other fixtures

For an N-round convergent run the trace is **2N + 2 writes**: 3 on the first fold
(enter, change, verdict), 2 on each middle fold (change, detect), 3 on the last
(change, advance, exit).

| Fixture | Rounds | Writes | Verdict writes in order |
|---|---|---|---|
| `issue-complete` | 1 | 4 | `movement/advance` |
| `issue-missing-root-cause` | 2 | 6 | `exception/detect`, `movement/advance` |
| `issue-missing-owner` | 2 | 6 | `exception/detect`, `movement/advance` |
| `issue-missing-resolution-path` | 2 | 6 | `exception/detect`, `movement/advance` |
| `issue-multiple-missing` | 3 | 8 | `exception/detect`, `exception/detect`, `movement/advance` |

The one-round case is the degenerate one: a single fold carries both `boundary/enter`
and `boundary/exit`. The three-round case is the interesting one: two
`exception/detect` writes before the final `movement/advance`, because the model names
one gap per round and the fixture repairs one gap per round.

### Classification

Each fold is classified from the pressures it emitted, not from a declared expression:
any `exception` pressure makes the fold an `exception`, otherwise `confirmed`. So the
two-round run classifies as `[exception, confirmed]` and the three-round run as
`[exception, exception, confirmed]`. Classification is part of the run's return value,
alongside `state`, `trace`, `converged`, and `snapshot` — it is not a write and does
not appear in the trace.

### When a run does not converge

If no supplied Result is complete, `converged` is false, **no `boundary/exit` write is
emitted, and no snapshot exists**. The log still chains intact; it simply ends on an
`exception/detect`. A snapshot is the settled durable output of convergence, so
building one from an unconverged state is an error rather than a half-filled record.

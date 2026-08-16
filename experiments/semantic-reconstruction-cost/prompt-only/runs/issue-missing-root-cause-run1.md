# Method A transcript — issue-missing-root-cause — run 1

`issue-missing-root-cause.yaml` has 2 rounds: round 0 is missing
`root_cause`, round 1 supplies it. This transcript captures the **terminal
round** (round 1, fully supplied) rather than the sequence — Method A, as
captured here, has no state or replay mechanism analogous to Method B's
fold-across-rounds in `domain/run.run()`; each transcript is one prompt, one
response, against one snapshot of the issue. A prompt-only agent given only
round 0 would instead report `finding: missing_root_cause` and `verdict:
does not conform`; that per-round behavior is not re-demonstrated per
transcript here, since it is identical in shape to what
`issue-missing-owner-run1.md` and `issue-missing-resolution-path-run1.md`
already show for their own missing field. This asymmetry — Method B
naturally folds a sequence of rounds into one convergence judgment, Method A
has no equivalent without a new harness — is itself part of what `results.md`
should describe under Inspectability/Reuse.

## prompt

```
You are reviewing a support issue. Decide whether it is complete.

An issue is complete only if it has all three of the following, each with a
real, non-null value:
- root_cause: what actually caused the problem
- owner: who is responsible for resolving it
- resolution_path: the plan to resolve it

If a field is absent, it will appear in the issue record below as `null` —
treat `null` as explicitly missing, never as "not checked yet."

Given the issue, return exactly these four fields:
- verdict: "conforms" if all three required fields are present and non-null,
  otherwise "does not conform"
- finding: one of "complete", "missing_root_cause", "missing_owner",
  "missing_resolution_path". If more than one field is missing, name the
  first missing field in this fixed order: root_cause, then owner, then
  resolution_path.
- next_action: what should happen next to move this issue forward, in prose
- explanation: why you reached this verdict, in prose

Issue:
id: "ISS-4512"
title: "Nightly export silently drops rows"
description: "The nightly account export lands with fewer rows than the source table, and the job still reports success."
root_cause: "The export paginates on created_at, so rows written while a page is in flight fall between two page boundaries and are never read."
owner: "dmitri"
resolution_path: "Re-run the export for the affected window and reconcile row counts before publishing."
```

## output

```
verdict: conforms
finding: complete
next_action: Dmitri should re-run the affected export window and reconcile row counts against the source table before republishing.
explanation: root_cause, owner, and resolution_path are all present and non-null now that the pagination bug has been diagnosed — root_cause explains the dropped rows as a created_at pagination race, owner is dmitri, and resolution_path is a concrete re-run-and-reconcile plan.
```

## token_estimate

221

## verdict

conforms

## finding

complete

## next_action

Dmitri should re-run the affected export window and reconcile row counts
against the source table before republishing.

## explanation

root_cause, owner, and resolution_path are all present and non-null now
that the pagination bug has been diagnosed — root_cause explains the
dropped rows as a created_at pagination race, owner is dmitri, and
resolution_path is a concrete re-run-and-reconcile plan.

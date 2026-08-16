# Method A transcript — issue-multiple-missing — run 1

`issue-multiple-missing.yaml` has 3 rounds: round 0 is missing both
`root_cause` and `owner`, round 1 supplies `root_cause`, round 2 supplies
`owner`. This transcript captures the **terminal round** (round 2, fully
supplied), for the same reason given in `issue-missing-root-cause-run1.md`.
Unlike Method B — which, per `libera/snapshots/issue-multiple-missing.txt`,
needs two `exception/detect` folds (naming `missing_root_cause` then
`missing_owner`, one gap per round, per the model's fixed check order) to
walk from round 0 to convergence — a Method A transcript captured only
against the terminal round never observes that two-step narrowing at all;
it sees one flat snapshot with everything already filled in. That gap is
itself evidence for `results.md`'s Inspectability row.

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
id: "ISS-4601"
title: "Annual plans billed at the monthly rate"
description: "Accounts that upgraded to an annual plan mid-term were charged one month of list price instead of twelve, across the last two billing runs."
root_cause: "The mid-term upgrade path rebuilds the subscription without copying the plan interval multiplier, so the invoice falls back to a one-month term."
owner: "marcus"
resolution_path: "Credit the affected accounts and re-issue corrected invoices before the next billing run."
```

## output

```
verdict: conforms
finding: complete
next_action: Marcus should credit the affected accounts and re-issue corrected annual invoices before the next billing run.
explanation: root_cause, owner, and resolution_path are all present and non-null — the dropped interval multiplier on mid-term upgrades is diagnosed, marcus owns it, and resolution_path covers both the customer credit and the corrected re-invoicing.
```

## token_estimate

228

## verdict

conforms

## finding

complete

## next_action

Marcus should credit the affected accounts and re-issue corrected annual
invoices before the next billing run.

## explanation

root_cause, owner, and resolution_path are all present and non-null — the
dropped interval multiplier on mid-term upgrades is diagnosed, marcus owns
it, and resolution_path covers both the customer credit and the corrected
re-invoicing.

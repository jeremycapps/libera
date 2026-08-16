# Method A transcript — issue-multiple-missing — run 3

Second independent repeat of `issue-multiple-missing-run1.md`. Same prompt
as run 1 and run 2; authored independently of both.

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
next_action: Route to marcus to process the credits and reissue the twelve corrected invoices before the next run closes.
explanation: The issue states a specific root cause (the copied-interval-multiplier bug), a specific owner (marcus), and a specific resolution_path (credit plus re-invoice) — all three required fields are present and non-null, which is all the stated rule checks, so this conforms and is complete.
```

## token_estimate

228

## verdict

conforms

## finding

complete

## next_action

Route to marcus to process the credits and reissue the twelve corrected
invoices before the next run closes.

## explanation

The issue states a specific root cause (the copied-interval-multiplier
bug), a specific owner (marcus), and a specific resolution_path (credit
plus re-invoice) — all three required fields are present and non-null,
which is all the stated rule checks, so this conforms and is complete.

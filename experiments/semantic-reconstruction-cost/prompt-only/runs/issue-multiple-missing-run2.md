# Method A transcript — issue-multiple-missing — run 2

Independent repeat of `issue-multiple-missing-run1.md`, for the
reproducibility/drift measurement in `results.md`. Same prompt (template +
terminal-round issue) as run 1; authored as a fresh hand-simulation — see
run 1 for the round-context note (this fixture's 3-round walk to
convergence is invisible to a Method A transcript captured only against the
terminal round).

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
next_action: Have marcus issue the account credits and corrected invoices ahead of the next billing cycle, and flag the upgrade path for a fix so this doesn't recur.
explanation: root_cause, owner, and resolution_path are all filled in — the interval-multiplier bug is diagnosed, marcus is the named owner, and there's a stated plan to credit and re-invoice. All three required fields are non-null, so the issue conforms.
```

## token_estimate

228

## verdict

conforms

## finding

complete

## next_action

Have marcus issue the account credits and corrected invoices ahead of the
next billing cycle, and flag the upgrade path for a fix so this doesn't
recur.

## explanation

root_cause, owner, and resolution_path are all filled in — the
interval-multiplier bug is diagnosed, marcus is the named owner, and
there's a stated plan to credit and re-invoice. All three required fields
are non-null, so the issue conforms.

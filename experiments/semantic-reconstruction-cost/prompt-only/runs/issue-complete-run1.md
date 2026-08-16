# Method A transcript — issue-complete — run 1

Single-round fixture: `issue-complete.yaml` has exactly one round, and that
round is already complete, so there is no terminal-vs-earlier-round
distinction to note here.

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
id: "ISS-4417"
title: "Checkout returns 502 for EU customers"
description: "Customers billing to EU addresses see a 502 at the payment step. US and APAC checkouts are unaffected."
root_cause: "The TLS certificate on the EU payment gateway expired at 02:00 UTC and the proxy refused the upstream handshake."
owner: "priya"
resolution_path: "Renew the gateway certificate and add a 14-day expiry alert to the on-call rotation."
```

## output

```
verdict: conforms
finding: complete
next_action: Hand the issue to priya to execute the certificate renewal and add the expiry alert; no further completeness review is needed.
explanation: All three required fields are present and non-null — root_cause names the expired TLS certificate and the handshake failure it caused, owner is priya, and resolution_path lays out both the immediate fix and a preventive alert. The issue is ready to move forward.
```

## token_estimate

219

## verdict

conforms

## finding

complete

## next_action

Hand the issue to priya to execute the certificate renewal and add the
expiry alert; no further completeness review is needed.

## explanation

All three required fields are present and non-null — root_cause names the
expired TLS certificate and the handshake failure it caused, owner is
priya, and resolution_path lays out both the immediate fix and a
preventive alert. The issue is ready to move forward.

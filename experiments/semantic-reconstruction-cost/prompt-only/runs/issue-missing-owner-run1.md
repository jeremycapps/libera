# Method A transcript — issue-missing-owner — run 1

`issue-missing-owner.yaml` has 2 rounds: round 0 is missing `owner`, round 1
supplies it. This transcript captures the **terminal round** (round 1),
for the same reason given in `issue-missing-root-cause-run1.md`: Method A as
captured here has no state/replay mechanism across rounds, so each
transcript is one prompt against one snapshot of the issue rather than a
folded sequence.

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
id: "ISS-4530"
title: "Mobile app logs users out after fifteen minutes"
description: "iOS and Android users are returned to the sign-in screen roughly fifteen minutes into a session, even while actively using the app."
root_cause: "The refresh token is minted with the access token's TTL, so it expires at the same moment the session it is meant to renew."
owner: "sam"
resolution_path: "Issue refresh tokens with a 30-day TTL and add a regression test that asserts the two lifetimes differ."
```

## output

```
verdict: conforms
finding: complete
next_action: Assign the fix to sam: issue refresh tokens with a 30-day TTL and add the regression test asserting the two token lifetimes diverge.
explanation: root_cause, owner, and resolution_path are all present and non-null — the refresh-token/access-token TTL collision is diagnosed, sam now owns it, and resolution_path names both the fix and a regression test to prevent recurrence.
```

## token_estimate

234

## verdict

conforms

## finding

complete

## next_action

Assign the fix to sam: issue refresh tokens with a 30-day TTL and add the
regression test asserting the two token lifetimes diverge.

## explanation

root_cause, owner, and resolution_path are all present and non-null — the
refresh-token/access-token TTL collision is diagnosed, sam now owns it, and
resolution_path names both the fix and a regression test to prevent
recurrence.

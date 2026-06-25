# Libera Protocol

Libera v1 is YAML-first.

Libera defines replayable workstream state paths.

## Core model

```text
Execution path  = how work flows
Governance path = how work is allowed, aligned, and triaged
```

## Path format

```text
{type}/{id}/{field}
```

Example:

```text
task/update_hero_layout/status = ready_for_review
```

## Boundary

Libera does not record observations.
Libera does not decide truth.
Libera validates workstream paths and local values.

## Keeper

```text
Libera defines the workstream address.
Workstream files define allowed local values.
Timpos records observed changes.
Corus replays changes into coordination.
```

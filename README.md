# Libera

A small open spec for defining replayable workstream state paths.

Libera defines where state lands inside a workstream. Timpos records the moment.

## Path format

A Libera path has the form:

```text
{type}/{id}/{field}
```

Example:

```text
task/update_hero_layout/status = ready_for_review
```

## Core model

Libera v1 has two mirrored paths:

```text
Execution path  = how work flows
Governance path = how work is allowed, aligned, and triaged
```

They are organized around three workstream pressures:

```text
Boundary  = work enters or exits the stream
Movement  = work advances or changes inside the stream
Exception = work deviates from expected state
```

## Standard types

```text
Boundary
Execution: request, deliverable
Governance: approval, acceptance

Movement
Execution: task, change
Governance: review, decision

Exception
Execution: issue, incident
Governance: validation, escalation
```

## Boundaries

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
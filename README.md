# Libera

A small open spec for defining replayable program state paths.

Libera defines where state lands inside a program. Timpos records the moment.

## Program

A Program is an authored workflow address space.

A program defines the valid paths that operational state can occupy. In plain language, a program may also be called a workstream when that improves readability for business or operations audiences.

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

They are organized around three program pressures:

```text
Boundary  = work enters or exits the program
Movement  = work advances or changes inside the program
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
Libera validates program paths and local values.

## Keeper

```text
Libera defines the program address.
Program files define allowed local values.
Timpos records observed changes.
Corus replays changes into coordination.
```

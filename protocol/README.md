# Libera Protocol

Libera v1 is YAML-first.

Libera defines replayable program state paths.

## Program

A Program is an authored workflow address space.

A program defines the valid paths that operational state can occupy. In plain language, a program may also be called a workstream when that improves readability for business or operations audiences.

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
Libera validates program paths and local values.

## Keeper

```text
Libera defines the program address.
Program files define allowed local values.
Timpos records observed changes.
Corus replays changes into coordination.
```

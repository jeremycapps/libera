# Libera Protocol

Libera v2 is YAML-first.

Libera defines replayable program state addresses.

`libera.schema.yaml` in this directory is the canonical specification. Everything else in
this repository — including the Mojo runtime — implements or references it.

## Program

A Program is an authored workflow address space.

A program defines the valid addresses that operational state can occupy. In plain
language, a program may also be called a workstream when that improves readability for
business or operations audiences.

## Core model

```text
Pressure  = the situation acting on a program
Operation = the motion within that situation
Slot      = the addressable state location
```

## Path format

```text
{pressure}/{operation}/{slot}
```

Example:

```text
movement/change/facia_surface_model.status = updated
```

`program` is a required field on a path, but is not part of the rendered path format — it
is carried alongside, as a sibling. A path is a record with identity, not a string:

```yaml
- id: path.facia_surface_model_status
  program: program.protocol_design
  pressure: movement
  operation: change
  slot: facia_surface_model.status
```

## Pressures and operations

Each operation belongs to exactly one pressure. There are six pairs and no others.

```text
boundary    enter    Something comes into scope.
            exit     Something leaves scope or becomes output.

movement    advance  Something moves forward.
            change   Something is altered.

exception   detect   Deviation is identified.
            respond  Deviation is acted on.
```

## Boundary

Libera does not define domain types.
Libera does not define execution or meaning.
Libera does not record observations.
Libera does not decide truth.
Libera does not render use surfaces.

These boundaries are claims about **this protocol**, not about the repository. The
repository also contains a reference runtime that does evaluate and does assign meaning;
it does so in layers above this one, and never inside it.

## Keeper

```text
Libera defines the program address.
Program files define allowed local values.
Domain assigns meaning to addressed motion.
Timpos records observed changes.
Corus replays changes into coordination.
```

## Predecessor

v1 used `{type}/{id}/{field}` over a fixed vocabulary of twelve domain types. It is
superseded, archived under `archive/v1/`, and explained in `docs/migration_v1_to_v2.md`.

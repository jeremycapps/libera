# The Address Protocol

Address is the layer of Libera that records **where a value belongs and what transition
occurred**. It is YAML-first, and `address.schema.yaml` in this directory is canonical.

Address is one layer of a larger platform. Libera itself composes, shares, and deploys
executable semantic models; this protocol is the part that gives their state motion a
stable, replayable location.

## Program

A Program is an authored address space.

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
is carried alongside, as a sibling. A path is a record with identity, not a string, and
identity is what makes it replayable:

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

## Filesystem rendering

A runtime may mount an address as a file:

```text
programs/protocol_design/movement/change/facia_surface_model/status.yaml
```

Address defines the grammar. A host decides whether to mount it.

## What this protocol does not do

```text
Address does not define domain types.
Address does not define execution or meaning.
Address does not record observations.
Address does not decide truth.
Address does not coordinate objectives.
Address does not render use surfaces.

Address validates program addresses and local values.
```

**These are claims about this protocol, not about Libera.** Libera is a platform for
composing and deploying executable semantic models — it very much defines execution and
meaning. It does so in layers above this one, never inside it:

```text
kernel     evaluates expressions, knows nothing above it
address    records where a value belongs        <- this protocol
domain     supplies coordination semantics
strategy   supplies search and response
```

Keeping those claims true of Address is what lets Domain be swapped, extended, or replaced
without touching the address grammar. A layering test enforces it.

## Keeper

```text
Address defines where motion happened.

Pressure names the situation.
Operation names the motion.
Slot names the addressable state.

Domain names what the motion means.
Timpos records observed changes.
Corus evaluates objective satisfaction.
Facia routes active state into use.
```

## Predecessor

v1 used `{type}/{id}/{field}` over a fixed vocabulary of twelve domain types. It is
superseded, archived under `archive/v1/`, and explained in `docs/migration_v1_to_v2.md`.

# Libera

A small open spec for defining replayable program state addresses.

Libera defines filesystem motion. Domain defines what that motion means. Timpos records observed state at the address.

## Version

Libera v2 removes domain-specific path types from the core protocol.

Libera does not define `request`, `deliverable`, `task`, `decision`, `validation`, or other business/workflow types.

Those names belong to a Domain binding.

## Program

A Program is an authored workflow address space.

A program defines the valid addresses that operational state can occupy. In plain language, a program may also be called a workstream when that improves readability for business or operations audiences.

## Path format

A Libera path has the form:

```text
{pressure}/{operation}/{slot}
```

Example:

```text
movement/change/facia_surface_model.status = updated
```

As a mounted filesystem path, a Domain OS runtime may render the same address as:

```text
programs/protocol_design/movement/change/facia_surface_model/status.yaml
```

Libera defines the address grammar. Domain OS mounts addresses as files.

## Core model

Libera v2 has three core concepts:

```text
Pressure  = situation acting on the program
Operation = motion inside that situation
Slot      = addressable state location
```

## Pressures and operations

```text
Boundary
  enter
  exit

Movement
  advance
  change

Exception
  detect
  respond
```

### Boundary

Boundary is where work crosses a program edge.

```text
enter = something comes into scope
exit  = something leaves scope or becomes output
```

### Movement

Movement is where work progresses inside the program.

```text
advance = something moves forward
change  = something is altered
```

### Exception

Exception is where work deviates from expected state.

```text
detect  = deviation is identified
respond = deviation is acted on
```

## Domain bindings

Domain binds Libera motion to domain meaning.

Example:

```yaml
binding:
  id: binding.facia_surface_model_change
  libera:
    pressure: movement
    operation: change
    slot: facia_surface_model.status
  type: schema_change
```

Libera knows only:

```text
movement/change/facia_surface_model.status
```

Domain may interpret that as:

```text
schema_change
customer_request
model_delta
clearance_violation
approval
validation
```

## Boundaries

Libera does not define domain types.
Libera does not define execution or meaning.
Libera does not record observations.
Libera does not decide truth.
Libera does not coordinate objectives.
Libera does not render use surfaces.

Libera validates program addresses and local values.

## Keeper

```text
Libera defines filesystem motion.

Pressure names the situation.
Operation names the motion.
Slot names the addressable state.

Domain names what the motion means.
Timpos records observed changes.
Corus evaluates objective satisfaction.
Facia routes active state into use.
```

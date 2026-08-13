# Libera v1 to v2 Migration

Libera v2 removes domain-specific path types from the core protocol.

## What changed

### v1-style

```text
{type}/{id}/{field}
```

Example:

```text
task/update_schema/status
```

### v2-style

```text
{pressure}/{operation}/{slot}
```

Example:

```text
movement/change/facia_surface_model.status
```

## Removed from Libera core

```text
execution/governance
request/deliverable
approval/acceptance
task/change
review/decision
issue/incident
validation/escalation
```

These are no longer Libera primitives.

They should be represented as Domain bindings.

## New core grammar

```text
boundary:
  enter
  exit

movement:
  advance
  change

exception:
  detect
  respond
```

## Migration pattern

```text
old type -> domain binding -> Libera pressure/operation/slot
```

Example:

```yaml
binding:
  id: binding.update_schema
  libera:
    pressure: movement
    operation: change
    slot: schema.status
  type: schema_change
```

## Keeper

```text
Libera v2 defines motion.
Domain defines meaning.
```

# Timpos Compatibility

Libera and Timpos answer different questions.

```text
Libera: where does state land inside the program?
Timpos: when and where was that state observed?
```

## Libera address

```text
{pressure}/{operation}/{slot}
```

Example:

```text
movement/change/result.actual
```

## Moment shape

A Moment records a value at a Libera address using a Timpo.

```yaml
moment:
  id: moment.001
  program: client_homepage_update
  path: movement/change/task_update_hero_layout.status
  value: ready_for_review
  timpo: timpo.001
  previous: moment.000
```

## Boundary

Libera does not record observations.

Timpos does not define program vocabulary.

Corus may replay Timpos Moments over Libera addresses to derive coordinated state.

## Relationship to the runtime's Write

This repository's reference runtime emits a `Write` for every addressed state change:

```yaml
write:
  id: path.result_actual_change#0
  step: 0
  address: { program, pressure, operation, slot }
  value: { count: 2 }
  prev: path.contract_expected_enter#0
```

A Write is **a Moment minus the timestamp**. The `prev` chain is structure; the timestamp
is observation, and observation is Timpos's concern, not Libera's. The runtime therefore
stops at the chain and leaves the seam clean — a Timpo can be attached to a Write without
either side having to know about the other.

One consequence worth naming: a snapshot stored *inside* the log carries no trace, because
its position in the log is its trace. Only a snapshot handed out of the log has one
projected onto it. See `docs/superpowers/specs/2026-08-12-libera-convergence-design.md` §5a.

## Keeper

```text
Libera defines the address.
Domain assigns meaning to addressed motion.
Timpos records the observed change.
Corus replays changes into coordination.
```

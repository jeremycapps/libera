# Timpos Compatibility

Libera and Timpos answer different questions.

```text
Libera: where does state land inside the workstream?
Timpos: when and where was that state observed?
```

## Libera path

```text
{type}/{id}/{field}
```

Example:

```text
task/update_hero_layout/status
```

## Moment shape

A Moment records a value at a Libera path using a Timpo.

```yaml
moment:
  id: moment.001
  workstream: client_homepage_update
  path: task/update_hero_layout/status
  value: ready_for_review
  timpo: timpo.001
  previous: moment.000
```

## Boundary

Libera does not record observations.

Timpos does not define workstream vocabulary.

Corus may replay Timpos Moments over Libera paths to derive coordinated state.

## Keeper

```text
Libera defines the address.
Timpos records the observed change.
Corus replays changes into coordination.
```

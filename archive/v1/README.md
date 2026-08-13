# Libera v1 — superseded

This directory holds Libera v1 as it stood before the v2 path grammar replaced it.
Nothing here is current. It is kept because v1 made distinctions v2 dropped without
replacing, and because the migration note in `docs/migration_v1_to_v2.md` refers to it.

## What v1 was

A path was `{type}/{id}/{field}`:

```text
task/update_hero_layout/status = ready_for_review
```

The `type` came from a fixed vocabulary of twelve domain concepts, paired across an
execution and a governance track:

```text
boundary    request, deliverable   |  approval, acceptance
movement    task, change           |  review, decision
exception   issue, incident        |  validation, escalation
```

## Why it was replaced

Those twelve types are domain meanings, and a protocol that names them cannot claim to be
neutral about meaning. v2 removed all of them, keeping only the three pressures they were
grouped under, and pushed the concepts out to Domain bindings:

```text
v1  {type}/{id}/{field}
v2  {pressure}/{operation}/{slot}
```

`docs/migration_v1_to_v2.md` closes with the reason: *"Libera v2 defines motion. Domain
defines meaning."*

## What survived

Two things from v1 are still load-bearing and did not move here:

- **The field vocabulary** — `status`, `owner`, `result`, `priority`, `due`, `evidence`,
  `authority` — lives on in `docs/fields.md`. v2 did not delete it; it moved *inside* the
  slot. A v2 slot is shaped `<object>.<field>`, and `movement/change/facia_surface_model.status`
  ends in one of these fields.
- **The `priority↔evidence` / `due↔authority` symmetry**, which v2 has no replacement for.
  Execution needs importance and time; governance needs trust and permission.

## Retrieving the original

The files here are the whole v1 surface, but the repository at that point is tagged:

```bash
git show v1-final          # the last commit before the v2 refactor
git show spec-only         # Libera as a pure spec, before the runtime was consolidated in
```

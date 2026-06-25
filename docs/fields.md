# Fields

Fields are replayable properties on a workstream path.

```text
{type}/{id}/{field} -> value
```

## Standard fields

```text
Universal:
status, owner, result

Execution:
priority, due

Governance:
evidence, authority
```

## Field meanings

```text
status    = where it is in its lifecycle
owner     = who carries it
result    = what happened
priority  = how much it matters
due       = when it matters
evidence  = why it can be trusted
authority = who or what can make it count
```

## Field symmetry

```text
priority <-> evidence
due      <-> authority
```

Execution needs pressure:

```text
priority gives importance
due gives time
```

Governance needs legitimacy:

```text
evidence gives trust
authority gives permission
```

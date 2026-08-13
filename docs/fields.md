# Fields

Fields are replayable properties at a Libera address.

In v1 a field was the last segment of the path itself (`{type}/{id}/{field}`). v2 removed
that grammar but not the vocabulary: a field is now the tail of a **slot**.

```text
{pressure}/{operation}/{object}.{field}
```

```text
movement/change/facia_surface_model.status
                └── object ─────┘ └field┘
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

## Reserved, not enforced

These names are a **reserved vocabulary with defined meanings**, not a constraint on
slots. The runtime does not reject a slot whose field is something else, and should not:
its own Domain layer addresses `contract.expected` and `verdict.conforms`, which are
neither `status` nor `owner` nor `result`. Forcing those into this list would smuggle
workflow-management meaning back into a protocol that removed exactly that in v2.

Four of these names already appear in the Domain layer's own shapes, and carry the
meanings above wherever they do: `result`, `evidence`, `authority`, `owner`.

## Where the governance half is still missing

`priority↔evidence` and `due↔authority` have no counterpart yet in the Strategy layer,
which is unbuilt. Its Boundary is currently all execution — `max_depth`, `max_cost`,
`exhausted_when` — with no governance equivalent:

```text
execution   max_depth · max_cost · exhausted_when        <- priority, due
governance  evidence_required · authority_required       <- evidence, authority
```

This is also where escalation belongs. Escalation is not a peer of `detect`; it is a
species of `respond`, distinguished by carrying an `authority` — which is what a
deviation needs when it exceeds the layer's own ability to resolve it. v1's own triage
rule predicted this split: non-urgent exceptions map to validation, urgent ones to
escalation; urgency is `due`, and `due ↔ authority`.

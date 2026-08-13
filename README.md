# Libera

A protocol for addressing replayable program state, and its Mojo reference runtime.

Libera defines *where* state motion happened and under what pressure. It does not define
what that motion means, when it was observed, or whether it satisfies anything — those
belong to Domain, Timpos, and Corus respectively.

```text
Pressure  = the situation acting on the program
Operation = the motion within that situation
Slot      = the addressable state location
```

```text
{pressure}/{operation}/{slot}

movement/change/facia_surface_model.status = updated
```

`program` is a required field on a path, carried alongside rather than rendered into it.
A path is a record with identity, not a string — which is what makes it replayable.

## What is in this repository

| | |
|---|---|
| `protocol/` | **The specification.** `libera.schema.yaml` is canonical. |
| `kernel/` `modelir/` `address/` `domain/` | The Mojo reference runtime. |
| `models/` | Model documents: a Domain contract, and the default write policy. |
| `docs/` | Field vocabulary, Timpos compatibility, the v1→v2 migration, runtime internals. |
| `examples/` | v2 path examples. |
| `archive/v1/` | Libera v1, superseded and kept for reference. |
| `tests/` `testkit/` | 604 assertions. `./run_tests.sh` is the entry point. |

The protocol is the stable artifact. The runtime is one implementation of it, and the
conformance test reads `protocol/libera.schema.yaml` directly — so the two cannot drift
apart without the suite failing.

## Pressures and operations

Each operation belongs to exactly one pressure. There are six pairs and no others.

```text
boundary    enter    something comes into scope
            exit     something leaves scope or becomes output

movement    advance  something moves forward
            change   something is altered

exception   detect   deviation is identified
            respond  deviation is acted on
```

## Domain bindings

Libera knows only the address. Domain says what it means.

```yaml
binding:
  id: binding.facia_surface_model_change
  libera:
    pressure: movement
    operation: change
    slot: facia_surface_model.status
  type: schema_change
```

The same address may be bound as `schema_change`, `customer_request`, `model_delta`,
`clearance_violation`, `approval`, or `validation`. None of those words appear in the
protocol, and that is the point — v1 defined twelve such types and v2 removed all of them.

## Filesystem rendering

A Domain OS runtime may mount an address as a file:

```text
programs/protocol_design/movement/change/facia_surface_model/status.yaml
```

Libera defines the address grammar. Domain OS mounts addresses as files.

## Boundaries

```text
Libera does not define domain types.
Libera does not define execution or meaning.
Libera does not record observations.
Libera does not decide truth.
Libera does not coordinate objectives.
Libera does not render use surfaces.

Libera validates program addresses and local values.
```

**These are claims about the protocol, not about this repository.** The repository also
contains a runtime that evaluates expressions and assigns meaning. It does so in layers
strictly above the protocol, never inside it, and a layering test enforces the separation
that used to be enforced by these being separate projects:

```text
kernel/     Value · Ref · Expression · Evaluate      knows nothing above it
modelir/    YAML → Model IR                          knows syntax, not meaning
address/    Address · Write                          knows addresses, not meaning
domain/     Contract · Result · Verdict · State      knows meaning
strategy/   Operator · Goal · Boundary · Heuristic   not built
```

A module may not import from a layer above it. The test enumerates the files rather than
listing them, so the guard does not rot as the runtime grows.

## Running the tests

```bash
./run_tests.sh
```

Exits non-zero on any failure. Requires Mojo 0.26.2.0 or compatible; there are no other
dependencies.

## Keeper

```text
Libera defines the address.

Pressure names the situation.
Operation names the motion.
Slot names the addressable state.

Domain names what the motion means.
Timpos records observed changes.
Corus evaluates objective satisfaction.
Facia routes active state into use.
```

## Further reading

- [`protocol/README.md`](protocol/README.md) — the protocol in full
- [`docs/runtime.md`](docs/runtime.md) — how the Mojo runtime works
- [`docs/fields.md`](docs/fields.md) — the reserved field vocabulary
- [`docs/timpos_compatibility.md`](docs/timpos_compatibility.md) — the Libera/Timpos seam
- [`docs/migration_v1_to_v2.md`](docs/migration_v1_to_v2.md) — what v2 removed and why
- [`archive/v1/README.md`](archive/v1/README.md) — the superseded v1 protocol

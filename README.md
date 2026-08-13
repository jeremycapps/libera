# Libera

A page-based platform for composing, sharing, and deploying executable semantic models.

> Write the model once. Share the meaning. Deploy the behavior.

Libera exists so people can build shared models of how work, time, coordination,
interfaces, verification, and execution should behave. These are semantic models and
ontologies, not machine-learning weights — they describe meaning, structure, rules, roles,
states, transitions, evidence, and authority. Libera makes them executable.

A model should not be trapped inside a codebase, a whiteboard, a task manager, or a single
agent session. It should be a durable page that humans can read, teams can improve, agents
can execute, and systems can depend on.

## Page → Package → Deployment

| Unit | What it is |
|---|---|
| **Page** | The authoring unit. A markdown body explaining the model, plus executable metadata declaring what it imports, exports, verifies, and how it participates in execution. |
| **Package** | The shareable unit. A versioned collection of pages, schemas, examples, tests, and runtime metadata — importable, remixable, forkable, testable. |
| **Deployment** | The live unit. A package running behind a usable boundary: an API, an MCP server, a CLI, a workspace, a calendar assistant, an interface surface. |

## What is built today

**The deterministic runtime — the technical spine.** The page, package, and deployment
layers are not built yet; this repository is the foundation they will sit on.

```text
kernel/     Value · Ref · Expression · Evaluate      evaluates, knows nothing above it
modelir/    YAML → Model IR                          normalizes, knows syntax not meaning
address/    Address · Write                          records where a value belongs
domain/     Contract · Result · Verdict · State      supplies coordination semantics
strategy/   Operator · Goal · Boundary · Heuristic   not built
```

The kernel's whole execution surface is one principle:

```text
Value_out = Evaluate(Expression, Props)
```

The boundary that makes this composable: **the kernel does not know what a contract or a
verdict means.** Domain is one protocol compiled onto the runtime — Contract → Result →
Verdict → CurrentState → Snapshot. Address records where values belong and what transition
occurred. Strategy will later choose candidates, repairs, retries, heuristics, and
escalations when convergence fails.

A layering test enforces this: a module may not import from a layer above it.

## The Address protocol

Address answers *where state motion happened and under what pressure* — without knowing
what the motion means. That is Domain's job.

```text
{pressure}/{operation}/{slot}

movement/change/facia_surface_model.status = updated
```

```text
boundary    enter    something comes into scope
            exit     something leaves scope or becomes output

movement    advance  something moves forward
            change   something is altered

exception   detect   deviation is identified
            respond  deviation is acted on
```

`protocol/libera.schema.yaml` is the canonical schema, and the conformance test reads it
directly — so the runtime cannot drift from the protocol it ships.

The protocol deliberately defines no domain types. It does not name `request`,
`deliverable`, `task`, `decision`, `validation`, or any other workflow concept; those are
Domain bindings. An earlier version did name twelve such types, and removing them is what
`archive/v1/` records.

## Repository map

| | |
|---|---|
| `protocol/` | The Address protocol. `libera.schema.yaml` is canonical. |
| `kernel/` `modelir/` `address/` `domain/` | The deterministic runtime. |
| `models/` | Model documents: a Domain contract, and the default write policy. |
| `docs/` | Runtime internals, field vocabulary, Timpos compatibility, v1→v2 migration. |
| `examples/` | Address examples. |
| `archive/v1/` | The superseded v1 protocol, kept for reference. |
| `tests/` `testkit/` | 604 assertions. `./run_tests.sh` is the entry point. |

## Running the tests

```bash
./run_tests.sh
```

Exits non-zero on any failure. Requires Mojo 0.26.2.0 or compatible; there are no other
dependencies.

## The ecosystem

```text
Address defines where motion happened.
Domain names what the motion means.
Timpos records observed changes.
Corus evaluates objective satisfaction.
Facia routes active state into use.
```

## Further reading

- [`docs/north-star.md`](docs/north-star.md) — the product vision this serves
- [`docs/runtime.md`](docs/runtime.md) — how the runtime works
- [`protocol/README.md`](protocol/README.md) — the Address protocol in full
- [`docs/fields.md`](docs/fields.md) — the reserved field vocabulary
- [`docs/timpos_compatibility.md`](docs/timpos_compatibility.md) — the Address/Timpos seam
- [`docs/migration_v1_to_v2.md`](docs/migration_v1_to_v2.md) — what v2 removed and why
- [`archive/v1/README.md`](archive/v1/README.md) — the superseded v1 protocol

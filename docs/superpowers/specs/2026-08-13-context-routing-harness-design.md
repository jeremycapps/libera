# Context-routing experiment: scripted harness design

**Date:** 2026-08-13

**Status:** implementation contract

**Predecessor:** `2026-08-13-context-routing-execution-design.md`

**Pilot record:** `../../session-handoff-2026-08-13-context-routing-pilot.md`

## Purpose

The pilot validated the projections, topology, gate, and contamination controls, but
could not attribute usage below an orchestrator that owned two subagents. This harness
replaces that one opaque process with an explicit state machine. Each role invocation is
one Claude CLI process, so its provider-reported usage belongs to exactly one role, phase,
and loop.

The harness does not choose a winning context policy and does not launch repetitions by
default. A real run requires an explicit repetition count because it creates nine or more
model sessions and therefore carries material cost.

## Preserved invariant

> Same start state. Same domain goal. Same operational topology. Different context
> projection.

The source, three projections, evaluator contract, gate, model, role count, role order,
repair and escalation limits, and permissions remain fixed across arms. Only the projected
role context varies.

The execution substrate necessarily changes from the pilot: role processes no longer use
the Agent tool. That is the point of the scripted harness and means harness results are a
new experiment version, not extra observations appended to the pilot.

## State machine

```text
prepare isolated clone at frozen commit
  -> orchestrator/start
  -> implementer/initial
  -> validator/initial
       -> conforming: deterministic gate -> orchestrator/finalize
       -> defects: implementer/repair[N] -> validator/repair[N]
       -> escalation: orchestrator/escalation[N]
            -> answered: resume requesting role
            -> unanswered: blocked
       -> repair or escalation boundary: exhausted
  -> freeze patch, repository state, event stream, and candidate result
```

The harness, not an agent, enforces ordering and numerical boundaries. The orchestrator
still owns semantic decisions: whether a request is an escalation, whether supplied
context answers it, and the final status. Every model-issued transition must validate
against the same JSON schema for every arm.

## Isolation

Each repetition creates a fresh run directory and three independent local clones. A clone
is pinned to the frozen commit, has one local `arm` branch, and has no sibling remotes or
refs. Projection and telemetry files remain outside clones. Agents receive prompt bytes;
they are not given paths to canonical source or sibling projections.

Role tool sets are fixed:

- orchestrator: no repository tools;
- implementer: read, search, shell, and edit tools inside its clone;
- validator: read, search, and shell tools; the prompt forbids writes;
- all roles: no Agent, web, browser, or network tool.

The CLI itself needs provider network access. "No network" describes agent tools, not the
model transport.

## Telemetry contract

One append-only `events.jsonl` is the authoritative trace. Every event carries run, arm,
role, phase, loop, monotonic sequence, wall-clock timestamps, and refs to immutable raw
artifacts. Model invocations additionally carry:

- session id and resume parent;
- exact prompt SHA-256 and a prompt artifact ref;
- exact CLI argv with secrets excluded;
- provider model identifier and stop reason;
- provider-reported `input_tokens`, `cache_creation_input_tokens`,
  `cache_read_input_tokens`, and `output_tokens`;
- tool calls, commands, and inspected paths extracted from stream JSON;
- raw stream and final structured-output refs.

`charged_input_tokens` is the sum of uncached, cache-creation, and cache-read input. This is
the only honest total for a cache-aware provider; reporting the often tiny uncached
`input_tokens` field alone would recreate cost displacement. `total_tokens` is charged
input plus output across every orchestration, implementation, validation, repair, and
escalation invocation.

Repository inspection is not estimated separately: tool-return text is already charged in
the next provider input. The trace still records inspected paths so retrieval behavior can
be compared. Additional-context text is stored verbatim and byte-counted; its downstream
invocation is charged in full. No tokenizer estimate is presented as provider telemetry.

## Repetition and ordering

The harness requires `--repetitions N`; there is no implicit evidence-producing default.
Within each repetition, arm order is deterministically shuffled from a recorded seed, then
arms run serially. Serial execution avoids machine-contention noise while randomized block
order avoids a fixed warm-cache or time-of-day advantage. Parallelism can be added later as
a separately frozen control.

The harness reports per-arm distributions and paired per-block differences. It does not
define an automatic stopping rule or winner. The first authenticated run should be one
smoke block; its purpose is harness validation and it remains excluded from evidence. The
repetition count for an evidentiary run is then pre-registered from observed within-arm
variance and the acceptable equivalence band.

## Failure semantics

- CLI/auth/configuration failure before any role response: `harness_failed`.
- Invalid structured output: one format-repair attempt charged to the same role and loop;
  then `failed`.
- Agent-requested unavailable context: orchestrator decides; unanswered means `blocked`.
- Repair limit reached with remaining defects: `exhausted`.
- Deterministic gate failure: `completed` plus `nonconforming`; never silently repaired by
  the harness.
- Wall-clock breach: terminate the active process, record partial telemetry, `exhausted`.

Harness failures are not candidate failures and must not be compared as strategy outcomes.

## Deliverables and validation boundary

The implementation lives beside the external experiment artifacts, not in Libera. It must
provide:

1. a versioned harness configuration and event/result schemas;
2. `harness.py prepare` and `harness.py run` entry points;
3. a fake CLI runner that exercises the complete happy path without model usage,
   plus deterministic scenario tests for recovery transitions;
4. deterministic tests for token aggregation, path extraction, boundaries, arm-order
   randomization, and harness-vs-candidate failure classification;
5. a preflight that refuses source/hash/baseline/auth drift before creating paid sessions.

No authenticated arm is launched as part of implementation validation.

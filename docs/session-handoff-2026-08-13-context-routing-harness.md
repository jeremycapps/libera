# Session handoff — context-routing scripted harness (2026-08-13)

## Summary

Picked up from `session-handoff-2026-08-13-context-routing-pilot.md` and built the
first scripted harness slice. The main pilot blocker is materially reduced: each
orchestrator, implementer, validator, repair, and escalation is now represented as
an independent Claude CLI invocation with provider usage attributed to its role,
phase, and loop.

No paid or evidentiary experiment was launched. The local Claude CLI is currently
logged out, and the harness refuses an authenticated run before creating a model
session.

## Where the implementation lives

Per the isolation design, harness code and run artifacts remain outside Libera:

```text
~/Dev/libera-experiments/ctxroute-pilot-001/
  harness.py
  harness-config.yaml
  HARNESS.md
  schemas/event.schema.json
  schemas/role-output.schema.json
  tests/test_harness.py
```

The durable Libera-side artifact on this branch is the implementation contract:
`docs/superpowers/specs/2026-08-13-context-routing-harness-design.md`.

## What is implemented

- Frozen-commit, tree-hash, source-hash, CLI, and optional auth preflight.
- Explicit `--repetitions` and `--seed`; no implicit paid run.
- Deterministically randomized serial arm order per repeated block.
- Fresh isolated clones pinned to `4937ce1`, local `arm` branch, remotes removed.
- Existing deterministic projector reused without modifying pilot inputs.
- Scripted orchestrator → implementer → validator order.
- Bounded repair loop and escalation routing; additional context is stored verbatim
  and byte-counted.
- One persistent CLI session per role, resumed for repair/escalation/finalization.
- Raw stream, stderr, exact prompt, structured result, gate output, patch, and final
  result artifacts.
- Tool-call, explicit path, and command extraction from stream events.
- Cache-aware accounting: `charged_input_tokens` is uncached + cache creation +
  cache read; `total_tokens` adds output. Nothing is hidden behind the provider's
  often tiny uncached-input field.
- Deterministic gate remains authoritative over an agent's claimed verdict.

## Validation performed

Six unit tests pass:

```text
Ran 6 tests in 0.017s
OK
```

They cover cache-aware aggregation, component preservation, block ordering,
stream termination, tool/path extraction, and frozen-source preflight. Both
`harness.py` and its tests compile under Python 3.9.

A no-model end-to-end run completed at:

```text
/private/tmp/ctxroute-harness-smoke.ZPHWJD/fake-smoke-r01
```

It created all three clones and nine projections, ran four fake role invocations
per arm, emitted complete artifacts, and ran the real gate. All three gates
returned `conforming`; each gate ran the Libera suite at the frozen 858-assertion
floor. Each result recorded measured component usage and a cache-aware total.

The first sandboxed attempt correctly exposed an environment issue: Mojo crashpad
cannot write its settings under the Codex filesystem sandbox, so DC-6 reported no
assertion count. Re-running the same no-model harness outside that sandbox made all
three gates pass. This is a harness-environment fact, not a candidate difference.

Auth refusal is also verified:

```text
HARNESS FAILURE: Claude CLI is not authenticated; no model sessions were started
```

## Deliberate boundary

The harness is not yet evidentiary-run ready. The following paths need one more
hardening pass:

1. **Authenticate and run one paid smoke block.** This validates Claude 2.1.231's
   actual `stream-json` structured-output shape, session resume behavior, and
   allowed/disallowed tool behavior. It requires user auth and material model usage,
   so this session did not guess authority.
2. **Format repair.** The schema and `max_format_repairs` boundary exist, but the CLI
   runner currently classifies malformed structured output as a harness failure
   rather than charging one format-repair turn.
3. **Timeout rendering.** A wall-clock deadline is enforced across an arm, but an
   expired subprocess currently becomes a harness failure. It must preserve partial
   telemetry and render candidate status `exhausted` when the provider process itself
   is healthy.
4. **Recovery tests.** The repair and escalation state-machine paths are implemented,
   but the fake runner currently exercises only the clean happy path. Add scripted
   scenarios for answered escalation, blocked escalation, repaired defect, and repair
   exhaustion before calling the harness complete.
5. **Pre-register repetitions.** After the paid smoke validates telemetry, use its
   within-arm variance and an explicit equivalence band to select N. Do not treat the
   smoke block as evidence and do not choose N after reading comparative outcomes.

## Commands for the next agent

```sh
cd ~/Dev/libera-experiments/ctxroute-pilot-001
python3 -m unittest discover -s tests -v
python3 harness.py preflight
python3 harness.py preflight --require-auth
```

After auth and explicit cost authorization, the non-evidentiary paid smoke is:

```sh
python3 harness.py run \
  --run-prefix authenticated-smoke \
  --repetitions 1 \
  --seed 419
```

Do not unseal or reuse the pilot's A/B/C mapping as if it anonymized a new run.
Generate a fresh sealed mapping before any comparative human reading.

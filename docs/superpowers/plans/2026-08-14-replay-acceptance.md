# Plan — replay(snapshot.trace) acceptance test

**Spec:** `docs/superpowers/specs/Libera_Core_Runtime_v0_Spec.docx` §10 (revised 2026-08-14)
**Baseline:** `4937ce1`, 858 assertions, 0 failures
**Branch:** `dawn-swan-20260813`

Closes the one remaining gap before the core engine is v0-complete. §9's acceptance
test already passes (`boundary/exit/snapshot` is asserted in `test_domain.mojo:597,635`,
`test_emit.mojo:160`, `test_issue_model.mojo:348`). §10 does not: no `replay` exists —
the only occurrence of the word repo-wide is a comment at `tests/test_write.mojo:3`.

## Global Constraints

- **Mojo 0.26.2.0.** `comptime`, not `alias`. `var` for owned args, not `owned`. Imports
  fully qualified from `std.`. There is no `mojo test` — the suite is a plain program.
- **Entry point** `tests/run_all.mojo`; harness `testkit/harness.mojo` (assertions record
  and continue, never abort). Run with `./run_tests.sh`, which exits non-zero on failure.
- **Assertion count may only increase.** Baseline 858. A drop means a test was deleted.
- **Layering.** `domain/` may import `kernel/`, `modelir/`, `address/`. It may **never**
  import `strategy/`. `tests/test_layering.mojo` enforces this by import direction.
- **Errors are Values, never exceptions.** Only filesystem reads may raise.
- **No semantic judgment in Mojo.** Slot meaning lives in the write policy document
  (`models/writes-default.yaml:5` — "It is data, not code"). `replay` must fold the log
  mechanically, by rendered slot path. It must not hardcode that `result.actual` means
  the final result, or that `verdict.conforms` means the verdict.
- **Do not modify** `kernel/`, `modelir/`, `address/`, `models/`, `protocol/`, or any
  existing test file except `tests/run_all.mojo` (one import + one call).

## Ruling carried into both tasks

§10 originally said reconstruction equals `snapshot.final_state`. **No such field exists.**
`settled()` (`domain/run.mojo:233`) returns `{contract, final_result, final_verdict}`, and
`snapshot()` adds `trace`. This is deliberate, not an omission: `run.mojo:238` argues a
snapshot stored inside the log cannot embed the log, so "its position in the log is its
trace." `models/writes-default.yaml` records exactly four slots — `contract.expected`,
`result.actual`, `verdict.conforms`, `snapshot` — so a full `CurrentState` is not
reconstructable from the log by design.

The spec was revised on 2026-08-14 to target `settled()`. This is provable because
`run.mojo:180` sets `snap = settled(model, next)` and binds it into the write frame as
`snapshot`, so the terminal `boundary/exit/snapshot` write's **value is** `settled()`.

---

## Task 1 — `replay()` over a write log

**Files:** `domain/replay.mojo` (new), `tests/test_replay.mojo` (new)

Add `domain/replay.mojo` exposing one function:

```mojo
fn replay(trace: Value) -> Value
```

Returns a RECORD `{reconstructed, final_address, steps}` on success, or a `Value.error`
with domain code `replay_error` on failure. Behaviour:

1. **Reject a non-log.** `trace.tag != LIST` → error "trace must be a list".
   Empty list → error "cannot replay an empty trace".
2. **Verify chain integrity** using `address.write.chain_is_intact(trace, String(""))`.
   A broken or orphaned chain → error "trace chain is broken". Do not reimplement the
   check; the function already exists at `address/write.mojo:45`.
3. **Fold the log in order.** Walk writes from first to last, accumulating a RECORD keyed
   by the rendered address of each write (`address.grammar.render` on the write's
   `address` field). Later writes at the same address overwrite earlier ones — that is
   what makes it a fold rather than a collection. Expose the fold as `steps` (an INT: how
   many writes were folded).
4. **Reconstruct.** The terminal write must render to an address whose pressure/operation
   is `boundary/exit`; otherwise error "trace does not end at a boundary/exit write".
   `reconstructed` is that write's `value`. `final_address` is its rendered address string.

Each write is `{id, step, address, value, prev}` (`address/write.mojo:15`). Address
records render via `render()` (`address/grammar.mojo:109`).

**Tests** in `tests/test_replay.mojo`, over hand-built traces (build writes with
`address.write.write` and `address.grammar.address`; do not run a full model here — that
is Task 2):

- a well-formed three-write log folds and returns the terminal value
- `steps` equals the number of writes
- two writes at the same address: the later value wins
- non-LIST input errors
- empty list errors
- a log whose second write's `prev` does not point at the first errors
- a log whose head `prev` is non-null errors (orphan)
- a log not ending at `boundary/exit` errors
- every error is a `Value.error`, never a raise

**Acceptance:** `./run_tests.sh` exits 0; assertion count above 858; `domain/replay.mojo`
defines `replay`; `tests/test_replay.mojo` exists and is imported and called from
`tests/run_all.mojo`; no file outside the two new files and `run_all.mojo` is modified.

---

## Task 2 — the §10 end-to-end acceptance test

**Files:** `tests/test_replay.mojo` (append a second suite function), `tests/run_all.mojo`
(call it)

Prove the trace of a **real run** is reconstructable, not merely emitted.

1. Load an existing domain model and the default write policy the way `tests/test_domain.mojo`
   already does — reuse that setup pattern rather than inventing a new fixture.
2. Drive it to convergence with `run(model, policy, results)`.
3. Take `out.get("snapshot").get("trace")` and pass it to `replay`.

Assert, each as its own harness check:

- `replay` returns a RECORD, not an error
- `final_address` equals `"boundary/exit/snapshot"`
- `reconstructed` equals `settled(model, out.get("state"))` field by field:
  `contract`, `final_result`, `final_verdict`
- `reconstructed` has **no** `trace` field — a settled value inside the log must not
  carry one (`run.mojo:238`)
- `steps` equals `out.get("snapshot").get("trace").len()`
- the chain is intact across the whole trace

**Acceptance:** `./run_tests.sh` exits 0; assertion count above Task 1's; the four §10
conditions above are each asserted; no file outside `tests/test_replay.mojo` and
`tests/run_all.mojo` is modified.

---

## Amendment — final review, 2026-08-14

Review of `57b60e5` proved the fold was dead: replacing the fold loop with
`for k in range(trace.len() - 1, trace.len())` — folding only the terminal write —
left all 882 assertions passing. `replay` was `trace.last().value` with an unread
`Dict` in front of it, and the §10 test could not tell the difference.

Two corrections to the text above:

- **Task 1 step 3 said "keyed by the rendered address".** It is now keyed by **slot**.
  A real run writes `verdict.conforms` under `exception/detect` on one fold and
  `movement/advance` on the next; rendered-address keying leaves the stale, superseded
  `false` standing beside its replacement, which is a collection, not a fold. The slot
  is *where a value belongs*; pressure and operation describe the transition. This is a
  structural reading of the address, not a semantic one, so it does not breach
  "no semantic judgment in Mojo".
- **The return record is `{reconstructed, slots, final_address, steps}`.** The fold is
  now part of the contract rather than an internal detail, so it cannot go dead again
  without a test noticing.

Task 2's acceptance test additionally rebuilds `{contract, final_result, final_verdict}`
from the **non-terminal** slots and compares against `settled(model, out.state)`. The
comparison is against a projection of `settled()` — `final_verdict` narrowed to its
`conforms` field — because `models/writes-default.yaml` records `verdict.conforms`, not
the whole Verdict. The log cannot be asked to give back more than it wrote; that is the
same by-design limit already noted in the ruling above.

Two further narrowings, recorded so the claim is not read as larger than it is.
`final_result` is *compared* in full but not *rebuilt* in full: the log records
`result.actual`, and `final_result.source` (`manual`) is re-supplied by the test from its
own fixture, since no slot records it. `contract`'s `{expected: …}` wrapper shape is
likewise supplied by the test. Both are within the standing ruling — the test may know the
model, `replay` may not — but "rebuilt from the log" is true only of the values, not of
the record shapes around them.

What §10 is therefore proven by, precisely: `tests/test_replay.mojo:276-296` compares
`reconstructed` against `settled(model, out.state)` on all three fields unnarrowed, and the
non-terminal rebuild proves the fold is what does the reconstructing. Neither alone
suffices — the first is satisfiable by `trace.last().value`, which is how the suite was
fooled at `57b60e5`; the second is projected. Together they close it.

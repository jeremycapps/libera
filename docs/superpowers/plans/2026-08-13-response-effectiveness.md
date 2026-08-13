# Response Effectiveness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Libera's Strategy layer the ability to notice that its own response changed nothing, and escalate for that reason instead of merely running out of attempts.

**Architecture:** Two optional keys join a strategy document — `expressions.progress` (a model-declared predicate asking whether the deviation moved) and `expressions.ineffective` (the response when it did not). `strategy/run.mojo` carries the last verdict and last response forward, consults `progress` before selecting a response, and prefers the futility conclusion over the boundary one. The conclusion lands in the write log as two writes: `exception/detect` for the fact, `exception/respond` for the decision that follows.

**Tech Stack:** Mojo 0.26.2.0, no dependencies. Tests are an ordinary program (`mojo test` does not exist in this version); `testkit/harness.mojo` provides assertions and `tests/run_all.mojo` drives every module.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-08-13-response-effectiveness-design.md`. Read it before Task 1.
- **No changes to `kernel/`, `modelir/`, `address/`, or `domain/`.** This feature needs none, and `tests/test_layering.mojo` enforces import direction. If you believe a kernel change is required, stop and say so rather than making one.
- **Errors are Values, never exceptions.** Nothing added here may `raise` except filesystem reads (`load_strategy` is already `raises` for that reason).
- **Assertions never abort.** `t.check`, `t.eq_value`, etc. record and continue.
- **Baseline is 815 assertions, 0 failures.** Run `./run_tests.sh` before starting; it takes ~1.7s. Every task ends with the full suite green and a higher assertion count.
- **Mojo string idiom:** wrap literals as `String("...")` at call sites, per the surrounding code.
- **`converge()` (rung 3) is out of scope.** It is touched in exactly one place — a new argument threaded through `respond_write_props` — and gains no effectiveness detection.

---

## File Structure

| File | Responsibility |
|---|---|
| `strategy/respond.mojo` (modify) | Load and validate the two new keys; evaluate the progress test and the ineffective response. Stays the "what does this strategy say" module. |
| `strategy/run.mojo` (modify) | Carry previous verdict/response across folds, three-way selection, `stopped` in the result. Stays the "drive the loop" module. |
| `models/strategy-issue-effectiveness.yaml` (create) | A new strategy document over the existing `issue-completeness` contract. **Not** a modification of `strategy-issue-triage.yaml` — see Task 3. |
| `tests/test_effectiveness.mojo` (create) | The new behavior end to end. Mirrors `test_strategy_triage.mojo`'s structure. |
| `tests/fixtures/*.yaml` (create, 5 files) | Malformed and special-case strategy documents. |
| `tests/run_all.mojo` (modify) | Register the new module. |
| `docs/runtime.md` (modify) | Move progress detection out of "deliberately not built". |

---

## Task 1: The load-time surface

Compile `expressions.progress` and `expressions.ineffective`, and refuse a document that declares one without the other.

**Files:**
- Modify: `strategy/respond.mojo` (compile block after line 96; validation block after line 221; new accessor after `has_boundary`)
- Create: `tests/fixtures/strategy-progress-without-ineffective.yaml`
- Create: `tests/fixtures/strategy-ineffective-without-progress.yaml`
- Create: `tests/test_effectiveness.mojo`
- Modify: `tests/run_all.mojo`

**Interfaces:**
- Consumes: `load_strategy(path: String) raises -> Value`, `E_STRATEGY`, existing `TestSuite` assertions.
- Produces: `has_progress_test(strategy: Value) -> Bool`. Loaded strategies may now carry `progress` and `ineffective` keys.

- [ ] **Step 1: Write the two invalid fixtures**

`tests/fixtures/strategy-progress-without-ineffective.yaml`:

```yaml
# Invalid: a progress test whose conclusion nothing acts on.
model: strategy-progress-without-ineffective
expressions:
  candidates:
    list:
      - record:
          when: true
          action: a
  progress:
    eq:
      - ref: verdict.finding
      - ref: previous.verdict.finding
  writes:
    list: []
```

`tests/fixtures/strategy-ineffective-without-progress.yaml`:

```yaml
# Invalid: a response for a conclusion nothing can reach.
model: strategy-ineffective-without-progress
expressions:
  candidates:
    list:
      - record:
          when: true
          action: a
  ineffective:
    record:
      action: escalate
  writes:
    list: []
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_effectiveness.mojo`:

```mojo
"""A strategy that notices its own response did nothing.

Rung 2 counts answers, not progress. `strategy-issue-triage.yaml` knows it has
responded twice; it does not know that asking for logs accomplished nothing. Its
only way to stop is a budget, so it reports *exhausted* when what happened was
*ineffective*.

The second conclusion is strictly better: it is knowable before the budget runs
out, and it names a cause rather than a limit.

The comparison is over `finding` rather than over the whole verdict, and the
tests below pin exactly that difference -- a resubmission can change `actual`
while leaving the deviation untouched.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, LIST
from kernel.ir import kv, rec, sym, record_of, list_of
from domain.model import DomainModel, load_domain_model
from domain.emit import load_policy
from domain.run import make_result, verify
from strategy.respond import (
    load_strategy,
    has_progress_test,
    E_STRATEGY,
)
from testkit.harness import TestSuite


comptime MODEL_PATH = "models/issue-completeness.yaml"
comptime POLICY_PATH = "models/writes-default.yaml"
comptime EFFECTIVE_PATH = "models/strategy-issue-effectiveness.yaml"
comptime TRIAGE_PATH = "models/strategy-issue-triage.yaml"


fn run(mut t: TestSuite) raises:
    _validation(t)


fn _validation(mut t: TestSuite) raises:
    t.section(String("effectiveness / half a feature is refused"))

    # A progress test with no response to it computes a value nobody reads.
    t.is_error(
        String("progress without ineffective"),
        load_strategy(
            String("tests/fixtures/strategy-progress-without-ineffective.yaml")
        ),
        String(E_STRATEGY),
    )
    # An ineffective response with no test can never fire.
    t.is_error(
        String("ineffective without progress"),
        load_strategy(
            String("tests/fixtures/strategy-ineffective-without-progress.yaml")
        ),
        String(E_STRATEGY),
    )
    # Rung 2 declares neither, and must keep loading unchanged.
    var triage = load_strategy(String(TRIAGE_PATH))
    t.not_error(String("a strategy declaring neither still loads"), triage)
    t.check(
        String("and reports no progress test"),
        not has_progress_test(triage),
        String("triage should not claim effectiveness detection"),
    )
```

Register it in `tests/run_all.mojo`. Add the import alongside the others:

```mojo
import tests.test_effectiveness as test_effectiveness
```

and the call in the Strategy block, after `test_strategy_triage.run(t)`:

```mojo
    test_effectiveness.run(t)
```

- [ ] **Step 3: Run it to confirm it fails**

```bash
./run_tests.sh
```

Expected: a compile error — `has_progress_test` is not defined in `strategy.respond`.

- [ ] **Step 4: Add the compile block**

In `strategy/respond.mojo`, immediately after the `exhausted` block (which ends at line 96, `d[String("exhausted")] = ir^`) and before the `# Search machinery (rung 3).` comment:

```mojo
    # Effectiveness detection. Absent for strategies that only count attempts.
    if exprs.has(String("progress")):
        var ir = compile_expression(exprs.get(String("progress")))
        if ir.is_error():
            return ir^
        d[String("progress")] = ir^

    if exprs.has(String("ineffective")):
        var ir = compile_expression(exprs.get(String("ineffective")))
        if ir.is_error():
            return ir^
        d[String("ineffective")] = ir^
```

- [ ] **Step 5: Add the validation block**

In the same function, after the existing `has_limit` check (ends line 221 with the closing `)`), and before `return Value.record(d^)`:

```mojo
    # A progress test with no response to it computes a value nobody reads; an
    # ineffective response with no test can never fire. Each is half a feature,
    # and half a feature that loads silently is worse than one that refuses.
    var has_progress = d.__contains__(String("progress"))
    var has_ineffective = d.__contains__(String("ineffective"))
    if has_progress != has_ineffective:
        return Value.error(
            String(E_STRATEGY),
            String(
                "effectiveness detection needs both 'expressions.progress' and"
                " 'expressions.ineffective'; this declares only one"
            ),
        )
```

- [ ] **Step 6: Add the accessor**

After `fn has_boundary(...)` (ends line 267):

```mojo
fn has_progress_test(strategy: Value) -> Bool:
    """Whether this strategy can tell that its own response changed nothing.

    Both halves are required at load time, so testing one is testing both.
    """
    if strategy.is_error():
        return False
    return strategy.has(String("progress")) and strategy.has(
        String("ineffective")
    )
```

- [ ] **Step 7: Run the tests**

```bash
./run_tests.sh
```

Expected: PASS, with 4 more assertions than the 815 baseline (819).

- [ ] **Step 8: Commit**

```bash
git add strategy/respond.mojo tests/test_effectiveness.mojo tests/run_all.mojo tests/fixtures/
git commit -m "Accept a progress test and an ineffective response, or neither"
```

---

## Task 2: Evaluating the progress test

Turn the two compiled expressions into callable judgments, with the boolean discipline the rest of the layer already applies.

**Files:**
- Modify: `strategy/respond.mojo` (append three functions after `escalation`)
- Create: `tests/fixtures/strategy-progress-not-boolean.yaml`
- Modify: `tests/test_effectiveness.mojo`

**Interfaces:**
- Consumes: `has_progress_test`, `E_STRATEGY`, `evaluate`, `BOOL` (already imported at `strategy/respond.mojo:23`).
- Produces:
  - `progress_props(verdict: Value, prev_verdict: Value, prev_response: Value) -> Value` — a RECORD `{verdict, previous: {verdict, response}}`
  - `progress(strategy: Value, props: Value) -> Value` — a BOOL Value or an Error
  - `ineffective(strategy: Value, props: Value) -> Value` — the response record or an Error

- [ ] **Step 1: Write the non-boolean fixture**

`tests/fixtures/strategy-progress-not-boolean.yaml`:

```yaml
# Valid to load, wrong at evaluation: `progress` yields a symbol, not a boolean.
model: strategy-progress-not-boolean
expressions:
  candidates:
    list:
      - record:
          when: true
          action: a
  progress:
    ref: verdict.finding
  ineffective:
    record:
      action: escalate
  writes:
    list: []
```

- [ ] **Step 2: Write the failing test**

Add to `tests/test_effectiveness.mojo` — a new section function, and a call to it from `run`:

```mojo
fn _progress_evaluation(mut t: TestSuite) raises:
    t.section(String("effectiveness / the progress test"))

    var strategy = load_strategy(String(EFFECTIVE_PATH))
    t.not_error(String("the effectiveness strategy loads"), strategy)
    t.check(
        String("and reports a progress test"),
        has_progress_test(strategy),
        String("should claim effectiveness detection"),
    )

    # A finding that changed is progress.
    var moved = progress(
        strategy,
        progress_props(
            _verdict_finding(sym(String("missing_owner"))),
            _verdict_finding(sym(String("missing_root_cause"))),
            _response(sym(String("ask_for_logs"))),
        ),
    )
    t.eq_value(
        String("a changed finding is progress"), moved, Value.bool(True)
    )

    # A finding that did not is not.
    var stuck = progress(
        strategy,
        progress_props(
            _verdict_finding(sym(String("missing_root_cause"))),
            _verdict_finding(sym(String("missing_root_cause"))),
            _response(sym(String("ask_for_logs"))),
        ),
    )
    t.eq_value(
        String("an unchanged finding is not"), stuck, Value.bool(False)
    )

    # A non-boolean is an error, not a coercion -- the same discipline
    # `respond` applies to a candidate's `when`.
    var bad = load_strategy(
        String("tests/fixtures/strategy-progress-not-boolean.yaml")
    )
    t.is_error(
        String("a non-boolean progress test is an error"),
        progress(
            bad,
            progress_props(
                _verdict_finding(sym(String("a"))),
                _verdict_finding(sym(String("b"))),
                _response(sym(String("x"))),
            ),
        ),
        String(E_STRATEGY),
    )

    # The ineffective response names what was already tried.
    var handed_up = ineffective(
        strategy,
        progress_props(
            _verdict_finding(sym(String("missing_root_cause"))),
            _verdict_finding(sym(String("missing_root_cause"))),
            _response(sym(String("ask_for_logs"))),
        ),
    )
    t.eq_value(
        String("the ineffective response escalates"),
        handed_up.get(String("action")),
        sym(String("escalate")),
    )
    t.eq_value(
        String("and names what was already tried"),
        handed_up.get(String("tried")),
        sym(String("ask_for_logs")),
    )
    t.eq_value(
        String("and marks itself ineffective"),
        handed_up.get(String("effective")),
        Value.bool(False),
    )
```

Add these two helpers near the top of the file, below the `comptime` block:

```mojo
fn _verdict_finding(var finding: Value) -> Value:
    """The slice of a Verdict a progress test actually reads."""
    return rec(kv(String("finding"), finding^))


fn _response(var action: Value) -> Value:
    return rec(kv(String("action"), action^))
```

Extend the imports from `strategy.respond` to include `progress`, `progress_props`, and `ineffective`. Add `_progress_evaluation(t)` to `run`.

- [ ] **Step 3: Run it to confirm it fails**

```bash
./run_tests.sh
```

Expected: a compile error — `progress`, `progress_props`, and `ineffective` are not defined.

- [ ] **Step 4: Implement the three functions**

Append to `strategy/respond.mojo`, after `fn escalation(...)`:

```mojo
fn progress_props(
    verdict: Value, prev_verdict: Value, prev_response: Value
) -> Value:
    """What a progress test may reference.

    `previous` is one pair rather than two loose bindings, because
    `previous.verdict` must be the verdict `previous.response` was aimed at.
    Packaging them together is what keeps that true at every call site.
    """
    var p = Dict[String, Value]()
    p[String("verdict")] = prev_verdict.copy()
    p[String("response")] = prev_response.copy()

    var d = Dict[String, Value]()
    d[String("verdict")] = verdict.copy()
    d[String("previous")] = Value.record(p^)
    return Value.record(d^)


fn progress(strategy: Value, props: Value) -> Value:
    """Did the deviation move? A BOOL Value, or an Error.

    Never consulted before a response has been recorded, so `previous` is always
    populated and the test never reaches through a null -- which is why this
    needs no presence operator to be written safely.
    """
    if strategy.is_error():
        return strategy.copy()
    if not strategy.has(String("progress")):
        return Value.error(
            String(E_STRATEGY), String("strategy has no 'progress' test")
        )

    var got = evaluate(strategy.get(String("progress")), props)
    if got.is_error():
        return got^
    if got.tag != BOOL:
        return Value.error(
            String(E_STRATEGY),
            String("'progress' must evaluate to a boolean, got ")
            + got.to_string(),
        )
    return got^


fn ineffective(strategy: Value, props: Value) -> Value:
    """The response for a previous response that changed nothing."""
    if strategy.is_error():
        return strategy.copy()
    if not strategy.has(String("ineffective")):
        return Value.error(
            String(E_STRATEGY),
            String("strategy has no 'ineffective' response"),
        )
    return evaluate(strategy.get(String("ineffective")), props)
```

- [ ] **Step 5: Run the tests**

```bash
./run_tests.sh
```

Expected: still failing — `models/strategy-issue-effectiveness.yaml` does not exist yet, so `load_strategy` returns a parse error and the `not_error` assertion fails. That is the correct intermediate state; Task 3 creates the document.

- [ ] **Step 6: Commit**

```bash
git add strategy/respond.mojo tests/test_effectiveness.mojo tests/fixtures/strategy-progress-not-boolean.yaml
git commit -m "Evaluate the progress test and the ineffective response"
```

---

## Task 3: The strategy document

**Files:**
- Create: `models/strategy-issue-effectiveness.yaml`

**Interfaces:**
- Consumes: the `issue-completeness` contract's `verdict.finding` vocabulary; write props bindings `next.converged`, `ineffective`, `response.*`.
- Produces: a loadable strategy whose `progress`, `ineffective`, `exhausted`, `candidates`, and `writes` the later tasks exercise.

**Why a new document rather than editing `strategy-issue-triage.yaml`:** rung 2's tests pin escalation arriving *from exhaustion*, at a known attempt count. Adding a progress test to that document would make it escalate earlier, from futility, and break `_escalation_on_crossing` and `_boundary_arithmetic` in `tests/test_strategy_triage.mojo`. Keeping both documents also makes the distinction demonstrable: one contract, two strategies, two different conclusions from the same deviations.

- [ ] **Step 1: Write the document**

```yaml
# A strategy that notices its own response did nothing.
#
# `strategy-issue-triage.yaml` can tell that it has answered twice. It cannot
# tell that asking for logs accomplished nothing -- its only way to stop is a
# budget. Two different conclusions are being confused there:
#
#   exhausted    the budget ran out; says nothing about whether anything worked
#   ineffective  something was tried and the deviation did not move
#
# The second is knowable earlier and names a cause rather than a limit. This
# document adds it, and nothing else: same contract, same shape of candidate,
# one new question asked between folds.
#
# The test is over `finding`, not over the whole verdict, and the difference is
# not academic. A supplier can answer `ask_for_logs` by resubmitting with a
# resolution_path added and still no root cause: `actual` changed, so the two
# verdicts differ structurally, but the deviation is untouched. Comparing
# verdicts would report progress that did not happen.
#
# `finding` is this model's vocabulary rather than the protocol's, which is why
# the test lives in this document instead of in the runtime.

model: strategy-issue-effectiveness
version: 0.1

boundary:
  # Deliberately larger than the number of attempts the tests need, so that an
  # escalation arriving early is unambiguously futility rather than the budget.
  max_attempts: 3

expressions:

  # Unchanged in kind from rung 2: the first candidate whose `when` holds.
  # `authority: null` is required, not decorative -- the last write policy below
  # reads `response.authority`, and a missing key is an unresolved-ref error
  # rather than an absent value.
  candidates:
    list:
      - record:
          when:
            eq:
              - ref: verdict.finding
              - missing_root_cause
          action: ask_for_logs
          to: engineering
          because:
            ref: verdict.finding
          authority: null

      - record:
          when: true
          action: route_back
          to:
            ref: result.source
          because:
            ref: verdict.finding
          authority: null

  # Did the deviation move? Consulted only once a response has been recorded,
  # so `previous` is always populated.
  progress:
    not:
      eq:
        - ref: verdict.finding
        - ref: previous.verdict.finding

  # It did not. Hand it up, and say what was already tried -- an escalation that
  # cannot name the failed attempt is asking someone to start over.
  ineffective:
    record:
      action: escalate
      to: engineering_lead
      because:
        ref: verdict.finding
      tried:
        ref: previous.response.action
      effective: false
      authority: engineering_lead

  # The budget ran out without the deviation ever standing still. A different
  # conclusion, so a different destination.
  exhausted:
    record:
      action: escalate
      to: product
      because:
        ref: verdict.finding
      authority: product_owner

  writes:
    list:

      # An ordinary response.
      - record:
          when:
            and:
              - not:
                  ref: next.converged
              - not:
                  ref: ineffective
          pressure: exception
          operation: respond
          slot: response.action

      # The fact. Strategy detects this about its own conduct -- Domain detects
      # deviation in a Result, which is a different subject. The boundary that
      # matters is not who may write `detect` but what a detect write is about.
      - record:
          when:
            ref: ineffective
          pressure: exception
          operation: detect
          slot: response.effective

      # The decision that follows from the fact. Declared after it, because
      # `emit` walks this list in order and the log should read as an argument.
      - record:
          when:
            ref: ineffective
          pressure: exception
          operation: respond
          slot: response.action

      # Who it was handed to.
      - record:
          when:
            not:
              eq:
                - ref: response.authority
                - null
          pressure: exception
          operation: respond
          slot: response.authority
```

- [ ] **Step 2: Run the tests**

```bash
./run_tests.sh
```

Expected: PASS. Task 2's assertions now find the document. Count should be 828.

- [ ] **Step 3: Commit**

```bash
git add models/strategy-issue-effectiveness.yaml
git commit -m "Add a strategy document that declares a progress test"
```

---

## Task 4: The loop

Carry the previous verdict and response forward, consult the progress test, and prefer futility over exhaustion.

**Files:**
- Modify: `strategy/run.mojo` — imports (lines 27-35), `respond_write_props` (lines 54-79), `converge` call site (~line 180), `run` (lines 248-355)
- Modify: `tests/test_effectiveness.mojo`

**Interfaces:**
- Consumes: `progress`, `progress_props`, `ineffective`, `has_progress_test` from Task 2.
- Produces: `run(...)` returns the existing record plus `stopped` (a SYMBOL: `converged`, `ineffective`, `exhausted`, or `results_consumed`). `respond_write_props` gains a trailing `futile: Bool` parameter and binds `ineffective` into write props.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_effectiveness.mojo`, plus the calls in `run`:

```mojo
fn _issue(var root_cause: Value, var owner: Value, var path: Value) -> Value:
    return make_result(
        rec(
            kv(String("root_cause"), root_cause^),
            kv(String("owner"), owner^),
            kv(String("resolution_path"), path^),
        ),
        String("support"),
    )


fn _text(var s: String) -> Value:
    return Value.string(s^)


fn _deviation_moves(
    mut t: TestSuite, model: DomainModel, strategy: Value, policy: Value
) raises:
    t.section(String("effectiveness / a deviation that moves is not futile"))

    # missing_root_cause, then missing_owner, then complete. The finding changes
    # every fold, so the strategy never concludes it is getting nowhere.
    var results = List[Value]()
    results.append(
        _issue(Value.null(), _text(String("alice")), _text(String("rollback")))
    )
    results.append(
        _issue(
            _text(String("bad deploy")), Value.null(), _text(String("rollback"))
        )
    )
    results.append(
        _issue(
            _text(String("bad deploy")),
            _text(String("alice")),
            _text(String("rollback")),
        )
    )

    var out = run_with_strategy(model, strategy, policy, results)
    t.not_error(String("the run completes"), out)
    t.eq_value(
        String("it converges"), out.get(String("converged")), Value.bool(True)
    )
    t.eq_value(
        String("and says so"),
        out.get(String("stopped")),
        sym(String("converged")),
    )
    t.eq_int(
        String("two responses, neither an escalation"),
        out.get(String("responses")).len(),
        2,
    )
    t.eq_int(
        String("nothing was detected by the strategy"),
        _count_operation(out.get(String("trace")), String("detect")),
        # Domain's own detect writes are counted here too, so the assertion is
        # against the strategy's contribution: two folds deviated, so Domain
        # detected twice and the strategy added none.
        2,
    )


fn _deviation_stands_still(
    mut t: TestSuite, model: DomainModel, strategy: Value, policy: Value
) raises:
    t.section(String("effectiveness / a deviation that stands still is futile"))

    # Both results are missing a root cause, so the finding is identical -- but
    # the second is missing a resolution_path as well, so `actual` differs and
    # the two verdicts are structurally unequal. This is the case that separates
    # "did anything change" from "did the deviation change".
    var results = List[Value]()
    results.append(
        _issue(Value.null(), _text(String("alice")), _text(String("rollback")))
    )
    results.append(_issue(Value.null(), _text(String("alice")), Value.null()))
    results.append(
        _issue(Value.null(), _text(String("alice")), _text(String("rollback")))
    )

    var out = run_with_strategy(model, strategy, policy, results)
    t.not_error(String("the run completes"), out)
    t.eq_value(
        String("it does not converge"),
        out.get(String("converged")),
        Value.bool(False),
    )
    t.eq_value(
        String("it stopped because the response was ineffective"),
        out.get(String("stopped")),
        sym(String("ineffective")),
    )

    var responses = out.get(String("responses"))
    t.eq_int(String("it answered twice"), responses.len(), 2)
    t.eq_value(
        String("first it asked for logs"),
        responses.at(0).get(String("action")),
        sym(String("ask_for_logs")),
    )
    t.eq_value(
        String("then it escalated"),
        responses.at(1).get(String("action")),
        sym(String("escalate")),
    )
    t.eq_value(
        String("naming what had already been tried"),
        responses.at(1).get(String("tried")),
        sym(String("ask_for_logs")),
    )
    t.eq_value(
        String("and handing it to engineering, not product"),
        responses.at(1).get(String("authority")),
        sym(String("engineering_lead")),
    )

    # The point of the whole feature: this happened on attempt 2 of a budget of
    # 3. The strategy stopped because it was getting nowhere, not because it ran
    # out of room, and the third result was never even verified.
    t.eq_int(String("having spent two of three attempts"), out.get(String("attempts")).i, 2)
```

Add `_count_operation` (copied from `tests/test_strategy_triage.mojo:81` — repeated here rather than shared, since the two suites are independent):

```mojo
fn _count_operation(trace: Value, var op: String) -> Int:
    var n = 0
    for k in range(trace.len()):
        var o = trace.at(k).get(String("address")).get(String("operation"))
        if o.is_text() and o.s == op:
            n += 1
    return n
```

Extend imports with `from strategy.run import run as run_with_strategy`, and add to `run`:

```mojo
    var model = load_domain_model(String(MODEL_PATH))
    var policy = load_policy(String(POLICY_PATH))
    var strategy = load_strategy(String(EFFECTIVE_PATH))

    _validation(t)
    _progress_evaluation(t)
    _deviation_moves(t, model, strategy, policy)
    _deviation_stands_still(t, model, strategy, policy)
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
./run_tests.sh
```

Expected: FAIL. `out.get(String("stopped"))` resolves to an error Value because `run` does not yet emit that field.

- [ ] **Step 3: Thread `futile` through the write props**

In `strategy/run.mojo`, change the signature of `respond_write_props` (line 54) to take a trailing `futile: Bool`, and bind it:

```mojo
fn respond_write_props(
    state: Value,
    next: Value,
    result: Value,
    verdict: Value,
    response: Value,
    step: Int,
    futile: Bool,
) -> Value:
    """Props for a strategy's write policy.

    Domain's shape plus `response`, so a policy can gate on what the strategy
    actually decided -- which is how an escalation's `authority` write knows to
    fire and an ordinary retry's does not -- plus `ineffective`, which is how the
    detect/respond pair knows to fire.
    """
    var ev = Dict[String, Value]()
    ev[String("is_first")] = Value.bool(step == 0)
    ev[String("step")] = Value.int(step)

    var d = Dict[String, Value]()
    d[String("state")] = state.copy()
    d[String("next")] = next.copy()
    d[String("result")] = result.copy()
    d[String("output")] = verdict.copy()
    d[String("response")] = response.copy()
    d[String("ineffective")] = Value.bool(futile)
    d[String("event")] = Value.record(ev^)
    return Value.record(d^)
```

Update the call inside `converge` (around line 176) to pass `False` — rung 3 does no effectiveness detection:

```mojo
        var wprops = respond_write_props(
            state, next, result, verdict, response, round, False
        )
```

- [ ] **Step 4: Add the carried state and the three-way selection**

In `fn run(...)`, after `var gave_up = False` (line 270), add:

```mojo
    var prev_verdict = Value.null()
    var prev_response = Value.null()
    var have_previous = False
    var stopped = String("results_consumed")
```

Replace the block from `# The boundary is consulted before the response` (line 300) through the `respond`/`escalation` selection (line 310) with:

```mojo
        # Did the last response accomplish anything? Asked only once there has
        # been a response to judge, which is why nothing here reaches through a
        # null and why this needs no presence operator.
        var futile = False
        if has_progress_test(strategy) and have_previous and not converged(next):
            var moved = progress(
                strategy,
                progress_props(verdict, prev_verdict, prev_response),
            )
            # A broken predicate is a defect in the model. Reading it as "no
            # progress" would escalate for the wrong reason and hide the defect
            # behind plausible behaviour.
            if moved.is_error():
                return moved^
            futile = not moved.b

        # The boundary is consulted before the response, not after: once the
        # strategy has answered as many times as it is allowed to, it stops
        # choosing among candidates and escalates instead.
        var over_boundary = not converged(next) and exhausted(strategy, attempts)

        # Futility takes precedence. If both hold, "your response did not work"
        # is the more specific and more actionable conclusion, and escalating on
        # it immediately is what the boundary alone cannot express.
        var response: Value
        if futile:
            response = ineffective(strategy, props)
        elif over_boundary:
            response = escalation(strategy, props)
        else:
            response = respond(strategy, props)
        if response.is_error():
            return response^
```

- [ ] **Step 5: Record the previous pair and the stop reason**

Update the write-props call (line 313) to pass `futile`:

```mojo
        var wprops = respond_write_props(
            state, next, results[k], verdict, response, k, futile
        )
```

In the `if rwrites.len() > 0:` block, replace `responses.append(response^)` with a copy and record the pair. Both assignments must happen together, so that `previous.verdict` is always the verdict `previous.response` was aimed at:

```mojo
        if rwrites.len() > 0:
            for w in range(rwrites.len()):
                log.append(rwrites.at(w))
            var rtail = last_id(rwrites)
            if len(rtail) > 0:
                prev = rtail^
            responses.append(response.copy())
            attempts += 1
            prev_verdict = verdict.copy()
            prev_response = response.copy()
            have_previous = True
```

Replace the loop-exit block (lines 338-342) with:

```mojo
        # Handing off ends this strategy's involvement. Continuing to verify
        # after escalating would be answering a question already given away.
        if futile:
            gave_up = True
            stopped = String("ineffective")
            break
        if over_boundary:
            gave_up = True
            stopped = String("exhausted")
            break
```

Finally, before building the output record, and add the field to it:

```mojo
    if converged(state):
        stopped = String("converged")

    var trace_value = Value.list(log^)
    var out = Dict[String, Value]()
    out[String("state")] = state.copy()
    out[String("trace")] = trace_value.copy()
    out[String("classifications")] = Value.list(classifications^)
    out[String("responses")] = Value.list(responses^)
    out[String("attempts")] = Value.int(attempts)
    out[String("exhausted")] = Value.bool(gave_up)
    out[String("stopped")] = Value.symbol(stopped^)
    out[String("converged")] = Value.bool(converged(state))
```

Note `exhausted` keeps its current meaning — *this strategy stopped early and handed off* — so the existing assertions across three suites keep passing. `stopped` names why.

Add the new imports to the `from strategy.respond import (...)` block:

```mojo
    has_progress_test,
    progress,
    progress_props,
    ineffective,
```

- [ ] **Step 6: Run the tests**

```bash
./run_tests.sh
```

Expected: PASS, 843 assertions. If `test_strategy.mojo`, `test_strategy_triage.mojo`, or `test_search.mojo` fail, the `exhausted` field's meaning was changed rather than preserved — revisit Step 5.

- [ ] **Step 7: Commit**

```bash
git add strategy/run.mojo tests/test_effectiveness.mojo
git commit -m "Escalate on a response that changed nothing, before the budget runs out"
```

---

## Task 5: The write log, and precedence

Two claims that are easy to get subtly wrong and that no earlier task pins: the log's ordering, and futility beating exhaustion when both hold.

**Files:**
- Create: `tests/fixtures/strategy-precedence.yaml`
- Modify: `tests/test_effectiveness.mojo`

**Interfaces:**
- Consumes: everything from Tasks 1-4. `chain_is_intact` from `address.write`, `render` from `address.grammar`.
- Produces: no new production interfaces — this task is assertions only. If it fails, the fix belongs in Task 3's document or Task 4's loop.

- [ ] **Step 1: Write the precedence fixture**

A budget of 1 makes exhaustion and futility both true on the second fold. The two escalations differ in `authority`, which is what lets the test tell which one fired.

`tests/fixtures/strategy-precedence.yaml`:

```yaml
# Both conclusions available at once: a budget of one, and a progress test.
# Futility must win, and `authority` is how the test can tell which fired.
model: strategy-precedence
boundary:
  max_attempts: 1
expressions:
  candidates:
    list:
      - record:
          when: true
          action: ask_for_logs
          to: engineering
          authority: null
  progress:
    not:
      eq:
        - ref: verdict.finding
        - ref: previous.verdict.finding
  ineffective:
    record:
      action: escalate
      effective: false
      authority: engineering_lead
  exhausted:
    record:
      action: escalate
      authority: product_owner
  writes:
    list:
      - record:
          when:
            not:
              ref: next.converged
          pressure: exception
          operation: respond
          slot: response.action
```

- [ ] **Step 2: Write the failing tests**

```mojo
fn _futility_beats_exhaustion(
    mut t: TestSuite, model: DomainModel, policy: Value
) raises:
    t.section(String("effectiveness / futility outranks the boundary"))

    var strategy = load_strategy(
        String("tests/fixtures/strategy-precedence.yaml")
    )
    t.not_error(String("the fixture loads"), strategy)

    # Budget of one, and the same finding twice. On fold 2 the strategy is both
    # out of attempts and demonstrably getting nowhere.
    var results = List[Value]()
    results.append(
        _issue(Value.null(), _text(String("alice")), _text(String("rollback")))
    )
    results.append(_issue(Value.null(), _text(String("alice")), Value.null()))

    var out = run_with_strategy(model, strategy, policy, results)
    t.not_error(String("the run completes"), out)
    t.eq_value(
        String("it reports ineffective, not exhausted"),
        out.get(String("stopped")),
        sym(String("ineffective")),
    )
    # The assertion that matters: this is precedence, not arithmetic. Both
    # conditions held, and the more specific conclusion was drawn.
    t.eq_value(
        String("the escalation is the futility one"),
        out.get(String("responses")).at(1).get(String("authority")),
        sym(String("engineering_lead")),
    )


fn _the_log_reads_as_an_argument(
    mut t: TestSuite, model: DomainModel, strategy: Value, policy: Value
) raises:
    t.section(String("effectiveness / the fact, then the decision"))

    var results = List[Value]()
    results.append(
        _issue(Value.null(), _text(String("alice")), _text(String("rollback")))
    )
    results.append(_issue(Value.null(), _text(String("alice")), Value.null()))

    var out = run_with_strategy(model, strategy, policy, results)
    var trace = out.get(String("trace"))

    # Walk the tail of the log: the strategy's contribution to the futile fold
    # is detect(response.effective), then respond(response.action), then
    # respond(response.authority).
    var strategy_writes = List[Value]()
    for k in range(trace.len()):
        var w = trace.at(k)
        var slot = w.get(String("address")).get(String("slot"))
        if slot.is_text() and slot.s.startswith("response."):
            strategy_writes.append(w)

    # Fold 0 is an ordinary response: one write, and no `authority` write,
    # because its candidate declares `authority: null`. Fold 1 is futile: three.
    t.eq_int(
        String("one write for the ordinary fold, three for the futile one"),
        len(strategy_writes),
        4,
    )

    var fact = strategy_writes[len(strategy_writes) - 3]
    var decision = strategy_writes[len(strategy_writes) - 2]
    var governance = strategy_writes[len(strategy_writes) - 1]

    t.eq_str(
        String("the fact is detected"),
        fact.get(String("address")).get(String("operation")).s,
        String("detect"),
    )
    t.eq_str(
        String("at the effectiveness slot"),
        fact.get(String("address")).get(String("slot")).s,
        String("response.effective"),
    )
    t.eq_value(
        String("and it records that the response did not work"),
        fact.get(String("value")),
        Value.bool(False),
    )
    t.eq_str(
        String("the decision follows it"),
        decision.get(String("address")).get(String("operation")).s,
        String("respond"),
    )
    t.eq_str(
        String("and the governance follows that"),
        governance.get(String("address")).get(String("slot")).s,
        String("response.authority"),
    )

    # Both layers' writes are still one chain. A detect write inserted by
    # Strategy must not break the prev links Domain's writes established.
    t.check(
        String("the prev chain is unbroken across both layers"),
        chain_is_intact(trace),
        String("chain broken"),
    )

    # A fold that was not futile emits no strategy detect write.
    var moving = List[Value]()
    moving.append(
        _issue(Value.null(), _text(String("alice")), _text(String("rollback")))
    )
    moving.append(
        _issue(
            _text(String("bad deploy")), Value.null(), _text(String("rollback"))
        )
    )
    var out2 = run_with_strategy(model, strategy, policy, moving)
    var n = 0
    for k in range(out2.get(String("trace")).len()):
        var w = out2.get(String("trace")).at(k)
        var s = w.get(String("address")).get(String("slot"))
        if s.is_text() and s.s == String("response.effective"):
            n += 1
    t.eq_int(String("a fold that moved emits no detect"), n, 0)
```

Add `from address.write import chain_is_intact` to the imports, and both functions to `run`.

- [ ] **Step 3: Run it**

```bash
./run_tests.sh
```

Expected: PASS if Tasks 3 and 4 were implemented correctly. **If the ordering assertions fail,** the write list in `models/strategy-issue-effectiveness.yaml` is in the wrong order — `emit` walks it top to bottom, so `detect` must be declared before the `ineffective` respond. **If `chain_is_intact` fails,** the `prev` tail is not being carried across the three writes; check that `last_id(rwrites)` is read after all of them are appended.

- [ ] **Step 4: Commit**

```bash
git add tests/test_effectiveness.mojo tests/fixtures/strategy-precedence.yaml
git commit -m "Pin the log ordering and futility's precedence over the boundary"
```

---

## Task 6: Documentation, and proving the tests are coupled to the document

**Files:**
- Modify: `docs/runtime.md` (the Strategy section and "Deliberately not built")
- Modify: `docs/superpowers/specs/2026-08-13-response-effectiveness-design.md` (status line)

- [ ] **Step 1: Verify the new model document is mutation-tested**

The repository's standing discipline: a model document that the tests do not actually read is a document that can rot silently. Mutate one semantic value and confirm the suite catches it.

```bash
sed -i '' 's/- ref: previous.verdict.finding/- ref: verdict.finding/' models/strategy-issue-effectiveness.yaml && ./run_tests.sh; echo "exit=$?"; git checkout -- models/strategy-issue-effectiveness.yaml
```

Expected: non-zero exit. That mutation makes `progress` compare the finding to itself, so it always reports progress and futility can never fire — the run would report `exhausted` where the tests expect `ineffective`.

**If the suite passes, stop and report it.** It means the tests are not reading the progress test and the assertions are vacuous. Do not proceed to Step 2.

- [ ] **Step 2: Update `docs/runtime.md`**

In the "Deliberately not built" section, delete this bullet:

```markdown
- **Strategy counts answers, not progress.** Rung 2 knows it responded twice; it does
  not know that asking for logs accomplished nothing. Designed in
  `docs/superpowers/specs/2026-08-13-response-effectiveness-design.md`, not yet built.
```

In the Strategy section, add a row to the rung table:

```markdown
| 2b | `strategy-issue-effectiveness.yaml` | A progress test, and escalation on futility |
```

And add this after the escalation paragraph:

```markdown
**Exhausted and ineffective are different conclusions.** A boundary reports that the
budget ran out, which says nothing about whether anything was working. A strategy
declaring `expressions.progress` can compare the deviation across folds and conclude
that what it tried changed nothing — knowable before the budget runs out, and naming a
cause rather than a limit. Futility takes precedence when both hold.

The comparison is over the model's own deviation vocabulary, not over whole verdicts: a
resubmission can change `actual` while leaving the finding untouched, and reporting that
as progress would be wrong. Since the deviation's name is the model's word rather than
the protocol's, the model declares the test — the same relationship `goal.satisfy` has
with search.

`exception/detect` records the fact and `exception/respond` the decision that follows,
which settles what "Domain only detects" meant: **Strategy may detect, about its own
conduct.** Domain detects deviation in a Result; Strategy detects the failure of its own
response. Neither detects the other's subject.
```

Also update the mutation-coverage line to say **seven** model documents.

- [ ] **Step 3: Mark the spec implemented**

Change the spec's status line to:

```markdown
**Status:** implemented
```

- [ ] **Step 4: Run the full suite one more time**

```bash
./run_tests.sh
```

Expected: PASS, 0 failures. Report the final assertion count.

- [ ] **Step 5: Commit**

```bash
git add docs/runtime.md docs/superpowers/specs/2026-08-13-response-effectiveness-design.md
git commit -m "Document effectiveness detection as built"
```

---

## Self-review notes

**Spec coverage.** Model surface → Task 3. Load-time validation → Task 1. Props shape and boolean discipline → Task 2. Control flow, precedence, error handling, carried-pair coherence → Task 4. Run result `stopped` → Task 4. Write log and detect/respond ordering → Tasks 3 and 5. All ten spec test cases appear: 1 and 9 in `_deviation_moves`, 2 in `_deviation_stands_still`, 3 in `_futility_beats_exhaustion`, 4 in `_deviation_moves` fold zero, 5 in `_validation`, 6 and 7 in `_progress_evaluation`, 8 in `_the_log_reads_as_an_argument`, 10 in Task 6 Step 1.

**Deliberately deferred.** `converge()` gains no effectiveness detection and therefore no `stopped` field, so its result shape stays as it is. The two functions already differ (`converge` returns `proposals`), so this is a divergence rather than an inconsistency — but a reviewer should know it was a decision, not an oversight.

**Assertion counts** in the "Expected" lines are estimates from counting assertions in the plan's test code. Treat a mismatch as information, not failure; treat any nonzero failure count as a stop.

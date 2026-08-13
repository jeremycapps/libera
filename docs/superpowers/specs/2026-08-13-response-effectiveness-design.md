# Response effectiveness: a strategy that notices its own response did nothing

**Date:** 2026-08-13
**Status:** implemented
**Scope:** `strategy/respond.mojo`, `strategy/run.mojo`, a new model document, and tests.
No kernel, `modelir/`, `address/`, or `domain/` changes.

## Problem

Rung 2 counts answers, not progress. `strategy-issue-triage.yaml` can tell that it has
responded twice; it cannot tell that asking for logs the first time accomplished nothing.
Its only way to stop is `boundary.max_attempts`, which is a budget, not a judgment — it
reports *exhausted* when what actually happened was *ineffective*.

The two are different conclusions, and the second is strictly better:

- **exhausted** — the budget ran out. Says nothing about whether anything was working.
- **ineffective** — something was tried and the deviation did not move. Knowable *before*
  the budget runs out, and it names a cause rather than a limit.

A strategy that can draw the second conclusion escalates for a reason a human can act on.

## What the code already provides, and why it is not enough

Two findings from reading the current implementation, both verified rather than assumed.

**The previous verdict is already bound, and is unusable.** `respond_props`
(`strategy/respond.mojo:226`) binds `state` (pre-fold) and `next` (post-fold).
`issue-completeness.yaml`'s orchestrator folds `verdict: {ref: output}` into state, so
`state.verdict` *is* the prior fold's verdict. A candidate could in principle write
`eq: [{ref: verdict.finding}, {ref: state.verdict.finding}]` today.

It detonates on the first fold. `initial_state` (`domain/run.mojo:60`) seeds
`verdict: null`, and resolving through a null returns `cannot descend into null`
(`kernel/eval.mojo:113`). That error propagates strictly through `eq`, leaves `when`
non-boolean, and `respond` fails the whole run. The comparison is expressible and cannot
be written safely, because the expression language has no presence test — the same
missing-`has` gap already documented in `issue-completeness.yaml:44`, surfacing a second
time.

**The previous response is genuinely absent.** Domain state cannot carry it: Domain does
not know Strategy exists, and `test_layering.mojo` enforces that direction. Nothing feeds
a response forward into the next fold.

So this is not "add history." It is closing two specific gaps: making the comparison safe
to ask, and carrying Strategy's own conduct forward.

## Why the comparison is over findings, not verdicts

A supplier answers `ask_for_logs` by resubmitting: they add a `resolution_path`, still no
`root_cause`.

- The **verdict** differs structurally — `actual` changed.
- The **finding** is identical — still `missing_root_cause`.

Structural verdict equality reports progress here. It is wrong: the deviation the response
was aimed at did not move. What matters is whether the *deviation* changed, not whether
anything changed.

Which means something must decide what counts as the deviation — and `finding` is
vocabulary from `issue-completeness.yaml:65`, not from the protocol. The runtime hardcodes
`state.converged`; it has never hardcoded `conforms` or `finding`, and should not start.
The model declares the test.

## Design

### Model surface

Two optional keys in a strategy document, declared together or not at all:

```yaml
expressions:
  # Did the deviation move? Consulted only once a response has been recorded.
  progress:
    not:
      eq:
        - ref: verdict.finding
        - ref: previous.verdict.finding

  # The response when it did not.
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
```

`progress` is evaluated against `{ verdict, previous: { verdict, response } }` and must
return a boolean. A non-boolean is an error, not a coercion — the same discipline
`respond` already applies to a candidate's `when` (`strategy/respond.mojo:314`).

Binding the response, and not only the verdicts, is what makes the question *"did the
thing I tried work?"* rather than *"did anything change?"* It also lets a model reason
about a specific response later without another props change.

`effective: false` is load-bearing, not decorative: `emit` resolves a write's slot against
the response frame (`domain/emit.mojo:66`), so the `detect` write's `response.effective`
slot needs that field to exist on the response record.

### Load-time validation

`load_strategy` gains two compilations and one refusal:

- compile `expressions.progress` → `progress`
- compile `expressions.ineffective` → `ineffective`
- **refuse a strategy declaring one without the other.**

This follows the `operators`/`goal` precedent (`strategy/respond.mojo:193`) and the
`max_attempts`/`exhausted` precedent (`:213`), for the same reason both exist: a `progress`
test with no `ineffective` response computes a value nobody reads, and an `ineffective`
response with no test can never fire. Each is half a feature, and half a feature that
loads silently is worse than one that refuses.

### Control flow

The runtime carries two values across folds — the last verdict and the last response — set
**together, in the same assignment**, only when a response was actually recorded, i.e.
under the same `rwrites.len() > 0` condition that already gates `attempts`
(`strategy/run.mojo:327`).

Setting them together is what makes the pair coherent: `previous.verdict` must be the
verdict that `previous.response` was aimed at, not merely the most recent verdict seen. A
fold that produces no recorded response updates neither, so the strategy always compares
against the last state of affairs it actually acted on.

Tying it to recorded writes rather than to the loop index is what dissolves the first-fold
problem. Before a response has been recorded there is nothing to judge, `progress` is never
consulted, and no null is ever reached. The feature does not need `has` to exist.

Selection becomes three-way:

```
futile = has_progress_test(strategy)
         and a response was previously recorded
         and not converged(next)
         and not progress(strategy, progress_props(...))

if   futile:        response = ineffective(strategy, props)
elif over_boundary: response = escalation(strategy, props)
else:               response = respond(strategy, props)
```

**Futility takes precedence over exhaustion.** If both hold, "your response did not work"
is the more specific and more actionable conclusion, and escalating immediately is what
the feature means. With `max_attempts: 2` the two do not collide — futility fires at fold
1, exhaustion at fold 2 — but leaving precedence implicit would make that an accident of
the numbers rather than a decision.

**An error from `progress` aborts the run.** It is not read as "no progress." A broken
predicate is a defect in the model; treating it as failure would escalate for the wrong
reason and hide the defect behind plausible behavior.

Both `ineffective` and `exhausted` end this strategy's involvement, so both break the loop
— continuing to verify after handing off would be answering a question already given away,
which is the reasoning already recorded at `strategy/run.mojo:338`.

### Run result

`run()` keeps `exhausted: Bool` with its current meaning — *this strategy stopped early and
handed off* — and gains a symbol naming why:

```
stopped: converged | ineffective | exhausted | results_consumed
```

Additive, so existing assertions reading `exhausted` keep passing. Repurposing `exhausted`
into a three-valued field would churn tests across three suites to express what a second
field expresses cleanly.

`ineffective: Bool` is also bound into the write props, which is what lets the policy gate
the two writes below.

### The write log

Per the recorded separation test — *detect writes a fact; respond writes a decision that
branches* — concluding the response was ineffective is a fact, and escalating because of it
is a decision. They are two writes at two addresses.

This settles an ambiguity in that decision as recorded. *"Strategy owns `exception/respond`;
Domain only detects"* can be read as *Domain does only detection* or *only Domain detects*.
This case forces the first reading: **Strategy may detect, about its own conduct.** The
boundary that matters is not who may write `detect` but what a `detect` write is about —
Domain detects deviation in a Result; Strategy detects the failure of its own response.
Neither layer detects the other's subject.

The strategy document declares four writes, in this order:

```yaml
writes:
  list:
    - record:                       # ordinary response
        when: { and: [ {not: {ref: next.converged}}, {not: {ref: ineffective}} ] }
        pressure: exception
        operation: respond
        slot: response.action

    - record:                       # the fact
        when: { ref: ineffective }
        pressure: exception
        operation: detect
        slot: response.effective

    - record:                       # the decision that follows from it
        when: { ref: ineffective }
        pressure: exception
        operation: respond
        slot: response.action

    - record:                       # who it was handed to
        when: { not: { eq: [ {ref: response.authority}, null ] } }
        pressure: exception
        operation: respond
        slot: response.authority
```

`emit` walks the list in order, so a futile fold produces `detect` → `respond` →
`authority`: the fact, then the decision, then the governance. The log reads as an argument
rather than an announcement.

Classification is unaffected — it derives from emitted pressures, and every write here is
still `exception`.

## Deliberately not built

**`converge()` (rung 3) is unchanged.** There the strategy re-derives a proposal from actual
state each round rather than repeating a response, and the search bound plus attempt budget
already govern termination. Extending effectiveness detection into it would double the
surface to serve a loop where the question is less sharp. Defensible later; not now.

**No `max_futile` boundary.** One repeat escalates. A second tunable would need a reason to
exist, and "one repeat may be noise" is a hypothesis about real triage data that does not
exist yet.

**No candidate suppression.** A dead response is not removed from the candidate list for a
retry, because there is no retry — futility escalates immediately.

## Testing

Fold-level behavior:

1. The deviation moves between folds — `progress` holds, no escalation, ordinary response.
2. The deviation stands still — escalates as ineffective, **before** the attempt budget is
   spent, and `stopped` is `ineffective`.
3. Futility and exhaustion both hold — futility wins, and the assertion pins the precedence
   rather than the arithmetic.
4. First fold with a progress test declared — `progress` is not consulted, no error.

Load-time:

5. `progress` without `ineffective` is refused; `ineffective` without `progress` is refused.
6. A `progress` expression returning a non-boolean is an error naming the value.
7. An error inside `progress` aborts the run rather than escalating.

Log:

8. A futile fold emits `detect` then `respond` then `authority`, in that order, with the
   `prev` chain unbroken across all three.
9. A non-futile fold emits no `detect`.

Coupling:

10. Mutating the new model document produces failures rather than passing vacuously — the
    discipline that has caught real bugs three times in this repository, including twice in
    tests written the same session.

## Documentation debt to clear alongside

Both are already false in `main` and this change touches the same subject matter:

- `README.md:34` says `strategy/ … not built`, and `README.md:91` claims 604 assertions
  (actual: 815).
- `docs/runtime.md:169–177` has a *"Deliberately not built — No Strategy layer / No
  `exception/respond`"* section, contradicted by the three rungs already committed.

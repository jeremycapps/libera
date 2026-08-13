# The Mojo reference runtime

How this repository's implementation of the Libera protocol works. The protocol itself is
`protocol/address.schema.yaml`; this document is about the code that implements it.

```
kernel/value.mojo     Value: the universal representable object
kernel/eval.mojo      Resolve(ref, props) and Evaluate(expr, props)
kernel/ir.mojo        Construction helpers for the normalized Model IR

modelir/text.mojo     Byte-level text helpers
modelir/yaml.mojo     YAML subset reader -> plain data Values
modelir/compile.mojo  Data tree -> normalized Model IR

address/grammar.mojo  Address: {program, pressure, operation, slot}
address/write.mojo    Write: a value landing at an Address, with a prev chain

domain/model.mojo     DomainModel: a YAML model object loaded into IR
domain/emit.mojo      Write policy evaluation and slot resolution
domain/run.mojo       Contract -> Result -> Verdict -> CurrentState -> Snapshot

strategy/respond.mojo Loading a strategy; selecting a response; the boundary
strategy/search.mojo  Candidate generation and scoring over composed operators
strategy/run.mojo     Driving a Domain run with a Strategy attached
```

## The kernel law

    Value_out = Evaluate(Expression, Props)

`Props` is an environment Value (a record) mapping names to Values. That is the
entire execution surface. The kernel has no notion of Contract, Result,
Verdict, CurrentState, Operator, Goal, Boundary, or Heuristic — those are
Domain and Strategy concepts that compile *down* to the forms below.

## Value forms

Eleven tags, per doc §2.1 plus `error`:

`null` · `bool` · `int` · `float` · `string` · `symbol` · `list` · `record` ·
`ref` · `expression` · `error`

Everything is a Value — including expressions, which is what makes them *data
until Evaluate applies them*.

## Expression forms

All of doc §2.2:

| Form | Example | Notes |
|---|---|---|
| literal | `Value.int(3)` | Evaluates to itself |
| ref | `r("contract.expected.count")` | Resolved against props |
| record / list | `record_of(...)`, `list_of(...)` | Build by evaluating parts |
| arithmetic | `add`, `subtract`, `abs` | `add` variadic; Int-ness preserved |
| comparison | `eq`, `lt`, `gt`, `lte`, `gte` | `eq` structural; ordering numeric |
| logic | `and`, `or`, `not` | `and`/`or` short-circuit |
| conditional | `if_(cond, then, else)` | Only the taken branch evaluates |
| merge | `merge(state, patch)` | Shallow; later argument wins |
| projection | `get(subject, key)` | Reaches into a computed value |
| lambda-like | `lam(props, body)` + `call` | `props + body + returns` |

## Design decisions

Choices the doc left open (§8), resolved for v0. They are stated here rather
than buried in the code, because each is a candidate for revisiting.

**Values are immutable.** Children live behind `ArcPointer`, so copies are O(1)
and structural sharing is safe. This also sidesteps Mojo's inability to
synthesize a copy constructor for a struct directly containing `List[Self]`.

**Errors are Values, not exceptions.** Neither `evaluate` nor `resolve` raises.
Every failure — unresolved ref, type mismatch, bad arity, unknown op — returns
an `error` Value carrying a code and message. This keeps the kernel law total
and leaves failures inspectable and foldable into state by the layers above.
Errors propagate strictly through operators; the exceptions are `and`/`or` and
`if`, which are lazy by declaration.

**Literal records are inert.** `evaluate` does not descend into a literal
`record` or `list`; building one from expressions is the separate `record` /
`list` form. Without that split there would be no way to carry an expression
as data.

**Truthiness is strict.** Only the boolean `true` is true. A non-boolean
condition is a type error, never a silent coercion.

**Int-ness is preserved.** `add`/`subtract`/`abs` return an Int only when every
argument is an Int, so counting stays exact; any Float widens the result.
Numeric comparison works across the two tags (`3 == 3.0`), since counts may
arrive either way.

**String and Symbol do not cross-compare.** `"confirmed"` is not the symbol
`confirmed`; the distinction carries meaning upstream.

**`merge` is shallow.** Deep-merge semantics would smuggle a policy decision
into the kernel.

**Lambdas are not closures.** They capture nothing from their definition site,
which keeps them inert data that survives a YAML round-trip. Arguments are
evaluated in the caller's environment; the body sees only its own props.

**Refs.** Local and model paths are indistinguishable to the kernel — both are
dotted lookups into props, which is the point: the kernel does not know what
`contract` means. A qualified ref (`@domain/bootstrap.contract.expected`)
resolves its `@`-prefixed qualifier as an ordinary props key, so a host can
bind other models by name; an unbound qualifier reports `unresolved_model`
rather than a generic missing key. External URI resolution is out of scope.

## YAML authoring format

An expression is a **single-key mapping whose key names an operator**, exactly
as the architecture doc writes them:

```yaml
conforms:
  eq:
    - ref: actual.count
    - ref: expected.count
```

Anything else is data. A mapping with several keys, or with one key that is not
an operator, compiles to a literal record — so `contract.expected.count` stays
plain data while `conforms:` becomes an expression.

That rule has one sharp edge: a data record whose only key happens to be named
after an operator would be read as an expression. `literal:` is the escape
hatch:

```yaml
literal:
  eq: 1        # a data record with a field called "eq"
```

**Scalar typing.** Quoted text is a String; bare text that is not a recognised
bool, null, or number is a Symbol. That is what makes the doc's
`then: confirmed` a symbol, comparable to a verdict finding rather than to
arbitrary text.

**Supported subset:** block mappings, block sequences, flow mappings and
sequences, comments. Anchors, aliases, tags, multiple documents, and block
scalars (`|`, `>`) are **rejected with a parse error naming the line** rather
than silently mis-parsed. Parse errors are Values carrying a `line` field.

## Domain (layer 2)

Domain is a YAML model object, not Mojo code. `domain/` holds only the wiring;
every semantic decision — what conformance means, how state folds, what counts
as converged — lives in the model document.

Per doc §3.2, the runtime decides only which props each expression sees:

    Verdict     = Evaluate(Contract.verifier, { expected, actual })
    State_next  = Evaluate(orchestrate,       { state, output })

`contract` and `result` are also bound during verification, so a richer
verifier can reach the whole contract; the doc's two-binding form is the subset
the Level 0 model actually uses.

**Level 0 does not plan.** A Result is supplied from outside, Domain verifies
it, folds the outcome into state, and emits a Snapshot once converged. Given
only non-conforming results it stays unconverged rather than deriving a
conforming one — that is Strategy's job, and there is a test pinning the
absence.

**The verifier** is taken from `contract.verifier` when present, falling back to
`expressions.verify`. Doc §3.1 gives Contract the shape `{ expected, verifier? }`
while §3.3 writes the verifier under `expressions:`; both work.

**Missing expressions are reported when asked for, not at load time.** D0 needs
only a verifier, so a model without an orchestrator still loads and still
verifies.

## Strategy (layer 3)

Domain decides whether a Result conforms. Strategy decides what to do when it does
not — which is why this layer, not Domain, owns `exception/respond`. Like Domain it
is a YAML model object; `strategy/` holds only the wiring.

Built as three rungs of one ladder rather than a single leap, because the doc's
`count +2/+3` example jumps straight to search and makes Strategy look more abstract
than it is:

| Rung | Document | What it adds |
|---|---|---|
| 1 | `strategy-route-back.yaml` | One fixed response, and no way to stop |
| 2 | `strategy-issue-triage.yaml` | Several candidates, a selection rule, a boundary |
| 2b | `strategy-issue-effectiveness.yaml` | A progress test, and escalation on futility |
| 3 | `strategy-count-search.yaml` | Bounded search over composed operators |

**Selection is rule-based, not scored** (rung 2). Each candidate declares a `when`;
the first whose condition holds is taken. The last must be unconditional, or a
deviation could arrive that nothing answers — which is a gap in the model, not a
reason to do nothing quietly.

**The boundary is what makes a strategy stoppable.** `boundary.max_attempts` bounds
how many times it answers without converging. Crossing it does not fail silently: it
escalates, and the escalation names an `authority`.

**Escalation is a species of respond, not a peer of detect** — distinguished by naming
who can make the decision count. This is what `due ↔ authority` in `docs/fields.md`
predicted from the opposite direction.

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

**Rung 3 closes the loop.** `converge` lets Strategy propose Results until Domain
accepts one, so the runtime can reach a contract on its own. The goal and heuristic
guide the search; they never decide the outcome. A proposal is still just a Result and
Domain still verifies it, so a misleading heuristic costs attempts, not correctness —
`_goal_does_not_decide_truth` pins this by giving the search a goal that contradicts
the contract and showing the proposal rejected anyway.

## Deliberately not built

- **Domain never emits `exception/respond`.** Responding to a deviation means choosing
  what to try next. The grammar knows the operation; Domain Level 0 never emits it, and
  a test pins the absence.
- **No `has` operator**, and no way to bind a helper into a verifier's props. This is
  why `issue-completeness.yaml` spells out its presence tests once per field.
- **No operator `cost` or `max_cost`.** Depth bounds the search adequately; weighing
  operators differently without a reason to would be ceremony.
- **The frontier is bounded-exhaustive, not best-first.** It expands everything at each
  depth rather than pursuing the lowest score. Fine at depth 2 with two operators; it
  would matter with a real branching factor.

The bootstrap table (§6) is complete: K0, D0, D1, S0, S1, and Integration all pass.

## Test coverage

| Module | Covers |
|---|---|
| `test_value.mojo` | Tags, scalars, numeric and structural equality, ref parsing, non-trapping access, deterministic rendering, copy semantics |
| `test_resolve.mojo` | Dotted paths, list indexing, qualified refs, and every failure mode |
| `test_eval.mojo` | Every §2.2 expression form, plus laziness, strict error propagation, determinism, and props immutability |
| `test_k0.mojo` | The doc's K0 case, its complement, and order-independence |
| `test_yaml.mojo` | Scalar typing, block maps and sequences, flow collections, comments, CRLF, and every rejected construct |
| `test_compile.mojo` | Operator recognition, data-versus-construction, the `literal:` escape, lambdas, and round-trip evaluation of compiled IR |
| `test_domain.mojo` | D0, D1, traces A and B, convergence, Snapshot, model validation, the absence of planning, and the addressed write log |
| `test_address.mojo` | Pressure/operation vocabulary, pairing rules, construction, render/parse round-trip |
| `test_write.mojo` | Write records, id derivation, and `prev` chain integrity including orphan heads |
| `test_policy_doc.mojo` | The default write policy parses, compiles, and never mentions `respond` |
| `test_emit.mojo` | Policy evaluation, `when` filtering, slot resolution, duplicate-id rejection |
| `test_layering.mojo` | Import-direction layering, and conformance against `protocol/address.schema.yaml` |
| `test_issue_model.mojo` | A Domain model over a real contract shape, and that the default write policy is contract-agnostic |
| `test_strategy.mojo` | Rung 1: a response decided and addressed, and that Strategy is optional |
| `test_strategy_triage.mojo` | Rung 2: candidate selection, the boundary, and escalation carrying an `authority` |
| `test_search.mojo` | Rung 3: operator composition, scoring, the closed loop, and that a goal does not decide truth |

Two things were verified beyond the suite passing:

- **The harness can fail.** Run against a deliberately failing suite, all eight
  assertion kinds report correctly and the process exits 1.
- **The tests are coupled to the data.** A semantic mutation of **each of the seven model
  documents** in `models/`, and of `protocol/address.schema.yaml`, produces failures
  rather than passing vacuously — verified by mutating one value per file and running the
  suite against it. The conformance test reads the canonical schema directly, so the
  runtime cannot drift from the protocol it ships.

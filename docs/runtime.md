# The Mojo reference runtime

How this repository's implementation of the Libera protocol works. The protocol itself is
`protocol/libera.schema.yaml`; this document is about the code that implements it.

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

## Deliberately not built

- **No Strategy layer** — Operators, Goal, Boundary, Candidate, Heuristic (§4).
  Levels S0, S1, and Integration from the bootstrap table (§6) remain open.
- **No `exception/respond`.** Responding to a deviation means choosing what to try
  next, which is Strategy's job. The grammar knows the operation; Level 0 never emits
  it, and a test pins the absence.

K0, D0, and D1 are done.

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
| `test_layering.mojo` | Import-direction layering, and conformance against `protocol/libera.schema.yaml` |

Two things were verified beyond the suite passing:

- **The harness can fail.** Run against a deliberately failing suite, all eight
  assertion kinds report correctly and the process exits 1.
- **The tests are coupled to the data.** Mutations of
  `models/domain-count-level-0.yaml`, `models/writes-default.yaml`, and
  `protocol/libera.schema.yaml` each produce failures rather than passing vacuously.
  The conformance test reads the canonical schema directly, so the runtime cannot
  drift from the protocol it ships.

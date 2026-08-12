# Libera Kernel

The Mojo evaluation substrate from *Model Kernel, Domain, and Strategy
Architecture* — layer 1 only. Domain and Strategy are **not** built here, by
design.

```
kernel/value.mojo   Value: the universal representable object
kernel/eval.mojo    Resolve(ref, props) and Evaluate(expr, props)
kernel/ir.mojo      Construction helpers for the normalized Model IR
testkit/harness.mojo  Assertion harness (Mojo 0.26 has no `mojo test`)
tests/              The suite; `run_all.mojo` is the entry point
```

## Running the tests

```bash
./run_tests.sh
```

Or directly:

```bash
mojo run -I . tests/run_all.mojo
```

Exits non-zero on any failure. Current status: **237 assertions, 0 failures**,
including K0 from doc §2.3.

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

## Deliberately not built

- **No YAML front end.** Per doc §7, YAML is an authoring format that compiles
  to Model IR; the kernel evaluates the IR. `kernel/ir.mojo` is the current
  producer of that IR, and a YAML loader would become another producer rather
  than getting its own path into the evaluator. K0 is therefore transcribed
  into IR in `tests/test_k0.mojo`, with the doc's YAML quoted verbatim above it.
- **No Domain layer** — Contract, Result, Verdict, CurrentState, Snapshot (§3).
- **No Strategy layer** — Operators, Goal, Boundary, Candidate, Heuristic (§4).

Levels D0, D1, S0, S1, and Integration from the doc's bootstrap table (§6)
remain open. K0 is done.

## Test coverage

| Module | Covers |
|---|---|
| `test_value.mojo` | Tags, scalars, numeric and structural equality, ref parsing, non-trapping access, deterministic rendering, copy semantics |
| `test_resolve.mojo` | Dotted paths, list indexing, qualified refs, and every failure mode |
| `test_eval.mojo` | Every §2.2 expression form, plus laziness, strict error propagation, determinism, and props immutability |
| `test_k0.mojo` | The doc's K0 case, its complement, and order-independence |

The harness itself was verified against a deliberately failing suite: all eight
assertion kinds report correctly and the process exits 1.

"""K0 -- the kernel bootstrap test from doc 2.3 and the level table in doc 6.

    Level  Purpose             Test                      Pass condition
    K0     Kernel evaluation   Evaluate eq over refs.     Returns correct
                                                          boolean Value.

The doc states the case as YAML:

    # Kernel test: evaluate equality over refs
    props:
      expected:
        count: 3
      actual:
        count: 2
    expression:
      eq:
        - ref: expected.count
        - ref: actual.count
    expected_output: false

Since v0 ships the evaluator without a YAML front end, that document is
transcribed here into the same normalized Model IR a YAML loader would emit.

The point of K0 is negative as much as positive: it must pass while the kernel
knows nothing about Contract, Result, or Verdict. `expected` and `actual` here
are just record keys -- the kernel never interprets them. D0 is where they
start to mean something, and D0 is not this layer's problem.
"""

from std.collections import List, Dict

from kernel.value import Value, BOOL
from kernel.eval import evaluate
from kernel.ir import kv, rec, r, ex
from testkit.harness import TestSuite


fn _k0_props(expected_count: Int, actual_count: Int) -> Value:
    """The `props:` block, parameterised by the two counts."""
    return rec(
        kv(String("expected"), rec(kv(String("count"), Value.int(expected_count)))),
        kv(String("actual"), rec(kv(String("count"), Value.int(actual_count)))),
    )


fn _k0_expression() -> Value:
    """The `expression:` block -- eq over two refs."""
    return ex(
        String("eq"),
        r(String("expected.count")),
        r(String("actual.count")),
    )


fn run(mut t: TestSuite):
    t.section(String("K0 / kernel evaluation (doc 2.3)"))

    var expr = _k0_expression()

    # The case exactly as written in the doc: expected 3, actual 2 -> false.
    var props = _k0_props(3, 2)
    var out = evaluate(expr, props)

    t.eq_value(
        String("K0 returns the documented expected_output: false"),
        out,
        Value.bool(False),
    )
    t.check(
        String("K0 returns a boolean Value, not a truthy one"),
        out.tag == BOOL,
        String("expected a bool tag, got ") + out.to_string(),
    )
    t.not_error(String("K0 evaluates without error"), out)

    # The complementary case, so the test is falsifiable rather than merely
    # agreeing with a hardcoded `false`.
    t.eq_value(
        String("K0 with matching counts returns true"),
        evaluate(expr, _k0_props(3, 3)),
        Value.bool(True),
    )
    t.eq_value(
        String("K0 with actual above expected returns false"),
        evaluate(expr, _k0_props(3, 4)),
        Value.bool(False),
    )

    # The expression is inert data until applied: the identical expression
    # value drives every case above, and is unchanged afterwards.
    t.eq_value(
        String("K0 expression is unchanged by evaluation"),
        expr,
        _k0_expression(),
    )
    t.eq_str(
        String("K0 expression renders as eq over two refs"),
        expr.to_string(),
        String("(eq ref(expected.count) ref(actual.count))"),
    )

    # Reordering the props record must not change the outcome -- records are
    # unordered, and resolution is by name.
    var reordered = rec(
        kv(String("actual"), rec(kv(String("count"), Value.int(2)))),
        kv(String("expected"), rec(kv(String("count"), Value.int(3)))),
    )
    t.eq_value(
        String("K0 is independent of props field order"),
        evaluate(expr, reordered),
        Value.bool(False),
    )

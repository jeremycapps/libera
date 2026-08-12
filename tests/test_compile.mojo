"""Tests for YAML -> Model IR normalization.

Two things are checked throughout: that the YAML compiles to the *shape* the
kernel expects, and that evaluating the compiled form gives the right answer.
The second matters more -- a compiler that produces plausible-looking IR that
evaluates wrongly is the failure mode worth catching.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, LIST, REF, EXPR, SYMBOL
from kernel.eval import evaluate
from kernel.ir import kv, rec, lst, r, ex, sym, record_of, list_of, if_
from modelir.yaml import parse_yaml
from modelir.compile import compile_expression, is_operator
from testkit.harness import TestSuite


fn _compile(var src: String) -> Value:
    """Parse a YAML fragment and normalize it to IR."""
    return compile_expression(parse_yaml(src^))


fn _env() -> Value:
    return rec(
        kv(String("expected"), rec(kv(String("count"), Value.int(3)))),
        kv(String("actual"), rec(kv(String("count"), Value.int(2)))),
        kv(String("n"), Value.int(4)),
    )


fn run(mut t: TestSuite):
    _operator_table(t)
    _refs(t)
    _data_vs_construction(t)
    _operators(t)
    _conditional(t)
    _literal_escape(t)
    _lambdas(t)
    _errors(t)


fn _operator_table(mut t: TestSuite):
    t.section(String("compile / operator recognition"))

    t.check(String("eq is an operator"), is_operator(String("eq")), String("eq"))
    t.check(String("ref is an operator"), is_operator(String("ref")), String("ref"))
    t.check(
        String("record is an operator"), is_operator(String("record")), String("record")
    )
    t.check(String("if is an operator"), is_operator(String("if")), String("if"))
    t.check(
        String("literal is an operator"),
        is_operator(String("literal")),
        String("literal"),
    )
    t.check(
        String("count is not an operator"),
        not is_operator(String("count")),
        String("count must be data"),
    )
    t.check(
        String("expected is not an operator"),
        not is_operator(String("expected")),
        String("expected must be data"),
    )


fn _refs(mut t: TestSuite):
    t.section(String("compile / refs"))

    var ir = _compile(String("ref: expected.count\n"))
    t.check(
        String("ref compiles to a REF value"),
        ir.tag == REF,
        String("got ") + ir.to_string(),
    )
    t.eq_value(String("ref path"), ir, r(String("expected.count")))
    t.eq_value(
        String("compiled ref resolves"), evaluate(ir, _env()), Value.int(3)
    )

    # A quoted path works too, and a qualified path survives compilation.
    t.eq_value(
        String("quoted ref path"),
        _compile(String('ref: "expected.count"\n')),
        r(String("expected.count")),
    )
    t.eq_value(
        String("qualified ref"),
        _compile(String("ref: @domain/bootstrap.contract\n")),
        r(String("@domain/bootstrap.contract")),
    )


fn _data_vs_construction(mut t: TestSuite):
    t.section(String("compile / data versus construction"))

    # A multi-key mapping is data: it compiles to a literal RECORD, which the
    # kernel leaves inert.
    var data = _compile(String("expected:\n  count: 3\nother: 1\n"))
    t.check(
        String("multi-key mapping is a literal record"),
        data.tag == RECORD,
        String("got ") + data.to_string(),
    )
    t.eq_value(String("data record is inert"), evaluate(data, _env()), data)

    # A single-key mapping whose key is not an operator is also data.
    var single = _compile(String("expected:\n  count: 3\n"))
    t.check(
        String("single non-operator key is a literal record"),
        single.tag == RECORD,
        String("got ") + single.to_string(),
    )
    t.eq_value(
        String("contract-shaped data compiles to itself"),
        single,
        rec(kv(String("expected"), rec(kv(String("count"), Value.int(3))))),
    )

    # `record:` is construction: it evaluates its fields.
    var built = _compile(
        String(
            """
record:
  actual:
    ref: actual.count
  expected:
    ref: expected.count
"""
        )
    )
    t.check(
        String("record form compiles to an expression"),
        built.tag == EXPR,
        String("got ") + built.to_string(),
    )
    t.eq_value(
        String("record form evaluates its fields"),
        evaluate(built, _env()),
        rec(
            kv(String("actual"), Value.int(2)),
            kv(String("expected"), Value.int(3)),
        ),
    )

    # The same field names as data stay unevaluated -- this is the distinction
    # the whole authoring convention rests on.
    var as_data = _compile(
        String("actual:\n  ref: actual.count\nexpected:\n  ref: expected.count\n")
    )
    var evaluated_as_data = evaluate(as_data, _env())
    t.eq_value(String("same fields as data stay inert"), evaluated_as_data, as_data)
    t.ne_value(
        String("data and construction differ"),
        evaluated_as_data,
        evaluate(built, _env()),
    )

    var list_form = _compile(String("list:\n  - ref: n\n  - 7\n"))
    t.eq_value(
        String("list form evaluates its items"),
        evaluate(list_form, _env()),
        lst(Value.int(4), Value.int(7)),
    )

    var data_list = _compile(String("- 1\n- 2\n"))
    t.eq_value(
        String("a bare sequence is a literal list"),
        data_list,
        lst(Value.int(1), Value.int(2)),
    )


fn _operators(mut t: TestSuite):
    t.section(String("compile / operators"))

    var eq = _compile(
        String("eq:\n  - ref: actual.count\n  - ref: expected.count\n")
    )
    t.eq_value(
        String("eq compiles to the kernel form"),
        eq,
        ex(String("eq"), r(String("actual.count")), r(String("expected.count"))),
    )
    t.eq_value(
        String("eq evaluates to false for 2 vs 3"),
        evaluate(eq, _env()),
        Value.bool(False),
    )

    t.eq_value(
        String("add over a ref and a literal"),
        evaluate(_compile(String("add:\n  - ref: n\n  - 6\n")), _env()),
        Value.int(10),
    )
    t.eq_value(
        String("subtract"),
        evaluate(
            _compile(String("subtract:\n  - ref: expected.count\n  - ref: actual.count\n")),
            _env(),
        ),
        Value.int(1),
    )
    t.eq_value(
        String("nested arithmetic"),
        evaluate(
            _compile(
                String(
                    """
abs:
  - subtract:
      - ref: actual.count
      - ref: expected.count
"""
                )
            ),
            _env(),
        ),
        Value.int(1),
    )
    t.eq_value(
        String("logic operators"),
        evaluate(
            _compile(
                String(
                    """
and:
  - eq:
      - ref: expected.count
      - 3
  - not:
      - eq:
          - ref: actual.count
          - 3
"""
                )
            ),
            _env(),
        ),
        Value.bool(True),
    )

    # Unary convenience: a single argument need not be wrapped in a sequence.
    t.eq_value(
        String("unary operator without a sequence"),
        evaluate(_compile(String("abs:\n  subtract:\n    - 1\n    - 5\n")), _env()),
        Value.int(4),
    )
    t.eq_value(
        String("flow-style arguments"),
        evaluate(_compile(String("add: [1, 2, 3]\n")), _env()),
        Value.int(6),
    )
    t.eq_value(
        String("merge"),
        evaluate(
            _compile(String("merge:\n  - literal: {a: 1}\n  - literal: {a: 2, b: 3}\n")),
            _env(),
        ),
        rec(kv(String("a"), Value.int(2)), kv(String("b"), Value.int(3))),
    )


fn _conditional(mut t: TestSuite):
    t.section(String("compile / conditional"))

    var src = String(
        """
if:
  condition:
    eq:
      - ref: actual.count
      - ref: expected.count
  then: confirmed
  else: not_confirmed
"""
    )
    var ir = _compile(src)
    t.check(
        String("if compiles to an expression"),
        ir.tag == EXPR,
        String("got ") + ir.to_string(),
    )
    t.eq_value(
        String("if evaluates the else branch for 2 vs 3"),
        evaluate(ir, _env()),
        sym(String("not_confirmed")),
    )

    var matching = rec(
        kv(String("expected"), rec(kv(String("count"), Value.int(3)))),
        kv(String("actual"), rec(kv(String("count"), Value.int(3)))),
    )
    t.eq_value(
        String("if evaluates the then branch when counts match"),
        evaluate(ir, matching),
        sym(String("confirmed")),
    )

    # The branch values are symbols, not strings -- so they compare equal to a
    # verdict finding written the same way.
    t.check(
        String("branch results are symbols"),
        evaluate(ir, matching).tag == SYMBOL,
        String("got ") + evaluate(ir, matching).to_string(),
    )

    t.eq_value(
        String("if without else yields null"),
        evaluate(_compile(String("if:\n  condition: false\n  then: 1\n")), _env()),
        Value.null(),
    )


fn _literal_escape(mut t: TestSuite):
    t.section(String("compile / literal escape hatch"))

    # Without `literal:`, a single-key mapping named after an operator would be
    # read as an expression. This is the way out.
    var escaped = _compile(String("literal:\n  eq: 1\n"))
    t.check(
        String("literal produces data, not an expression"),
        escaped.tag == RECORD,
        String("got ") + escaped.to_string(),
    )
    t.eq_value(
        String("literal preserves the operator-named key"),
        escaped,
        rec(kv(String("eq"), Value.int(1))),
    )
    t.eq_value(String("literal data is inert"), evaluate(escaped, _env()), escaped)

    # Contrast: the same mapping without the escape compiles to an expression.
    var unescaped = _compile(String("eq: 1\n"))
    t.check(
        String("unescaped operator key becomes an expression"),
        unescaped.tag == EXPR,
        String("got ") + unescaped.to_string(),
    )

    t.eq_value(
        String("literal passes scalars through"),
        _compile(String("literal: 3\n")),
        Value.int(3),
    )
    t.eq_value(
        String("literal keeps nested refs as data"),
        _compile(String("literal:\n  ref: a.b\n")),
        rec(kv(String("ref"), Value.symbol(String("a.b")))),
    )


fn _lambdas(mut t: TestSuite):
    t.section(String("compile / lambda and call"))

    var src = String(
        """
call:
  callee:
    lambda:
      props:
        x: 0
      body:
        add:
          - ref: x
          - ref: x
  args:
    x: 5
"""
    )
    t.eq_value(
        String("lambda declared and applied from YAML"),
        evaluate(_compile(src), _env()),
        Value.int(10),
    )

    var with_returns = String(
        """
call:
  callee:
    lambda:
      props:
        x: 0
      body:
        record:
          doubled:
            add:
              - ref: x
              - ref: x
      returns:
        ref: body.doubled
  args:
    x:
      ref: n
"""
    )
    t.eq_value(
        String("lambda returns projection, argument from a ref"),
        evaluate(_compile(with_returns), _env()),
        Value.int(8),
    )

    t.eq_value(
        String("call uses declared defaults when args are omitted"),
        evaluate(
            _compile(
                String(
                    """
call:
  callee:
    lambda:
      props:
        x: 7
      body:
        ref: x
"""
                )
            ),
            _env(),
        ),
        Value.int(7),
    )


fn _errors(mut t: TestSuite):
    t.section(String("compile / errors"))

    t.is_error(
        String("ref with a non-text path"),
        _compile(String("ref:\n  a: 1\n")),
        String("compile_error"),
    )
    t.is_error(
        String("record form with a sequence"),
        _compile(String("record:\n  - 1\n")),
        String("compile_error"),
    )
    t.is_error(
        String("list form with a mapping"),
        _compile(String("list:\n  a: 1\n")),
        String("compile_error"),
    )
    t.is_error(
        String("if with a sequence"),
        _compile(String("if:\n  - 1\n")),
        String("compile_error"),
    )
    t.is_error(
        String("call without a callee"),
        _compile(String("call:\n  args:\n    x: 1\n")),
        String("compile_error"),
    )
    t.is_error(
        String("call args as a sequence"),
        _compile(String("call:\n  callee: 1\n  args:\n    - 1\n")),
        String("compile_error"),
    )

    # A parse error upstream passes through the compiler unchanged rather than
    # being reclassified as a compile error.
    t.is_error(
        String("parse errors pass through"),
        _compile(String("a: {b: 1\n")),
        String("parse_error"),
    )

    # An error nested inside data propagates out.
    t.is_error(
        String("error nested in data propagates"),
        _compile(String("outer:\n  inner:\n    ref:\n      bad: 1\n")),
        String("compile_error"),
    )

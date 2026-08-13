"""The default write policy must parse and compile like any other model expression.

The policy is data, not Mojo. That is what keeps the runtime from making semantic
judgments of its own -- it evaluates a declared expression and filters on a declared
boolean.
"""

from std.collections import List, Dict

from kernel.value import Value, EXPR, LIST
from modelir.yaml import parse_yaml_file
from modelir.compile import compile_expression
from testkit.harness import TestSuite


comptime POLICY_PATH = "models/writes-default.yaml"


fn run(mut t: TestSuite) raises:
    t.section(String("policy / default document"))

    var root = parse_yaml_file(String(POLICY_PATH))
    t.not_error(String("policy document parses"), root)
    t.check(
        String("declares a model name"),
        root.has(String("model")),
        String("missing model:"),
    )
    t.check(
        String("declares expressions"),
        root.has(String("expressions")),
        String("missing expressions:"),
    )
    t.check(
        String("declares expressions.writes"),
        root.get(String("expressions")).has(String("writes")),
        String("missing expressions.writes"),
    )

    var ir = compile_expression(
        root.get(String("expressions")).get(String("writes"))
    )
    t.not_error(String("policy compiles to IR"), ir)
    t.check(
        String("compiles to a list expression"),
        ir.tag == EXPR and ir.s == String("list"),
        String("got ") + ir.to_string(),
    )
    t.eq_int(String("declares four candidate writes"), ir.len(), 4)

    # exception/respond must not appear. Level 0 detects; Strategy responds.
    var rendered = ir.to_string()
    t.check(
        String("policy never emits respond"),
        rendered.find("respond") == -1,
        String("Level 0 must not respond to deviations"),
    )
    t.check(
        String("policy does emit detect"),
        rendered.find("detect") >= 0,
        String("expected a detect branch"),
    )

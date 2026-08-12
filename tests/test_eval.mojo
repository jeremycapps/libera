"""Tests for `Evaluate(expr, props) -> Value`.

Organised by the expression forms table in doc 2.2: literal, ref, record/list,
arithmetic, comparison, logic, conditional, merge/reduce, and the lambda-like
declaration. Plus the cross-cutting properties the kernel promises: strict
error propagation, laziness where declared, and totality.
"""

from std.collections import List, Dict

from kernel.value import (
    Value,
    E_TYPE,
    E_ARITY,
    E_UNKNOWN_OP,
    E_KEY,
    E_INDEX,
    E_NOT_CALLABLE,
    E_UNRESOLVED_REF,
)
from kernel.eval import evaluate
from kernel.ir import (
    kv,
    rec,
    lst,
    r,
    ex,
    exn,
    sym,
    record_of,
    list_of,
    if_,
    if_only,
    lam,
    lam_returns,
    call,
)
from testkit.harness import TestSuite


fn _env() -> Value:
    return rec(
        kv(String("a"), Value.int(2)),
        kv(String("b"), Value.int(5)),
        kv(String("x"), Value.float(1.5)),
        kv(String("yes"), Value.bool(True)),
        kv(String("no"), Value.bool(False)),
        kv(String("word"), Value.string(String("hi"))),
        kv(String("state"), rec(kv(String("count"), Value.int(1)))),
    )


fn run(mut t: TestSuite):
    _literals(t)
    _construction(t)
    _arithmetic(t)
    _comparison(t)
    _logic(t)
    _conditional(t)
    _merge(t)
    _projection(t)
    _lambda(t)
    _errors(t)
    _composition(t)


fn _literals(mut t: TestSuite):
    t.section(String("eval / literals"))
    var p = _env()

    t.eq_value(String("int literal"), evaluate(Value.int(3), p), Value.int(3))
    t.eq_value(
        String("bool literal"), evaluate(Value.bool(True), p), Value.bool(True)
    )
    t.eq_value(
        String("string literal"),
        evaluate(Value.string(String("confirmed")), p),
        Value.string(String("confirmed")),
    )
    t.eq_value(
        String("symbol literal"),
        evaluate(sym(String("confirmed")), p),
        sym(String("confirmed")),
    )
    t.eq_value(String("null literal"), evaluate(Value.null(), p), Value.null())

    # A literal RECORD is inert: `evaluate` does not descend into it. Building
    # a record from expressions is the separate `record` form. Without this
    # split there would be no way to carry an expression as data.
    var inert = rec(kv(String("k"), r(String("a"))))
    var out = evaluate(inert, p)
    t.eq_value(String("literal record is inert"), out, inert)
    t.check(
        String("inert record keeps its ref unevaluated"),
        out.get(String("k")).tag == r(String("a")).tag,
        String("ref inside a literal record was evaluated"),
    )
    var inert_list = lst(r(String("a")))
    t.eq_value(String("literal list is inert"), evaluate(inert_list, p), inert_list)

    t.eq_value(String("ref evaluates"), evaluate(r(String("a")), p), Value.int(2))
    t.eq_value(
        String("nested ref evaluates"),
        evaluate(r(String("state.count")), p),
        Value.int(1),
    )


fn _construction(mut t: TestSuite):
    t.section(String("eval / record and list construction"))
    var p = _env()

    t.eq_value(
        String("record form evaluates its fields"),
        evaluate(
            record_of(
                kv(String("actual"), r(String("a"))),
                kv(String("expected"), r(String("b"))),
            ),
            p,
        ),
        rec(
            kv(String("actual"), Value.int(2)),
            kv(String("expected"), Value.int(5)),
        ),
    )
    t.eq_value(
        String("empty record form"), evaluate(record_of(), p), rec()
    )
    t.eq_value(
        String("list form evaluates its items"),
        evaluate(list_of(r(String("a")), Value.int(9)), p),
        lst(Value.int(2), Value.int(9)),
    )
    t.eq_value(String("empty list form"), evaluate(list_of(), p), lst())

    # Construction nests, and inner expressions are evaluated at every level.
    t.eq_value(
        String("nested construction"),
        evaluate(
            record_of(
                kv(
                    String("pair"),
                    list_of(r(String("a")), ex(String("add"), r(String("a")), Value.int(1))),
                )
            ),
            p,
        ),
        rec(kv(String("pair"), lst(Value.int(2), Value.int(3)))),
    )

    t.is_error(
        String("error inside record form propagates"),
        evaluate(record_of(kv(String("k"), r(String("missing")))), p),
        String(E_UNRESOLVED_REF),
    )
    t.is_error(
        String("error inside list form propagates"),
        evaluate(list_of(r(String("missing"))), p),
        String(E_UNRESOLVED_REF),
    )


fn _arithmetic(mut t: TestSuite):
    t.section(String("eval / arithmetic"))
    var p = _env()

    t.eq_value(
        String("add two ints"),
        evaluate(ex(String("add"), Value.int(1), Value.int(2)), p),
        Value.int(3),
    )
    t.eq_value(
        String("add over refs"),
        evaluate(ex(String("add"), r(String("a")), r(String("b"))), p),
        Value.int(7),
    )
    t.eq_value(
        String("add is variadic"),
        evaluate(
            ex(String("add"), Value.int(1), Value.int(2), Value.int(3)), p
        ),
        Value.int(6),
    )
    t.eq_value(
        String("add with one argument"),
        evaluate(ex(String("add"), Value.int(4)), p),
        Value.int(4),
    )

    # Int-ness is preserved so counting stays exact; any float widens the result.
    var int_sum = evaluate(ex(String("add"), Value.int(1), Value.int(2)), p)
    t.check(
        String("int + int stays an int"),
        int_sum.tag == Value.int(0).tag,
        String("expected an int tag, got ") + int_sum.to_string(),
    )
    var mixed = evaluate(ex(String("add"), Value.int(1), Value.float(0.5)), p)
    t.check(
        String("int + float widens to float"),
        mixed.tag == Value.float(0.0).tag,
        String("expected a float tag, got ") + mixed.to_string(),
    )
    t.eq_value(String("mixed addition value"), mixed, Value.float(1.5))

    t.eq_value(
        String("subtract ints"),
        evaluate(ex(String("subtract"), Value.int(5), Value.int(3)), p),
        Value.int(2),
    )
    t.eq_value(
        String("subtract to a negative"),
        evaluate(ex(String("subtract"), Value.int(3), Value.int(5)), p),
        Value.int(-2),
    )
    t.eq_value(
        String("subtract floats"),
        evaluate(ex(String("subtract"), Value.float(2.5), Value.int(1)), p),
        Value.float(1.5),
    )

    t.eq_value(
        String("abs of a negative int"),
        evaluate(ex(String("abs"), Value.int(-4)), p),
        Value.int(4),
    )
    t.eq_value(
        String("abs of a positive int"),
        evaluate(ex(String("abs"), Value.int(4)), p),
        Value.int(4),
    )
    t.eq_value(
        String("abs of a negative float"),
        evaluate(ex(String("abs"), Value.float(-2.5)), p),
        Value.float(2.5),
    )

    t.is_error(
        String("add rejects a string"),
        evaluate(ex(String("add"), Value.int(1), Value.string(String("x"))), p),
        String(E_TYPE),
    )
    t.is_error(
        String("add rejects null"),
        evaluate(ex(String("add"), Value.int(1), Value.null()), p),
        String(E_TYPE),
    )
    t.is_error(
        String("add with no arguments"),
        evaluate(ex(String("add")), p),
        String(E_ARITY),
    )
    t.is_error(
        String("subtract arity"),
        evaluate(ex(String("subtract"), Value.int(1)), p),
        String(E_ARITY),
    )
    t.is_error(
        String("abs arity"),
        evaluate(ex(String("abs"), Value.int(1), Value.int(2)), p),
        String(E_ARITY),
    )


fn _comparison(mut t: TestSuite):
    t.section(String("eval / comparison"))
    var p = _env()

    t.eq_value(
        String("eq true"),
        evaluate(ex(String("eq"), Value.int(3), Value.int(3)), p),
        Value.bool(True),
    )
    t.eq_value(
        String("eq false"),
        evaluate(ex(String("eq"), Value.int(3), Value.int(2)), p),
        Value.bool(False),
    )
    # eq is structural, so it works on any Value -- not just numbers.
    t.eq_value(
        String("eq on records"),
        evaluate(
            ex(
                String("eq"),
                rec(kv(String("k"), Value.int(1))),
                rec(kv(String("k"), Value.int(1))),
            ),
            p,
        ),
        Value.bool(True),
    )
    t.eq_value(
        String("eq on symbols"),
        evaluate(
            ex(String("eq"), sym(String("confirmed")), sym(String("confirmed"))),
            p,
        ),
        Value.bool(True),
    )
    t.eq_value(
        String("eq across int and float"),
        evaluate(ex(String("eq"), Value.int(3), Value.float(3.0)), p),
        Value.bool(True),
    )
    t.is_error(
        String("eq arity"),
        evaluate(ex(String("eq"), Value.int(1)), p),
        String(E_ARITY),
    )

    t.eq_value(
        String("lt true"),
        evaluate(ex(String("lt"), Value.int(1), Value.int(2)), p),
        Value.bool(True),
    )
    t.eq_value(
        String("lt false at equality"),
        evaluate(ex(String("lt"), Value.int(2), Value.int(2)), p),
        Value.bool(False),
    )
    t.eq_value(
        String("gt true"),
        evaluate(ex(String("gt"), Value.int(3), Value.int(2)), p),
        Value.bool(True),
    )
    t.eq_value(
        String("lte at equality"),
        evaluate(ex(String("lte"), Value.int(2), Value.int(2)), p),
        Value.bool(True),
    )
    t.eq_value(
        String("gte at equality"),
        evaluate(ex(String("gte"), Value.int(2), Value.int(2)), p),
        Value.bool(True),
    )
    t.eq_value(
        String("gte false"),
        evaluate(ex(String("gte"), Value.int(1), Value.int(2)), p),
        Value.bool(False),
    )
    t.eq_value(
        String("comparison across int and float"),
        evaluate(ex(String("lt"), Value.int(1), Value.float(1.5)), p),
        Value.bool(True),
    )

    # Ordered comparison is numeric only; structural equality is `eq`'s job.
    t.is_error(
        String("lt rejects strings"),
        evaluate(
            ex(String("lt"), Value.string(String("a")), Value.string(String("b"))),
            p,
        ),
        String(E_TYPE),
    )
    t.is_error(
        String("gt arity"),
        evaluate(ex(String("gt"), Value.int(1)), p),
        String(E_ARITY),
    )


fn _logic(mut t: TestSuite):
    t.section(String("eval / logic"))
    var p = _env()

    t.eq_value(
        String("and of two trues"),
        evaluate(ex(String("and"), Value.bool(True), Value.bool(True)), p),
        Value.bool(True),
    )
    t.eq_value(
        String("and with a false"),
        evaluate(ex(String("and"), Value.bool(True), Value.bool(False)), p),
        Value.bool(False),
    )
    t.eq_value(
        String("or with a true"),
        evaluate(ex(String("or"), Value.bool(False), Value.bool(True)), p),
        Value.bool(True),
    )
    t.eq_value(
        String("or of two falses"),
        evaluate(ex(String("or"), Value.bool(False), Value.bool(False)), p),
        Value.bool(False),
    )
    t.eq_value(
        String("not true"),
        evaluate(ex(String("not"), Value.bool(True)), p),
        Value.bool(False),
    )
    t.eq_value(
        String("not false"),
        evaluate(ex(String("not"), Value.bool(False)), p),
        Value.bool(True),
    )
    t.eq_value(
        String("and is variadic"),
        evaluate(
            ex(
                String("and"),
                Value.bool(True),
                Value.bool(True),
                Value.bool(True),
            ),
            p,
        ),
        Value.bool(True),
    )

    # Identity elements, so generated conjunctions/disjunctions degrade sanely.
    t.eq_value(
        String("empty and is true"),
        evaluate(ex(String("and")), p),
        Value.bool(True),
    )
    t.eq_value(
        String("empty or is false"),
        evaluate(ex(String("or")), p),
        Value.bool(False),
    )

    # Short-circuiting is observable: a later argument that would error is
    # never evaluated once the result is already decided.
    t.eq_value(
        String("and short-circuits past an error"),
        evaluate(ex(String("and"), Value.bool(False), r(String("missing"))), p),
        Value.bool(False),
    )
    t.eq_value(
        String("or short-circuits past an error"),
        evaluate(ex(String("or"), Value.bool(True), r(String("missing"))), p),
        Value.bool(True),
    )
    # But an error that IS reached still propagates.
    t.is_error(
        String("and propagates a reached error"),
        evaluate(ex(String("and"), Value.bool(True), r(String("missing"))), p),
        String(E_UNRESOLVED_REF),
    )

    t.is_error(
        String("and rejects a non-bool"),
        evaluate(ex(String("and"), Value.int(1)), p),
        String(E_TYPE),
    )
    t.is_error(
        String("not rejects a non-bool"),
        evaluate(ex(String("not"), Value.int(1)), p),
        String(E_TYPE),
    )
    t.is_error(
        String("not arity"),
        evaluate(ex(String("not"), Value.bool(True), Value.bool(True)), p),
        String(E_ARITY),
    )


fn _conditional(mut t: TestSuite):
    t.section(String("eval / conditional"))
    var p = _env()

    t.eq_value(
        String("if takes the then branch"),
        evaluate(
            if_(Value.bool(True), sym(String("confirmed")), sym(String("no"))),
            p,
        ),
        sym(String("confirmed")),
    )
    t.eq_value(
        String("if takes the else branch"),
        evaluate(
            if_(
                Value.bool(False),
                sym(String("confirmed")),
                sym(String("not_confirmed")),
            ),
            p,
        ),
        sym(String("not_confirmed")),
    )
    t.eq_value(
        String("if evaluates its condition"),
        evaluate(
            if_(
                ex(String("eq"), r(String("a")), Value.int(2)),
                sym(String("yes")),
                sym(String("no")),
            ),
            p,
        ),
        sym(String("yes")),
    )
    t.eq_value(
        String("if evaluates the taken branch"),
        evaluate(
            if_(Value.bool(True), ex(String("add"), r(String("a")), Value.int(1)), Value.int(0)),
            p,
        ),
        Value.int(3),
    )

    # Missing `else` yields null, which keeps orchestration expressions terse.
    t.eq_value(
        String("missing else yields null"),
        evaluate(if_only(Value.bool(False), Value.int(1)), p),
        Value.null(),
    )

    # Only the taken branch is evaluated -- an error in the other is not raised.
    t.eq_value(
        String("untaken then branch is not evaluated"),
        evaluate(if_(Value.bool(False), r(String("missing")), Value.int(9)), p),
        Value.int(9),
    )
    t.eq_value(
        String("untaken else branch is not evaluated"),
        evaluate(if_(Value.bool(True), Value.int(9), r(String("missing"))), p),
        Value.int(9),
    )

    # A non-boolean condition is an error, not a silent coercion.
    t.is_error(
        String("if rejects an int condition"),
        evaluate(if_(Value.int(1), Value.int(1), Value.int(2)), p),
        String(E_TYPE),
    )
    t.is_error(
        String("if rejects a null condition"),
        evaluate(if_(Value.null(), Value.int(1), Value.int(2)), p),
        String(E_TYPE),
    )
    t.is_error(
        String("error in the condition propagates"),
        evaluate(if_(r(String("missing")), Value.int(1), Value.int(2)), p),
        String(E_UNRESOLVED_REF),
    )
    t.is_error(
        String("if requires a condition"),
        evaluate(exn(String("if"), kv(String("then"), Value.int(1))), p),
        String(E_ARITY),
    )
    t.is_error(
        String("if requires a then"),
        evaluate(
            exn(String("if"), kv(String("condition"), Value.bool(True))), p
        ),
        String(E_ARITY),
    )


fn _merge(mut t: TestSuite):
    t.section(String("eval / merge"))
    var p = _env()

    t.eq_value(
        String("merge disjoint records"),
        evaluate(
            ex(
                String("merge"),
                rec(kv(String("a"), Value.int(1))),
                rec(kv(String("b"), Value.int(2))),
            ),
            p,
        ),
        rec(kv(String("a"), Value.int(1)), kv(String("b"), Value.int(2))),
    )
    t.eq_value(
        String("later argument wins"),
        evaluate(
            ex(
                String("merge"),
                rec(kv(String("a"), Value.int(1))),
                rec(kv(String("a"), Value.int(9))),
            ),
            p,
        ),
        rec(kv(String("a"), Value.int(9))),
    )
    t.eq_value(
        String("merge is variadic"),
        evaluate(
            ex(
                String("merge"),
                rec(kv(String("a"), Value.int(1))),
                rec(kv(String("b"), Value.int(2))),
                rec(kv(String("a"), Value.int(3))),
            ),
            p,
        ),
        rec(kv(String("a"), Value.int(3)), kv(String("b"), Value.int(2))),
    )
    t.eq_value(
        String("merge with an empty record"),
        evaluate(ex(String("merge"), rec(kv(String("a"), Value.int(1))), rec()), p),
        rec(kv(String("a"), Value.int(1))),
    )

    # Shallow by design: a nested record is replaced wholesale, not deep-merged.
    # Deep-merge semantics would be a policy decision, and policy belongs above
    # the kernel.
    t.eq_value(
        String("merge is shallow, not deep"),
        evaluate(
            ex(
                String("merge"),
                rec(
                    kv(
                        String("s"),
                        rec(
                            kv(String("keep"), Value.int(1)),
                            kv(String("over"), Value.int(1)),
                        ),
                    )
                ),
                rec(kv(String("s"), rec(kv(String("over"), Value.int(2))))),
            ),
            p,
        ),
        rec(kv(String("s"), rec(kv(String("over"), Value.int(2))))),
    )

    t.is_error(
        String("merge rejects a non-record"),
        evaluate(ex(String("merge"), rec(), Value.int(1)), p),
        String(E_TYPE),
    )
    t.is_error(
        String("merge with no arguments"),
        evaluate(ex(String("merge")), p),
        String(E_ARITY),
    )


fn _projection(mut t: TestSuite):
    t.section(String("eval / projection"))
    var p = _env()

    # `get` reaches into a value an expression just produced -- refs address
    # the environment, `get` addresses a result.
    t.eq_value(
        String("get a record field"),
        evaluate(
            ex(
                String("get"),
                record_of(kv(String("k"), r(String("a")))),
                Value.string(String("k")),
            ),
            p,
        ),
        Value.int(2),
    )
    t.eq_value(
        String("get accepts a symbol key"),
        evaluate(
            ex(String("get"), rec(kv(String("k"), Value.int(1))), sym(String("k"))),
            p,
        ),
        Value.int(1),
    )
    t.eq_value(
        String("get a list index"),
        evaluate(
            ex(String("get"), list_of(Value.int(7), Value.int(8)), Value.int(1)),
            p,
        ),
        Value.int(8),
    )

    t.is_error(
        String("get a missing field"),
        evaluate(ex(String("get"), rec(), Value.string(String("k"))), p),
        String(E_KEY),
    )
    t.is_error(
        String("get an out-of-range index"),
        evaluate(ex(String("get"), lst(Value.int(1)), Value.int(5)), p),
        String(E_INDEX),
    )
    t.is_error(
        String("get a record with a numeric key"),
        evaluate(ex(String("get"), rec(), Value.int(0)), p),
        String(E_TYPE),
    )
    t.is_error(
        String("get a list with a text key"),
        evaluate(ex(String("get"), lst(), Value.string(String("k"))), p),
        String(E_TYPE),
    )
    t.is_error(
        String("get on a scalar"),
        evaluate(ex(String("get"), Value.int(1), Value.string(String("k"))), p),
        String(E_TYPE),
    )
    t.is_error(
        String("get arity"),
        evaluate(ex(String("get"), rec()), p),
        String(E_ARITY),
    )


fn _lambda(mut t: TestSuite):
    t.section(String("eval / lambda and call"))
    var p = _env()

    var double = lam(
        rec(kv(String("n"), Value.int(0))),
        ex(String("add"), r(String("n")), r(String("n"))),
    )

    # A lambda is inert data until applied -- it survives evaluation unchanged,
    # which is what lets it be stored and passed around as a Value.
    t.eq_value(String("lambda evaluates to itself"), evaluate(double, p), double)

    t.eq_value(
        String("call binds a named argument"),
        evaluate(call(double, kv(String("n"), Value.int(4))), p),
        Value.int(8),
    )
    t.eq_value(
        String("call uses the declared default"),
        evaluate(call(double), p),
        Value.int(0),
    )
    # Arguments are evaluated in the CALLER's environment.
    t.eq_value(
        String("argument evaluates in the caller scope"),
        evaluate(call(double, kv(String("n"), r(String("b")))), p),
        Value.int(10),
    )

    # v0 lambdas are not closures: the body sees only its own props, so a name
    # that exists in the caller's environment is not visible inside.
    t.is_error(
        String("lambda body cannot see the caller scope"),
        evaluate(
            call(lam(rec(), r(String("a")))),
            p,
        ),
        String(E_UNRESOLVED_REF),
    )

    # `returns` projects out of the body result, with `body` bound to it.
    var verdict_like = lam_returns(
        rec(kv(String("n"), Value.int(0))),
        record_of(
            kv(String("doubled"), ex(String("add"), r(String("n")), r(String("n")))),
            kv(String("original"), r(String("n"))),
        ),
        r(String("body.doubled")),
    )
    t.eq_value(
        String("returns projects from the body"),
        evaluate(call(verdict_like, kv(String("n"), Value.int(3))), p),
        Value.int(6),
    )
    # `returns` can also still see the parameters.
    var echo = lam_returns(
        rec(kv(String("n"), Value.int(0))),
        Value.int(0),
        r(String("n")),
    )
    t.eq_value(
        String("returns can see the parameters"),
        evaluate(call(echo, kv(String("n"), Value.int(42))), p),
        Value.int(42),
    )

    t.is_error(
        String("calling a non-lambda"),
        evaluate(call(Value.int(1)), p),
        String(E_NOT_CALLABLE),
    )
    t.is_error(
        String("calling a plain expression"),
        evaluate(call(ex(String("add"), Value.int(1), Value.int(1))), p),
        String(E_NOT_CALLABLE),
    )
    t.is_error(
        String("call with no callee"),
        evaluate(ex(String("call")), p),
        String(E_ARITY),
    )
    t.is_error(
        String("lambda without a body"),
        evaluate(call(exn(String("lambda"), kv(String("props"), rec()))), p),
        String(E_ARITY),
    )
    t.is_error(
        String("error in an argument propagates"),
        evaluate(call(double, kv(String("n"), r(String("missing")))), p),
        String(E_UNRESOLVED_REF),
    )


fn _errors(mut t: TestSuite):
    t.section(String("eval / errors are Values"))
    var p = _env()

    t.is_error(
        String("unknown operator"),
        evaluate(ex(String("frobnicate"), Value.int(1)), p),
        String(E_UNKNOWN_OP),
    )

    # Strict propagation: an error surfaces from arbitrary depth, unchanged.
    var deep = ex(
        String("add"),
        Value.int(1),
        ex(
            String("add"),
            Value.int(1),
            ex(String("abs"), r(String("missing"))),
        ),
    )
    t.is_error(
        String("error propagates from depth"),
        evaluate(deep, p),
        String(E_UNRESOLVED_REF),
    )

    # The original code survives propagation rather than being reclassified.
    var typed = ex(
        String("add"), Value.int(1), ex(String("not"), Value.int(1))
    )
    t.is_error(
        String("inner type_error is not reclassified"),
        evaluate(typed, p),
        String(E_TYPE),
    )

    # An error Value handed in as a literal is inert data, not a trigger --
    # only operators propagate it.
    var literal_error = Value.error(String("type_error"), String("carried"))
    t.eq_value(
        String("literal error evaluates to itself"),
        evaluate(literal_error, p),
        literal_error,
    )

    # Totality: none of these raise, they all return a Value.
    t.not_error(
        String("well-formed expression yields no error"),
        evaluate(ex(String("eq"), Value.int(1), Value.int(1)), p),
    )


fn _composition(mut t: TestSuite):
    t.section(String("eval / composition"))
    var p = _env()

    # A realistic multi-form expression: comparison inside a conditional inside
    # a constructed record, over refs. This is the shape Domain will compile to,
    # built here purely from kernel forms.
    var e = record_of(
        kv(String("sum"), ex(String("add"), r(String("a")), r(String("b")))),
        kv(
            String("verdict"),
            if_(
                ex(
                    String("and"),
                    ex(String("gt"), r(String("b")), r(String("a"))),
                    ex(String("eq"), r(String("a")), Value.int(2)),
                ),
                sym(String("confirmed")),
                sym(String("not_confirmed")),
            ),
        ),
        kv(
            String("distance"),
            ex(String("abs"), ex(String("subtract"), r(String("a")), r(String("b")))),
        ),
    )
    t.eq_value(
        String("composed expression"),
        evaluate(e, p),
        rec(
            kv(String("sum"), Value.int(7)),
            kv(String("verdict"), sym(String("confirmed"))),
            kv(String("distance"), Value.int(3)),
        ),
    )

    # Evaluation is deterministic: same expression, same props, same result.
    t.eq_value(String("evaluation is deterministic"), evaluate(e, p), evaluate(e, p))

    # Props are not mutated by evaluation.
    var before = p.to_string()
    var _ = evaluate(e, p)
    t.eq_str(String("props are unchanged by evaluation"), p.to_string(), before)

    # The same expression against a different environment gives a different
    # answer -- expressions carry no state of their own.
    var p2 = rec(
        kv(String("a"), Value.int(5)),
        kv(String("b"), Value.int(1)),
    )
    t.eq_value(
        String("same expression, different props"),
        evaluate(e, p2),
        rec(
            kv(String("sum"), Value.int(6)),
            kv(String("verdict"), sym(String("not_confirmed"))),
            kv(String("distance"), Value.int(4)),
        ),
    )

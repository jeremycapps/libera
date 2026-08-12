"""Tests for the Value layer: construction, equality, refs, rendering.

These exercise the substrate the evaluator sits on, independently of
`evaluate`. Nothing here should mention a Domain or Strategy concept -- if a
test needs one, the kernel has grown something it should not know.
"""

from std.collections import List, Dict

from kernel.value import (
    Value,
    tag_name,
    NULL,
    BOOL,
    INT,
    FLOAT,
    STRING,
    SYMBOL,
    LIST,
    RECORD,
    REF,
    EXPR,
    ERROR,
    E_TYPE,
    E_KEY,
    E_INDEX,
)
from kernel.ir import kv, rec, lst, r, ex, sym
from testkit.harness import TestSuite


fn run(mut t: TestSuite):
    _tags(t)
    _scalars(t)
    _numeric_equality(t)
    _structural_equality(t)
    _refs(t)
    _access(t)
    _rendering(t)
    _sharing(t)


fn _tags(mut t: TestSuite):
    t.section(String("value / tags"))
    t.eq_str(String("null tag name"), tag_name(NULL), String("null"))
    t.eq_str(String("record tag name"), tag_name(RECORD), String("record"))
    t.eq_str(
        String("expression tag name"), tag_name(EXPR), String("expression")
    )
    t.eq_str(String("unknown tag name"), tag_name(99), String("unknown"))
    # Comparing the comptime constants directly would be folded away by the
    # compiler, so collect them at runtime and check pairwise distinctness --
    # a duplicated tag would silently make two value forms interchangeable.
    var tags = List[Int]()
    tags.append(NULL)
    tags.append(BOOL)
    tags.append(INT)
    tags.append(FLOAT)
    tags.append(STRING)
    tags.append(SYMBOL)
    tags.append(LIST)
    tags.append(RECORD)
    tags.append(REF)
    tags.append(EXPR)
    tags.append(ERROR)

    var collision = String("")
    for a in range(len(tags)):
        for b in range(a + 1, len(tags)):
            if tags[a] == tags[b]:
                collision = (
                    tag_name(tags[a]) + String(" / ") + tag_name(tags[b])
                )
    t.eq_str(String("tags are pairwise distinct"), collision, String(""))
    t.eq_int(String("all eleven value forms present"), len(tags), 11)


fn _scalars(mut t: TestSuite):
    t.section(String("value / scalars"))

    t.check(
        String("null is null"), Value.null().is_null(), String("expected null")
    )
    t.check(
        String("bool tag"),
        Value.bool(True).tag == BOOL,
        String("wrong tag for bool"),
    )
    t.eq_int(String("int payload"), Value.int(7).i, 7)
    t.check(
        String("float payload"),
        Value.float(2.5).f == 2.5,
        String("wrong float payload"),
    )
    t.eq_str(
        String("string payload"),
        Value.string(String("hi")).s,
        String("hi"),
    )
    t.eq_str(
        String("symbol payload"),
        Value.symbol(String("confirmed")).s,
        String("confirmed"),
    )

    t.check(
        String("int is number"),
        Value.int(1).is_number(),
        String("int should be numeric"),
    )
    t.check(
        String("float is number"),
        Value.float(1.0).is_number(),
        String("float should be numeric"),
    )
    t.check(
        String("string is not number"),
        not Value.string(String("1")).is_number(),
        String("string must not be numeric"),
    )
    t.check(
        String("string is text"),
        Value.string(String("a")).is_text(),
        String("string should be text"),
    )
    t.check(
        String("symbol is text"),
        Value.symbol(String("a")).is_text(),
        String("symbol should be text"),
    )

    # Numeric widening is a read, not a coercion of the stored tag.
    t.check(
        String("int widens to float"),
        Value.int(3).as_float() == 3.0,
        String("as_float on int failed"),
    )

    # Truthiness is strict: only the boolean `true` is true. This is what
    # turns a malformed condition into a type error rather than a silent branch.
    t.check(
        String("true is truthy"),
        Value.bool(True).truthy(),
        String("true must be truthy"),
    )
    t.check(
        String("false is not truthy"),
        not Value.bool(False).truthy(),
        String("false must not be truthy"),
    )
    t.check(
        String("nonzero int is not truthy"),
        not Value.int(1).truthy(),
        String("kernel must not coerce ints to bool"),
    )
    t.check(
        String("nonempty string is not truthy"),
        not Value.string(String("yes")).truthy(),
        String("kernel must not coerce strings to bool"),
    )
    t.check(
        String("null is not truthy"),
        not Value.null().truthy(),
        String("null must not be truthy"),
    )


fn _numeric_equality(mut t: TestSuite):
    t.section(String("value / numeric equality"))

    t.eq_value(String("int equals int"), Value.int(3), Value.int(3))
    t.ne_value(String("int differs from int"), Value.int(3), Value.int(2))
    # Counts may arrive as either tag; the doc's arithmetic treats them alike.
    t.eq_value(
        String("int equals float across tags"), Value.int(3), Value.float(3.0)
    )
    t.eq_value(
        String("float equals int across tags"), Value.float(3.0), Value.int(3)
    )
    t.ne_value(
        String("int differs from float"), Value.int(3), Value.float(3.5)
    )

    # Text kinds are deliberately NOT cross-comparable: the string "confirmed"
    # and the symbol `confirmed` mean different things upstream.
    t.ne_value(
        String("string does not equal symbol"),
        Value.string(String("confirmed")),
        Value.symbol(String("confirmed")),
    )
    t.eq_value(
        String("symbol equals symbol"),
        Value.symbol(String("confirmed")),
        Value.symbol(String("confirmed")),
    )

    t.eq_value(String("null equals null"), Value.null(), Value.null())
    t.ne_value(String("null differs from false"), Value.null(), Value.bool(False))
    t.ne_value(String("null differs from int 0"), Value.null(), Value.int(0))
    t.eq_value(String("bool equality"), Value.bool(True), Value.bool(True))
    t.ne_value(String("bool inequality"), Value.bool(True), Value.bool(False))


fn _structural_equality(mut t: TestSuite):
    t.section(String("value / structural equality"))

    t.eq_value(
        String("equal lists"),
        lst(Value.int(1), Value.int(2)),
        lst(Value.int(1), Value.int(2)),
    )
    t.ne_value(
        String("lists differ by order"),
        lst(Value.int(1), Value.int(2)),
        lst(Value.int(2), Value.int(1)),
    )
    t.ne_value(
        String("lists differ by length"),
        lst(Value.int(1)),
        lst(Value.int(1), Value.int(2)),
    )
    t.eq_value(String("empty lists equal"), lst(), lst())

    t.eq_value(
        String("equal records"),
        rec(kv(String("a"), Value.int(1)), kv(String("b"), Value.int(2))),
        rec(kv(String("a"), Value.int(1)), kv(String("b"), Value.int(2))),
    )
    # Records are unordered: insertion order must not affect equality.
    t.eq_value(
        String("record equality ignores insertion order"),
        rec(kv(String("a"), Value.int(1)), kv(String("b"), Value.int(2))),
        rec(kv(String("b"), Value.int(2)), kv(String("a"), Value.int(1))),
    )
    t.ne_value(
        String("records differ by value"),
        rec(kv(String("a"), Value.int(1))),
        rec(kv(String("a"), Value.int(2))),
    )
    t.ne_value(
        String("records differ by key"),
        rec(kv(String("a"), Value.int(1))),
        rec(kv(String("z"), Value.int(1))),
    )
    t.ne_value(
        String("records differ by size"),
        rec(kv(String("a"), Value.int(1))),
        rec(kv(String("a"), Value.int(1)), kv(String("b"), Value.int(2))),
    )

    # Nesting to depth, mixing both container kinds.
    var deep_a = rec(
        kv(
            String("outer"),
            lst(rec(kv(String("inner"), lst(Value.int(1), Value.int(2))))),
        )
    )
    var deep_b = rec(
        kv(
            String("outer"),
            lst(rec(kv(String("inner"), lst(Value.int(1), Value.int(2))))),
        )
    )
    var deep_c = rec(
        kv(
            String("outer"),
            lst(rec(kv(String("inner"), lst(Value.int(1), Value.int(9))))),
        )
    )
    t.eq_value(String("deep nested equality"), deep_a, deep_b)
    t.ne_value(String("deep nested inequality"), deep_a, deep_c)

    t.ne_value(
        String("list does not equal record"),
        lst(Value.int(1)),
        rec(kv(String("0"), Value.int(1))),
    )

    # Expressions are Values, so equality must cover them too.
    t.eq_value(
        String("equal expressions"),
        ex(String("eq"), r(String("a")), r(String("b"))),
        ex(String("eq"), r(String("a")), r(String("b"))),
    )
    t.ne_value(
        String("expressions differ by op"),
        ex(String("eq"), r(String("a")), r(String("b"))),
        ex(String("lt"), r(String("a")), r(String("b"))),
    )
    t.ne_value(
        String("expressions differ by argument"),
        ex(String("eq"), r(String("a")), r(String("b"))),
        ex(String("eq"), r(String("a")), r(String("z"))),
    )
    t.ne_value(
        String("ref does not equal string of same text"),
        r(String("a.b")),
        Value.string(String("a.b")),
    )


fn _refs(mut t: TestSuite):
    t.section(String("value / ref parsing"))

    var local = Value.ref(String("state.current.count"))
    t.eq_int(String("local path segment count"), local.len(), 3)
    t.eq_str(String("local segment 0"), local.at(0).s, String("state"))
    t.eq_str(String("local segment 2"), local.at(2).s, String("count"))
    t.check(
        String("ref keeps source text"),
        local.s == String("state.current.count"),
        String("ref source text lost"),
    )

    var single = Value.ref(String("count"))
    t.eq_int(String("single segment ref"), single.len(), 1)

    # A qualifier such as `@domain/bootstrap` contains no dot, so splitting on
    # "." separates it cleanly from the path that follows.
    var qualified = Value.ref(String("@domain/bootstrap.contract.expected"))
    t.eq_int(String("qualified segment count"), qualified.len(), 3)
    t.eq_str(
        String("qualified keeps @ on qualifier"),
        qualified.at(0).s,
        String("@domain/bootstrap"),
    )
    t.eq_str(
        String("qualified path segment"),
        qualified.at(1).s,
        String("contract"),
    )

    var empty = Value.ref(String(""))
    t.eq_int(String("empty ref has no segments"), empty.len(), 0)

    # Repeated/trailing dots produce no empty segments.
    var messy = Value.ref(String("a..b."))
    t.eq_int(String("empty segments dropped"), messy.len(), 2)
    t.eq_str(String("messy segment 1"), messy.at(1).s, String("b"))


fn _access(mut t: TestSuite):
    t.section(String("value / access returns errors, never traps"))

    var xs = lst(Value.int(10), Value.int(20))
    t.eq_value(String("list index 0"), xs.at(0), Value.int(10))
    t.eq_value(String("list index 1"), xs.at(1), Value.int(20))
    t.is_error(
        String("list index out of range"), xs.at(2), String(E_INDEX)
    )
    t.is_error(
        String("negative list index"), xs.at(-1), String(E_INDEX)
    )

    var record = rec(kv(String("a"), Value.int(1)))
    t.eq_value(String("record field"), record.get(String("a")), Value.int(1))
    t.check(
        String("record has present key"),
        record.has(String("a")),
        String("has() missed a present key"),
    )
    t.check(
        String("record lacks absent key"),
        not record.has(String("zz")),
        String("has() found an absent key"),
    )
    t.is_error(
        String("missing field is key_error"),
        record.get(String("zz")),
        String(E_KEY),
    )
    t.is_error(
        String("field access on scalar is type_error"),
        Value.int(1).get(String("a")),
        String(E_TYPE),
    )
    t.eq_value(
        String("get_or falls back"),
        record.get_or(String("zz"), Value.int(99)),
        Value.int(99),
    )
    t.eq_value(
        String("get_or prefers present value"),
        record.get_or(String("a"), Value.int(99)),
        Value.int(1),
    )

    t.eq_int(String("len of list"), xs.len(), 2)
    t.eq_int(String("len of record"), record.len(), 1)
    t.eq_int(String("len of scalar"), Value.int(1).len(), 0)


fn _rendering(mut t: TestSuite):
    t.section(String("value / rendering"))

    t.eq_str(String("null renders"), Value.null().to_string(), String("null"))
    t.eq_str(
        String("true renders"), Value.bool(True).to_string(), String("true")
    )
    t.eq_str(
        String("false renders"), Value.bool(False).to_string(), String("false")
    )
    t.eq_str(String("int renders"), Value.int(-4).to_string(), String("-4"))
    t.eq_str(
        String("string renders quoted"),
        Value.string(String("hi")).to_string(),
        String('"hi"'),
    )
    t.eq_str(
        String("symbol renders bare"),
        Value.symbol(String("confirmed")).to_string(),
        String("confirmed"),
    )
    t.eq_str(
        String("ref renders"),
        r(String("a.b")).to_string(),
        String("ref(a.b)"),
    )
    t.eq_str(
        String("list renders"),
        lst(Value.int(1), Value.int(2)).to_string(),
        String("[1, 2]"),
    )

    # Field order is sorted, so rendered output is stable regardless of the
    # Dict's internal iteration order -- which is what makes it test-safe.
    t.eq_str(
        String("record renders with sorted keys"),
        rec(
            kv(String("z"), Value.int(1)), kv(String("a"), Value.int(2))
        ).to_string(),
        String("{a: 2, z: 1}"),
    )
    t.eq_str(
        String("record rendering is order-independent"),
        rec(
            kv(String("a"), Value.int(2)), kv(String("z"), Value.int(1))
        ).to_string(),
        String("{a: 2, z: 1}"),
    )
    t.eq_str(
        String("expression renders"),
        ex(String("eq"), r(String("a")), Value.int(3)).to_string(),
        String("(eq ref(a) 3)"),
    )
    t.eq_str(
        String("error renders with code and message"),
        Value.error(String("type_error"), String("boom")).to_string(),
        String("error(type_error: boom)"),
    )
    t.eq_str(
        String("nested rendering"),
        rec(kv(String("k"), lst(rec(kv(String("n"), Value.int(1)))))).to_string(),
        String("{k: [{n: 1}]}"),
    )


fn _sharing(mut t: TestSuite):
    t.section(String("value / copy semantics"))

    # Values are immutable and share their children via ArcPointer, so copying
    # must be observationally identical to the original at any depth.
    var original = rec(
        kv(String("outer"), lst(Value.int(1), rec(kv(String("n"), Value.int(2)))))
    )
    var copied = original
    t.eq_value(String("copy equals original"), copied, original)
    t.eq_str(
        String("copy renders identically"),
        copied.to_string(),
        original.to_string(),
    )
    t.eq_value(
        String("copy preserves depth"),
        copied.get(String("outer")).at(1).get(String("n")),
        Value.int(2),
    )

    # Values survive being stored and re-read through a container.
    var box = List[Value]()
    box.append(original)
    t.eq_value(String("round-trip through list"), box[0], original)

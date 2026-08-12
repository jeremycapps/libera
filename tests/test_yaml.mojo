"""Tests for the YAML subset reader.

The reader's contract is narrow: produce a plain data tree and interpret
nothing. So these tests check syntax and scalar typing only -- no operator
anywhere. Operators are `test_compile.mojo`'s business.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, LIST, INT, FLOAT, STRING, SYMBOL, BOOL
from kernel.ir import kv, rec, lst
from modelir.yaml import parse_yaml
from testkit.harness import TestSuite


fn run(mut t: TestSuite):
    _scalars(t)
    _block_maps(t)
    _sequences(t)
    _flow(t)
    _comments(t)
    _errors(t)


fn _scalars(mut t: TestSuite):
    t.section(String("yaml / scalar typing"))

    var src = String(
        """
i: 3
neg: -4
f: 0.1
t: true
fa: false
n: null
tilde: ~
q: "hello"
sq: 'world'
bare: confirmed
dotted: a.b.c
version: 0.1
"""
    )
    var doc = parse_yaml(src)
    t.not_error(String("document parses"), doc)

    t.eq_value(String("integer"), doc.get(String("i")), Value.int(3))
    t.eq_value(String("negative integer"), doc.get(String("neg")), Value.int(-4))
    t.eq_value(String("float"), doc.get(String("f")), Value.float(0.1))
    t.eq_value(String("true"), doc.get(String("t")), Value.bool(True))
    t.eq_value(String("false"), doc.get(String("fa")), Value.bool(False))
    t.eq_value(String("null"), doc.get(String("n")), Value.null())
    t.eq_value(String("tilde is null"), doc.get(String("tilde")), Value.null())

    # Quoted text is a String; bare text is a Symbol. That distinction is what
    # makes the doc's `then: confirmed` a symbol, comparable to a verdict
    # finding rather than to arbitrary text.
    t.eq_value(
        String("double-quoted is a string"),
        doc.get(String("q")),
        Value.string(String("hello")),
    )
    t.eq_value(
        String("single-quoted is a string"),
        doc.get(String("sq")),
        Value.string(String("world")),
    )
    t.eq_value(
        String("bare word is a symbol"),
        doc.get(String("bare")),
        Value.symbol(String("confirmed")),
    )
    t.check(
        String("bare word is not a string"),
        doc.get(String("bare")).tag == SYMBOL,
        String("expected SYMBOL, got ") + doc.get(String("bare")).to_string(),
    )
    t.eq_value(
        String("dotted path stays a symbol"),
        doc.get(String("dotted")),
        Value.symbol(String("a.b.c")),
    )
    t.check(
        String("version 0.1 is a float"),
        doc.get(String("version")).tag == FLOAT,
        String("got ") + doc.get(String("version")).to_string(),
    )


fn _block_maps(mut t: TestSuite):
    t.section(String("yaml / block mappings"))

    var doc = parse_yaml(
        String(
            """
contract:
  expected:
    count: 3
  other: 1
top: 9
"""
        )
    )
    t.not_error(String("nested map parses"), doc)
    t.eq_value(
        String("nested three deep"),
        doc.get(String("contract")).get(String("expected")).get(String("count")),
        Value.int(3),
    )
    t.eq_value(
        String("sibling at depth"),
        doc.get(String("contract")).get(String("other")),
        Value.int(1),
    )
    t.eq_value(
        String("dedent back to top level"),
        doc.get(String("top")),
        Value.int(9),
    )

    # A key with an empty value and nothing indented under it is null.
    var empty = parse_yaml(String("a:\nb: 1\n"))
    t.eq_value(
        String("empty value is null"), empty.get(String("a")), Value.null()
    )
    t.eq_value(String("following key survives"), empty.get(String("b")), Value.int(1))

    # A colon inside a value must not be mistaken for the key separator.
    var colon = parse_yaml(String('a: "x: y"\nb: 12:30\n'))
    t.eq_value(
        String("colon inside quotes"),
        colon.get(String("a")),
        Value.string(String("x: y")),
    )
    t.eq_value(
        String("colon without space is not a separator"),
        colon.get(String("b")),
        Value.symbol(String("12:30")),
    )

    t.eq_value(String("empty document is null"), parse_yaml(String("")), Value.null())
    t.eq_value(
        String("comments-only document is null"),
        parse_yaml(String("# just a comment\n")),
        Value.null(),
    )

    # CRLF line endings must not leak a stray \r into the last scalar.
    var crlf = parse_yaml(String("a: 1\r\nb: two\r\n"))
    t.eq_value(String("CRLF integer"), crlf.get(String("a")), Value.int(1))
    t.eq_value(
        String("CRLF symbol"),
        crlf.get(String("b")),
        Value.symbol(String("two")),
    )


fn _sequences(mut t: TestSuite):
    t.section(String("yaml / block sequences"))

    var doc = parse_yaml(
        String(
            """
plain:
  - 1
  - 2
maps:
  - ref: actual.count
  - ref: expected.count
"""
        )
    )
    t.not_error(String("sequences parse"), doc)
    t.eq_value(
        String("scalar sequence"),
        doc.get(String("plain")),
        lst(Value.int(1), Value.int(2)),
    )
    t.check(
        String("sequence is a list"),
        doc.get(String("plain")).tag == LIST,
        String("expected LIST"),
    )

    # `- ref: x` -- a mapping that begins on the dash line. This is the shape
    # the architecture doc uses for every operator's arguments.
    var maps = doc.get(String("maps"))
    t.eq_int(String("two mapping items"), maps.len(), 2)
    t.eq_value(
        String("first item mapping"),
        maps.at(0),
        rec(kv(String("ref"), Value.symbol(String("actual.count")))),
    )
    t.eq_value(
        String("second item mapping"),
        maps.at(1),
        rec(kv(String("ref"), Value.symbol(String("expected.count")))),
    )

    # A multi-key mapping item continues on lines aligned under the dash.
    var multi = parse_yaml(
        String(
            """
items:
  - name: a
    value: 1
  - name: b
    value: 2
"""
        )
    )
    t.eq_int(String("two multi-key items"), multi.get(String("items")).len(), 2)
    t.eq_value(
        String("multi-key item field"),
        multi.get(String("items")).at(1).get(String("value")),
        Value.int(2),
    )

    # Nesting: a sequence inside a mapping inside a sequence item.
    var nested = parse_yaml(
        String(
            """
outer:
  - inner:
      - 1
      - 2
"""
        )
    )
    t.eq_value(
        String("sequence nested in sequence item"),
        nested.get(String("outer")).at(0).get(String("inner")),
        lst(Value.int(1), Value.int(2)),
    )

    var top_seq = parse_yaml(String("- 1\n- 2\n"))
    t.eq_value(
        String("top-level sequence"), top_seq, lst(Value.int(1), Value.int(2))
    )


fn _flow(mut t: TestSuite):
    t.section(String("yaml / flow collections"))

    var doc = parse_yaml(
        String(
            """
m: {a: 1, b: 2}
s: [1, 2, 3]
nested: {k: [1, {z: 2}]}
empty_m: {}
empty_s: []
spaced: { a : 1 }
quoted: {k: "a, b"}
"""
        )
    )
    t.not_error(String("flow collections parse"), doc)

    t.eq_value(
        String("flow mapping"),
        doc.get(String("m")),
        rec(kv(String("a"), Value.int(1)), kv(String("b"), Value.int(2))),
    )
    t.eq_value(
        String("flow sequence"),
        doc.get(String("s")),
        lst(Value.int(1), Value.int(2), Value.int(3)),
    )
    t.eq_value(
        String("nested flow"),
        doc.get(String("nested")),
        rec(
            kv(
                String("k"),
                lst(Value.int(1), rec(kv(String("z"), Value.int(2)))),
            )
        ),
    )
    t.eq_value(String("empty flow mapping"), doc.get(String("empty_m")), rec())
    t.eq_value(String("empty flow sequence"), doc.get(String("empty_s")), lst())
    t.eq_value(
        String("whitespace inside flow"),
        doc.get(String("spaced")),
        rec(kv(String("a"), Value.int(1))),
    )
    # A comma inside quotes must not split the entry.
    t.eq_value(
        String("comma inside a quoted flow value"),
        doc.get(String("quoted")),
        rec(kv(String("k"), Value.string(String("a, b")))),
    )


fn _comments(mut t: TestSuite):
    t.section(String("yaml / comments"))

    var doc = parse_yaml(
        String(
            """
# leading comment
a: 1  # trailing comment
# full line
b: 2
c: "has # inside"
d: a#b
"""
        )
    )
    t.not_error(String("comments parse"), doc)
    t.eq_value(String("value before trailing comment"), doc.get(String("a")), Value.int(1))
    t.eq_value(String("value after full-line comment"), doc.get(String("b")), Value.int(2))
    # `#` only opens a comment at line start or after whitespace.
    t.eq_value(
        String("hash inside quotes is literal"),
        doc.get(String("c")),
        Value.string(String("has # inside")),
    )
    t.eq_value(
        String("hash without preceding space is literal"),
        doc.get(String("d")),
        Value.symbol(String("a#b")),
    )


fn _errors(mut t: TestSuite):
    t.section(String("yaml / errors are Values with line numbers"))

    var dup = parse_yaml(String("a: 1\na: 2\n"))
    t.is_error(String("duplicate key"), dup, String("parse_error"))
    t.eq_value(
        String("error carries its line number"),
        dup.get(String("line")),
        Value.int(2),
    )

    t.is_error(
        String("tab in indentation"),
        parse_yaml(String("a:\n\tb: 1\n")),
        String("parse_error"),
    )
    t.is_error(
        String("unterminated flow mapping"),
        parse_yaml(String("a: {b: 1\n")),
        String("parse_error"),
    )
    t.is_error(
        String("unterminated flow sequence"),
        parse_yaml(String("a: [1, 2\n")),
        String("parse_error"),
    )
    t.is_error(
        String("trailing text after a flow collection"),
        parse_yaml(String("a: {b: 1} junk\n")),
        String("parse_error"),
    )
    t.is_error(
        String("anchors are rejected, not ignored"),
        parse_yaml(String("a: &anchor 1\n")),
        String("parse_error"),
    )
    t.is_error(
        String("block scalars are rejected, not ignored"),
        parse_yaml(String("a: |\n  text\n")),
        String("parse_error"),
    )
    t.is_error(
        String("duplicate key in a flow mapping"),
        parse_yaml(String("a: {b: 1, b: 2}\n")),
        String("parse_error"),
    )

    # A parse error from deep inside a document propagates out rather than
    # yielding a partial tree.
    var deep = parse_yaml(
        String(
            """
outer:
  inner:
    - ok: 1
    - bad: {unterminated: 1
"""
        )
    )
    t.is_error(String("error from depth propagates"), deep, String("parse_error"))

"""Compile a parsed YAML tree into the normalized Model IR.

Doc 7 is explicit that YAML quirks must not define runtime semantics: the
runtime parses YAML into a normalized Model IR, and the kernel evaluates *that*.
This module is that normalization step, and it is the only place that knows the
YAML spelling of an operator.

The authoring convention
------------------------
An expression is written as a single-key mapping whose key names an operator,
exactly as in the architecture doc:

    eq:
      - ref: actual.count
      - ref: expected.count

Anything else is data. A mapping with several keys, or with one key that is not
an operator, compiles to a literal record -- so `contract.expected.count` stays
plain data while `conforms:` becomes an expression.

That rule has one sharp edge: a data record whose only key happens to be named
after an operator would be read as an expression. `literal:` is the escape
hatch, and it is why the escape hatch exists.

Recall the kernel distinction this rests on: a literal RECORD is inert under
evaluation, while the `record` form builds a record by evaluating its fields.
Data and construction are different things, and the YAML says which is meant.
"""

from std.collections import List, Dict

from kernel.value import (
    Value,
    RECORD,
    LIST,
    STRING,
    SYMBOL,
    E_TYPE,
)


comptime E_COMPILE = "compile_error"


fn _fail(var message: String) -> Value:
    return Value.error(String(E_COMPILE), message^)


# --- Operator tables -------------------------------------------------------
# Kept as functions rather than sets so the kernel's operator vocabulary and
# its YAML spelling stay visibly in one place.


fn _is_positional_op(k: String) -> Bool:
    """Operators whose YAML value is a sequence of arguments (or a single
    argument, as a convenience for the unary ones)."""
    return (
        k == "add"
        or k == "subtract"
        or k == "abs"
        or k == "eq"
        or k == "lt"
        or k == "gt"
        or k == "lte"
        or k == "gte"
        or k == "and"
        or k == "or"
        or k == "not"
        or k == "merge"
        or k == "get"
    )


fn _is_named_op(k: String) -> Bool:
    """Operators whose YAML value is a mapping of named arguments."""
    return k == "if" or k == "lambda"


fn is_operator(k: String) -> Bool:
    return (
        _is_positional_op(k)
        or _is_named_op(k)
        or k == "ref"
        or k == "record"
        or k == "list"
        or k == "call"
        or k == "literal"
    )


# --- Compilation -----------------------------------------------------------


fn compile_expression(node: Value) -> Value:
    """Normalize one YAML node into Model IR."""
    if node.is_error():
        return node.copy()

    if node.tag == RECORD:
        if node.len() == 1:
            var key = _sole_key(node)
            if is_operator(key):
                return _compile_op(key, node.get(key))
        return _compile_literal_record(node)

    if node.tag == LIST:
        var items = List[Value]()
        for k in range(node.len()):
            var got = compile_expression(node.at(k))
            if got.is_error():
                return got^
            items.append(got^)
        return Value.list(items^)

    # Scalars are already IR.
    return node.copy()


fn _sole_key(node: Value) -> String:
    for key in node.fields[].keys():
        return key.copy()
    return String("")


fn _compile_literal_record(node: Value) -> Value:
    """A data record. Field values are still compiled, so an expression nested
    inside data (a contract's `verifier`, say) is normalized in place."""
    var d = Dict[String, Value]()
    for key in node.fields[].keys():
        var k = key.copy()
        var got = compile_expression(node.fields[].get(k).value())
        if got.is_error():
            return got^
        d[k] = got^
    return Value.record(d^)


fn _compile_op(key: String, value: Value) -> Value:
    if key == "literal":
        # The parsed tree is already pure data, so the escape hatch is simply
        # to stop interpreting.
        return value.copy()

    if key == "ref":
        if not value.is_text():
            return _fail(
                String("ref expects a path string, got ") + value.to_string()
            )
        return Value.ref(value.s.copy())

    if key == "record":
        if value.tag != RECORD:
            return _fail(
                String("record expects a mapping, got ") + value.to_string()
            )
        var d = Dict[String, Value]()
        for k in value.fields[].keys():
            var kk = k.copy()
            var got = compile_expression(value.fields[].get(kk).value())
            if got.is_error():
                return got^
            d[kk] = got^
        return Value.expr_named(String("record"), d^)

    if key == "list":
        if value.tag != LIST:
            return _fail(
                String("list expects a sequence, got ") + value.to_string()
            )
        var items = List[Value]()
        for k in range(value.len()):
            var got = compile_expression(value.at(k))
            if got.is_error():
                return got^
            items.append(got^)
        return Value.expr(String("list"), items^)

    if key == "call":
        return _compile_call(value)

    if _is_named_op(key):
        if value.tag != RECORD:
            return _fail(
                key
                + String(" expects a mapping of named arguments, got ")
                + value.to_string()
            )
        var d = Dict[String, Value]()
        for k in value.fields[].keys():
            var kk = k.copy()
            var got = compile_expression(value.fields[].get(kk).value())
            if got.is_error():
                return got^
            d[kk] = got^
        return Value.expr_named(key.copy(), d^)

    # Positional operator.
    var args = List[Value]()
    if value.tag == LIST:
        for k in range(value.len()):
            var got = compile_expression(value.at(k))
            if got.is_error():
                return got^
            args.append(got^)
    else:
        # Convenience for unary operators: `abs: {ref: x}` rather than a
        # one-element sequence.
        var got = compile_expression(value)
        if got.is_error():
            return got^
        args.append(got^)

    return Value.expr(key.copy(), args^)


fn _compile_call(value: Value) -> Value:
    """`call: {callee: <expr>, args: {name: <expr>}}`.

    The doc does not spell `call` in YAML, so this is the reader's own
    convention -- named to match the kernel's `call` form rather than inventing
    new vocabulary.
    """
    if value.tag != RECORD:
        return _fail(
            String("call expects a mapping, got ") + value.to_string()
        )
    if not value.has(String("callee")):
        return _fail(String("call requires a 'callee' field"))

    var callee = compile_expression(value.get(String("callee")))
    if callee.is_error():
        return callee^

    var args = Dict[String, Value]()
    if value.has(String("args")):
        var raw = value.get(String("args"))
        if raw.tag != RECORD:
            return _fail(
                String("call args expect a mapping, got ") + raw.to_string()
            )
        for k in raw.fields[].keys():
            var kk = k.copy()
            var got = compile_expression(raw.fields[].get(kk).value())
            if got.is_error():
                return got^
            args[kk] = got^

    var positional = List[Value]()
    positional.append(callee^)
    return Value.expr_full(String("call"), positional^, args^)

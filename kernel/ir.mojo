"""Construction helpers for the normalized Model IR.

Doc 7 puts a Model IR between the YAML authoring format and the kernel. The
kernel evaluates that IR; this module is the programmatic way to build it.
A YAML front end, when it exists, becomes just another producer of these
same shapes -- it does not get its own path into the evaluator.

Naming: trailing underscores (`if_`, `not_`, `and_`) avoid Mojo keywords and
builtins; everything else matches the operator name used by `evaluate`.
"""

from std.collections import List, Dict

from kernel.value import Value


struct Field(ImplicitlyCopyable, Copyable, Movable):
    """A named field: the pairing used by records and named-argument forms."""

    var name: String
    var value: Value

    fn __init__(out self, var name: String, var value: Value):
        self.name = name^
        self.value = value^


fn kv(var name: String, var value: Value) -> Field:
    return Field(name^, value^)


# --- Literals --------------------------------------------------------------


fn rec(*fields: Field) -> Value:
    """A literal RECORD. Inert under evaluation -- see `record_of`."""
    var d = Dict[String, Value]()
    for k in range(len(fields)):
        d[fields[k].name.copy()] = fields[k].value.copy()
    return Value.record(d^)


fn lst(*items: Value) -> Value:
    """A literal LIST. Inert under evaluation -- see `list_of`."""
    var out = List[Value]()
    for k in range(len(items)):
        out.append(items[k].copy())
    return Value.list(out^)


fn r(var path: String) -> Value:
    """A Ref, e.g. `r("contract.expected.count")`."""
    return Value.ref(path^)


fn sym(var name: String) -> Value:
    return Value.symbol(name^)


# --- Expressions -----------------------------------------------------------


fn ex(var op: String, *args: Value) -> Value:
    """An expression with positional arguments, e.g. `ex("eq", a, b)`."""
    var out = List[Value]()
    for k in range(len(args)):
        out.append(args[k].copy())
    return Value.expr(op^, out^)


fn exn(var op: String, *fields: Field) -> Value:
    """An expression with named arguments."""
    var d = Dict[String, Value]()
    for k in range(len(fields)):
        d[fields[k].name.copy()] = fields[k].value.copy()
    return Value.expr_named(op^, d^)


fn record_of(*fields: Field) -> Value:
    """The `record` form: builds a record by evaluating each field."""
    var d = Dict[String, Value]()
    for k in range(len(fields)):
        d[fields[k].name.copy()] = fields[k].value.copy()
    return Value.expr_named(String("record"), d^)


fn list_of(*items: Value) -> Value:
    """The `list` form: builds a list by evaluating each item."""
    var out = List[Value]()
    for k in range(len(items)):
        out.append(items[k].copy())
    return Value.expr(String("list"), out^)


fn if_(var cond: Value, var then: Value, var els: Value) -> Value:
    return exn(
        String("if"),
        kv(String("condition"), cond^),
        kv(String("then"), then^),
        kv(String("else"), els^),
    )


fn if_only(var cond: Value, var then: Value) -> Value:
    """`if` with no `else`; the untaken branch yields null."""
    return exn(
        String("if"),
        kv(String("condition"), cond^),
        kv(String("then"), then^),
    )


fn lam(var params: Value, var body: Value) -> Value:
    """A lambda-like declaration: `props` (defaults) plus `body`."""
    return exn(
        String("lambda"),
        kv(String("props"), params^),
        kv(String("body"), body^),
    )


fn lam_returns(
    var params: Value, var body: Value, var returns: Value
) -> Value:
    """A lambda that projects `returns` from its body result."""
    return exn(
        String("lambda"),
        kv(String("props"), params^),
        kv(String("body"), body^),
        kv(String("returns"), returns^),
    )


fn call(var callee: Value, *args: Field) -> Value:
    """Apply a lambda with named arguments."""
    var d = Dict[String, Value]()
    for k in range(len(args)):
        d[args[k].name.copy()] = args[k].value.copy()
    var positional = List[Value]()
    positional.append(callee^)
    return Value.expr_full(String("call"), positional^, d^)

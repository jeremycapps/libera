"""Evaluate: the kernel's only execution operation.

    Value_out = Evaluate(Expression, Props)

`Props` is an environment Value (a RECORD) mapping names to Values. `Resolve`
turns a Ref into a Value against that environment. Nothing here knows what a
Contract, Verdict, Operator, or Goal is -- those are Domain and Strategy
concepts that compile *down* to the forms below.

Totality
--------
Neither `evaluate` nor `resolve` raises. Every failure -- unresolved ref, type
mismatch, bad arity, unknown op -- comes back as an Error Value that callers
may inspect or fold into state. Errors propagate strictly through operators:
an operator receiving an Error argument returns that Error unchanged. The two
deliberate exceptions are `and`/`or`, which short-circuit before evaluating
their remaining arguments, and `if`, which only evaluates the taken branch.
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
    E_UNRESOLVED_REF,
    E_UNRESOLVED_MODEL,
    E_TYPE,
    E_ARITY,
    E_UNKNOWN_OP,
    E_KEY,
    E_INDEX,
    E_NOT_CALLABLE,
)


# --- Resolve ---------------------------------------------------------------


fn resolve(r: Value, props: Value) -> Value:
    """Resolve a Ref against an environment: `Resolve(ref, props) -> Value`.

    Walks the ref's dotted segments from `props`. Records are indexed by field
    name; lists by decimal segment. A qualified ref (`@model.path`) resolves
    its `@`-prefixed qualifier as an ordinary key in props -- so a host can
    bind other models by name -- and reports `unresolved_model` when absent.
    External URI resolution is explicitly out of scope for v0.
    """
    if r.tag != REF:
        return Value.error(
            String(E_TYPE),
            String("resolve expects a ref, got ") + tag_name(r.tag),
        )

    var current = props.copy()
    var n = r.len()

    for k in range(n):
        var seg = r.at(k).s.copy()

        if current.tag == RECORD:
            if not current.has(seg):
                if k == 0 and seg.startswith("@"):
                    return Value.error(
                        String(E_UNRESOLVED_MODEL),
                        String("no model bound for '")
                        + seg
                        + String("' in ")
                        + r.s,
                    )
                return Value.error(
                    String(E_UNRESOLVED_REF),
                    String("cannot resolve '")
                    + seg
                    + String("' in ")
                    + r.s,
                )
            current = current.get(seg)

        elif current.tag == LIST:
            var idx = _parse_index(seg)
            if idx < 0:
                return Value.error(
                    String(E_INDEX),
                    String("list segment '")
                    + seg
                    + String("' is not an index in ")
                    + r.s,
                )
            if idx >= current.len():
                return Value.error(
                    String(E_INDEX),
                    String("index ")
                    + seg
                    + String(" out of range in ")
                    + r.s,
                )
            current = current.at(idx)

        else:
            return Value.error(
                String(E_UNRESOLVED_REF),
                String("cannot descend into ")
                + tag_name(current.tag)
                + String(" at '")
                + seg
                + String("' in ")
                + r.s,
            )

    return current^


fn _parse_index(s: String) -> Int:
    """Decimal segment to Int, or -1 if the segment is not a plain index."""
    if len(s) == 0:
        return -1
    var acc = 0
    var bytes = s.as_bytes()
    for k in range(len(bytes)):
        var c = Int(bytes[k])
        if c < 48 or c > 57:
            return -1
        acc = acc * 10 + (c - 48)
    return acc


# --- Evaluate --------------------------------------------------------------


fn evaluate(e: Value, props: Value) -> Value:
    """Apply an expression to a props environment and return a Value.

    Any Value that is neither a Ref nor an Expression evaluates to itself --
    that is what makes expressions *data until Evaluate applies them*. Note
    that a literal RECORD is therefore inert: to build a record by evaluating
    its parts, use the `record` expression form.
    """
    if e.tag == REF:
        return resolve(e, props)
    if e.tag != EXPR:
        return e.copy()

    var op = e.s.copy()

    # --- Construction ------------------------------------------------------
    if op == "record":
        var out = Dict[String, Value]()
        for key in e.fields[].keys():
            var k = key.copy()
            var got = evaluate(e.fields[].get(k).value(), props)
            if got.is_error():
                return got^
            out[k] = got^
        return Value.record(out^)

    if op == "list":
        var out = List[Value]()
        for k in range(e.len()):
            var got = evaluate(e.at(k), props)
            if got.is_error():
                return got^
            out.append(got^)
        return Value.list(out^)

    # --- Lazy forms (evaluated before generic argument evaluation) ----------
    if op == "if":
        return _eval_if(e, props)
    if op == "and":
        return _eval_and_or(e, props, True)
    if op == "or":
        return _eval_and_or(e, props, False)
    if op == "lambda":
        # A lambda declaration is inert data; `call` applies it.
        return e.copy()
    if op == "call":
        return _eval_call(e, props)

    # --- Strict forms ------------------------------------------------------
    var args = List[Value]()
    for k in range(e.len()):
        var got = evaluate(e.at(k), props)
        if got.is_error():
            return got^
        args.append(got^)

    if op == "add":
        return _eval_add(args)
    if op == "subtract":
        return _eval_subtract(args)
    if op == "abs":
        return _eval_abs(args)
    if op == "eq":
        if len(args) != 2:
            return _arity(op, 2, len(args))
        return Value.bool(args[0].equals(args[1]))
    if op == "lt" or op == "gt" or op == "lte" or op == "gte":
        return _eval_compare(op, args)
    if op == "not":
        if len(args) != 1:
            return _arity(op, 1, len(args))
        if args[0].tag != BOOL:
            return _type_op(op, args[0])
        return Value.bool(not args[0].b)
    if op == "merge":
        return _eval_merge(args)
    if op == "get":
        return _eval_get(args)

    return Value.error(
        String(E_UNKNOWN_OP), String("unknown operator '") + op + String("'")
    )


# --- Operator implementations ----------------------------------------------


fn _eval_add(args: List[Value]) -> Value:
    """Fold addition over one or more numbers.

    Int-ness is preserved: the result is an Int only if every argument is an
    Int, so counting stays exact and mixed arithmetic widens to Float.
    """
    if len(args) < 1:
        return Value.error(
            String(E_ARITY), String("add expects at least 1 argument")
        )
    var all_int = True
    for k in range(len(args)):
        if not args[k].is_number():
            return _type_op(String("add"), args[k])
        if args[k].tag != INT:
            all_int = False

    if all_int:
        var acc = 0
        for k in range(len(args)):
            acc += args[k].i
        return Value.int(acc)

    var facc = 0.0
    for k in range(len(args)):
        facc += args[k].as_float()
    return Value.float(facc)


fn _eval_subtract(args: List[Value]) -> Value:
    if len(args) != 2:
        return _arity(String("subtract"), 2, len(args))
    for k in range(2):
        if not args[k].is_number():
            return _type_op(String("subtract"), args[k])
    if args[0].tag == INT and args[1].tag == INT:
        return Value.int(args[0].i - args[1].i)
    return Value.float(args[0].as_float() - args[1].as_float())


fn _eval_abs(args: List[Value]) -> Value:
    if len(args) != 1:
        return _arity(String("abs"), 1, len(args))
    if not args[0].is_number():
        return _type_op(String("abs"), args[0])
    if args[0].tag == INT:
        if args[0].i < 0:
            return Value.int(-args[0].i)
        return Value.int(args[0].i)
    return Value.float(abs(args[0].f))


fn _eval_compare(op: String, args: List[Value]) -> Value:
    """Ordered comparison. Numeric only -- `eq` covers structural equality."""
    if len(args) != 2:
        return _arity(op, 2, len(args))
    for k in range(2):
        if not args[k].is_number():
            return _type_op(op, args[k])
    var a = args[0].as_float()
    var b = args[1].as_float()
    if op == "lt":
        return Value.bool(a < b)
    if op == "gt":
        return Value.bool(a > b)
    if op == "lte":
        return Value.bool(a <= b)
    return Value.bool(a >= b)


fn _eval_and_or(e: Value, props: Value, is_and: Bool) -> Value:
    """Short-circuiting `and`/`or` over zero or more boolean arguments.

    Identity cases follow the usual algebra: empty `and` is true, empty `or`
    is false. Because evaluation stops at the decisive argument, an Error in a
    later argument is never reached -- e.g. `and(false, <error>)` is `false`.
    """
    for k in range(e.len()):
        var got = evaluate(e.at(k), props)
        if got.is_error():
            return got^
        if got.tag != BOOL:
            if is_and:
                return _type_op(String("and"), got)
            return _type_op(String("or"), got)
        if is_and and not got.b:
            return Value.bool(False)
        if (not is_and) and got.b:
            return Value.bool(True)
    return Value.bool(is_and)


fn _eval_if(e: Value, props: Value) -> Value:
    """`if{condition, then, else}` -- only the taken branch is evaluated.

    `else` is optional and defaults to null, which keeps simple orchestration
    expressions terse.
    """
    if not e.has(String("condition")):
        return Value.error(
            String(E_ARITY), String("if requires a 'condition' field")
        )
    if not e.has(String("then")):
        return Value.error(
            String(E_ARITY), String("if requires a 'then' field")
        )

    var cond = evaluate(e.get(String("condition")), props)
    if cond.is_error():
        return cond^
    if cond.tag != BOOL:
        return _type_op(String("if condition"), cond)

    if cond.b:
        return evaluate(e.get(String("then")), props)
    if e.has(String("else")):
        return evaluate(e.get(String("else")), props)
    return Value.null()


fn _eval_merge(args: List[Value]) -> Value:
    """Shallow record merge; later arguments win.

    Shallow is deliberate for v0: folding a role output into CurrentState is a
    field-level replace, and deep-merge semantics would smuggle a policy
    decision into the kernel.
    """
    if len(args) < 1:
        return Value.error(
            String(E_ARITY), String("merge expects at least 1 argument")
        )
    var out = Dict[String, Value]()
    for k in range(len(args)):
        if args[k].tag != RECORD:
            return _type_op(String("merge"), args[k])
        for key in args[k].fields[].keys():
            var kk = key.copy()
            out[kk] = args[k].fields[].get(kk).value()
    return Value.record(out^)


fn _eval_get(args: List[Value]) -> Value:
    """Projection out of an already-computed value.

    Refs address the environment; `get` addresses a result -- e.g. the record
    an inner expression just produced.
    """
    if len(args) != 2:
        return _arity(String("get"), 2, len(args))
    var subject = args[0]
    var key = args[1]

    if subject.tag == RECORD:
        if not key.is_text():
            return _type_op(String("get key"), key)
        if not subject.has(key.s):
            return Value.error(
                String(E_KEY),
                String("no such field: '") + key.s + String("'"),
            )
        return subject.get(key.s)

    if subject.tag == LIST:
        if key.tag != INT:
            return _type_op(String("get index"), key)
        if key.i < 0 or key.i >= subject.len():
            return Value.error(
                String(E_INDEX),
                String("index ") + String(key.i) + String(" out of range"),
            )
        return subject.at(key.i)

    return _type_op(String("get"), subject)


fn _eval_call(e: Value, props: Value) -> Value:
    """Apply a lambda-like declaration: `props + body + returns`.

    The callee's `props` field declares parameter names with default Values;
    named arguments on the `call` are evaluated in the *caller's* environment
    and overlaid on those defaults to form the callee's environment. `body` is
    evaluated there. If `returns` is present it is evaluated in that same
    environment extended with `body` bound to the body's result, which lets a
    lambda project a single field out of a record it just built.

    v0 lambdas are not closures: they capture nothing from their definition
    site, which keeps them inert data that survives a YAML round-trip.
    """
    if e.len() < 1:
        return Value.error(
            String(E_ARITY),
            String("call requires the callee as its first argument"),
        )

    var callee = evaluate(e.at(0), props)
    if callee.is_error():
        return callee^
    if callee.tag != EXPR or callee.s != "lambda":
        return Value.error(
            String(E_NOT_CALLABLE),
            String("cannot call ") + tag_name(callee.tag),
        )

    var env = Dict[String, Value]()

    var declared = callee.get_or(String("props"), Value.empty_record())
    if declared.tag != RECORD:
        return _type_op(String("lambda props"), declared)
    for key in declared.fields[].keys():
        var k = key.copy()
        env[k] = declared.fields[].get(k).value()

    for key in e.fields[].keys():
        var k = key.copy()
        var got = evaluate(e.fields[].get(k).value(), props)
        if got.is_error():
            return got^
        env[k] = got^

    if not callee.has(String("body")):
        return Value.error(
            String(E_ARITY), String("lambda requires a 'body' field")
        )

    var inner = Value.record(env^)
    var result = evaluate(callee.get(String("body")), inner)
    if result.is_error():
        return result^

    if not callee.has(String("returns")):
        return result^

    var ret_env = Dict[String, Value]()
    for key in inner.fields[].keys():
        var k = key.copy()
        ret_env[k] = inner.fields[].get(k).value()
    ret_env[String("body")] = result^
    return evaluate(callee.get(String("returns")), Value.record(ret_env^))


# --- Error helpers ---------------------------------------------------------


fn _arity(op: String, want: Int, got: Int) -> Value:
    return Value.error(
        String(E_ARITY),
        op
        + String(" expects ")
        + String(want)
        + String(" arguments, got ")
        + String(got),
    )


fn _type_op(op: String, v: Value) -> Value:
    return Value.error(
        String(E_TYPE),
        op + String(" does not accept ") + tag_name(v.tag),
    )

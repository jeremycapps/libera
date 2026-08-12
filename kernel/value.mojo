"""Value: the universal representable object of the Libera kernel.

Per the architecture doc (2.1), *everything* the layers above the kernel deal
in -- contracts, results, verdicts, states, strategies, operators, and
expressions -- is a Value. The kernel therefore knows nothing about Domain or
Strategy semantics; it only knows how to represent, compare, and print Values.

Representation notes
--------------------
Value is a recursive type. Mojo cannot synthesize a copy constructor for a
struct that directly contains `List[Self]`, so children live behind
`ArcPointer`. This is not merely a workaround: kernel Values are treated as
*immutable* (open design decision 8, resolved to immutable for v0), which
makes structural sharing safe and copies O(1).

Errors are Values (tag ERROR) rather than raised exceptions, so that the kernel
law `Value_out = Evaluate(Expression, Props)` stays literally total: evaluation
always returns a Value, and failures remain inspectable and composable as data.
"""

from std.collections import List, Dict
from std.collections.optional import Optional
from std.memory import ArcPointer


# --- Tags ------------------------------------------------------------------
# The value forms named in doc 2.1, plus ERROR (see module docstring).

comptime NULL = 0
comptime BOOL = 1
comptime INT = 2
comptime FLOAT = 3
comptime STRING = 4
comptime SYMBOL = 5
comptime LIST = 6
comptime RECORD = 7
comptime REF = 8
comptime EXPR = 9
comptime ERROR = 10


fn tag_name(tag: Int) -> String:
    if tag == NULL:
        return String("null")
    if tag == BOOL:
        return String("bool")
    if tag == INT:
        return String("int")
    if tag == FLOAT:
        return String("float")
    if tag == STRING:
        return String("string")
    if tag == SYMBOL:
        return String("symbol")
    if tag == LIST:
        return String("list")
    if tag == RECORD:
        return String("record")
    if tag == REF:
        return String("ref")
    if tag == EXPR:
        return String("expression")
    if tag == ERROR:
        return String("error")
    return String("unknown")


# --- Error codes -----------------------------------------------------------

comptime E_UNRESOLVED_REF = "unresolved_ref"
comptime E_UNRESOLVED_MODEL = "unresolved_model"
comptime E_TYPE = "type_error"
comptime E_ARITY = "arity_error"
comptime E_UNKNOWN_OP = "unknown_op"
comptime E_KEY = "key_error"
comptime E_INDEX = "index_error"
comptime E_NOT_CALLABLE = "not_callable"


struct Value(ImplicitlyCopyable, Copyable, Movable):
    """A kernel value. Immutable by convention; construct via the static
    factories rather than mutating fields in place."""

    var tag: Int
    var b: Bool
    var i: Int
    var f: Float64
    # Doubles as: string/symbol text, ref source text, expression op name,
    # and error code -- depending on `tag`.
    var s: String
    var items: ArcPointer[List[Value]]
    var fields: ArcPointer[Dict[String, Value]]

    fn __init__(out self):
        self.tag = NULL
        self.b = False
        self.i = 0
        self.f = 0.0
        self.s = String("")
        self.items = ArcPointer(List[Value]())
        self.fields = ArcPointer(Dict[String, Value]())

    # --- Scalar factories --------------------------------------------------

    @staticmethod
    fn null() -> Self:
        return Value()

    @staticmethod
    fn bool(x: Bool) -> Self:
        var v = Value()
        v.tag = BOOL
        v.b = x
        return v^

    @staticmethod
    fn int(x: Int) -> Self:
        var v = Value()
        v.tag = INT
        v.i = x
        return v^

    @staticmethod
    fn float(x: Float64) -> Self:
        var v = Value()
        v.tag = FLOAT
        v.f = x
        return v^

    @staticmethod
    fn string(var x: String) -> Self:
        var v = Value()
        v.tag = STRING
        v.s = x^
        return v^

    @staticmethod
    fn symbol(var x: String) -> Self:
        """A symbol is an interned-looking bare word, e.g. `confirmed`."""
        var v = Value()
        v.tag = SYMBOL
        v.s = x^
        return v^

    # --- Structural factories ----------------------------------------------

    @staticmethod
    fn list(var xs: List[Value]) -> Self:
        var v = Value()
        v.tag = LIST
        v.items = ArcPointer(xs^)
        return v^

    @staticmethod
    fn record(var d: Dict[String, Value]) -> Self:
        var v = Value()
        v.tag = RECORD
        v.fields = ArcPointer(d^)
        return v^

    @staticmethod
    fn empty_record() -> Self:
        var v = Value()
        v.tag = RECORD
        return v^

    # --- Ref ---------------------------------------------------------------

    @staticmethod
    fn ref(var path: String) -> Self:
        """Build a Ref from dotted path text.

        Three shapes are recognised (doc 2.1):
          local path      `state.current.count`
          model path      `contract.expected.count`
          qualified path  `@domain/bootstrap.contract.expected`

        Local and model paths are indistinguishable to the kernel -- both are
        just dotted lookups into props, which is exactly the point: the kernel
        does not know what `contract` means. A qualified path is one beginning
        with `@`; its qualifier is the text up to the first `.`, and that
        qualifier is looked up in props verbatim (including the `@`).
        """
        var v = Value()
        v.tag = REF
        v.s = path.copy()

        # Splitting on "." handles all three shapes uniformly: for a qualified
        # path the leading segment simply *is* the qualifier, since a qualifier
        # such as `@domain/bootstrap` contains no dot.
        var segments = List[Value]()
        var parts = path.split(".")
        for pi in range(len(parts)):
            var seg = String(parts[pi])
            if len(seg) > 0:
                segments.append(Value.string(seg^))

        v.items = ArcPointer(segments^)
        return v^

    # --- Expression --------------------------------------------------------

    @staticmethod
    fn expr(var op: String, var args: List[Value]) -> Self:
        """Expression with positional arguments, e.g. `eq(a, b)`."""
        var v = Value()
        v.tag = EXPR
        v.s = op^
        v.items = ArcPointer(args^)
        return v^

    @staticmethod
    fn expr_named(var op: String, var named: Dict[String, Value]) -> Self:
        """Expression with named arguments, e.g. `if{condition,then,else}`."""
        var v = Value()
        v.tag = EXPR
        v.s = op^
        v.fields = ArcPointer(named^)
        return v^

    @staticmethod
    fn expr_full(
        var op: String,
        var args: List[Value],
        var named: Dict[String, Value],
    ) -> Self:
        """Expression carrying both positional and named arguments, as `call`
        does (callee positionally, arguments by name)."""
        var v = Value()
        v.tag = EXPR
        v.s = op^
        v.items = ArcPointer(args^)
        v.fields = ArcPointer(named^)
        return v^

    # --- Error -------------------------------------------------------------

    @staticmethod
    fn error(var code: String, var message: String) -> Self:
        var v = Value()
        v.tag = ERROR
        v.s = code^
        var d = Dict[String, Value]()
        d[String("message")] = Value.string(message^)
        v.fields = ArcPointer(d^)
        return v^

    @staticmethod
    fn error_with(
        var code: String, var message: String, var extra: Dict[String, Value]
    ) -> Self:
        """An Error carrying additional structured detail alongside `message`
        -- a source line, an offending key, and so on."""
        var v = Value()
        v.tag = ERROR
        v.s = code^
        var d = extra^
        d[String("message")] = Value.string(message^)
        v.fields = ArcPointer(d^)
        return v^

    # --- Predicates --------------------------------------------------------

    fn is_null(self) -> Bool:
        return self.tag == NULL

    fn is_error(self) -> Bool:
        return self.tag == ERROR

    fn is_number(self) -> Bool:
        return self.tag == INT or self.tag == FLOAT

    fn is_text(self) -> Bool:
        return self.tag == STRING or self.tag == SYMBOL

    fn as_float(self) -> Float64:
        """Numeric widening. Only meaningful when `is_number()`."""
        if self.tag == INT:
            return Float64(self.i)
        if self.tag == FLOAT:
            return self.f
        return 0.0

    fn truthy(self) -> Bool:
        """Strict truthiness: only `true` is true.

        The kernel deliberately refuses Python-style coercion so that a
        malformed condition surfaces as a type error rather than silently
        taking a branch.
        """
        return self.tag == BOOL and self.b

    # --- Structural access (non-raising) -----------------------------------

    fn len(self) -> Int:
        if self.tag == LIST or self.tag == EXPR or self.tag == REF:
            return len(self.items[])
        if self.tag == RECORD:
            return len(self.fields[])
        return 0

    fn at(self, idx: Int) -> Value:
        """Positional access; out-of-range yields an Error Value."""
        if idx < 0 or idx >= len(self.items[]):
            return Value.error(
                String(E_INDEX),
                String("index ") + String(idx) + String(" out of range"),
            )
        return self.items[][idx]

    fn has(self, key: String) -> Bool:
        if self.tag != RECORD and self.tag != EXPR and self.tag != ERROR:
            return False
        return key in self.fields[]

    fn get(self, key: String) -> Value:
        """Field access; a missing key yields an Error Value."""
        if self.tag != RECORD and self.tag != EXPR and self.tag != ERROR:
            return Value.error(
                String(E_TYPE),
                String("cannot read field '")
                + key
                + String("' from ")
                + tag_name(self.tag),
            )
        var found = self.fields[].get(key)
        if found:
            return found.value()
        return Value.error(
            String(E_KEY), String("no such field: '") + key + String("'")
        )

    fn get_or(self, key: String, fallback: Value) -> Value:
        if self.has(key):
            return self.fields[].get(key).value()
        return fallback

    # --- Structural equality -----------------------------------------------

    fn equals(self, other: Value) -> Bool:
        """Deep structural equality.

        Int and Float compare numerically across tags (`3 == 3.0`), matching
        the doc's arithmetic examples where counts may arrive either way.
        String and Symbol do *not* cross-compare: `"confirmed"` is not the
        symbol `confirmed`, since the distinction carries meaning upstream.
        """
        if self.is_number() and other.is_number():
            return self.as_float() == other.as_float()
        if self.tag != other.tag:
            return False

        if self.tag == NULL:
            return True
        if self.tag == BOOL:
            return self.b == other.b
        if self.tag == STRING or self.tag == SYMBOL:
            return self.s == other.s
        if self.tag == REF:
            return self.s == other.s
        if self.tag == ERROR:
            return self.s == other.s
        if self.tag == LIST:
            if len(self.items[]) != len(other.items[]):
                return False
            for k in range(len(self.items[])):
                if not self.items[][k].equals(other.items[][k]):
                    return False
            return True
        if self.tag == EXPR:
            if self.s != other.s:
                return False
            if len(self.items[]) != len(other.items[]):
                return False
            for k in range(len(self.items[])):
                if not self.items[][k].equals(other.items[][k]):
                    return False
            return self._fields_equal(other)
        if self.tag == RECORD:
            return self._fields_equal(other)
        return False

    fn _fields_equal(self, other: Value) -> Bool:
        if len(self.fields[]) != len(other.fields[]):
            return False
        for key in self.fields[].keys():
            var k = key.copy()
            if k not in other.fields[]:
                return False
            var mine = self.fields[].get(k)
            var theirs = other.fields[].get(k)
            if not mine.value().equals(theirs.value()):
                return False
        return True

    # --- Rendering ---------------------------------------------------------

    fn to_string(self) -> String:
        """Compact, deterministic rendering used by tests and error messages.

        Record fields are emitted in sorted key order so that comparisons of
        rendered output are stable across Dict iteration order.
        """
        if self.tag == NULL:
            return String("null")
        if self.tag == BOOL:
            if self.b:
                return String("true")
            return String("false")
        if self.tag == INT:
            return String(self.i)
        if self.tag == FLOAT:
            return String(self.f)
        if self.tag == STRING:
            return String('"') + self.s + String('"')
        if self.tag == SYMBOL:
            return self.s.copy()
        if self.tag == REF:
            return String("ref(") + self.s + String(")")
        if self.tag == ERROR:
            var msg = String("")
            var m = self.fields[].get(String("message"))
            if m:
                msg = m.value().s.copy()
            return String("error(") + self.s + String(": ") + msg + String(")")
        if self.tag == LIST:
            var out = String("[")
            for k in range(len(self.items[])):
                if k > 0:
                    out += ", "
                out += self.items[][k].to_string()
            return out + String("]")
        if self.tag == RECORD:
            return String("{") + self._render_fields() + String("}")
        if self.tag == EXPR:
            var out = String("(") + self.s
            for k in range(len(self.items[])):
                out += String(" ") + self.items[][k].to_string()
            if len(self.fields[]) > 0:
                out += String(" {") + self._render_fields() + String("}")
            return out + String(")")
        return String("<?>")

    fn _render_fields(self) -> String:
        var keys = List[String]()
        for key in self.fields[].keys():
            keys.append(key.copy())
        # Insertion sort: field counts here are small and this keeps the
        # kernel free of any sorting dependency.
        for a in range(1, len(keys)):
            var cur = keys[a].copy()
            var b = a - 1
            while b >= 0 and keys[b] > cur:
                keys[b + 1] = keys[b].copy()
                b -= 1
            keys[b + 1] = cur^

        var out = String("")
        for a in range(len(keys)):
            if a > 0:
                out += ", "
            var k = keys[a].copy()
            var got = self.fields[].get(k)
            out += k + String(": ") + got.value().to_string()
        return out^

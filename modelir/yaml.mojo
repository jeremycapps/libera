"""A YAML subset reader, producing plain kernel Values.

Doc 7: *YAML declares the model. Model IR normalizes the model.* This module
does only the first half -- it reads YAML into a pure data tree (records,
lists, scalars) and interprets nothing. Turning `eq:` into an expression is
`modelir/compile.mojo`'s job. Keeping the two apart means the reader has no
opinion about operators, and the compiler has no opinion about syntax.

Supported subset
----------------
Block mappings, block sequences, flow mappings (`{a: 1}`), flow sequences
(`[1, 2]`), comments, and the scalar types in `text.scalar_value`. That covers
the model documents in the architecture doc.

Not supported: anchors and aliases, tags, multiple documents, block scalars
(`|`, `>`), and complex keys. These fail loudly rather than silently
mis-parsing -- an unsupported construct becomes a parse Error Value naming its
line.

Errors are Values here too, carrying `line`, so a malformed model reports
where it broke instead of raising.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, LIST
from modelir.text import (
    substr,
    byte_at,
    byte_len,
    leading_spaces,
    has_tab_indent,
    strip_comment,
    find_key_colon,
    scalar_value,
    unquote,
    is_quoted,
    SPACE,
    DASH,
    DQUOTE,
    SQUOTE,
    COLON,
    COMMA,
    LBRACKET,
    RBRACKET,
    LBRACE,
    RBRACE,
    BACKSLASH,
)


comptime E_PARSE = "parse_error"


fn _fail(var message: String, line: Int) -> Value:
    """A parse error carrying its line number as a first-class field, so
    callers can act on the location rather than scraping the message."""
    var extra = Dict[String, Value]()
    extra[String("line")] = Value.int(line)
    return Value.error_with(String(E_PARSE), message^, extra^)


# --- Line model ------------------------------------------------------------


struct Line(ImplicitlyCopyable, Copyable, Movable):
    var indent: Int
    var text: String
    var is_item: Bool
    var lineno: Int

    fn __init__(out self, indent: Int, var text: String, is_item: Bool, lineno: Int):
        self.indent = indent
        self.text = text^
        self.is_item = is_item
        self.lineno = lineno


fn _prepare(source: String) -> List[Line]:
    """Strip comments and blanks, and split `- x` into a marker plus content.

    Rewriting `- ref: a` into a bare `-` marker followed by `ref: a` indented
    two further columns is the trick that lets sequences and mappings share one
    block parser: after this pass, every sequence item is simply a nested block.
    """
    var out = List[Line]()
    var raw_lines = source.split("\n")

    for k in range(len(raw_lines)):
        var raw = String(raw_lines[k])
        var lineno = k + 1

        if raw.endswith("\r"):
            raw = substr(raw, 0, byte_len(raw) - 1)

        var tabbed = has_tab_indent(raw)
        var stripped = strip_comment(raw)
        var content = String(stripped.strip())
        if len(content) == 0:
            continue

        var indent = leading_spaces(stripped)
        if tabbed:
            # Recorded as a poison line; the parser turns it into an error.
            out.append(Line(indent, String("\t"), False, lineno))
            continue

        # Peel off any number of leading "- " markers.
        while True:
            if content == "-":
                out.append(Line(indent, String(""), True, lineno))
                break
            if content.startswith("- "):
                out.append(Line(indent, String(""), True, lineno))
                var rest = substr(content, 2, byte_len(content))
                content = String(rest.strip())
                indent += 2
                continue
            out.append(Line(indent, content^, False, lineno))
            break

    return out^


# --- Block parser ----------------------------------------------------------


struct _Reader(Movable):
    var lines: List[Line]
    var i: Int

    fn __init__(out self, var lines: List[Line]):
        self.lines = lines^
        self.i = 0

    fn _at_end(self) -> Bool:
        return self.i >= len(self.lines)

    fn parse_block(mut self, min_indent: Int) -> Value:
        if self._at_end():
            return Value.null()
        var indent = self.lines[self.i].indent
        if indent < min_indent:
            return Value.null()

        if self.lines[self.i].text == "\t":
            return _fail(String("tab character in indentation"), self.lines[self.i].lineno)

        if self.lines[self.i].is_item:
            return self.parse_seq(indent)

        # A lone scalar line (no `key:`) is a scalar block -- this is how a
        # sequence item such as `- 3` bottoms out.
        if find_key_colon(self.lines[self.i].text) == -1:
            var text = self.lines[self.i].text.copy()
            var lineno = self.lines[self.i].lineno
            self.i += 1
            return _parse_inline(text, lineno)

        return self.parse_map(indent)

    fn parse_map(mut self, indent: Int) -> Value:
        var d = Dict[String, Value]()
        while True:
            if self._at_end():
                break
            var line = self.lines[self.i]
            if line.indent != indent or line.is_item:
                break
            if line.text == "\t":
                return _fail(String("tab character in indentation"), line.lineno)

            var cut = find_key_colon(line.text)
            if cut == -1:
                return _fail(
                    String("expected 'key:' but found '")
                    + line.text
                    + String("'"),
                    line.lineno,
                )

            var key_raw = String(substr(line.text, 0, cut).strip())
            var key = unquote(key_raw) if is_quoted(key_raw) else key_raw.copy()
            if len(key) == 0:
                return _fail(String("empty mapping key"), line.lineno)
            if key in d:
                return _fail(
                    String("duplicate key '") + key + String("'"),
                    line.lineno,
                )

            var rest = String(
                substr(line.text, cut + 1, byte_len(line.text)).strip()
            )
            var lineno = line.lineno
            self.i += 1

            var value: Value
            if len(rest) == 0:
                value = self.parse_block(indent + 1)
            else:
                value = _parse_inline(rest, lineno)

            if value.is_error():
                return value^
            d[key] = value^

        return Value.record(d^)

    fn parse_seq(mut self, indent: Int) -> Value:
        var items = List[Value]()
        while True:
            if self._at_end():
                break
            var line = self.lines[self.i]
            if line.indent != indent or not line.is_item:
                break
            self.i += 1
            var item = self.parse_block(indent + 1)
            if item.is_error():
                return item^
            items.append(item^)
        return Value.list(items^)


# --- Flow and scalar -------------------------------------------------------


fn _parse_inline(text: String, lineno: Int) -> Value:
    """Parse the right-hand side of a mapping entry, or a bare scalar line."""
    var s = String(text.strip())
    if len(s) == 0:
        return Value.null()

    var first = byte_at(s, 0)
    if first == LBRACE or first == LBRACKET:
        var cursor = _Flow(s.copy(), lineno)
        var out = cursor.parse_value()
        if out.is_error():
            return out^
        cursor.skip_space()
        if not cursor.at_end():
            return _fail(
                String("trailing text after flow collection"), lineno
            )
        return out^

    if first == 42 or first == 38:  # * alias, & anchor
        return _fail(String("anchors and aliases are not supported"), lineno)
    if first == 124 or first == 62:  # | or >
        return _fail(String("block scalars are not supported"), lineno)

    return scalar_value(s)


struct _Flow(Movable):
    """Cursor over a flow collection: `{a: 1, b: [2, 3]}`."""

    var s: String
    var pos: Int
    var lineno: Int

    fn __init__(out self, var s: String, lineno: Int):
        self.s = s^
        self.pos = 0
        self.lineno = lineno

    fn at_end(self) -> Bool:
        return self.pos >= byte_len(self.s)

    fn skip_space(mut self):
        while not self.at_end() and byte_at(self.s, self.pos) == SPACE:
            self.pos += 1

    fn parse_value(mut self) -> Value:
        self.skip_space()
        if self.at_end():
            return Value.null()
        var c = byte_at(self.s, self.pos)
        if c == LBRACE:
            return self.parse_map()
        if c == LBRACKET:
            return self.parse_seq()
        return scalar_value(self.read_scalar())

    fn parse_map(mut self) -> Value:
        self.pos += 1  # consume '{'
        var d = Dict[String, Value]()
        while True:
            self.skip_space()
            if self.at_end():
                return self._unterminated(String("}"))
            if byte_at(self.s, self.pos) == RBRACE:
                self.pos += 1
                break

            var key_text = self.read_scalar()
            var key_raw = String(key_text.strip())
            var key = unquote(key_raw) if is_quoted(key_raw) else key_raw.copy()
            if len(key) == 0:
                return self._err(String("empty key in flow mapping"))

            self.skip_space()
            if self.at_end() or byte_at(self.s, self.pos) != COLON:
                return self._err(
                    String("expected ':' after key '") + key + String("'")
                )
            self.pos += 1

            var value = self.parse_value()
            if value.is_error():
                return value^
            if key in d:
                return self._err(
                    String("duplicate key '") + key + String("'")
                )
            d[key] = value^

            self.skip_space()
            if self.at_end():
                return self._unterminated(String("}"))
            var sep = byte_at(self.s, self.pos)
            if sep == COMMA:
                self.pos += 1
            elif sep != RBRACE:
                return self._err(String("expected ',' or '}' in flow mapping"))

        return Value.record(d^)

    fn parse_seq(mut self) -> Value:
        self.pos += 1  # consume '['
        var items = List[Value]()
        while True:
            self.skip_space()
            if self.at_end():
                return self._unterminated(String("]"))
            if byte_at(self.s, self.pos) == RBRACKET:
                self.pos += 1
                break

            var value = self.parse_value()
            if value.is_error():
                return value^
            items.append(value^)

            self.skip_space()
            if self.at_end():
                return self._unterminated(String("]"))
            var sep = byte_at(self.s, self.pos)
            if sep == COMMA:
                self.pos += 1
            elif sep != RBRACKET:
                return self._err(String("expected ',' or ']' in flow sequence"))

        return Value.list(items^)

    fn read_scalar(mut self) -> String:
        """Read up to the next structural character, honouring quotes."""
        var start = self.pos
        var n = byte_len(self.s)
        var in_single = False
        var in_double = False

        while self.pos < n:
            var c = byte_at(self.s, self.pos)
            if in_double:
                if c == BACKSLASH:
                    self.pos += 2
                    continue
                if c == DQUOTE:
                    in_double = False
            elif in_single:
                if c == SQUOTE:
                    in_single = False
            else:
                if c == DQUOTE:
                    in_double = True
                elif c == SQUOTE:
                    in_single = True
                elif (
                    c == COMMA
                    or c == COLON
                    or c == RBRACE
                    or c == RBRACKET
                    or c == LBRACE
                    or c == LBRACKET
                ):
                    break
            self.pos += 1

        return String(substr(self.s, start, self.pos).strip())

    fn _err(self, var message: String) -> Value:
        return _fail(message^, self.lineno)

    fn _unterminated(self, var closer: String) -> Value:
        var msg = String("unterminated flow collection, expected '")
        msg += closer
        msg += "'"
        return self._err(msg^)


# --- Public API ------------------------------------------------------------


fn parse_yaml(source: String) -> Value:
    """Read a YAML document into a plain data Value.

    Returns an Error Value (code `parse_error`, with a `line` field) rather
    than raising, matching the kernel's convention that failures are data.
    """
    var lines = _prepare(source)
    if len(lines) == 0:
        return Value.null()

    var reader = _Reader(lines^)
    var out = reader.parse_block(0)
    if out.is_error():
        return out^

    if not reader._at_end():
        var line = reader.lines[reader.i]
        return _fail(
            String("unexpected indentation at '") + line.text + String("'"),
            line.lineno,
        )

    return out^


fn parse_yaml_file(path: String) raises -> Value:
    """Read and parse a model document from disk."""
    with open(path, "r") as f:
        var text = f.read()
        return parse_yaml(text)

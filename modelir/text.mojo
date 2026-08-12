"""Byte-level text helpers for the YAML reader.

Mojo 0.26's `String` has no range slicing (`__getitem__` requires a keyword-only
`byte` argument that the slice forms do not satisfy), so substring extraction
is done here over the raw byte span. Building the result from bytes rather than
from `chr()` keeps multi-byte UTF-8 intact -- a `chr()` loop silently mangles
any non-ASCII scalar.
"""

from std.collections import List

from kernel.value import Value


fn substr(s: String, start: Int, end: Int) -> String:
    """Byte-range substring, clamped to bounds. UTF-8 safe."""
    var b = s.as_bytes()
    var lo = start
    if lo < 0:
        lo = 0
    var hi = end
    if hi > len(b):
        hi = len(b)
    if hi <= lo:
        return String("")

    var buf = List[UInt8]()
    for k in range(lo, hi):
        buf.append(b[k])
    buf.append(0)
    var out = String(unsafe_from_utf8_ptr=buf.unsafe_ptr())
    # Mojo destroys values as soon as they are dead; without this the buffer
    # could be freed before String finishes copying from the pointer.
    _ = buf^
    return out^


fn byte_at(s: String, idx: Int) -> Int:
    var b = s.as_bytes()
    if idx < 0 or idx >= len(b):
        return -1
    return Int(b[idx])


fn byte_len(s: String) -> Int:
    return len(s.as_bytes())


comptime SPACE = 32
comptime TAB = 9
comptime HASH = 35
comptime DQUOTE = 34
comptime SQUOTE = 39
comptime COLON = 58
comptime DASH = 45
comptime DOT = 46
comptime COMMA = 44
comptime LBRACKET = 91
comptime RBRACKET = 93
comptime LBRACE = 123
comptime RBRACE = 125
comptime BACKSLASH = 92


fn is_digit(c: Int) -> Bool:
    return c >= 48 and c <= 57


fn leading_spaces(s: String) -> Int:
    var n = byte_len(s)
    var k = 0
    while k < n and byte_at(s, k) == SPACE:
        k += 1
    return k


fn has_tab_indent(s: String) -> Bool:
    """True if the line's indentation contains a tab.

    YAML forbids tabs in indentation, and silently treating one as whitespace
    would misalign the whole block, so the reader rejects it outright.
    """
    var n = byte_len(s)
    var k = 0
    while k < n:
        var c = byte_at(s, k)
        if c == TAB:
            return True
        if c != SPACE:
            return False
        k += 1
    return False


fn strip_comment(s: String) -> String:
    """Remove a `#` comment, ignoring `#` inside quotes.

    A `#` only starts a comment at the start of the line or after whitespace,
    which is what keeps values such as `name: a#b` intact.
    """
    var n = byte_len(s)
    var in_single = False
    var in_double = False
    var k = 0
    while k < n:
        var c = byte_at(s, k)
        if in_double:
            if c == BACKSLASH:
                k += 2
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
            elif c == HASH:
                if k == 0 or byte_at(s, k - 1) == SPACE:
                    return substr(s, 0, k)
        k += 1
    return s.copy()


fn find_key_colon(s: String) -> Int:
    """Index of the `:` ending a mapping key, or -1.

    The colon must be followed by a space or end the line -- that is what
    distinguishes `key: value` from a bare scalar such as `12:30` or a ref
    path. Quoted regions are skipped, and flow collections are respected so
    that a colon inside `{...}` or `[...]` is not mistaken for the key's.
    """
    var n = byte_len(s)
    var in_single = False
    var in_double = False
    var depth = 0
    var k = 0
    while k < n:
        var c = byte_at(s, k)
        if in_double:
            if c == BACKSLASH:
                k += 2
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
            elif c == LBRACE or c == LBRACKET:
                depth += 1
            elif c == RBRACE or c == RBRACKET:
                depth -= 1
            elif c == COLON and depth == 0:
                if k + 1 >= n or byte_at(s, k + 1) == SPACE:
                    return k
        k += 1
    return -1


fn unquote(s: String) -> String:
    """Strip surrounding quotes and expand the escapes YAML double quotes use."""
    var n = byte_len(s)
    if n < 2:
        return s.copy()
    var first = byte_at(s, 0)
    var last = byte_at(s, n - 1)

    if first == SQUOTE and last == SQUOTE:
        # In single quotes the only escape is '' for a literal quote.
        var raw = substr(s, 1, n - 1)
        return raw.replace("''", "'")

    if first != DQUOTE or last != DQUOTE:
        return s.copy()

    var out = String("")
    var k = 1
    while k < n - 1:
        var c = byte_at(s, k)
        if c == BACKSLASH and k + 1 < n - 1:
            var e = byte_at(s, k + 1)
            if e == 110:  # \n
                out += "\n"
            elif e == 116:  # \t
                out += "\t"
            elif e == DQUOTE:
                out += '"'
            elif e == BACKSLASH:
                out += "\\"
            else:
                out += substr(s, k + 1, k + 2)
            k += 2
            continue
        out += substr(s, k, k + 1)
        k += 1
    return out^


fn is_quoted(s: String) -> Bool:
    var n = byte_len(s)
    if n < 2:
        return False
    var first = byte_at(s, 0)
    var last = byte_at(s, n - 1)
    return (first == DQUOTE and last == DQUOTE) or (
        first == SQUOTE and last == SQUOTE
    )


fn scalar_value(raw: String) -> Value:
    """Type a YAML scalar.

    Quoted text is always a String. Bare text that is not a recognised bool,
    null, or number becomes a Symbol -- which is what makes the doc's
    `then: confirmed` a symbol rather than a string, matching how verdict
    findings are compared upstream.
    """
    var s = String(raw.strip())

    if is_quoted(s):
        return Value.string(unquote(s))

    if len(s) == 0 or s == "null" or s == "Null" or s == "NULL" or s == "~":
        return Value.null()
    if s == "true" or s == "True" or s == "TRUE":
        return Value.bool(True)
    if s == "false" or s == "False" or s == "FALSE":
        return Value.bool(False)

    var numeric = _classify_number(s)
    if numeric == 1:
        try:
            return Value.int(Int(s))
        except:
            return Value.symbol(s^)
    if numeric == 2:
        try:
            return Value.float(Float64(s))
        except:
            return Value.symbol(s^)

    return Value.symbol(s^)


fn _classify_number(s: String) -> Int:
    """0 = not a number, 1 = integer, 2 = float."""
    var n = byte_len(s)
    if n == 0:
        return 0

    var k = 0
    var c0 = byte_at(s, 0)
    if c0 == DASH or c0 == 43:  # - or +
        k = 1
    if k >= n:
        return 0

    var digits = 0
    var dots = 0
    while k < n:
        var c = byte_at(s, k)
        if is_digit(c):
            digits += 1
        elif c == DOT:
            dots += 1
            if dots > 1:
                return 0
        else:
            return 0
        k += 1

    if digits == 0:
        return 0
    if dots == 0:
        return 1
    return 2

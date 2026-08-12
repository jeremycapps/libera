"""The Libera address grammar: {program}/{pressure}/{operation}/{slot}.

An Address names *where a write landed and under what pressure*. It is built from
kernel Values and nothing else -- the slot component is a kernel `Ref`, which is why
this layer needs no new kernel type and no change to `Evaluate`.

This module must never name Domain vocabulary. It does not know what a Contract is,
what conformance means, or why a pressure was chosen. Deciding that is the write
policy's job, and the policy lives in `domain/`.
"""

from std.collections import Dict

from kernel.value import Value


comptime E_ADDRESS = "address_error"


fn is_pressure(p: String) -> Bool:
    """The three pressures from `protocol/libera.schema.yaml`."""
    return p == "boundary" or p == "movement" or p == "exception"


fn is_operation(o: String) -> Bool:
    return (
        o == "enter"
        or o == "exit"
        or o == "advance"
        or o == "change"
        or o == "detect"
        or o == "respond"
    )


fn valid_pair(p: String, o: String) -> Bool:
    """Each operation belongs to exactly one pressure.

    Checking the pair rather than the two fields separately is what stops
    `boundary/detect` -- a well-formed-looking address that names nothing.
    """
    if p == "boundary":
        return o == "enter" or o == "exit"
    if p == "movement":
        return o == "advance" or o == "change"
    if p == "exception":
        return o == "detect" or o == "respond"
    return False


fn default_id(slot_text: String, operation: String) -> String:
    """A stable identity derived from slot and operation.

    Libera's own examples use ids like `path.facia_surface_model_status`. Deriving
    rather than counting is what makes a write addressable across runs -- positional
    `step: 0, 1, 2` is not.
    """
    var out = String("path.")
    var parts = slot_text.split(".")
    for k in range(len(parts)):
        if k > 0:
            out += "_"
        out += String(parts[k])
    out += "_"
    out += operation
    return out^


fn address(
    var program: String,
    var pressure: String,
    var operation: String,
    var slot_text: String,
) -> Value:
    """Build an Address, or an Error Value describing why it is not one."""
    if len(program) == 0:
        return Value.error(
            String(E_ADDRESS), String("address requires a program")
        )
    if len(slot_text) == 0:
        return Value.error(String(E_ADDRESS), String("address requires a slot"))
    if not is_pressure(pressure):
        return Value.error(
            String(E_ADDRESS),
            String("unknown pressure '") + pressure + String("'"),
        )
    if not is_operation(operation):
        return Value.error(
            String(E_ADDRESS),
            String("unknown operation '") + operation + String("'"),
        )
    if not valid_pair(pressure, operation):
        var msg = String("operation '")
        msg += operation
        msg += "' is not valid for pressure '"
        msg += pressure
        msg += "'"
        return Value.error(String(E_ADDRESS), msg^)

    var d = Dict[String, Value]()
    d[String("id")] = Value.string(default_id(slot_text, operation))
    d[String("program")] = Value.string(program^)
    d[String("pressure")] = Value.symbol(pressure^)
    d[String("operation")] = Value.symbol(operation^)
    d[String("slot")] = Value.ref(slot_text^)
    return Value.record(d^)


fn render(addr: Value) -> String:
    """Render as `{pressure}/{operation}/{slot}`.

    `program` is deliberately absent: the schema keeps it a sibling field, not part of
    `path_format`.
    """
    if addr.is_error():
        return addr.to_string()
    var out = addr.get(String("pressure")).s.copy()
    out += "/"
    out += addr.get(String("operation")).s
    out += "/"
    out += addr.get(String("slot")).s
    return out^


fn parse(text: String, var program: String) -> Value:
    """Parse a rendered path back into an Address, given its program."""
    var parts = text.split("/")
    if len(parts) != 3:
        return Value.error(
            String(E_ADDRESS),
            String("expected {pressure}/{operation}/{slot}, got '")
            + text
            + String("'"),
        )
    return address(
        program^,
        String(parts[0]),
        String(parts[1]),
        String(parts[2]),
    )

"""Write: a value landing at an Address, linked to the write before it.

This is Timpos's Moment minus the timestamp. The `prev` chain is structure; the
timestamp is observation, and observation stays Timpos's concern.
"""

from std.collections import Dict

from kernel.value import Value, LIST, STRING


comptime E_WRITE = "write_error"


fn write(addr: Value, value: Value, step: Int, var prev: String) -> Value:
    """Build a Write. An Error address propagates unchanged."""
    if addr.is_error():
        return addr.copy()
    if value.is_error():
        return value.copy()

    var wid = addr.get(String("id")).s.copy()
    wid += "#"
    wid += String(step)

    var d = Dict[String, Value]()
    d[String("id")] = Value.string(wid^)
    d[String("step")] = Value.int(step)
    d[String("address")] = addr.copy()
    d[String("value")] = value.copy()
    if len(prev) == 0:
        d[String("prev")] = Value.null()
    else:
        d[String("prev")] = Value.string(prev^)
    return Value.record(d^)


fn last_id(writes: Value) -> String:
    """The id of the final write, or empty for an empty log."""
    if writes.tag != LIST or writes.len() == 0:
        return String("")
    return writes.at(writes.len() - 1).get(String("id")).s.copy()


fn chain_is_intact(writes: Value, var head_prev: String) -> Bool:
    """Every write points at its predecessor, and the head points at `head_prev`.

    `head_prev` is empty when the log starts a fresh chain, which requires the head's
    `prev` to be null. A non-null head prev with no expected predecessor is an orphan.
    """
    if writes.tag != LIST:
        return False
    var expected = head_prev^
    for k in range(writes.len()):
        var w = writes.at(k)
        var prev = w.get(String("prev"))
        if len(expected) == 0:
            if not prev.is_null():
                return False
        else:
            if prev.tag != STRING or prev.s != expected:
                return False
        expected = w.get(String("id")).s.copy()
    return True

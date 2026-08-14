"""Replay: reconstruct a settled snapshot from a write log.

This is Domain rather than address/ because "the log is done" is a Domain reading
of the grammar -- `boundary/exit` is just an address until something decides that
reaching it means replay is complete. The address layer builds and links writes;
it does not know what finishing looks like.

Reconstruction is mechanical: fold writes into a RECORD keyed by rendered address,
last write at an address wins, then read the terminal write's own address back out
of that fold. Nothing here knows what any particular slot *means* -- that stays the
write policy's business (`models/writes-default.yaml`).
"""

from std.collections import Dict

from kernel.value import Value, LIST
from address.grammar import render
from address.write import chain_is_intact


comptime E_REPLAY = "replay_error"


fn replay(trace: Value) -> Value:
    """Fold a write log into its terminal snapshot.

    Returns `{reconstructed, final_address, steps}` on success, or a
    `replay_error` on a malformed, broken, or unterminated log.
    """
    if trace.tag != LIST:
        return Value.error(String(E_REPLAY), String("trace must be a list"))
    if trace.len() == 0:
        return Value.error(
            String(E_REPLAY), String("cannot replay an empty trace")
        )
    if not chain_is_intact(trace, String("")):
        return Value.error(String(E_REPLAY), String("trace chain is broken"))

    # The fold: walk in order, keyed by rendered address. A later write at the
    # same address overwrites the earlier entry -- that overwrite is the whole
    # point, it is what turns a log into a snapshot.
    var folded = Dict[String, Value]()
    for k in range(trace.len()):
        var w = trace.at(k)
        var key = render(w.get(String("address")))
        folded[key] = w.get(String("value")).copy()

    var terminal = trace.at(trace.len() - 1)
    var terminal_addr = terminal.get(String("address"))
    var pressure = terminal_addr.get(String("pressure"))
    var operation = terminal_addr.get(String("operation"))
    if (
        not pressure.is_text()
        or pressure.s != "boundary"
        or not operation.is_text()
        or operation.s != "exit"
    ):
        return Value.error(
            String(E_REPLAY),
            String("trace does not end at a boundary/exit write"),
        )

    var final_address = render(terminal_addr)
    var found = folded.get(final_address)
    var reconstructed: Value
    if found:
        reconstructed = found.value()
    else:
        # Unreachable: final_address was just inserted by the fold above.
        reconstructed = Value.null()

    var d = Dict[String, Value]()
    d[String("reconstructed")] = reconstructed
    d[String("final_address")] = Value.string(final_address^)
    d[String("steps")] = Value.int(trace.len())
    return Value.record(d^)

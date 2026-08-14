"""Replay: reconstruct a settled snapshot from a write log.

This belongs in Domain rather than `address/` because "the log is done" is a
Domain reading of the grammar -- `boundary/exit` is just an address until
something decides that reaching it means replay is complete. The address layer
builds and links writes; it does not know what finishing looks like. Nothing in
the type system forces the placement; it is where the reading belongs, not where
the compiler puts it.

Reconstruction is mechanical: fold every write into a RECORD keyed by its SLOT,
the last write at a slot winning, then read the terminal write's own slot back
out of that fold.

The key is the slot, not the rendered `{pressure}/{operation}/{slot}` path. A
slot is *where a value belongs*; pressure and operation describe the transition
that produced the write, not its destination. In a real run `verdict.conforms` is
written once under `exception/detect` and later under `movement/advance` -- two
writes to one place, where the second supersedes the first. Keyed by rendered
path they become two live entries and the superseded value stands beside its
replacement, which makes the result a collection rather than a fold.

Nothing here knows what any particular slot *means* -- reading `result.actual` as
"the final result" stays the caller's business, and what a slot is for stays the
write policy's (`models/writes-default.yaml`).
"""

from std.collections import Dict

from kernel.value import Value, LIST, REF
from address.grammar import render
from address.write import chain_is_intact


comptime E_REPLAY = "replay_error"


fn replay(trace: Value) -> Value:
    """Fold a write log into its terminal snapshot.

    Returns `{reconstructed, slots, final_address, steps}` on success, or a
    `replay_error` on a malformed, broken, or unterminated log. `slots` is the
    fold itself -- every slot the log wrote, mapped to the value that won it --
    and `reconstructed` is the entry the terminal write's slot holds.

    Whole logs only. The chain check is anchored with
    `chain_is_intact(trace, "")`, which requires the head write's `prev` to be
    null, so a valid *suffix* of a longer log is rejected as an orphan. Replaying
    a suffix would need the caller to supply the id it continues from, and this
    function takes no such argument.
    """
    if trace.tag != LIST:
        return Value.error(String(E_REPLAY), String("trace must be a list"))
    if trace.len() == 0:
        return Value.error(
            String(E_REPLAY), String("cannot replay an empty trace")
        )
    if not chain_is_intact(trace, String("")):
        return Value.error(String(E_REPLAY), String("trace chain is broken"))

    # The fold: walk in order, keyed by slot. A later write to the same slot
    # overwrites the earlier entry -- that overwrite is the whole point, it is
    # what turns a log into a snapshot.
    var folded = Dict[String, Value]()
    for k in range(trace.len()):
        var w = trace.at(k)
        var slot = w.get(String("address")).get(String("slot"))
        if slot.tag != REF or len(slot.s) == 0:
            return Value.error(
                String(E_REPLAY),
                String("write ")
                + String(k)
                + String(" has no addressable slot"),
            )
        folded[slot.s.copy()] = w.get(String("value")).copy()

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

    # Read the reconstruction back out of the fold, by the terminal write's own
    # slot. Going to `terminal.get("value")` directly would be the same answer
    # by a route that never consults the fold -- and a fold nothing reads is a
    # fold that can rot without anything noticing.
    var terminal_slot = terminal_addr.get(String("slot")).s.copy()
    var found = folded.get(terminal_slot)
    if not found:
        return Value.error(
            String(E_REPLAY),
            String("terminal slot '")
            + terminal_slot
            + String("' is absent from the fold"),
        )
    var reconstructed = found.value()

    var final_address = render(terminal_addr)
    var d = Dict[String, Value]()
    d[String("reconstructed")] = reconstructed
    d[String("slots")] = Value.record(folded^)
    d[String("final_address")] = Value.string(final_address^)
    d[String("steps")] = Value.int(trace.len())
    return Value.record(d^)

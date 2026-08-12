"""The Domain Level 0 protocol: Contract -> Result -> Verdict -> CurrentState.

Doc 3: *Domain Level 0 should not solve planning or automatic repair. It should
preserve Contract -> Result -> Verdict -> CurrentState.* So there is no search
here and no transform: a Result is supplied from outside, Domain verifies it,
folds the outcome into state, and emits a Snapshot once converged. Choosing
what Result to try next is Strategy's job (doc 4), and it is not built.

Everything below is wiring. The two decisions that matter -- what conformance
means and how state folds -- are expressions in the model's YAML, evaluated by
the kernel. This module only decides *which props each expression sees*, per
the formulas in doc 3.2:

    Verdict     = Evaluate(Contract.verifier, { expected, actual })
    State_next  = Evaluate(orchestrate,       { state, output })
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD
from kernel.eval import evaluate
from kernel.ir import kv, rec
from domain.model import DomainModel
from domain.emit import (
    policy_props,
    slot_frame,
    emit,
    derive_classification,
)
from address.write import last_id


# --- Domain object constructors --------------------------------------------


fn make_result(var actual: Value, var source: String) -> Value:
    """A Result: `{ actual, source? }` (doc 3.1)."""
    var d = Dict[String, Value]()
    d[String("actual")] = actual^
    if len(source) > 0:
        d[String("source")] = Value.symbol(source^)
    return Value.record(d^)


fn initial_state(model: DomainModel) -> Value:
    """The CurrentState a run starts from.

    `contract` is seeded so the orchestrator's `ref: state.contract` resolves on
    the very first fold; the rest stay null until something has been observed.
    """
    if not model.is_valid():
        return model.error.copy()
    var d = Dict[String, Value]()
    d[String("contract")] = model.contract.copy()
    d[String("result")] = Value.null()
    d[String("verdict")] = Value.null()
    d[String("classification")] = Value.null()
    d[String("converged")] = Value.bool(False)
    return Value.record(d^)


# --- The protocol ----------------------------------------------------------


fn verify(model: DomainModel, result: Value) -> Value:
    """`Verdict = Evaluate(Contract.verifier, { expected, actual })`.

    `contract` and `result` are bound as well, so a richer verifier can reach
    the whole contract; doc 3.2's two-binding form is the subset that the
    Level 0 model actually uses.
    """
    var verifier = model.verifier()
    if verifier.is_error():
        return verifier^

    var expected = model.expected()
    if expected.is_error():
        return expected^

    if result.tag != RECORD or not result.has(String("actual")):
        return Value.error(
            String("domain_error"),
            String("result must be a record with an 'actual' field, got ")
            + result.to_string(),
        )

    var props = Dict[String, Value]()
    props[String("expected")] = expected^
    props[String("actual")] = result.get(String("actual"))
    props[String("contract")] = model.contract.copy()
    props[String("result")] = result.copy()

    return evaluate(verifier, Value.record(props^))


fn orchestrate(model: DomainModel, state: Value, output: Value) -> Value:
    """`State_next = Evaluate(orchestrate, { state, output })`.

    `output` is whatever is being folded in -- a Contract, Result, or Verdict
    (doc 3.2). The kernel does not care which, and neither does this function.
    """
    var orch = model.orchestrator()
    if orch.is_error():
        return orch^

    var props = Dict[String, Value]()
    props[String("state")] = state.copy()
    props[String("output")] = output.copy()
    return evaluate(orch, Value.record(props^))


fn step(model: DomainModel, state: Value, result: Value) -> Value:
    """One full Level 0 cycle: record the Result, verify it, fold the Verdict.

    The Result is placed into state *before* orchestration so that the
    orchestrator's `ref: state.result` sees the observation this verdict is
    about, rather than the previous one.
    """
    if not model.is_valid():
        return model.error.copy()

    var verdict = verify(model, result)
    if verdict.is_error():
        return verdict^

    var staged = _with_field(state, String("result"), result)
    if staged.is_error():
        return staged^

    return orchestrate(model, staged, verdict)


fn step_with_writes(
    model: DomainModel,
    policy: Value,
    state: Value,
    result: Value,
    step_index: Int,
    var prev: String,
) -> Value:
    """One Level 0 cycle that also emits addressed writes.

    Returns `{state, writes}`. `classification` is injected into the returned state
    from the emitted pressures rather than declared in the model, so there is one
    source of truth for whether a fold deviated.
    """
    if not model.is_valid():
        return model.error.copy()

    var verdict = verify(model, result)
    if verdict.is_error():
        return verdict^

    var staged = _with_field(state, String("result"), result)
    if staged.is_error():
        return staged^

    var next = orchestrate(model, staged, verdict)
    if next.is_error():
        return next^

    # The first fold is the one that has not yet recorded a result.
    var is_first = state.get_or(String("result"), Value.null()).is_null()

    var snap = Value.null()
    if converged(next):
        snap = snapshot(model, next, Value.list(List[Value]()))
        if snap.is_error():
            return snap^

    var props = policy_props(state, next, result, verdict, is_first, step_index)
    var frame = slot_frame(
        model.contract, result, verdict, state, next, snap
    )
    var writes = emit(policy, model.name, props, frame, step_index, prev^)
    if writes.is_error():
        return writes^

    var classified = _with_field(
        next, String("classification"), derive_classification(writes)
    )
    if classified.is_error():
        return classified^

    var out = Dict[String, Value]()
    out[String("state")] = classified^
    out[String("writes")] = writes^
    return Value.record(out^)


fn _with_field(state: Value, var key: String, value: Value) -> Value:
    if state.tag != RECORD:
        return Value.error(
            String("domain_error"),
            String("state must be a record, got ") + state.to_string(),
        )
    var d = Dict[String, Value]()
    for k in state.fields[].keys():
        var kk = k.copy()
        d[kk] = state.fields[].get(kk).value()
    d[key^] = value.copy()
    return Value.record(d^)


# --- Convergence and Snapshot ----------------------------------------------


fn converged(state: Value) -> Bool:
    """Whether the state reports convergence.

    Strict: only the boolean `true` counts, matching the kernel's refusal to
    coerce. A model that leaves `converged` null has not converged.
    """
    if state.tag != RECORD or not state.has(String("converged")):
        return False
    return state.get(String("converged")).truthy()


fn snapshot(model: DomainModel, state: Value, trace: Value) -> Value:
    """A Snapshot: `{ contract, final_result, final_verdict, trace }` (doc 3.1).

    Doc 3.1 calls this *the settled durable output when convergence is
    reached*, so emitting one from an unconverged state is an error rather
    than a half-filled record.
    """
    if not converged(state):
        return Value.error(
            String("domain_error"),
            String("cannot snapshot an unconverged state"),
        )
    var d = Dict[String, Value]()
    d[String("contract")] = model.contract.copy()
    d[String("final_result")] = state.get_or(String("result"), Value.null())
    d[String("final_verdict")] = state.get_or(String("verdict"), Value.null())
    d[String("trace")] = trace.copy()
    return Value.record(d^)


fn run(model: DomainModel, policy: Value, results: List[Value]) -> Value:
    """Apply supplied Results in order, stopping at convergence.

    Returns `{state, trace, classifications, converged, snapshot?}` where `trace` is
    the write log -- one unbroken `prev` chain across every fold.
    """
    if not model.is_valid():
        return model.error.copy()

    var state = initial_state(model)
    var log = List[Value]()
    var classifications = List[Value]()
    var prev = String("")

    for k in range(len(results)):
        if converged(state):
            break
        var folded = step_with_writes(model, policy, state, results[k], k, prev.copy())
        if folded.is_error():
            return folded^

        var writes = folded.get(String("writes"))
        for w in range(writes.len()):
            log.append(writes.at(w))
        var tail = last_id(writes)
        if len(tail) > 0:
            prev = tail^

        state = folded.get(String("state"))
        classifications.append(
            state.get_or(String("classification"), Value.null())
        )

    var trace_value = Value.list(log^)
    var out = Dict[String, Value]()
    out[String("state")] = state.copy()
    out[String("trace")] = trace_value.copy()
    out[String("classifications")] = Value.list(classifications^)
    out[String("converged")] = Value.bool(converged(state))
    if converged(state):
        out[String("snapshot")] = snapshot(model, state, trace_value)
    return Value.record(out^)

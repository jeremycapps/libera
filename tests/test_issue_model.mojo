"""A Domain model over a real contract shape.

`models/domain-count-level-0.yaml` proves the protocol against a counting puzzle.
This proves it against the shape actual work has: several required fields, a
Result that satisfies some and not others, and a finding that names what is
missing rather than reporting a bare false.

It also proves something the count model cannot: the default write policy is
contract-agnostic. The same `models/writes-default.yaml` addresses this model's
folds without modification, because a policy names slots and pressures, not
domain concepts.

Nothing here responds to a deviation. That is Strategy's job, and a test at the
end pins its absence.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD
from kernel.ir import kv, rec, sym
from domain.model import DomainModel, load_domain_model
from domain.emit import load_policy
from domain.run import make_result, verify, run as run_domain
from address.grammar import render
from address.write import chain_is_intact
from testkit.harness import TestSuite


comptime MODEL_PATH = "models/issue-completeness.yaml"
comptime POLICY_PATH = "models/writes-default.yaml"


fn _text(var s: String) -> Value:
    return Value.string(s^)


fn _issue(var root_cause: Value, var owner: Value, var path: Value) -> Value:
    """A supplied Result. Absence is stated as null, never by omitting a key."""
    return make_result(
        rec(
            kv(String("root_cause"), root_cause^),
            kv(String("owner"), owner^),
            kv(String("resolution_path"), path^),
        ),
        String("support"),
    )


fn _complete() -> Value:
    return _issue(
        _text(String("bad deploy")),
        _text(String("alice")),
        _text(String("rollback")),
    )


fn run(mut t: TestSuite) raises:
    var model = load_domain_model(String(MODEL_PATH))
    var policy = load_policy(String(POLICY_PATH))
    _loading(t, model)
    _the_example(t, model)
    _each_gap_is_named(t, model)
    _complete_conforms(t, model)
    _absence_must_be_explicit(t, model)
    _addressed_run(t, model, policy)


fn _loading(mut t: TestSuite, model: DomainModel):
    t.section(String("issue / model loading"))

    t.check(
        String("model loads from disk"),
        model.is_valid(),
        String("load failed: ") + model.error.to_string(),
    )
    t.eq_str(String("model name"), model.name, String("issue-completeness"))
    t.eq_value(
        String("contract declares three required fields"),
        model.expected(),
        rec(
            kv(String("root_cause"), sym(String("required"))),
            kv(String("owner"), sym(String("required"))),
            kv(String("resolution_path"), sym(String("required"))),
        ),
    )


fn _the_example(mut t: TestSuite, model: DomainModel):
    t.section(String("issue / owner and path present, root cause missing"))

    # Contract: an issue must have root cause, owner, and resolution path.
    # Result:   has owner and resolution path, but no root cause.
    # Verdict:  missing required root cause.
    var partial = _issue(
        Value.null(), _text(String("alice")), _text(String("rollback"))
    )
    var verdict = verify(model, partial)

    t.not_error(String("verify returns a Verdict"), verdict)
    t.eq_value(
        String("the issue does not conform"),
        verdict.get(String("conforms")),
        Value.bool(False),
    )
    t.eq_value(
        String("the finding names the missing field"),
        verdict.get(String("finding")),
        sym(String("missing_root_cause")),
    )
    t.eq_value(
        String("verdict is typed"),
        verdict.get(String("type")),
        sym(String("Verdict")),
    )

    # The verdict carries both sides, so a reader can see what was required
    # against what arrived without consulting the model.
    t.eq_value(
        String("verdict carries what was expected"),
        verdict.get(String("expected")),
        model.expected(),
    )
    t.eq_value(
        String("verdict carries what arrived"),
        verdict.get(String("actual")).get(String("owner")),
        _text(String("alice")),
    )
    t.eq_value(
        String("and records the gap as an explicit null"),
        verdict.get(String("actual")).get(String("root_cause")),
        Value.null(),
    )


fn _each_gap_is_named(mut t: TestSuite, model: DomainModel):
    t.section(String("issue / every gap is named, not just counted"))

    # Each gap is checked on BOTH fields. Asserting `finding` alone would let
    # `conforms` quietly stop checking a field while the finding still named
    # it -- the two expressions repeat the same presence logic, so nothing but
    # a test keeps them agreeing.
    var no_owner = verify(
        model,
        _issue(
            _text(String("bad deploy")),
            Value.null(),
            _text(String("rollback")),
        ),
    )
    t.eq_value(
        String("missing owner is named"),
        no_owner.get(String("finding")),
        sym(String("missing_owner")),
    )
    t.eq_value(
        String("missing owner does not conform"),
        no_owner.get(String("conforms")),
        Value.bool(False),
    )

    var no_path = verify(
        model,
        _issue(
            _text(String("bad deploy")),
            _text(String("alice")),
            Value.null(),
        ),
    )
    t.eq_value(
        String("missing resolution path is named"),
        no_path.get(String("finding")),
        sym(String("missing_resolution_path")),
    )
    t.eq_value(
        String("missing resolution path does not conform"),
        no_path.get(String("conforms")),
        Value.bool(False),
    )

    var no_cause = verify(
        model,
        _issue(
            Value.null(),
            _text(String("alice")),
            _text(String("rollback")),
        ),
    )
    t.eq_value(
        String("missing root cause does not conform"),
        no_cause.get(String("conforms")),
        Value.bool(False),
    )

    # With several gaps the finding names the first, in declared order. That is
    # a deliberate choice of the model, not a limitation of the runtime: a
    # supplier fixes one thing at a time, and the next verify names the next.
    var empty = _issue(Value.null(), Value.null(), Value.null())
    t.eq_value(
        String("all three missing names the first"),
        verify(model, empty).get(String("finding")),
        sym(String("missing_root_cause")),
    )
    t.eq_value(
        String("all three missing does not conform"),
        verify(model, empty).get(String("conforms")),
        Value.bool(False),
    )

    var two = _issue(
        _text(String("bad deploy")), Value.null(), Value.null()
    )
    t.eq_value(
        String("two missing names the first of those two"),
        verify(model, two).get(String("finding")),
        sym(String("missing_owner")),
    )


fn _complete_conforms(mut t: TestSuite, model: DomainModel):
    t.section(String("issue / a complete issue conforms"))

    var verdict = verify(model, _complete())
    t.eq_value(
        String("a complete issue conforms"),
        verdict.get(String("conforms")),
        Value.bool(True),
    )
    t.eq_value(
        String("and its finding is complete"),
        verdict.get(String("finding")),
        sym(String("complete")),
    )

    # Presence is what is checked, not the value. An empty string is a value.
    var blank = _issue(
        _text(String("")), _text(String("alice")), _text(String("rollback"))
    )
    t.eq_value(
        String("an empty string is present, not missing"),
        verify(model, blank).get(String("conforms")),
        Value.bool(True),
    )

    # `conforms` and `finding` are two expressions computing the same presence
    # logic, so they can drift apart. This ties them together across every
    # combination of the three fields: conforming exactly when nothing is
    # missing. Without it, dropping a field from `conforms` alone goes
    # undetected.
    _conforms_iff_complete(t, model)


fn _conforms_iff_complete(mut t: TestSuite, model: DomainModel):
    var present = List[Value]()
    present.append(_text(String("bad deploy")))
    present.append(_text(String("alice")))
    present.append(_text(String("rollback")))

    var agreed = 0
    var checked = 0
    for a in range(2):
        for b in range(2):
            for c in range(2):
                var rc = present[0] if a == 1 else Value.null()
                var ow = present[1] if b == 1 else Value.null()
                var rp = present[2] if c == 1 else Value.null()
                var verdict = verify(model, _issue(rc^, ow^, rp^))
                var conforms = verdict.get(String("conforms")).truthy()
                var complete = verdict.get(String("finding")).equals(
                    sym(String("complete"))
                )
                var all_present = a == 1 and b == 1 and c == 1
                checked += 1
                if conforms == complete and conforms == all_present:
                    agreed += 1

    t.eq_int(String("all eight field combinations checked"), checked, 8)
    t.eq_int(
        String("conforms agrees with finding, and with the facts, in all eight"),
        agreed,
        8,
    )


fn _absence_must_be_explicit(mut t: TestSuite, model: DomainModel):
    t.section(String("issue / absence must be stated, not implied"))

    # Omitting a key is not the same claim as leaving it blank. The model
    # requires an explicit null so that "nobody looked" cannot masquerade as
    # "we looked and there is nothing".
    var omitted = make_result(
        rec(kv(String("owner"), _text(String("alice")))), String("support")
    )
    t.is_error(
        String("an omitted field is an error, not a false presence check"),
        verify(model, omitted),
        String("unresolved_ref"),
    )

    var stated = _issue(
        Value.null(), _text(String("alice")), _text(String("rollback"))
    )
    t.not_error(
        String("the same field stated as null verifies normally"),
        verify(model, stated),
    )


fn _addressed_run(mut t: TestSuite, model: DomainModel, policy: Value):
    t.section(String("issue / the default write policy is contract-agnostic"))

    var results = List[Value]()
    results.append(
        _issue(Value.null(), _text(String("alice")), _text(String("rollback")))
    )
    results.append(_complete())
    var outcome = run_domain(model, policy, results)

    t.not_error(String("run completes"), outcome)
    t.eq_value(
        String("run converges once the issue is complete"),
        outcome.get(String("converged")),
        Value.bool(True),
    )

    # The same policy that addresses a counting contract addresses this one,
    # unmodified, because a policy names slots and pressures -- never domain
    # concepts.
    var trace = outcome.get(String("trace"))
    t.eq_int(String("six writes across two folds"), trace.len(), 6)
    t.eq_str(
        String("contract enters scope"),
        render(trace.at(0).get(String("address"))),
        String("boundary/enter/contract.expected"),
    )
    t.eq_str(
        String("the incomplete issue is a detected deviation"),
        render(trace.at(2).get(String("address"))),
        String("exception/detect/verdict.conforms"),
    )
    t.eq_str(
        String("the complete issue advances"),
        render(trace.at(4).get(String("address"))),
        String("movement/advance/verdict.conforms"),
    )
    t.eq_str(
        String("and the settled issue leaves scope"),
        render(trace.at(5).get(String("address"))),
        String("boundary/exit/snapshot"),
    )
    t.check(
        String("the log is one intact chain"),
        chain_is_intact(trace, String("")),
        String("chain broken"),
    )

    t.eq_value(
        String("the first fold classifies as exception"),
        outcome.get(String("classifications")).at(0),
        sym(String("exception")),
    )
    t.eq_value(
        String("the second classifies as confirmed"),
        outcome.get(String("classifications")).at(1),
        sym(String("confirmed")),
    )

    # The Strategy slot stays empty. Domain detected the gap and named it; it
    # did not decide to route the issue back, ask for logs, or escalate. Those
    # are responses, and no response was written.
    t.check(
        String("nothing responds to the deviation"),
        trace.to_string().find("respond") == -1,
        String("a response was emitted -- Strategy has leaked into Domain"),
    )

    # And Domain never repairs a Result on its own: given only incomplete
    # issues it stays unconverged rather than inventing a root cause.
    var never = List[Value]()
    never.append(_issue(Value.null(), Value.null(), Value.null()))
    never.append(
        _issue(Value.null(), _text(String("alice")), _text(String("rollback")))
    )
    var unresolved = run_domain(model, policy, never)
    t.eq_value(
        String("incomplete issues never converge on their own"),
        unresolved.get(String("converged")),
        Value.bool(False),
    )
    t.check(
        String("and no snapshot is emitted"),
        not unresolved.has(String("snapshot")),
        String("unexpected snapshot"),
    )

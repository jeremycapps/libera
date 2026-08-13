"""The smallest possible Strategy: one fixed response.

Two things are being proved here, and the second matters more.

First, that a response can be decided and addressed at all -- that
`exception/respond` gets its first write in this runtime, chained into the same
log as Domain's writes.

Second, that Strategy is *optional*. Domain run without it behaves exactly as
before and still emits no response. If attaching a Strategy were the only way
to run, the layering would be a claim rather than a fact.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD
from kernel.ir import kv, rec, sym
from domain.model import DomainModel, load_domain_model
from domain.emit import load_policy
from domain.run import make_result, run as run_domain_only, verify
from strategy.respond import load_strategy, respond_props, respond, E_STRATEGY
from strategy.run import run as run_with_strategy
from address.grammar import render
from address.write import chain_is_intact
from testkit.harness import TestSuite


comptime MODEL_PATH = "models/issue-completeness.yaml"
comptime POLICY_PATH = "models/writes-default.yaml"
comptime STRATEGY_PATH = "models/strategy-route-back.yaml"


fn _text(var s: String) -> Value:
    return Value.string(s^)


fn _issue(var root_cause: Value, var owner: Value, var path: Value) -> Value:
    return make_result(
        rec(
            kv(String("root_cause"), root_cause^),
            kv(String("owner"), owner^),
            kv(String("resolution_path"), path^),
        ),
        String("support"),
    )


fn _incomplete() -> Value:
    return _issue(
        Value.null(), _text(String("alice")), _text(String("rollback"))
    )


fn _complete() -> Value:
    return _issue(
        _text(String("bad deploy")),
        _text(String("alice")),
        _text(String("rollback")),
    )


fn _count_operation(trace: Value, var op: String) -> Int:
    var n = 0
    for k in range(trace.len()):
        var o = trace.at(k).get(String("address")).get(String("operation"))
        if o.is_text() and o.s == op:
            n += 1
    return n


fn run(mut t: TestSuite) raises:
    var model = load_domain_model(String(MODEL_PATH))
    var policy = load_policy(String(POLICY_PATH))
    var strategy = load_strategy(String(STRATEGY_PATH))

    _loading(t, strategy)
    _the_response(t, model, strategy)
    _addressed(t, model, strategy, policy)
    _strategy_is_optional(t, model, policy)
    _no_response_when_nothing_deviates(t, model, strategy, policy)
    _every_deviation_answered(t, model, strategy, policy)
    _failures(t)


fn _loading(mut t: TestSuite, strategy: Value):
    t.section(String("strategy / loading"))

    t.not_error(String("strategy document loads"), strategy)
    t.check(
        String("declares a respond expression"),
        strategy.has(String("respond")),
        String("missing respond"),
    )
    t.check(
        String("declares a write policy"),
        strategy.has(String("writes")),
        String("missing writes"),
    )


fn _the_response(mut t: TestSuite, model: DomainModel, strategy: Value):
    t.section(String("strategy / the response names what was missing"))

    var result = _incomplete()
    var verdict = verify(model, result)
    var props = respond_props(
        model.contract, result, verdict, Value.empty_record(), Value.empty_record()
    )
    var response = respond(strategy, props)

    t.not_error(String("respond returns a Response"), response)
    t.eq_value(
        String("the action is to route it back"),
        response.get(String("action")),
        sym(String("route_back")),
    )
    t.eq_value(
        String("routed back to whoever supplied it"),
        response.get(String("to")),
        sym(String("support")),
    )

    # The response quotes the verdict rather than re-deriving it. A strategy
    # that decided for its own reasons could disagree with the verdict it is
    # responding to; this one cannot.
    t.eq_value(
        String("and says why, in the verdict's own words"),
        response.get(String("because")),
        sym(String("missing_root_cause")),
    )
    t.eq_value(
        String("which is exactly the verdict's finding"),
        response.get(String("because")),
        verdict.get(String("finding")),
    )


fn _addressed(
    mut t: TestSuite, model: DomainModel, strategy: Value, policy: Value
):
    t.section(String("strategy / the response is addressed and chained"))

    var results = List[Value]()
    results.append(_incomplete())
    results.append(_complete())
    var outcome = run_with_strategy(model, strategy, policy, results)

    t.not_error(String("run completes"), outcome)
    t.eq_value(
        String("run converges once the issue is complete"),
        outcome.get(String("converged")),
        Value.bool(True),
    )

    var trace = outcome.get(String("trace"))
    t.eq_int(String("seven writes: six from Domain, one response"), trace.len(), 7)

    # The response lands immediately after the detection it answers.
    t.eq_str(
        String("the deviation is detected"),
        render(trace.at(2).get(String("address"))),
        String("exception/detect/verdict.conforms"),
    )
    t.eq_str(
        String("and answered on the next write"),
        render(trace.at(3).get(String("address"))),
        String("exception/respond/response.action"),
    )
    t.eq_value(
        String("the response write carries the action"),
        trace.at(3).get(String("value")),
        sym(String("route_back")),
    )

    # One chain across both layers. Strategy's write is part of the record,
    # not an annotation beside it.
    t.check(
        String("Domain's and Strategy's writes form one unbroken chain"),
        chain_is_intact(trace, String("")),
        String("chain broken: two layers writing must still be one log"),
    )
    t.eq_str(
        String("the response points back at the detection"),
        trace.at(3).get(String("prev")).s,
        trace.at(2).get(String("id")).s,
    )
    t.eq_str(
        String("and the next Domain write points back at the response"),
        trace.at(4).get(String("prev")).s,
        trace.at(3).get(String("id")).s,
    )

    t.eq_int(String("exactly one response"), _count_operation(trace, String("respond")), 1)
    t.eq_int(String("exactly one detection"), _count_operation(trace, String("detect")), 1)
    t.eq_int(String("one response recorded"), outcome.get(String("responses")).len(), 1)


fn _strategy_is_optional(mut t: TestSuite, model: DomainModel, policy: Value):
    t.section(String("strategy / Domain runs unchanged without one"))

    # The same results through Domain alone. This is the claim that makes the
    # layering real rather than asserted: attaching a Strategy is a choice, and
    # declining it changes nothing about how Domain behaves.
    var results = List[Value]()
    results.append(_incomplete())
    results.append(_complete())
    var plain = run_domain_only(model, policy, results)

    t.not_error(String("Domain alone still runs"), plain)
    t.eq_value(
        String("and still converges"),
        plain.get(String("converged")),
        Value.bool(True),
    )
    t.eq_int(
        String("six writes, not seven"), plain.get(String("trace")).len(), 6
    )
    t.eq_int(
        String("and no response among them"),
        _count_operation(plain.get(String("trace")), String("respond")),
        0,
    )
    t.check(
        String("Domain alone never writes exception/respond"),
        plain.get(String("trace")).to_string().find("respond") == -1,
        String("Domain has started responding on its own"),
    )


fn _no_response_when_nothing_deviates(
    mut t: TestSuite, model: DomainModel, strategy: Value, policy: Value
):
    t.section(String("strategy / nothing to answer, nothing written"))

    # A complete issue on the first fold. The write policy's `when` gates on the
    # deviation still standing, so no response is written even though a Strategy
    # is attached and its respond expression was evaluated.
    var results = List[Value]()
    results.append(_complete())
    var outcome = run_with_strategy(model, strategy, policy, results)

    t.eq_value(
        String("converges immediately"),
        outcome.get(String("converged")),
        Value.bool(True),
    )
    t.eq_int(
        String("no response is written"),
        _count_operation(outcome.get(String("trace")), String("respond")),
        0,
    )
    t.eq_int(
        String("and none recorded"), outcome.get(String("responses")).len(), 0
    )
    t.check(
        String("the log is still one intact chain"),
        chain_is_intact(outcome.get(String("trace")), String("")),
        String("chain broken"),
    )


fn _every_deviation_answered(
    mut t: TestSuite, model: DomainModel, strategy: Value, policy: Value
):
    t.section(String("strategy / one response per deviation"))

    var results = List[Value]()
    results.append(_issue(Value.null(), Value.null(), Value.null()))
    results.append(_incomplete())
    results.append(_complete())
    var outcome = run_with_strategy(model, strategy, policy, results)

    t.eq_value(
        String("eventually converges"),
        outcome.get(String("converged")),
        Value.bool(True),
    )
    t.eq_int(
        String("two deviations, two responses"),
        _count_operation(outcome.get(String("trace")), String("respond")),
        2,
    )
    t.eq_int(
        String("both recorded"), outcome.get(String("responses")).len(), 2
    )

    # Each response quotes the verdict it answers, so the reasons differ.
    t.eq_value(
        String("the first names the first gap"),
        outcome.get(String("responses")).at(0).get(String("because")),
        sym(String("missing_root_cause")),
    )
    t.eq_value(
        String("the second names the gap that remained"),
        outcome.get(String("responses")).at(1).get(String("because")),
        sym(String("missing_root_cause")),
    )
    t.check(
        String("the whole log stays one chain across three folds"),
        chain_is_intact(outcome.get(String("trace")), String("")),
        String("chain broken"),
    )

    # A run that never completes gets a response every time and never converges.
    # Strategy here has no boundary: it will answer forever without progressing,
    # which is exactly the limitation doc section 5 warns about for a fixed
    # transform, and exactly what stop conditions are for.
    var never = List[Value]()
    never.append(_incomplete())
    never.append(_incomplete())
    var stuck = run_with_strategy(model, strategy, policy, never)
    t.eq_value(
        String("repeated deviations never converge"),
        stuck.get(String("converged")),
        Value.bool(False),
    )
    t.eq_int(
        String("and are answered every time, making no progress"),
        stuck.get(String("responses")).len(),
        2,
    )


fn _failures(mut t: TestSuite) raises:
    t.section(String("strategy / malformed documents"))

    t.is_error(
        String("a document without expressions is rejected"),
        load_strategy(String(MODEL_PATH)),
        String(E_STRATEGY),
    )

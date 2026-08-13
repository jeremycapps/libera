"""Rung 3: search over composed operators (doc section 6, S0 / S1 / Integration).

This is the rung where Strategy stops commenting on Results and starts producing
them. Rungs 0 through 2 all took a Result from outside; here operators are
applied to the current state, candidates are scored, and the best is proposed
for Domain to verify.

The counting puzzle is a poor motivating example and an excellent test: the
right answer is known, and the space is small enough to check by hand.

The claim worth pinning hardest is the last one. A goal and heuristic guide the
search; they do not decide truth. `_goal_does_not_decide_truth` gives the search
a goal that contradicts the contract and shows Domain rejecting the proposal
anyway.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, LIST
from kernel.ir import kv, rec, sym
from domain.model import DomainModel, load_domain_model
from domain.emit import load_policy
from domain.run import make_result
from strategy.respond import (
    load_strategy,
    is_search,
    max_depth,
    has_boundary,
    E_STRATEGY,
)
from strategy.search import expand, lowest_score, search, E_SEARCH
from strategy.run import converge, E_STRATEGY_RUN
from address.grammar import render
from address.write import chain_is_intact
from testkit.harness import TestSuite


comptime COUNT_MODEL = "models/domain-count-level-0.yaml"
comptime POLICY_PATH = "models/writes-default.yaml"
comptime SEARCH_PATH = "models/strategy-count-search.yaml"
comptime RUNG2_PATH = "models/strategy-issue-triage.yaml"


fn _expecting(n: Int) -> Value:
    """A search environment whose goal is `count == n`."""
    return rec(kv(String("expected"), rec(kv(String("count"), Value.int(n)))))


fn _counting(n: Int) -> Value:
    return rec(kv(String("count"), Value.int(n)))


fn _count_operation(trace: Value, var op: String) -> Int:
    var n = 0
    for k in range(trace.len()):
        var o = trace.at(k).get(String("address")).get(String("operation"))
        if o.is_text() and o.s == op:
            n += 1
    return n


fn run(mut t: TestSuite) raises:
    var strategy = load_strategy(String(SEARCH_PATH))
    var model = load_domain_model(String(COUNT_MODEL))
    var policy = load_policy(String(POLICY_PATH))

    _loading(t, strategy)
    _s0_candidate_generation(t, strategy)
    _s1_heuristic_choice(t, strategy)
    _bounded_search(t, strategy)
    _multi_step(t, strategy)
    _integration(t, model, strategy, policy)
    _goal_does_not_decide_truth(t, model, policy)
    _validation(t, model, policy)


fn _loading(mut t: TestSuite, strategy: Value):
    t.section(String("search / loading"))

    t.not_error(String("the search strategy loads"), strategy)
    t.check(
        String("it is a search, not a responder"),
        is_search(strategy),
        String("operators and goal should both be present"),
    )
    t.eq_int(String("depth is bounded at two"), max_depth(strategy), 2)
    t.check(
        String("and proposals are bounded too"),
        has_boundary(strategy),
        String("no max_attempts"),
    )

    # Operator order is sorted, not hash order. A search whose candidates come
    # out in a different order each run is not reproducible.
    var ops = strategy.get(String("operators"))
    t.eq_int(String("two operators"), ops.len(), 2)
    t.eq_value(
        String("sorted first"), ops.at(0).get(String("id")), sym(String("add2"))
    )
    t.eq_value(
        String("sorted second"), ops.at(1).get(String("id")), sym(String("add3"))
    )


fn _s0_candidate_generation(mut t: TestSuite, strategy: Value):
    t.section(String("S0 / operators +2 and +3 from state 0"))

    # Doc section 6, S0: "Operators +2 and +3 from state 0. Produces candidates 2 and 3."
    var candidates = expand(strategy, _expecting(3), _counting(0))

    t.not_error(String("expansion succeeds"), candidates)
    t.eq_int(String("two candidates"), candidates.len(), 2)
    t.eq_value(
        String("add2 produces count 2"),
        candidates.at(0).get(String("state")),
        _counting(2),
    )
    t.eq_value(
        String("add3 produces count 3"),
        candidates.at(1).get(String("state")),
        _counting(3),
    )
    t.eq_value(
        String("each names the operator that made it"),
        candidates.at(0).get(String("operator")),
        sym(String("add2")),
    )

    # The goal is tested per candidate, not only at the end.
    t.eq_value(
        String("count 2 does not satisfy the goal"),
        candidates.at(0).get(String("satisfies")),
        Value.bool(False),
    )
    t.eq_value(
        String("count 3 does"),
        candidates.at(1).get(String("satisfies")),
        Value.bool(True),
    )


fn _s1_heuristic_choice(mut t: TestSuite, strategy: Value):
    t.section(String("S1 / score by abs(goal - candidate), choose lowest"))

    # Doc section 6, S1: "Score candidates by abs(goal - candidate). Chooses +3 for goal 3."
    var candidates = expand(strategy, _expecting(3), _counting(0))

    t.eq_value(
        String("abs(3 - 2) is 1"),
        candidates.at(0).get(String("score")),
        Value.int(1),
    )
    t.eq_value(
        String("abs(3 - 3) is 0"),
        candidates.at(1).get(String("score")),
        Value.int(0),
    )

    var chosen = lowest_score(candidates)
    t.eq_value(
        String("the lowest score is chosen"),
        chosen.get(String("operator")),
        sym(String("add3")),
    )
    t.eq_value(
        String("which is count 3"), chosen.get(String("state")), _counting(3)
    )

    # A different goal moves the choice, which is what makes it a heuristic
    # rather than a constant.
    var toward_two = expand(strategy, _expecting(2), _counting(0))
    t.eq_value(
        String("aiming at 2 chooses add2 instead"),
        lowest_score(toward_two).get(String("operator")),
        sym(String("add2")),
    )

    t.eq_value(
        String("an empty candidate list has no choice"),
        lowest_score(Value.list(List[Value]())),
        Value.null(),
    )


fn _bounded_search(mut t: TestSuite, strategy: Value):
    t.section(String("search / bounded, and honest when it fails"))

    var found = search(strategy, _expecting(3), _counting(0), 2)
    t.eq_value(
        String("the goal is reached"),
        found.get(String("found")),
        Value.bool(True),
    )
    t.eq_value(
        String("with count 3"), found.get(String("best")), _counting(3)
    )
    t.eq_value(
        String("at depth one"), found.get(String("depth")), Value.int(1)
    )
    t.eq_int(
        String("having examined only two candidates"),
        found.get(String("explored")).i,
        2,
    )

    # The path says how it got there, not only where it arrived.
    t.eq_value(
        String("by applying add3"),
        found.get(String("path")),
        Value.list(_one(sym(String("add3")))),
    )

    # A goal outside the bound is reported as unreached rather than searched
    # for indefinitely. That is the boundary doing its job.
    var missed = search(strategy, _expecting(100), _counting(0), 2)
    t.eq_value(
        String("an unreachable goal is not found"),
        missed.get(String("found")),
        Value.bool(False),
    )
    t.eq_value(
        String("the search stopped at the depth bound"),
        missed.get(String("depth")),
        Value.int(2),
    )
    t.eq_int(
        String("having explored the whole bounded space"),
        missed.get(String("explored")).i,
        6,
    )
    # It still reports how close it got, which an exhausted search should.
    t.eq_value(
        String("and reports the closest state reached"),
        missed.get(String("best")),
        _counting(6),
    )


fn _one(var v: Value) -> List[Value]:
    var out = List[Value]()
    out.append(v^)
    return out^


fn _multi_step(mut t: TestSuite, strategy: Value):
    t.section(String("search / composing operators across depths"))

    # 5 is unreachable in one step from 0 and reachable in two. This is the
    # difference between rung 3 and rung 2: candidates that no one wrote down.
    var one_step = expand(strategy, _expecting(5), _counting(0))
    t.check(
        String("no single operator reaches 5"),
        not one_step.at(0).get(String("satisfies")).truthy()
        and not one_step.at(1).get(String("satisfies")).truthy(),
        String("5 should not be one step from 0"),
    )

    var depth_one = search(strategy, _expecting(5), _counting(0), 1)
    t.eq_value(
        String("bounded at one, 5 is not found"),
        depth_one.get(String("found")),
        Value.bool(False),
    )

    var depth_two = search(strategy, _expecting(5), _counting(0), 2)
    t.eq_value(
        String("bounded at two, it is"),
        depth_two.get(String("found")),
        Value.bool(True),
    )
    t.eq_value(
        String("reaching count 5"), depth_two.get(String("best")), _counting(5)
    )
    t.eq_value(
        String("at depth two"), depth_two.get(String("depth")), Value.int(2)
    )
    t.eq_int(
        String("by a two-operator path"),
        depth_two.get(String("path")).len(),
        2,
    )


fn _integration(
    mut t: TestSuite, model: DomainModel, strategy: Value, policy: Value
):
    t.section(String("Integration / Strategy proposes, Domain verifies"))

    # Doc section 6, Integration: "Strategy proposes actual 3; Domain verifies.
    # State converges and snapshot emits."
    var start = make_result(_counting(0), String("initial"))
    var outcome = converge(model, strategy, policy, start)

    t.not_error(String("the run completes"), outcome)
    t.eq_value(
        String("state converges"),
        outcome.get(String("converged")),
        Value.bool(True),
    )
    t.check(
        String("and a snapshot emits"),
        outcome.has(String("snapshot")),
        String("no snapshot on a converged run"),
    )
    t.eq_value(
        String("without giving up"),
        outcome.get(String("exhausted")),
        Value.bool(False),
    )

    # One proposal was needed, and it was the right one.
    t.eq_int(String("one proposal"), outcome.get(String("proposals")).len(), 1)
    t.eq_value(
        String("proposing count 3"),
        outcome.get(String("proposals")).at(0),
        _counting(3),
    )

    var response = outcome.get(String("responses")).at(0)
    t.eq_value(
        String("the response is a proposal, not advice"),
        response.get(String("action")),
        sym(String("propose")),
    )
    t.eq_value(
        String("carrying the path that produced it"),
        response.get(String("path")),
        Value.list(_one(sym(String("add3")))),
    )
    t.eq_value(
        String("and its score"), response.get(String("score")), Value.int(0)
    )

    # The addressed record of a runtime reaching a contract on its own.
    var trace = outcome.get(String("trace"))
    t.eq_int(String("seven writes"), trace.len(), 7)
    t.eq_str(
        String("the initial state is a deviation"),
        render(trace.at(2).get(String("address"))),
        String("exception/detect/verdict.conforms"),
    )
    t.eq_str(
        String("answered by a proposal"),
        render(trace.at(3).get(String("address"))),
        String("exception/respond/response.action"),
    )
    t.eq_value(
        String("whose action is propose"),
        trace.at(3).get(String("value")),
        sym(String("propose")),
    )
    t.eq_value(
        String("the proposal becomes the next actual"),
        trace.at(4).get(String("value")),
        _counting(3),
    )
    t.eq_str(
        String("which advances"),
        render(trace.at(5).get(String("address"))),
        String("movement/advance/verdict.conforms"),
    )
    t.check(
        String("one intact chain across both layers"),
        chain_is_intact(trace, String("")),
        String("chain broken"),
    )

    # The Result Domain finally accepted came from the strategy, not a human.
    t.eq_value(
        String("the settled result is attributed to the strategy"),
        outcome.get(String("state")).get(String("result")).get(String("source")),
        sym(String("strategy")),
    )


fn _goal_does_not_decide_truth(
    mut t: TestSuite, model: DomainModel, policy: Value
) raises:
    t.section(String("Integration / the goal guides but does not decide"))

    # This strategy's goal says count 2 is success. The contract says 3.
    # Domain must reject the proposal regardless of how confident the search is.
    var wrong = load_strategy(String("tests/fixtures/strategy-wrong-goal.yaml"))
    t.not_error(String("the mistaken strategy loads"), wrong)

    var start = make_result(_counting(0), String("initial"))
    var outcome = converge(model, wrong, policy, start)
    t.not_error(String("the run completes"), outcome)

    t.eq_value(
        String("its first proposal is count 2"),
        outcome.get(String("proposals")).at(0),
        _counting(2),
    )
    t.eq_value(
        String("but the run does not converge"),
        outcome.get(String("converged")),
        Value.bool(False),
    )
    t.check(
        String("and no snapshot is emitted"),
        not outcome.has(String("snapshot")),
        String("a contract was not met, yet something settled"),
    )
    t.eq_value(
        String("the strategy gives up instead"),
        outcome.get(String("exhausted")),
        Value.bool(True),
    )

    # A wrong heuristic costs attempts, not correctness: Domain's verdict on
    # every proposal is still the contract's.
    var classifications = outcome.get(String("classifications"))
    for k in range(classifications.len()):
        t.eq_value(
            String("every fold was an exception"),
            classifications.at(k),
            sym(String("exception")),
        )
    t.eq_int(
        String("nothing ever advanced"),
        _count_operation(outcome.get(String("trace")), String("advance")),
        0,
    )


fn _validation(
    mut t: TestSuite, model: DomainModel, policy: Value
) raises:
    t.section(String("search / malformed searches are rejected"))

    t.is_error(
        String("a goal with no operators to reach it"),
        load_strategy(String("tests/fixtures/strategy-goal-no-operators.yaml")),
        String(E_STRATEGY),
    )
    # An unbounded search may never stop, which is the one thing a boundary is
    # for.
    t.is_error(
        String("a search with no depth bound"),
        load_strategy(String("tests/fixtures/strategy-search-no-depth.yaml")),
        String(E_STRATEGY),
    )

    # A responder has no operators, so it cannot be asked to search.
    var responder = load_strategy(String(RUNG2_PATH))
    t.not_error(String("the rung 2 strategy still loads"), responder)
    t.check(
        String("and is not a search"),
        not is_search(responder),
        String("rung 2 should not have become a search"),
    )
    t.is_error(
        String("converge refuses a strategy that cannot search"),
        converge(
            model, responder, policy, make_result(_counting(0), String("x"))
        ),
        String(E_STRATEGY_RUN),
    )
    t.is_error(
        String("and expand refuses one too"),
        expand(responder, _expecting(3), _counting(0)),
        String(E_SEARCH),
    )

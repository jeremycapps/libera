"""A strategy that notices its own response did nothing.

Rung 2 counts answers, not progress. `strategy-issue-triage.yaml` knows it has
responded twice; it does not know that asking for logs accomplished nothing. Its
only way to stop is a budget, so it reports *exhausted* when what happened was
*ineffective*.

The second conclusion is strictly better: it is knowable before the budget runs
out, and it names a cause rather than a limit.

The comparison is over `finding` rather than over the whole verdict, and the
tests below pin exactly that difference -- a resubmission can change `actual`
while leaving the deviation untouched.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, LIST
from kernel.ir import kv, rec, sym, record_of, list_of
from domain.model import DomainModel, load_domain_model
from domain.emit import load_policy
from domain.run import make_result, verify
from strategy.respond import (
    load_strategy,
    has_progress_test,
    progress,
    progress_props,
    ineffective,
    E_STRATEGY,
)
from testkit.harness import TestSuite


comptime MODEL_PATH = "models/issue-completeness.yaml"
comptime POLICY_PATH = "models/writes-default.yaml"
comptime EFFECTIVE_PATH = "models/strategy-issue-effectiveness.yaml"
comptime TRIAGE_PATH = "models/strategy-issue-triage.yaml"


fn _verdict_finding(var finding: Value) -> Value:
    """The slice of a Verdict a progress test actually reads."""
    return rec(kv(String("finding"), finding^))


fn _response(var action: Value) -> Value:
    return rec(kv(String("action"), action^))


fn run(mut t: TestSuite) raises:
    _validation(t)
    _progress_evaluation(t)


fn _validation(mut t: TestSuite) raises:
    t.section(String("effectiveness / half a feature is refused"))

    # A progress test with no response to it computes a value nobody reads.
    t.is_error(
        String("progress without ineffective"),
        load_strategy(
            String("tests/fixtures/strategy-progress-without-ineffective.yaml")
        ),
        String(E_STRATEGY),
    )
    # An ineffective response with no test can never fire.
    t.is_error(
        String("ineffective without progress"),
        load_strategy(
            String("tests/fixtures/strategy-ineffective-without-progress.yaml")
        ),
        String(E_STRATEGY),
    )
    # Rung 2 declares neither, and must keep loading unchanged.
    var triage = load_strategy(String(TRIAGE_PATH))
    t.not_error(String("a strategy declaring neither still loads"), triage)
    t.check(
        String("and reports no progress test"),
        not has_progress_test(triage),
        String("triage should not claim effectiveness detection"),
    )


fn _progress_evaluation(mut t: TestSuite) raises:
    t.section(String("effectiveness / the progress test"))

    var strategy = load_strategy(String(EFFECTIVE_PATH))
    t.not_error(String("the effectiveness strategy loads"), strategy)
    t.check(
        String("and reports a progress test"),
        has_progress_test(strategy),
        String("should claim effectiveness detection"),
    )

    # A finding that changed is progress.
    var moved = progress(
        strategy,
        progress_props(
            _verdict_finding(sym(String("missing_owner"))),
            _verdict_finding(sym(String("missing_root_cause"))),
            _response(sym(String("ask_for_logs"))),
        ),
    )
    t.eq_value(
        String("a changed finding is progress"), moved, Value.bool(True)
    )

    # A finding that did not is not.
    var stuck = progress(
        strategy,
        progress_props(
            _verdict_finding(sym(String("missing_root_cause"))),
            _verdict_finding(sym(String("missing_root_cause"))),
            _response(sym(String("ask_for_logs"))),
        ),
    )
    t.eq_value(
        String("an unchanged finding is not"), stuck, Value.bool(False)
    )

    # A non-boolean is an error, not a coercion -- the same discipline
    # `respond` applies to a candidate's `when`.
    var bad = load_strategy(
        String("tests/fixtures/strategy-progress-not-boolean.yaml")
    )
    t.is_error(
        String("a non-boolean progress test is an error"),
        progress(
            bad,
            progress_props(
                _verdict_finding(sym(String("a"))),
                _verdict_finding(sym(String("b"))),
                _response(sym(String("x"))),
            ),
        ),
        String(E_STRATEGY),
    )

    # The ineffective response names what was already tried.
    var handed_up = ineffective(
        strategy,
        progress_props(
            _verdict_finding(sym(String("missing_root_cause"))),
            _verdict_finding(sym(String("missing_root_cause"))),
            _response(sym(String("ask_for_logs"))),
        ),
    )
    t.eq_value(
        String("the ineffective response escalates"),
        handed_up.get(String("action")),
        sym(String("escalate")),
    )
    t.eq_value(
        String("and names what was already tried"),
        handed_up.get(String("tried")),
        sym(String("ask_for_logs")),
    )
    t.eq_value(
        String("and marks itself ineffective"),
        handed_up.get(String("effective")),
        Value.bool(False),
    )

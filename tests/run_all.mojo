"""Kernel test suite entry point.

    mojo run -I . tests/run_all.mojo

Exits non-zero if any assertion fails.
"""

from testkit.harness import TestSuite

import tests.test_value as test_value
import tests.test_resolve as test_resolve
import tests.test_eval as test_eval
import tests.test_k0 as test_k0
import tests.test_yaml as test_yaml
import tests.test_compile as test_compile
import tests.test_domain as test_domain
import tests.test_issue_model as test_issue_model
import tests.test_strategy as test_strategy
import tests.test_strategy_triage as test_strategy_triage
import tests.test_effectiveness as test_effectiveness
import tests.test_search as test_search
import tests.test_address as test_address
import tests.test_write as test_write
import tests.test_policy_doc as test_policy_doc
import tests.test_emit as test_emit
import tests.test_replay as test_replay
import tests.test_layering as test_layering
import tests.test_answer_contracts as test_answer_contracts
import tests.test_facia_bridge as test_facia_bridge


fn main() raises:
    print("=" * 62)
    print("Libera runtime test suite")
    print("=" * 62)

    var t = TestSuite()

    # Kernel (layer 1)
    test_value.run(t)
    test_resolve.run(t)
    test_eval.run(t)
    test_k0.run(t)

    # YAML -> Model IR
    test_yaml.run(t)
    test_compile.run(t)

    # Address layer
    test_address.run(t)
    test_write.run(t)
    test_policy_doc.run(t)
    test_emit.run(t)
    test_replay.run(t)

    # Domain (layer 2)
    # `run_acceptance` drives a real model through `run()`, so it belongs with
    # Domain rather than with the address-layer unit suites above.
    test_replay.run_acceptance(t)
    test_domain.run(t)
    test_issue_model.run(t)

    # Strategy (layer 3)
    test_strategy.run(t)
    test_strategy_triage.run(t)
    test_effectiveness.run(t)
    test_search.run(t)

    # Versioned answer contracts and the top Libera-to-Facia boundary
    test_answer_contracts.run(t)
    test_facia_bridge.run(t)

    # Architecture guards
    test_layering.run(t)

    t.report()

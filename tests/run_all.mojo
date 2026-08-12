"""Kernel test suite entry point.

    mojo run -I . tests/run_all.mojo

Exits non-zero if any assertion fails.
"""

from testkit.harness import TestSuite

import tests.test_value as test_value
import tests.test_resolve as test_resolve
import tests.test_eval as test_eval
import tests.test_k0 as test_k0


fn main():
    print("=" * 62)
    print("Libera kernel test suite")
    print("=" * 62)

    var t = TestSuite()

    test_value.run(t)
    test_resolve.run(t)
    test_eval.run(t)
    test_k0.run(t)

    t.report()

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
import tests.test_address as test_address


fn main() raises:
    print("=" * 62)
    print("Libera kernel + domain test suite")
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

    # Domain (layer 2)
    test_domain.run(t)

    t.report()

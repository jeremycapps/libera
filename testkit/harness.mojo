"""A very small assertion harness.

`mojo test` does not exist in Mojo 0.26, so the suite is an ordinary program:
each test module exposes `run(mut t: TestSuite)`, and `tests/run_all.mojo`
drives them and exits non-zero on failure.

Assertions never abort. A failing check records the expectation and keeps
going, so one run reports every problem rather than only the first.
"""

from std.collections import List
from std.sys import exit

from kernel.value import Value, ERROR


struct TestSuite(Movable):
    var passed: Int
    var failed: Int
    var section_name: String
    var failures: List[String]

    fn __init__(out self):
        self.passed = 0
        self.failed = 0
        self.section_name = String("")
        self.failures = List[String]()

    fn section(mut self, var name: String):
        self.section_name = name^
        print("")
        print("  " + self.section_name)

    fn _pass(mut self, name: String):
        self.passed += 1
        print("    ok   " + name)

    fn _fail(mut self, name: String, detail: String):
        self.failed += 1
        var line = self.section_name + String(" / ") + name
        print("    FAIL " + name)
        print("         " + detail)
        self.failures.append(line + String("\n         ") + detail)

    # --- Assertions --------------------------------------------------------

    fn check(mut self, var name: String, cond: Bool, var detail: String):
        """Assert a raw boolean condition."""
        if cond:
            self._pass(name)
        else:
            self._fail(name, detail)

    fn eq_value(mut self, var name: String, got: Value, want: Value):
        """Assert deep structural equality of two Values."""
        if got.equals(want):
            self._pass(name)
        else:
            self._fail(
                name,
                String("expected ")
                + want.to_string()
                + String("  got ")
                + got.to_string(),
            )

    fn ne_value(mut self, var name: String, a: Value, b: Value):
        """Assert two Values are *not* structurally equal."""
        if not a.equals(b):
            self._pass(name)
        else:
            self._fail(
                name,
                String("expected values to differ, both were ")
                + a.to_string(),
            )

    fn eq_str(mut self, var name: String, var got: String, var want: String):
        """Assert two strings match (used for rendering and error codes)."""
        if got == want:
            self._pass(name)
        else:
            self._fail(
                name,
                String("expected '") + want + String("'  got '") + got
                + String("'"),
            )

    fn eq_int(mut self, var name: String, got: Int, want: Int):
        if got == want:
            self._pass(name)
        else:
            self._fail(
                name,
                String("expected ") + String(want) + String("  got ")
                + String(got),
            )

    fn is_error(mut self, var name: String, got: Value, var code: String):
        """Assert a Value is an Error carrying the given code."""
        if not got.is_error():
            self._fail(
                name,
                String("expected error '")
                + code
                + String("'  got ")
                + got.to_string(),
            )
            return
        if got.s != code:
            self._fail(
                name,
                String("expected error code '")
                + code
                + String("'  got '")
                + got.s
                + String("'"),
            )
            return
        self._pass(name)

    fn not_error(mut self, var name: String, got: Value):
        if got.is_error():
            self._fail(
                name, String("unexpected error ") + got.to_string()
            )
        else:
            self._pass(name)

    # --- Reporting ---------------------------------------------------------

    fn report(self):
        print("")
        print("=" * 62)
        if self.failed == 0:
            print(
                "PASSED  " + String(self.passed) + " assertions, 0 failures"
            )
            print("=" * 62)
            return

        print(
            "FAILED  "
            + String(self.failed)
            + " of "
            + String(self.passed + self.failed)
            + " assertions"
        )
        print("-" * 62)
        for k in range(len(self.failures)):
            print("  * " + self.failures[k])
        print("=" * 62)
        exit(1)

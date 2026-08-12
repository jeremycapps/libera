"""Tests for `Resolve(ref, props) -> Value`.

Resolution is half the kernel law: refs are how an expression reaches into its
environment. The environment is itself a Value, so these tests also confirm
the kernel treats props as ordinary data.
"""

from std.collections import List, Dict

from kernel.value import (
    Value,
    E_TYPE,
    E_UNRESOLVED_REF,
    E_UNRESOLVED_MODEL,
    E_INDEX,
)
from kernel.eval import resolve, evaluate
from kernel.ir import kv, rec, lst, r
from testkit.harness import TestSuite


fn _props() -> Value:
    """A small environment reused across the resolution tests."""
    return rec(
        kv(String("count"), Value.int(3)),
        kv(
            String("expected"),
            rec(kv(String("count"), Value.int(3))),
        ),
        kv(
            String("state"),
            rec(
                kv(
                    String("current"),
                    rec(kv(String("count"), Value.int(7))),
                )
            ),
        ),
        kv(
            String("items"),
            lst(Value.int(10), Value.int(20), rec(kv(String("k"), Value.int(5)))),
        ),
        kv(String("flag"), Value.bool(True)),
    )


fn run(mut t: TestSuite):
    _happy_paths(t)
    _list_paths(t)
    _failures(t)
    _qualified(t)


fn _happy_paths(mut t: TestSuite):
    t.section(String("resolve / paths"))
    var p = _props()

    t.eq_value(
        String("single segment"), resolve(r(String("count")), p), Value.int(3)
    )
    t.eq_value(
        String("two segments"),
        resolve(r(String("expected.count")), p),
        Value.int(3),
    )
    t.eq_value(
        String("three segments"),
        resolve(r(String("state.current.count")), p),
        Value.int(7),
    )
    t.eq_value(
        String("resolves a non-numeric leaf"),
        resolve(r(String("flag")), p),
        Value.bool(True),
    )
    t.eq_value(
        String("resolves an interior record"),
        resolve(r(String("expected")), p),
        rec(kv(String("count"), Value.int(3))),
    )

    # An empty ref addresses the environment itself -- the identity of the
    # path walk, and a useful base case for generated refs.
    t.eq_value(String("empty ref yields props"), resolve(r(String("")), p), p)

    # Refs go through `evaluate` too, since a Ref is just another Value form.
    t.eq_value(
        String("evaluate dispatches refs to resolve"),
        evaluate(r(String("state.current.count")), p),
        Value.int(7),
    )


fn _list_paths(mut t: TestSuite):
    t.section(String("resolve / list indexing"))
    var p = _props()

    t.eq_value(
        String("index into list"),
        resolve(r(String("items.0")), p),
        Value.int(10),
    )
    t.eq_value(
        String("second index"),
        resolve(r(String("items.1")), p),
        Value.int(20),
    )
    t.eq_value(
        String("record through list index"),
        resolve(r(String("items.2.k")), p),
        Value.int(5),
    )
    t.is_error(
        String("index past end"),
        resolve(r(String("items.9")), p),
        String(E_INDEX),
    )
    t.is_error(
        String("non-numeric list segment"),
        resolve(r(String("items.nope")), p),
        String(E_INDEX),
    )


fn _failures(mut t: TestSuite):
    t.section(String("resolve / failures are Values"))
    var p = _props()

    t.is_error(
        String("missing top-level key"),
        resolve(r(String("nope")), p),
        String(E_UNRESOLVED_REF),
    )
    t.is_error(
        String("missing nested key"),
        resolve(r(String("expected.nope")), p),
        String(E_UNRESOLVED_REF),
    )
    t.is_error(
        String("cannot descend into a scalar"),
        resolve(r(String("count.deeper")), p),
        String(E_UNRESOLVED_REF),
    )
    t.is_error(
        String("resolve rejects a non-ref"),
        resolve(Value.int(1), p),
        String(E_TYPE),
    )
    t.is_error(
        String("resolving against a scalar environment"),
        resolve(r(String("a")), Value.int(1)),
        String(E_UNRESOLVED_REF),
    )

    # The error message should name the ref, so a failure upstream is
    # diagnosable without re-running with a debugger.
    var err = resolve(r(String("expected.nope")), p)
    var msg = err.get(String("message"))
    t.check(
        String("error message names the ref"),
        msg.s.find("expected.nope") >= 0,
        String("message was: ") + msg.s,
    )
    t.check(
        String("error message names the segment"),
        msg.s.find("nope") >= 0,
        String("message was: ") + msg.s,
    )


fn _qualified(mut t: TestSuite):
    t.section(String("resolve / qualified refs"))

    # A qualified ref resolves its `@`-prefixed qualifier as an ordinary key,
    # which is how a host binds other models by name. No URI handling in v0.
    var bound = rec(
        kv(
            String("@domain/bootstrap"),
            rec(
                kv(
                    String("contract"),
                    rec(kv(String("expected"), Value.int(3))),
                )
            ),
        )
    )
    t.eq_value(
        String("qualified ref resolves when bound"),
        resolve(r(String("@domain/bootstrap.contract.expected")), bound),
        Value.int(3),
    )

    # Unbound qualifiers get their own code, distinct from a plain missing key:
    # "no such model" and "no such field" are different problems upstream.
    t.is_error(
        String("unbound model is unresolved_model"),
        resolve(r(String("@other/model.contract")), bound),
        String(E_UNRESOLVED_MODEL),
    )
    t.is_error(
        String("bound model but missing field"),
        resolve(r(String("@domain/bootstrap.missing")), bound),
        String(E_UNRESOLVED_REF),
    )

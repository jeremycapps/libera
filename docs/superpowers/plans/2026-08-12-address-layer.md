# Address Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Libera addressing layer so every Domain state write carries a
`{program, pressure, operation, slot}` address and a `prev` chain link.

**Architecture:** A new `address/` package owns the address grammar and the `Write`
record. It depends on `kernel/` only — a slot *is* a kernel `Ref`. `domain/emit.mojo`
evaluates a write policy (a YAML expression, not Mojo logic) and resolves each slot
against a frame to obtain its value. The kernel is not modified. Evaluation still runs
`domain → kernel`; the address layer decorates writes after each fold and is never on the
evaluation path.

**Tech Stack:** Mojo 0.26.2.0. No external dependencies. Tests are a plain program
(`mojo run -I . tests/run_all.mojo`) because Mojo 0.26 has no `mojo test`.

**Spec:** `docs/superpowers/specs/2026-08-12-libera-convergence-design.md`

## Global Constraints

- Mojo 0.26.2.0. `comptime`, not `alias`. `var` for owned args, not `owned`.
- Imports must be fully qualified from `std.` — e.g. `from std.collections import List`.
- Structs needing implicit copy declare `(ImplicitlyCopyable, Copyable, Movable)`.
- Everything is a kernel `Value`. Do not introduce a parallel type system.
- **No kernel changes.** Nothing in this plan modifies `kernel/`.
- Failures are Error `Value`s, never raised exceptions. Only filesystem reads may `raise`.
- `Dict` iteration must copy the key first: `for k in d.keys(): var kk = k.copy()`.
- A transfer sigil (`x^`) at end-of-line followed by a binary operator fails to parse.
  Build the string in a `var` first.
- Run the full suite with `./run_tests.sh`. It must exit 0 before any commit.
- Existing suite baseline: **416 assertions, 0 failures.** Never let it regress.

---

## File Structure

| File | Responsibility |
|---|---|
| `address/__init__.mojo` | Package marker |
| `address/grammar.mojo` | `Address` construction, the pressure/operation vocabulary, render/parse/validate |
| `address/write.mojo` | `Write` record, chain helpers |
| `models/writes-default.yaml` | The default write policy |
| `domain/emit.mojo` | Evaluate the policy, build the slot frame, resolve slots, emit `Write`s |
| `domain/run.mojo` | Modified: thread writes through the run, derive `classification` |
| `tests/test_address.mojo` | Grammar and validation |
| `tests/test_write.mojo` | Write records and chain integrity |
| `tests/test_emit.mojo` | Policy evaluation, traces A and B |
| `tests/test_layering.mojo` | Import-direction enforcement |
| `tests/fixtures/libera.schema.yaml` | Vendored v2 schema for the conformance test |
| `tests/run_all.mojo` | Modified: register the new suites |

**Why the policy evaluator lives in `domain/`, not `address/`:** it binds `output` and
`verdict` props, so it names Domain vocabulary. Putting it in `address/` would fail the
layering test in Task 6.

---

### Task 1: Address grammar

**Files:**
- Create: `address/__init__.mojo`
- Create: `address/grammar.mojo`
- Create: `tests/test_address.mojo`
- Modify: `tests/run_all.mojo`

**Interfaces:**
- Consumes: `kernel.value.Value` (`Value.record`, `Value.ref`, `Value.symbol`,
  `Value.string`, `Value.error`, `.get`, `.is_text`, `.s`)
- Produces:
  - `fn is_pressure(p: String) -> Bool`
  - `fn is_operation(o: String) -> Bool`
  - `fn valid_pair(p: String, o: String) -> Bool`
  - `fn default_id(slot_text: String, operation: String) -> String`
  - `fn address(var program: String, var pressure: String, var operation: String, var slot_text: String) -> Value`
  - `fn render(addr: Value) -> String`
  - `fn parse(text: String, var program: String) -> Value`
  - `comptime E_ADDRESS = "address_error"`

- [ ] **Step 1: Create the package marker**

```bash
mkdir -p address
printf '"""Address: the Libera coordinate of a state write."""\n' > address/__init__.mojo
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_address.mojo`:

```mojo
"""Tests for the Libera address grammar.

Nothing here may mention Contract, Verdict, or conformance -- the address layer
knows where a write landed, never what it meant.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, REF, SYMBOL
from address.grammar import (
    is_pressure,
    is_operation,
    valid_pair,
    default_id,
    address,
    render,
    parse,
    E_ADDRESS,
)
from testkit.harness import TestSuite


fn run(mut t: TestSuite):
    _vocabulary(t)
    _pairing(t)
    _construction(t)
    _render_parse(t)
    _failures(t)


fn _vocabulary(mut t: TestSuite):
    t.section(String("address / vocabulary"))
    t.check(String("boundary is a pressure"), is_pressure(String("boundary")), String("x"))
    t.check(String("movement is a pressure"), is_pressure(String("movement")), String("x"))
    t.check(String("exception is a pressure"), is_pressure(String("exception")), String("x"))
    t.check(
        String("motion is not a pressure"),
        not is_pressure(String("motion")),
        String("only three pressures exist"),
    )
    var ops = List[String]()
    ops.append(String("enter"))
    ops.append(String("exit"))
    ops.append(String("advance"))
    ops.append(String("change"))
    ops.append(String("detect"))
    ops.append(String("respond"))
    for k in range(len(ops)):
        t.check(
            String("operation ") + ops[k],
            is_operation(ops[k]),
            String("expected an operation"),
        )
    t.check(
        String("escalate is not an operation"),
        not is_operation(String("escalate")),
        String("escalation is a species of respond, not its own operation"),
    )


fn _pairing(mut t: TestSuite):
    t.section(String("address / pressure-operation pairing"))
    t.check(String("boundary/enter"), valid_pair(String("boundary"), String("enter")), String("x"))
    t.check(String("boundary/exit"), valid_pair(String("boundary"), String("exit")), String("x"))
    t.check(String("movement/advance"), valid_pair(String("movement"), String("advance")), String("x"))
    t.check(String("movement/change"), valid_pair(String("movement"), String("change")), String("x"))
    t.check(String("exception/detect"), valid_pair(String("exception"), String("detect")), String("x"))
    t.check(String("exception/respond"), valid_pair(String("exception"), String("respond")), String("x"))

    # Operations belong to exactly one pressure.
    t.check(
        String("boundary/advance is invalid"),
        not valid_pair(String("boundary"), String("advance")),
        String("advance belongs to movement"),
    )
    t.check(
        String("movement/detect is invalid"),
        not valid_pair(String("movement"), String("detect")),
        String("detect belongs to exception"),
    )
    t.check(
        String("exception/enter is invalid"),
        not valid_pair(String("exception"), String("enter")),
        String("enter belongs to boundary"),
    )


fn _construction(mut t: TestSuite):
    t.section(String("address / construction"))
    var a = address(
        String("domain-count-level-0"),
        String("exception"),
        String("detect"),
        String("verdict.conforms"),
    )
    t.not_error(String("valid address builds"), a)
    t.eq_str(
        String("program is carried"),
        a.get(String("program")).s,
        String("domain-count-level-0"),
    )
    t.eq_value(
        String("pressure is a symbol"),
        a.get(String("pressure")),
        Value.symbol(String("exception")),
    )
    t.eq_value(
        String("operation is a symbol"),
        a.get(String("operation")),
        Value.symbol(String("detect")),
    )

    # The slot is a kernel Ref, not a string. This is the whole convergence.
    t.check(
        String("slot is a REF value"),
        a.get(String("slot")).tag == REF,
        String("got ") + a.get(String("slot")).to_string(),
    )
    t.eq_value(
        String("slot ref path"),
        a.get(String("slot")),
        Value.ref(String("verdict.conforms")),
    )

    t.eq_str(
        String("id is derived from slot and operation"),
        a.get(String("id")).s,
        String("path.verdict_conforms_detect"),
    )
    t.eq_str(
        String("default_id flattens dots"),
        default_id(String("contract.expected"), String("enter")),
        String("path.contract_expected_enter"),
    )
    t.eq_str(
        String("default_id on a single segment"),
        default_id(String("snapshot"), String("exit")),
        String("path.snapshot_exit"),
    )


fn _render_parse(mut t: TestSuite):
    t.section(String("address / render and parse"))
    var a = address(
        String("p"), String("movement"), String("change"), String("result.actual")
    )
    t.eq_str(
        String("renders as pressure/operation/slot"),
        render(a),
        String("movement/change/result.actual"),
    )

    var back = parse(String("movement/change/result.actual"), String("p"))
    t.not_error(String("parses a rendered address"), back)
    t.eq_value(String("round-trip is lossless"), back, a)

    t.eq_str(
        String("round-trip renders identically"),
        render(parse(render(a), String("p"))),
        render(a),
    )


fn _failures(mut t: TestSuite):
    t.section(String("address / failures are Values"))
    t.is_error(
        String("unknown pressure"),
        address(String("p"), String("motion"), String("change"), String("a.b")),
        String(E_ADDRESS),
    )
    t.is_error(
        String("unknown operation"),
        address(String("p"), String("movement"), String("escalate"), String("a.b")),
        String(E_ADDRESS),
    )
    t.is_error(
        String("mismatched pair"),
        address(String("p"), String("boundary"), String("detect"), String("a.b")),
        String(E_ADDRESS),
    )
    # `program` is required by the v2 schema; the finding's 3-part grammar dropped it.
    t.is_error(
        String("missing program"),
        address(String(""), String("movement"), String("change"), String("a.b")),
        String(E_ADDRESS),
    )
    t.is_error(
        String("missing slot"),
        address(String("p"), String("movement"), String("change"), String("")),
        String(E_ADDRESS),
    )
    t.is_error(
        String("parse rejects a two-part path"),
        parse(String("movement/change"), String("p")),
        String(E_ADDRESS),
    )
    t.is_error(
        String("parse rejects a four-part path"),
        parse(String("a/b/c/d"), String("p")),
        String(E_ADDRESS),
    )
```

- [ ] **Step 3: Register the suite in the runner**

In `tests/run_all.mojo`, add the import alongside the existing ones:

```mojo
import tests.test_address as test_address
```

and add the call after `test_compile.run(t)`:

```mojo
    # Address layer
    test_address.run(t)
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `./run_tests.sh`
Expected: FAIL — `unable to locate module 'address'`

- [ ] **Step 5: Write the implementation**

Create `address/grammar.mojo`:

```mojo
"""The Libera address grammar: {program}/{pressure}/{operation}/{slot}.

An Address names *where a write landed and under what pressure*. It is built from
kernel Values and nothing else -- the slot component is a kernel `Ref`, which is why
this layer needs no new kernel type and no change to `Evaluate`.

This module must never name Domain vocabulary. It does not know what a Contract is,
what conformance means, or why a pressure was chosen. Deciding that is the write
policy's job, and the policy lives in `domain/`.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, REF


comptime E_ADDRESS = "address_error"


fn is_pressure(p: String) -> Bool:
    """The three pressures from `protocol/libera.schema.yaml`."""
    return p == "boundary" or p == "movement" or p == "exception"


fn is_operation(o: String) -> Bool:
    return (
        o == "enter"
        or o == "exit"
        or o == "advance"
        or o == "change"
        or o == "detect"
        or o == "respond"
    )


fn valid_pair(p: String, o: String) -> Bool:
    """Each operation belongs to exactly one pressure.

    Checking the pair rather than the two fields separately is what stops
    `boundary/detect` -- a well-formed-looking address that names nothing.
    """
    if p == "boundary":
        return o == "enter" or o == "exit"
    if p == "movement":
        return o == "advance" or o == "change"
    if p == "exception":
        return o == "detect" or o == "respond"
    return False


fn default_id(slot_text: String, operation: String) -> String:
    """A stable identity derived from slot and operation.

    Libera's own examples use ids like `path.facia_surface_model_status`. Deriving
    rather than counting is what makes a write addressable across runs -- positional
    `step: 0, 1, 2` is not.
    """
    var out = String("path.")
    var parts = slot_text.split(".")
    for k in range(len(parts)):
        if k > 0:
            out += "_"
        out += String(parts[k])
    out += "_"
    out += operation
    return out^


fn address(
    var program: String,
    var pressure: String,
    var operation: String,
    var slot_text: String,
) -> Value:
    """Build an Address, or an Error Value describing why it is not one."""
    if len(program) == 0:
        return Value.error(
            String(E_ADDRESS), String("address requires a program")
        )
    if len(slot_text) == 0:
        return Value.error(String(E_ADDRESS), String("address requires a slot"))
    if not is_pressure(pressure):
        return Value.error(
            String(E_ADDRESS),
            String("unknown pressure '") + pressure + String("'"),
        )
    if not is_operation(operation):
        return Value.error(
            String(E_ADDRESS),
            String("unknown operation '") + operation + String("'"),
        )
    if not valid_pair(pressure, operation):
        var msg = String("operation '")
        msg += operation
        msg += "' is not valid for pressure '"
        msg += pressure
        msg += "'"
        return Value.error(String(E_ADDRESS), msg^)

    var d = Dict[String, Value]()
    d[String("id")] = Value.string(default_id(slot_text, operation))
    d[String("program")] = Value.string(program^)
    d[String("pressure")] = Value.symbol(pressure^)
    d[String("operation")] = Value.symbol(operation^)
    d[String("slot")] = Value.ref(slot_text^)
    return Value.record(d^)


fn render(addr: Value) -> String:
    """Render as `{pressure}/{operation}/{slot}`.

    `program` is deliberately absent: the schema keeps it a sibling field, not part of
    `path_format`.
    """
    if addr.is_error():
        return addr.to_string()
    var out = addr.get(String("pressure")).s.copy()
    out += "/"
    out += addr.get(String("operation")).s
    out += "/"
    out += addr.get(String("slot")).s
    return out^


fn parse(text: String, var program: String) -> Value:
    """Parse a rendered path back into an Address, given its program."""
    var parts = text.split("/")
    if len(parts) != 3:
        return Value.error(
            String(E_ADDRESS),
            String("expected {pressure}/{operation}/{slot}, got '")
            + text
            + String("'"),
        )
    return address(
        program^,
        String(parts[0]),
        String(parts[1]),
        String(parts[2]),
    )
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `./run_tests.sh`
Expected: PASS, assertion count risen from 416 to roughly 460, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add address tests/test_address.mojo tests/run_all.mojo
git commit -m "Add the Libera address grammar

Address is built from kernel Values only -- the slot component is a kernel
Ref, so the grammar needs no new kernel type and no change to Evaluate.
Validates the pressure/operation pairing rather than the fields separately,
and requires program, which the original proposal dropped."
```

---

### Task 2: The Write record and chain

**Files:**
- Create: `address/write.mojo`
- Create: `tests/test_write.mojo`
- Modify: `tests/run_all.mojo`

**Interfaces:**
- Consumes: `address.grammar.address`, `kernel.value.Value`
- Produces:
  - `fn write(addr: Value, value: Value, step: Int, var prev: String) -> Value`
  - `fn last_id(writes: Value) -> String`
  - `fn chain_is_intact(writes: Value, var head_prev: String) -> Bool`
  - `comptime E_WRITE = "write_error"`

- [ ] **Step 1: Write the failing test**

Create `tests/test_write.mojo`:

```mojo
"""Tests for Write records and the prev chain.

The chain is what upgrades a positional trace into a replayable log. It is Timpos's
Moment minus the timestamp -- structure without observation.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, STRING
from address.grammar import address
from address.write import write, last_id, chain_is_intact, E_WRITE
from testkit.harness import TestSuite


fn _addr(var slot: String, var op: String, var pressure: String) -> Value:
    return address(String("prog"), pressure^, op^, slot^)


fn run(mut t: TestSuite):
    _construction(t)
    _chaining(t)
    _integrity(t)


fn _construction(mut t: TestSuite):
    t.section(String("write / construction"))
    var a = _addr(String("result.actual"), String("change"), String("movement"))
    var w = write(a, Value.int(2), 0, String(""))

    t.not_error(String("write builds"), w)
    t.eq_value(String("carries its value"), w.get(String("value")), Value.int(2))
    t.eq_value(String("carries its step"), w.get(String("step")), Value.int(0))
    t.eq_value(String("address is nested"), w.get(String("address")), a)
    t.eq_value(
        String("head write has a null prev"), w.get(String("prev")), Value.null()
    )

    # The write id is address identity plus step -- identified, not merely positional.
    t.eq_str(
        String("write id combines address and step"),
        w.get(String("id")).s,
        String("path.result_actual_change#0"),
    )
    var w1 = write(a, Value.int(3), 1, String("path.result_actual_change#0"))
    t.eq_str(
        String("same address at a later step differs"),
        w1.get(String("id")).s,
        String("path.result_actual_change#1"),
    )

    # An Error address propagates rather than producing a malformed write.
    t.is_error(
        String("bad address propagates"),
        write(
            address(String("prog"), String("boundary"), String("detect"), String("a")),
            Value.int(1),
            0,
            String(""),
        ),
        String("address_error"),
    )


fn _chaining(mut t: TestSuite):
    t.section(String("write / chaining"))
    var a = _addr(String("result.actual"), String("change"), String("movement"))
    var b = _addr(String("verdict.conforms"), String("detect"), String("exception"))

    var w0 = write(a, Value.int(2), 0, String(""))
    var w1 = write(b, Value.bool(False), 0, w0.get(String("id")).s.copy())

    t.eq_str(
        String("second write points at the first"),
        w1.get(String("prev")).s,
        String("path.result_actual_change#0"),
    )

    var items = List[Value]()
    items.append(w0)
    items.append(w1)
    var log = Value.list(items^)

    t.eq_str(
        String("last_id returns the tail"),
        last_id(log),
        String("path.verdict_conforms_detect#0"),
    )
    t.eq_str(
        String("last_id of an empty log is empty"),
        last_id(Value.list(List[Value]())),
        String(""),
    )


fn _integrity(mut t: TestSuite):
    t.section(String("write / chain integrity"))
    var a = _addr(String("result.actual"), String("change"), String("movement"))
    var b = _addr(String("verdict.conforms"), String("detect"), String("exception"))

    var good = List[Value]()
    var w0 = write(a, Value.int(2), 0, String(""))
    good.append(w0)
    good.append(write(b, Value.bool(False), 0, w0.get(String("id")).s.copy()))
    t.check(
        String("a well-formed chain is intact"),
        chain_is_intact(Value.list(good^), String("")),
        String("expected an intact chain"),
    )

    # A broken link must be detected, not tolerated.
    var broken = List[Value]()
    broken.append(write(a, Value.int(2), 0, String("")))
    broken.append(write(b, Value.bool(False), 0, String("path.wrong#0")))
    t.check(
        String("a wrong prev is detected"),
        not chain_is_intact(Value.list(broken^), String("")),
        String("expected a broken chain"),
    )

    # An orphan head -- a non-null prev where none was expected.
    var orphan = List[Value]()
    orphan.append(write(a, Value.int(2), 0, String("path.ghost#0")))
    t.check(
        String("an orphan head is detected"),
        not chain_is_intact(Value.list(orphan^), String("")),
        String("expected a broken chain"),
    )

    # Continuing an existing chain: the head's prev must match head_prev.
    var cont = List[Value]()
    cont.append(write(a, Value.int(2), 1, String("path.earlier#0")))
    t.check(
        String("a continuation chain is intact"),
        chain_is_intact(Value.list(cont^), String("path.earlier#0")),
        String("expected an intact continuation"),
    )

    t.check(
        String("an empty log is intact"),
        chain_is_intact(Value.list(List[Value]()), String("")),
        String("empty is vacuously intact"),
    )
```

- [ ] **Step 2: Register the suite**

In `tests/run_all.mojo` add `import tests.test_write as test_write` and, after
`test_address.run(t)`, add `test_write.run(t)`.

- [ ] **Step 3: Run the test to verify it fails**

Run: `./run_tests.sh`
Expected: FAIL — `unable to locate module 'address.write'`

- [ ] **Step 4: Write the implementation**

Create `address/write.mojo`:

```mojo
"""Write: a value landing at an Address, linked to the write before it.

This is Timpos's Moment minus the timestamp. The `prev` chain is structure; the
timestamp is observation, and observation stays Timpos's concern.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, LIST, STRING


comptime E_WRITE = "write_error"


fn write(addr: Value, value: Value, step: Int, var prev: String) -> Value:
    """Build a Write. An Error address propagates unchanged."""
    if addr.is_error():
        return addr.copy()
    if value.is_error():
        return value.copy()

    var wid = addr.get(String("id")).s.copy()
    wid += "#"
    wid += String(step)

    var d = Dict[String, Value]()
    d[String("id")] = Value.string(wid^)
    d[String("step")] = Value.int(step)
    d[String("address")] = addr.copy()
    d[String("value")] = value.copy()
    if len(prev) == 0:
        d[String("prev")] = Value.null()
    else:
        d[String("prev")] = Value.string(prev^)
    return Value.record(d^)


fn last_id(writes: Value) -> String:
    """The id of the final write, or empty for an empty log."""
    if writes.tag != LIST or writes.len() == 0:
        return String("")
    return writes.at(writes.len() - 1).get(String("id")).s.copy()


fn chain_is_intact(writes: Value, var head_prev: String) -> Bool:
    """Every write points at its predecessor, and the head points at `head_prev`.

    `head_prev` is empty when the log starts a fresh chain, which requires the head's
    `prev` to be null. A non-null head prev with no expected predecessor is an orphan.
    """
    if writes.tag != LIST:
        return False
    var expected = head_prev^
    for k in range(writes.len()):
        var w = writes.at(k)
        var prev = w.get(String("prev"))
        if len(expected) == 0:
            if not prev.is_null():
                return False
        else:
            if prev.tag != STRING or prev.s != expected:
                return False
        expected = w.get(String("id")).s.copy()
    return True
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./run_tests.sh`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add address/write.mojo tests/test_write.mojo tests/run_all.mojo
git commit -m "Add the Write record and prev chain

Write ids combine address identity with step, so a write is identified
rather than merely positional. chain_is_intact detects both wrong links
and orphan heads."
```

---

### Task 3: The default write policy

**Files:**
- Create: `models/writes-default.yaml`
- Modify: `tests/test_emit.mojo` — not yet; this task only proves the document compiles
- Create: `tests/test_policy_doc.mojo`
- Modify: `tests/run_all.mojo`

**Interfaces:**
- Consumes: `modelir.yaml.parse_yaml_file`, `modelir.compile.compile_expression`
- Produces: `models/writes-default.yaml` with `expressions.writes`

- [ ] **Step 1: Write the failing test**

Create `tests/test_policy_doc.mojo`:

```mojo
"""The default write policy must parse and compile like any other model expression.

The policy is data, not Mojo. That is what keeps the runtime from making semantic
judgments of its own -- it evaluates a declared expression and filters on a declared
boolean.
"""

from std.collections import List, Dict

from kernel.value import Value, EXPR, LIST
from modelir.yaml import parse_yaml_file
from modelir.compile import compile_expression
from testkit.harness import TestSuite


comptime POLICY_PATH = "models/writes-default.yaml"


fn run(mut t: TestSuite) raises:
    t.section(String("policy / default document"))

    var root = parse_yaml_file(String(POLICY_PATH))
    t.not_error(String("policy document parses"), root)
    t.check(
        String("declares a model name"),
        root.has(String("model")),
        String("missing model:"),
    )
    t.check(
        String("declares expressions"),
        root.has(String("expressions")),
        String("missing expressions:"),
    )
    t.check(
        String("declares expressions.writes"),
        root.get(String("expressions")).has(String("writes")),
        String("missing expressions.writes"),
    )

    var ir = compile_expression(
        root.get(String("expressions")).get(String("writes"))
    )
    t.not_error(String("policy compiles to IR"), ir)
    t.check(
        String("compiles to a list expression"),
        ir.tag == EXPR and ir.s == String("list"),
        String("got ") + ir.to_string(),
    )
    t.eq_int(String("declares four candidate writes"), ir.len(), 4)

    # exception/respond must not appear. Level 0 detects; Strategy responds.
    var rendered = ir.to_string()
    t.check(
        String("policy never emits respond"),
        rendered.find("respond") == -1,
        String("Level 0 must not respond to deviations"),
    )
    t.check(
        String("policy does emit detect"),
        rendered.find("detect") >= 0,
        String("expected a detect branch"),
    )
```

- [ ] **Step 2: Register the suite**

In `tests/run_all.mojo` add `import tests.test_policy_doc as test_policy_doc` and call
`test_policy_doc.run(t)` after `test_write.run(t)`. `main()` already declares `raises`.

- [ ] **Step 3: Run the test to verify it fails**

Run: `./run_tests.sh`
Expected: FAIL — the file `models/writes-default.yaml` does not exist.

- [ ] **Step 4: Write the policy document**

Create `models/writes-default.yaml`:

```yaml
# The default write policy.
#
# Every state write in a Level 0 run gets a Libera address from this document.
# It is data, not code: the runtime evaluates it with the kernel and filters on the
# declared `when`, so no semantic judgment lives in Mojo.
#
# Props available here: state, next, output, result, event{is_first, step}.
# Slots resolve against the frame {contract, result, verdict, state, next, snapshot}.
#
# Note what is absent: exception/respond. Responding to a deviation means choosing
# what to try next, and that is Strategy's job (doc section 4). If a Level 0 run ever
# emits respond, planning has leaked into Domain.

model: writes-default
version: 0.1

expressions:

  writes:
    list:

      # The contract comes into scope on the first fold.
      - record:
          when:
            ref: event.is_first
          pressure: boundary
          operation: enter
          slot: contract.expected

      # The supplied result alters state.
      - record:
          when: true
          pressure: movement
          operation: change
          slot: result.actual

      # Conformance either advances the work or reveals a deviation.
      - record:
          when: true
          pressure:
            if:
              condition:
                ref: output.conforms
              then: movement
              else: exception
          operation:
            if:
              condition:
                ref: output.conforms
              then: advance
              else: detect
          slot: verdict.conforms

      # Convergence takes the work out of scope.
      - record:
          when:
            ref: next.converged
          pressure: boundary
          operation: exit
          slot: snapshot
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./run_tests.sh`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add models/writes-default.yaml tests/test_policy_doc.mojo tests/run_all.mojo
git commit -m "Add the default write policy as a model document

The policy is declared data evaluated by the kernel, not Mojo logic, so
the runtime makes no semantic judgments of its own. exception/respond is
absent by construction -- Level 0 detects, Strategy responds."
```

---

### Task 4: Policy evaluation and emission

**Files:**
- Create: `domain/emit.mojo`
- Create: `tests/test_emit.mojo`
- Modify: `tests/run_all.mojo`

**Interfaces:**
- Consumes: `kernel.eval.evaluate`, `kernel.eval.resolve`, `address.grammar.address`,
  `address.write.write`, `modelir.yaml.parse_yaml_file`,
  `modelir.compile.compile_expression`
- Produces:
  - `fn load_policy(path: String) raises -> Value`
  - `fn policy_props(state: Value, next: Value, result: Value, output: Value, is_first: Bool, step: Int) -> Value`
  - `fn slot_frame(contract: Value, result: Value, verdict: Value, state: Value, next: Value, snapshot: Value) -> Value`
  - `fn emit(policy: Value, program: String, props: Value, frame: Value, step: Int, var prev: String) -> Value`
  - `fn derive_classification(writes: Value) -> Value`
  - `comptime E_EMIT = "emit_error"`

**Why this lives in `domain/`:** `policy_props` binds `output` and `slot_frame` binds
`verdict`. Both name Domain vocabulary, so this module cannot sit in `address/` without
failing Task 6.

- [ ] **Step 1: Write the failing test**

Create `tests/test_emit.mojo`:

```mojo
"""Tests for write policy evaluation.

These build the props and frame directly rather than running a full Domain cycle, so a
failure here points at emission rather than at orchestration.
"""

from std.collections import List, Dict

from kernel.value import Value, LIST, RECORD, SYMBOL
from kernel.ir import kv, rec, sym
from domain.emit import (
    load_policy,
    policy_props,
    slot_frame,
    emit,
    derive_classification,
    E_EMIT,
)
from address.grammar import render
from address.write import chain_is_intact
from testkit.harness import TestSuite


comptime POLICY_PATH = "models/writes-default.yaml"


fn _contract() -> Value:
    return rec(kv(String("expected"), rec(kv(String("count"), Value.int(3)))))


fn _result(n: Int) -> Value:
    return rec(kv(String("actual"), rec(kv(String("count"), Value.int(n)))))


fn _verdict(conforms: Bool) -> Value:
    return rec(
        kv(String("conforms"), Value.bool(conforms)),
        kv(String("expected"), Value.int(3)),
        kv(String("actual"), Value.int(2)),
    )


fn _state(converged: Bool) -> Value:
    return rec(
        kv(String("contract"), _contract()),
        kv(String("converged"), Value.bool(converged)),
    )


fn run(mut t: TestSuite) raises:
    var policy = load_policy(String(POLICY_PATH))
    _loading(t, policy)
    _trace_a(t, policy)
    _trace_b(t, policy)
    _classification(t)
    _failures(t, policy)


fn _loading(mut t: TestSuite, policy: Value):
    t.section(String("emit / policy loading"))
    t.not_error(String("default policy loads"), policy)


fn _trace_a(mut t: TestSuite, policy: Value):
    t.section(String("emit / trace A -- first fold, non-conforming"))

    var result = _result(2)
    var verdict = _verdict(False)
    var next = _state(False)
    var props = policy_props(_state(False), next, result, verdict, True, 0)
    var frame = slot_frame(
        _contract(), result, verdict, _state(False), next, Value.null()
    )
    var writes = emit(policy, String("prog"), props, frame, 0, String(""))

    t.not_error(String("emission succeeds"), writes)
    t.eq_int(String("three writes on the first fold"), writes.len(), 3)

    t.eq_str(
        String("contract enters scope"),
        render(writes.at(0).get(String("address"))),
        String("boundary/enter/contract.expected"),
    )
    t.eq_str(
        String("result changes state"),
        render(writes.at(1).get(String("address"))),
        String("movement/change/result.actual"),
    )
    t.eq_str(
        String("deviation is detected"),
        render(writes.at(2).get(String("address"))),
        String("exception/detect/verdict.conforms"),
    )

    # Values are resolved from the frame, not declared in the policy.
    t.eq_value(
        String("enter carries the expected count"),
        writes.at(0).get(String("value")),
        rec(kv(String("count"), Value.int(3))),
    )
    t.eq_value(
        String("change carries the actual count"),
        writes.at(1).get(String("value")),
        rec(kv(String("count"), Value.int(2))),
    )
    t.eq_value(
        String("detect carries the conformance"),
        writes.at(2).get(String("value")),
        Value.bool(False),
    )

    t.check(
        String("the emitted chain is intact"),
        chain_is_intact(writes, String("")),
        String("chain broken: ") + writes.to_string(),
    )
    # An address renders as a record, so `to_string()` never contains the slash form.
    # Match on the bare operation symbol instead.
    t.check(
        String("no snapshot write before convergence"),
        writes.to_string().find("exit") == -1,
        String("exit emitted early"),
    )


fn _trace_b(mut t: TestSuite, policy: Value):
    t.section(String("emit / trace B -- later fold, conforming"))

    var result = _result(3)
    var verdict = _verdict(True)
    var next = _state(True)
    var snapshot = rec(kv(String("final_verdict"), verdict))
    var props = policy_props(_state(False), next, result, verdict, False, 1)
    var frame = slot_frame(
        _contract(), result, verdict, _state(False), next, snapshot
    )
    var writes = emit(
        policy, String("prog"), props, frame, 1, String("path.earlier#0")
    )

    t.not_error(String("emission succeeds"), writes)
    # Not the first fold, so no enter; converged, so an exit. Candidates 2, 3 and 4
    # all fire.
    t.eq_int(String("three writes on a converging fold"), writes.len(), 3)
    t.eq_str(
        String("result changes state"),
        render(writes.at(0).get(String("address"))),
        String("movement/change/result.actual"),
    )
    t.eq_str(
        String("conformance advances"),
        render(writes.at(1).get(String("address"))),
        String("movement/advance/verdict.conforms"),
    )
    t.eq_str(
        String("work leaves scope"),
        render(writes.at(2).get(String("address"))),
        String("boundary/exit/snapshot"),
    )
    t.eq_value(
        String("advance carries a true conformance"),
        writes.at(1).get(String("value")),
        Value.bool(True),
    )

    t.check(
        String("continuation chain is intact"),
        chain_is_intact(writes, String("path.earlier#0")),
        String("chain broken: ") + writes.to_string(),
    )
    t.check(
        String("step is carried onto each write"),
        writes.at(0).get(String("step")).equals(Value.int(1)),
        String("wrong step"),
    )


fn _classification(mut t: TestSuite):
    t.section(String("emit / classification is derived"))

    var exceptional = List[Value]()
    exceptional.append(
        rec(
            kv(
                String("address"),
                rec(kv(String("pressure"), sym(String("exception")))),
            )
        )
    )
    t.eq_value(
        String("an exception pressure yields exception"),
        derive_classification(Value.list(exceptional^)),
        sym(String("exception")),
    )

    var clean = List[Value]()
    clean.append(
        rec(
            kv(
                String("address"),
                rec(kv(String("pressure"), sym(String("movement")))),
            )
        )
    )
    clean.append(
        rec(
            kv(
                String("address"),
                rec(kv(String("pressure"), sym(String("boundary")))),
            )
        )
    )
    t.eq_value(
        String("no exception pressure yields confirmed"),
        derive_classification(Value.list(clean^)),
        sym(String("confirmed")),
    )
    t.eq_value(
        String("an empty log is confirmed"),
        derive_classification(Value.list(List[Value]())),
        sym(String("confirmed")),
    )


fn _failures(mut t: TestSuite, policy: Value):
    t.section(String("emit / failures"))

    # A slot that does not resolve is a policy error, caught at emission. This is
    # what makes a slot a Ref rather than a decorative string.
    var props = policy_props(
        _state(False), _state(False), _result(2), _verdict(False), True, 0
    )
    var bare = slot_frame(
        Value.empty_record(),
        _result(2),
        _verdict(False),
        _state(False),
        _state(False),
        Value.null(),
    )
    t.is_error(
        String("an unresolvable slot fails emission"),
        emit(policy, String("prog"), props, bare, 0, String("")),
        String("unresolved_ref"),
    )

    t.is_error(
        String("a policy returning a non-list is rejected"),
        emit(_not_a_policy(), String("prog"), props, bare, 0, String("")),
        String(E_EMIT),
    )


fn _not_a_policy() -> Value:
    """A 'policy' that evaluates to a scalar rather than a list of candidates."""
    return Value.int(1)
```

- [ ] **Step 2: Register the suite**

In `tests/run_all.mojo` add `import tests.test_emit as test_emit` and call
`test_emit.run(t)` after `test_policy_doc.run(t)`.

- [ ] **Step 3: Run the test to verify it fails**

Run: `./run_tests.sh`
Expected: FAIL — `unable to locate module 'domain.emit'`

- [ ] **Step 4: Write the implementation**

Create `domain/emit.mojo`:

```mojo
"""Evaluate a write policy and emit addressed Writes.

This is the seam between Domain and the address layer. It binds Domain props
(`output`, `verdict`) and so must live here rather than in `address/` -- the address
layer may not name Domain vocabulary.

The runtime decides nothing semantic. It evaluates a declared expression, drops
candidates whose declared `when` is false, and resolves each slot against a frame.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD, LIST, SYMBOL, STRING
from kernel.eval import evaluate, resolve
from modelir.yaml import parse_yaml_file
from modelir.compile import compile_expression
from address.grammar import address
from address.write import write


comptime E_EMIT = "emit_error"


fn load_policy(path: String) raises -> Value:
    """Load and compile `expressions.writes` from a policy document.

    Policy documents have no `contract:`, so they do not go through `DomainModel`.
    """
    var root = parse_yaml_file(path)
    if root.is_error():
        return root^
    if root.tag != RECORD or not root.has(String("expressions")):
        return Value.error(
            String(E_EMIT), String("policy document has no 'expressions'")
        )
    var exprs = root.get(String("expressions"))
    if not exprs.has(String("writes")):
        return Value.error(
            String(E_EMIT), String("policy document has no 'expressions.writes'")
        )
    return compile_expression(exprs.get(String("writes")))


fn policy_props(
    state: Value,
    next: Value,
    result: Value,
    output: Value,
    is_first: Bool,
    step: Int,
) -> Value:
    """The environment a write policy may reference."""
    var ev = Dict[String, Value]()
    ev[String("is_first")] = Value.bool(is_first)
    ev[String("step")] = Value.int(step)

    var d = Dict[String, Value]()
    d[String("state")] = state.copy()
    d[String("next")] = next.copy()
    d[String("result")] = result.copy()
    d[String("output")] = output.copy()
    d[String("event")] = Value.record(ev^)
    return Value.record(d^)


fn slot_frame(
    contract: Value,
    result: Value,
    verdict: Value,
    state: Value,
    next: Value,
    snapshot: Value,
) -> Value:
    """The environment a slot resolves against to obtain its value."""
    var d = Dict[String, Value]()
    d[String("contract")] = contract.copy()
    d[String("result")] = result.copy()
    d[String("verdict")] = verdict.copy()
    d[String("state")] = state.copy()
    d[String("next")] = next.copy()
    d[String("snapshot")] = snapshot.copy()
    return Value.record(d^)


fn emit(
    policy: Value,
    program: String,
    props: Value,
    frame: Value,
    step: Int,
    var prev: String,
) -> Value:
    """Evaluate the policy and return a LIST Value of Writes, or an Error."""
    var candidates = evaluate(policy, props)
    if candidates.is_error():
        return candidates^
    if candidates.tag != LIST:
        return Value.error(
            String(E_EMIT),
            String("write policy must return a list, got ")
            + candidates.to_string(),
        )

    var out = List[Value]()
    var last = prev^

    for k in range(candidates.len()):
        var c = candidates.at(k)
        if c.tag != RECORD:
            return Value.error(
                String(E_EMIT),
                String("write candidate must be a record, got ") + c.to_string(),
            )

        var when = c.get_or(String("when"), Value.bool(True))
        if when.is_error():
            return when^
        if not when.truthy():
            continue

        var pressure = c.get(String("pressure"))
        if pressure.is_error():
            return pressure^
        var operation = c.get(String("operation"))
        if operation.is_error():
            return operation^
        var slot = c.get(String("slot"))
        if slot.is_error():
            return slot^

        if not pressure.is_text() or not operation.is_text() or not slot.is_text():
            return Value.error(
                String(E_EMIT),
                String("pressure, operation and slot must be names, got ")
                + c.to_string(),
            )

        var addr = address(
            program.copy(),
            pressure.s.copy(),
            operation.s.copy(),
            slot.s.copy(),
        )
        if addr.is_error():
            return addr^

        # A slot that does not resolve is a policy error, not a silent null.
        var value = resolve(addr.get(String("slot")), frame)
        if value.is_error():
            return value^

        var w = write(addr, value, step, last.copy())
        if w.is_error():
            return w^
        last = w.get(String("id")).s.copy()
        out.append(w^)

    return Value.list(out^)


fn derive_classification(writes: Value) -> Value:
    """Classification follows from the pressures emitted, not from a hand-written
    expression: any exception pressure makes the fold an exception."""
    if writes.tag != LIST:
        return Value.symbol(String("confirmed"))
    for k in range(writes.len()):
        var p = writes.at(k).get(String("address")).get(String("pressure"))
        if p.is_text() and p.s == "exception":
            return Value.symbol(String("exception"))
    return Value.symbol(String("confirmed"))
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./run_tests.sh`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add domain/emit.mojo tests/test_emit.mojo tests/run_all.mojo
git commit -m "Evaluate write policies and emit addressed writes

Lives in domain/ because it binds output and verdict props; putting it in
address/ would fail the layering test. An unresolvable slot fails emission
rather than yielding null, which is what makes a slot a Ref rather than a
decorative string."
```

---

### Task 5: Thread writes through the Domain run

**Files:**
- Modify: `domain/run.mojo`
- Modify: `tests/test_domain.mojo`
- Modify: `models/domain-count-level-0.yaml`

**Interfaces:**
- Consumes: everything from Tasks 1–4
- Produces:
  - `fn step_with_writes(model: DomainModel, policy: Value, state: Value, result: Value, step_index: Int, var prev: String) -> Value` returning `{state, writes}`
  - `run(model, results)` gains a `policy` parameter and returns `trace` as a write log

- [ ] **Step 1: Write the failing test**

Append to `tests/test_domain.mojo` this helper and a new section, and call the section
from `run`:

```mojo
fn _count_operation(trace: Value, var op: String) -> Int:
    """How many writes in the log carry this operation."""
    var n = 0
    for k in range(trace.len()):
        var o = trace.at(k).get(String("address")).get(String("operation"))
        if o.is_text() and o.s == op:
            n += 1
    return n


fn _addressed_writes(mut t: TestSuite, model: DomainModel) raises:
    t.section(String("domain / writes carry addresses"))

    var policy = load_policy(String("models/writes-default.yaml"))
    var results = List[Value]()
    results.append(_count_result(2))
    results.append(_count_result(3))
    var outcome = run_domain(model, policy, results)

    t.not_error(String("run completes"), outcome)
    t.eq_value(
        String("run converges"),
        outcome.get(String("converged")),
        Value.bool(True),
    )

    # Three writes per fold. Fold 0: enter (first fold), change, detect. Fold 1: no
    # enter, change, advance, exit (converged). Six in total.
    var trace = outcome.get(String("trace"))
    t.eq_int(String("six writes across two folds"), trace.len(), 6)
    t.eq_str(
        String("write 0 -- contract enters"),
        render(trace.at(0).get(String("address"))),
        String("boundary/enter/contract.expected"),
    )
    t.eq_str(
        String("write 1 -- result changes"),
        render(trace.at(1).get(String("address"))),
        String("movement/change/result.actual"),
    )
    t.eq_str(
        String("write 2 -- deviation detected"),
        render(trace.at(2).get(String("address"))),
        String("exception/detect/verdict.conforms"),
    )
    t.eq_str(
        String("write 3 -- result changes again"),
        render(trace.at(3).get(String("address"))),
        String("movement/change/result.actual"),
    )
    t.eq_str(
        String("write 4 -- conformance advances"),
        render(trace.at(4).get(String("address"))),
        String("movement/advance/verdict.conforms"),
    )
    t.eq_str(
        String("write 5 -- work leaves scope"),
        render(trace.at(5).get(String("address"))),
        String("boundary/exit/snapshot"),
    )

    # `enter` fires exactly once even though two folds run.
    t.eq_int(
        String("contract enters scope only once"),
        _count_operation(trace, String("enter")),
        1,
    )
    t.eq_int(
        String("result changes once per fold"),
        _count_operation(trace, String("change")),
        2,
    )

    t.check(
        String("the whole log is one intact chain"),
        chain_is_intact(trace, String("")),
        String("chain broken"),
    )

    # Level 0 discipline, now assertable by address.
    t.check(
        String("no exception/respond is ever emitted"),
        trace.to_string().find("respond") == -1,
        String("planning has leaked into Domain"),
    )

    # Classification is derived, and still agrees with what the doc's traces say.
    t.eq_value(
        String("first fold classifies as exception"),
        outcome.get(String("classifications")).at(0),
        sym(String("exception")),
    )
    t.eq_value(
        String("second fold classifies as confirmed"),
        outcome.get(String("classifications")).at(1),
        sym(String("confirmed")),
    )

    # A conforming-only run never emits an exception pressure.
    var quick = List[Value]()
    quick.append(_count_result(3))
    var fast = run_domain(model, policy, quick)
    t.check(
        String("a conforming run emits no exception pressure"),
        fast.get(String("trace")).to_string().find("exception") == -1,
        String("unexpected exception pressure"),
    )
```

Add to the imports at the top of `tests/test_domain.mojo`:

```mojo
from domain.emit import load_policy
from domain.run import step_with_writes
from address.grammar import render
from address.write import chain_is_intact
```

and add `_addressed_writes(t, model)` to `fn run(mut t: TestSuite) raises:`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `./run_tests.sh`
Expected: FAIL — `run_domain` takes 2 arguments, not 3; `step_with_writes` not found.

- [ ] **Step 3: Update the model document to stop hand-computing classification**

In `models/domain-count-level-0.yaml`, delete the `classification:` block from
`orchestrate` (the six lines beginning `classification:` through `else: exception`).
Leave `contract`, `result`, `verdict`, and `converged` as they are.

Add this comment in its place:

```yaml
      # classification is not declared here: it is derived from the emitted
      # pressures. `movement/advance` is confirmed; `exception/detect` is an
      # exception. Declaring it as well would be two sources of truth.
```

- [ ] **Step 4: Write the implementation**

In `domain/run.mojo`, add these imports at the top:

```mojo
from domain.emit import (
    policy_props,
    slot_frame,
    emit,
    derive_classification,
)
from address.write import last_id
```

Add `step_with_writes` immediately after the existing `step`:

```mojo
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
```

Replace the body of `run` with:

```mojo
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
```

- [ ] **Step 5: Update the existing trace assertions**

The old `trace` held one entry per step; it now holds one entry per write. In
`tests/test_domain.mojo`, inside `_convergence_and_snapshot`, replace these three
assertions:

```mojo
    t.eq_int(String("trace has two entries"), outcome.get(String("trace")).len(), 2)
    t.eq_value(
        String("first trace entry is an exception"),
        outcome.get(String("trace")).at(0).get(String("classification")),
        sym(String("exception")),
    )
    t.eq_value(
        String("second trace entry is confirmed"),
        outcome.get(String("trace")).at(1).get(String("classification")),
        sym(String("confirmed")),
    )
```

with:

```mojo
    t.eq_int(String("trace holds six writes"), outcome.get(String("trace")).len(), 6)
    t.eq_value(
        String("first fold classifies as exception"),
        outcome.get(String("classifications")).at(0),
        sym(String("exception")),
    )
    t.eq_value(
        String("second fold classifies as confirmed"),
        outcome.get(String("classifications")).at(1),
        sym(String("confirmed")),
    )
```

Then update every remaining `run_domain(model, <results>)` call in that file to
`run_domain(model, policy, <results>)`, and add at the top of each affected section a
policy load:

```mojo
    var policy = load_policy(String("models/writes-default.yaml"))
```

Affected sections: `_convergence_and_snapshot`, `_no_planning`. Both must become
`raises` and be called as such from `run`.

In `_no_planning`, replace the trace-length assertion:

```mojo
    t.eq_int(
        String("every supplied result was verified"),
        outcome.get(String("trace")).len(),
        3,
    )
```

with:

```mojo
    t.eq_int(
        String("every supplied result was verified"),
        outcome.get(String("classifications")).len(),
        3,
    )
```

and replace the final trace assertion:

```mojo
    t.eq_value(
        String("every step classified as exception"),
        outcome.get(String("trace")).at(2).get(String("classification")),
        sym(String("exception")),
    )
```

with:

```mojo
    t.eq_value(
        String("every step classified as exception"),
        outcome.get(String("classifications")).at(2),
        sym(String("exception")),
    )
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `./run_tests.sh`
Expected: PASS, 0 failures. Traces A and B must still assert exactly as before —
`classification` is now derived, and must produce the same `exception` / `confirmed`
values the doc's traces specify.

- [ ] **Step 7: Mutation-test the policy**

Prove the new tests are not vacuous, the way the domain model was verified:

```bash
cp models/writes-default.yaml /tmp/policy.bak
sed -i '' 's/          operation: change/          operation: advance/' models/writes-default.yaml
./run_tests.sh 2>&1 | grep -E "^FAILED|^PASSED"
cp /tmp/policy.bak models/writes-default.yaml
sed -i '' 's/              then: movement/              then: exception/' models/writes-default.yaml
./run_tests.sh 2>&1 | grep -E "^FAILED|^PASSED"
cp /tmp/policy.bak models/writes-default.yaml
./run_tests.sh 2>&1 | grep -E "^FAILED|^PASSED"
diff /tmp/policy.bak models/writes-default.yaml && echo "policy restored"
```

Expected: the first two runs FAIL, the third PASSES, and the diff is empty. If a
mutation does not fail, the tests are not actually reading the policy — fix them before
committing.

- [ ] **Step 8: Commit**

```bash
git add domain/run.mojo tests/test_domain.mojo models/domain-count-level-0.yaml
git commit -m "Thread addressed writes through the Domain run

The trace becomes a write log with one unbroken prev chain across folds.
classification is no longer hand-computed in the model -- it is derived
from the emitted pressures, so there is one source of truth. Level 0
discipline is now assertable by address: no exception/respond is emitted."
```

---

### Task 6: Layering and conformance tests

**Files:**
- Create: `tests/test_layering.mojo`
- Create: `tests/fixtures/libera.schema.yaml`
- Modify: `tests/run_all.mojo`

**Interfaces:**
- Consumes: `modelir.yaml.parse_yaml_file`, `address.grammar.is_pressure`,
  `address.grammar.valid_pair`

**Design note — why imports, not words.** The spec called for a test that fails if
`kernel/` mentions "contract" or "pressure". That produces immediate false positives:
`kernel/value.mojo`'s own docstring reads *"Contracts, results, verdicts, states … are
all Values."* The enforceable form is the **import direction**, which is the actual
dependency rule and cannot be tripped by prose.

- [ ] **Step 1: Vendor the schema fixture**

Create `tests/fixtures/libera.schema.yaml` with the v2 schema, verbatim from
`github.com/jeremycapps/libera` at `protocol/libera.schema.yaml`:

```yaml
version: 2

path_format: "{pressure}/{operation}/{slot}"

pressures:
  boundary:
    description: Work crosses a program boundary.
    operations:
      enter: Something comes into scope.
      exit: Something leaves scope or becomes output.

  movement:
    description: Work moves or changes inside a program.
    operations:
      advance: Something moves forward.
      change: Something is altered.

  exception:
    description: Work deviates from expected state.
    operations:
      detect: Deviation is identified.
      respond: Deviation is acted on.

path:
  required:
    - program
    - pressure
    - operation
    - slot
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_layering.mojo`:

```mojo
"""Two guards on the architecture itself.

Layering: merging the runtimes gave up Libera's repo-level enforcement of its scope
boundaries. This replaces it -- a module may not import from a layer above it.

Conformance: the address vocabulary is checked against the published v2 schema, so the
runtime cannot drift from the spec it implements.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD
from modelir.yaml import parse_yaml_file
from address.grammar import is_pressure, is_operation, valid_pair
from testkit.harness import TestSuite


comptime SCHEMA_PATH = "tests/fixtures/libera.schema.yaml"


fn _read(path: String) raises -> String:
    with open(path, "r") as f:
        return f.read()


fn _imports_from(source: String, package: String) -> Bool:
    """True if the source imports from the named package."""
    return (
        source.find(String("from ") + package + String(".")) >= 0
        or source.find(String("import ") + package + String(".")) >= 0
    )


fn run(mut t: TestSuite) raises:
    _layering(t)
    _conformance(t)


fn _layering(mut t: TestSuite) raises:
    t.section(String("layering / a module may not import from above"))

    var kernel_files = List[String]()
    kernel_files.append(String("kernel/value.mojo"))
    kernel_files.append(String("kernel/eval.mojo"))
    kernel_files.append(String("kernel/ir.mojo"))

    var above_kernel = List[String]()
    above_kernel.append(String("modelir"))
    above_kernel.append(String("address"))
    above_kernel.append(String("domain"))

    for f in range(len(kernel_files)):
        var src = _read(kernel_files[f])
        for p in range(len(above_kernel)):
            t.check(
                kernel_files[f] + String(" does not import ") + above_kernel[p],
                not _imports_from(src, above_kernel[p]),
                String("the kernel must know nothing above it"),
            )

    var address_files = List[String]()
    address_files.append(String("address/grammar.mojo"))
    address_files.append(String("address/write.mojo"))

    for f in range(len(address_files)):
        var src = _read(address_files[f])
        t.check(
            address_files[f] + String(" does not import domain"),
            not _imports_from(src, String("domain")),
            String("the address layer must not name Domain vocabulary"),
        )
        # The policy evaluator lives in domain/emit.mojo precisely because it binds
        # verdict props. If it ever moves here, this catches it.
        t.check(
            address_files[f] + String(" does not mention conforms"),
            src.find(String("conforms")) == -1,
            String("conformance is a Domain concept"),
        )
        t.check(
            address_files[f] + String(" does not mention verdict"),
            src.find(String("verdict")) == -1,
            String("Verdict is a Domain concept"),
        )


fn _conformance(mut t: TestSuite) raises:
    t.section(String("conformance / vocabulary matches the published v2 schema"))

    var schema = parse_yaml_file(String(SCHEMA_PATH))
    t.not_error(String("schema fixture parses"), schema)
    t.eq_value(
        String("fixture is schema version 2"),
        schema.get(String("version")),
        Value.int(2),
    )
    t.eq_str(
        String("path format matches"),
        schema.get(String("path_format")).s,
        String("{pressure}/{operation}/{slot}"),
    )

    var pressures = schema.get(String("pressures"))
    t.eq_int(String("schema declares three pressures"), pressures.len(), 3)

    var seen_operations = 0
    for key in pressures.fields[].keys():
        var p = key.copy()
        t.check(
            String("schema pressure '") + p + String("' is recognised"),
            is_pressure(p),
            String("runtime does not know this pressure"),
        )
        var ops = pressures.get(p).get(String("operations"))
        for okey in ops.fields[].keys():
            var o = okey.copy()
            seen_operations += 1
            t.check(
                String("schema operation '") + o + String("' is recognised"),
                is_operation(o),
                String("runtime does not know this operation"),
            )
            t.check(
                String("pair ") + p + String("/") + o + String(" is valid"),
                valid_pair(p, o),
                String("runtime rejects a pair the schema declares"),
            )

    t.eq_int(String("schema declares six operations"), seen_operations, 6)

    var required = schema.get(String("path")).get(String("required"))
    t.eq_int(String("four required path fields"), required.len(), 4)
    var required_text = required.to_string()
    t.check(
        String("program is required"),
        required_text.find(String("program")) >= 0,
        String("program missing from required fields"),
    )
    t.check(
        String("slot is required"),
        required_text.find(String("slot")) >= 0,
        String("slot missing from required fields"),
    )
```

- [ ] **Step 3: Register the suite**

In `tests/run_all.mojo` add `import tests.test_layering as test_layering` and call
`test_layering.run(t)` last.

- [ ] **Step 4: Run the tests**

Run: `./run_tests.sh`
Expected: PASS, 0 failures. If the layering test fails, **do not weaken the test** —
move the offending import instead. That is the test doing its job.

- [ ] **Step 5: Verify the conformance test can fail**

```bash
cp tests/fixtures/libera.schema.yaml /tmp/schema.bak
python3 - <<'PY'
p='tests/fixtures/libera.schema.yaml'
s=open(p).read().replace("      detect: Deviation is identified.","      notice: Deviation is identified.")
open(p,'w').write(s)
PY
./run_tests.sh 2>&1 | grep -E "^FAILED|^PASSED"
cp /tmp/schema.bak tests/fixtures/libera.schema.yaml
./run_tests.sh 2>&1 | grep -E "^FAILED|^PASSED"
```

Expected: FAILED then PASSED. A conformance test that passes against a mutated schema is
checking nothing.

- [ ] **Step 6: Commit**

```bash
git add tests/test_layering.mojo tests/fixtures tests/run_all.mojo
git commit -m "Add layering and schema conformance tests

Layering is enforced by import direction rather than by word search --
kernel/value.mojo's own docstring mentions contracts and verdicts, so a
grep would false-positive immediately. The address layer is additionally
checked for Domain vocabulary, since that is where a policy evaluator
would wrongly drift.

Conformance parses the vendored v2 schema with our own YAML reader and
checks every pressure, operation, and pair against the runtime."
```

---

## Verification

After all six tasks:

```bash
./run_tests.sh
```

Expected: PASS, roughly 560 assertions, 0 failures. The original 416 must all still pass
except the six trace assertions explicitly rewritten in Task 5.

Confirm the architecture claims hold:

```bash
git log --oneline da5cdc6..HEAD -- kernel/
```

Expected: **empty** (`da5cdc6` is the commit this plan starts from). The spec claims this
layer needs no kernel changes; if any commit touched `kernel/`, something was designed
wrong and should be raised rather than quietly committed.

## Out of scope

Blocked on spec §7 (repo naming and publishing), which is deliberately open:

- Folding `protocol/` into the repo as published spec text (the schema is vendored as a
  test fixture only)
- Folding `docs/fields.md` in as the governance vocabulary reference
- `evidence` and `authority` on writes — both belong to `respond`, which Level 0 never
  emits
- Strategy: operators, goals, boundaries, heuristics, `exception/respond`

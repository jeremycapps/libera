"""DomainModel: a YAML model object loaded into Model IR.

Doc 3: *Domain is not Mojo code. Domain is a YAML model object that compiles
into Model IR and is evaluated by the Mojo kernel.* This struct is therefore
deliberately thin -- it holds the compiled Contract and the named expressions,
and knows where to find the verifier and the orchestrator. Every semantic
decision (what conformance means, how state folds, what counts as converged)
lives in the YAML, not here.

Document shape
--------------

    model: domain-count-level-0
    version: 0.1
    contract:
      expected:
        count: 3
    expressions:
      verify: <expression>
      orchestrate: <expression>

The verifier is taken from `contract.verifier` when present, falling back to
`expressions.verify`. Doc 3.1 gives Contract the shape `{ expected, verifier? }`
while doc 3.3 writes the verifier under `expressions:`; supporting both means a
model can put the verifier wherever it reads better without the runtime caring.
"""

from std.collections import List, Dict

from kernel.value import Value, RECORD
from modelir.yaml import parse_yaml, parse_yaml_file
from modelir.compile import compile_expression


comptime E_MODEL = "model_error"


struct DomainModel(ImplicitlyCopyable, Copyable, Movable):
    var name: String
    var version: Value
    var contract: Value
    var expressions: Value
    var error: Value
    """Non-null when loading failed; every accessor then returns it."""

    fn __init__(out self):
        self.name = String("")
        self.version = Value.null()
        self.contract = Value.empty_record()
        self.expressions = Value.empty_record()
        self.error = Value.null()

    fn is_valid(self) -> Bool:
        return not self.error.is_error()

    # --- Domain objects ----------------------------------------------------

    fn expected(self) -> Value:
        """`Contract.expected` -- what is supposed to be true."""
        if not self.is_valid():
            return self.error.copy()
        return self.contract.get(String("expected"))

    fn verifier(self) -> Value:
        """The expression that decides conformance."""
        if not self.is_valid():
            return self.error.copy()
        if self.contract.has(String("verifier")):
            return self.contract.get(String("verifier"))
        if self.expressions.has(String("verify")):
            return self.expressions.get(String("verify"))
        return Value.error(
            String(E_MODEL),
            String(
                "model declares no verifier: expected contract.verifier or"
                " expressions.verify"
            ),
        )

    fn orchestrator(self) -> Value:
        """The expression that folds an output into CurrentState."""
        if not self.is_valid():
            return self.error.copy()
        if self.expressions.has(String("orchestrate")):
            return self.expressions.get(String("orchestrate"))
        return Value.error(
            String(E_MODEL),
            String("model declares no expressions.orchestrate"),
        )

    fn expression(self, name: String) -> Value:
        """Any named expression, for models that declare more than the two."""
        if not self.is_valid():
            return self.error.copy()
        if self.expressions.has(name):
            return self.expressions.get(name)
        return Value.error(
            String(E_MODEL),
            String("model declares no expressions.") + name,
        )


fn _invalid(var message: String) -> DomainModel:
    var m = DomainModel()
    m.error = Value.error(String(E_MODEL), message^)
    return m^


fn domain_model_from_value(root: Value) -> DomainModel:
    """Build a model from an already-parsed YAML tree."""
    if root.is_error():
        var m = DomainModel()
        m.error = root.copy()
        return m^
    if root.tag != RECORD:
        return _invalid(
            String("model document must be a mapping, got ") + root.to_string()
        )
    if not root.has(String("contract")):
        return _invalid(String("model document has no 'contract'"))

    var m = DomainModel()

    if root.has(String("model")):
        var n = root.get(String("model"))
        m.name = n.s.copy() if n.is_text() else n.to_string()
    if root.has(String("version")):
        m.version = root.get(String("version"))

    # The contract is data, but may carry a `verifier` expression, so it goes
    # through the compiler like everything else.
    m.contract = compile_expression(root.get(String("contract")))
    if m.contract.is_error():
        var bad = DomainModel()
        bad.error = m.contract.copy()
        return bad^
    if m.contract.tag != RECORD:
        return _invalid(
            String("contract must be a mapping, got ") + m.contract.to_string()
        )

    if root.has(String("expressions")):
        var raw = root.get(String("expressions"))
        if raw.tag != RECORD:
            return _invalid(
                String("expressions must be a mapping, got ") + raw.to_string()
            )
        # Each named expression compiles independently; a `verify:` whose value
        # is a single-key `record:` mapping becomes a record-construction form,
        # which is exactly the doc's 3.3 shape.
        var d = Dict[String, Value]()
        for key in raw.fields[].keys():
            var k = key.copy()
            var got = compile_expression(raw.fields[].get(k).value())
            if got.is_error():
                var bad = DomainModel()
                bad.error = got.copy()
                return bad^
            d[k] = got^
        m.expressions = Value.record(d^)

    return m^


fn domain_model_from_text(source: String) -> DomainModel:
    """Parse and compile a model document from YAML text."""
    return domain_model_from_value(parse_yaml(source))


fn load_domain_model(path: String) raises -> DomainModel:
    """Read, parse, and compile a model document from disk."""
    return domain_model_from_value(parse_yaml_file(path))

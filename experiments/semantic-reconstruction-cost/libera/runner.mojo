"""Method B driver for the semantic-reconstruction-cost experiment.

Loads a fixture, runs it through the exact same Contract -> Result -> Verdict
-> CurrentState protocol `tests/test_issue_model.mojo::_addressed_run` already
proves, and writes the write-log trace (plus the converged snapshot) to
`libera/snapshots/<fixture-basename>.txt`.

Not part of the test suite. Invoked by hand from the repository root:

    mojo run -I . experiments/semantic-reconstruction-cost/libera/runner.mojo \
        experiments/semantic-reconstruction-cost/fixtures/<name>.yaml
"""

from std.collections import List

from std.sys import argv

from kernel.value import Value
from domain.model import load_domain_model
from domain.emit import load_policy
from domain.run import make_result, run as run_domain
from modelir.yaml import parse_yaml_file
from address.write import chain_is_intact


comptime MODEL_PATH = "models/issue-completeness.yaml"
comptime POLICY_PATH = "models/writes-default.yaml"


fn _basename(path: String) -> String:
    """The final path segment, e.g. `a/b/issue-complete.yaml` -> `issue-complete.yaml`."""
    var parts = path.split("/")
    return String(parts[len(parts) - 1])


fn _fixture_stem(path: String) -> String:
    """The fixture's basename with its `.yaml` extension replaced by nothing,
    e.g. `issue-complete.yaml` -> `issue-complete`."""
    var name = _basename(path)
    var parts = name.split(".")
    if len(parts) < 2 or String(parts[len(parts) - 1]) != String("yaml"):
        return name
    var out = String("")
    for k in range(len(parts) - 1):
        if k > 0:
            out += "."
        out += String(parts[k])
    return out^


fn main() raises:
    var fixture_path = argv()[1]
    var model = load_domain_model(String(MODEL_PATH))
    var policy = load_policy(String(POLICY_PATH))
    var fixture = parse_yaml_file(String(fixture_path))

    var results = List[Value]()
    for k in range(fixture.len()):
        results.append(make_result(fixture.at(k), String("support")))

    var outcome = run_domain(model, policy, results)
    var trace = outcome.get(String("trace"))
    var chain_ok = chain_is_intact(trace, String(""))

    var out = String("chain_intact: ")
    if chain_ok:
        out += String("true")
    else:
        out += String("false")
    out += String("\n\ntrace:\n")
    out += trace.to_string()
    out += String("\n")

    if outcome.has(String("snapshot")):
        out += String("\nsnapshot:\n")
        out += outcome.get(String("snapshot")).to_string()
        out += String("\n")

    var stem = _fixture_stem(String(fixture_path))
    var out_path = String("experiments/semantic-reconstruction-cost/libera/snapshots/") + stem + String(".txt")
    with open(out_path, "w") as f:
        f.write(out)

    print(String("wrote ") + out_path)

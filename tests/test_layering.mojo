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

"""Two guards on the architecture itself.

Layering: merging the runtimes gave up Libera's repo-level enforcement of its scope
boundaries. This replaces it -- a module may not import from a layer above it.

Conformance: the address vocabulary is checked against the published v2 schema, so the
runtime cannot drift from the spec it implements.
"""

from std.collections import List, Dict
from std.os import listdir

from kernel.value import Value, RECORD
from modelir.yaml import parse_yaml_file
from address.grammar import is_pressure, is_operation, valid_pair
from testkit.harness import TestSuite


comptime SCHEMA_PATH = "tests/fixtures/libera.schema.yaml"

# Layer ordering, lowest first. A module in one layer may not import from any
# layer that comes after it in this list -- enumerated from the package
# directories themselves (via `listdir`) so a new file cannot escape the
# check the way a hardcoded list would let it.
comptime LAYER_ORDER_0 = "kernel"
comptime LAYER_ORDER_1 = "modelir"
comptime LAYER_ORDER_2 = "address"
comptime LAYER_ORDER_3 = "domain"


fn _read(path: String) raises -> String:
    with open(path, "r") as f:
        return f.read()


fn _imports_from(source: String, package: String) -> Bool:
    """True if the source imports from the named package."""
    return (
        source.find(String("from ") + package + String(".")) >= 0
        or source.find(String("import ") + package + String(".")) >= 0
    )


fn _mojo_files_in(var dir: String) raises -> List[String]:
    """Every `*.mojo` file directly under `dir`, as `dir/name.mojo` paths."""
    var entries = listdir(dir)
    var out = List[String]()
    for k in range(len(entries)):
        var name = entries[k]
        if name.endswith(".mojo"):
            var path = dir.copy()
            path += "/"
            path += name
            out.append(path^)
    return out^


fn run(mut t: TestSuite) raises:
    _layering(t)
    _conformance(t)


fn _layering(mut t: TestSuite) raises:
    t.section(String("layering / a module may not import from above"))

    var layers = List[String]()
    layers.append(String(LAYER_ORDER_0))
    layers.append(String(LAYER_ORDER_1))
    layers.append(String(LAYER_ORDER_2))
    layers.append(String(LAYER_ORDER_3))

    # Only the layers that own real package directories are enumerated and
    # checked; `domain` has nothing above it in this ordering, so it never
    # needs an "above" check, but it still participates as an upper bound
    # for the others.
    var checked_layers = 3

    for i in range(checked_layers):
        var package = layers[i]
        var files = _mojo_files_in(package)
        t.check(
            package + String(" directory listing is non-empty"),
            len(files) > 0,
            String("listdir returned no files -- the guard would be vacuous"),
        )

        for f in range(len(files)):
            var src = _read(files[f])
            for a in range(i + 1, len(layers)):
                var above = layers[a]
                t.check(
                    files[f] + String(" does not import ") + above,
                    not _imports_from(src, above),
                    String("a module may not import from a layer above it"),
                )

    var address_files = _mojo_files_in(String(LAYER_ORDER_2))
    t.check(
        String("address/ directory listing is non-empty"),
        len(address_files) > 0,
        String("listdir returned no files -- the guard would be vacuous"),
    )

    for f in range(len(address_files)):
        var src = _read(address_files[f])
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
        t.check(
            address_files[f] + String(" does not mention contract"),
            src.find(String("contract")) == -1,
            String("Contract is a Domain concept"),
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

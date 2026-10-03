import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import generate_wamp_flatbuffers as generator


class PinnedSchemaTests(unittest.TestCase):
    def test_pinned_inputs_and_append_only_extension(self):
        generator.verify_inputs(generator.ROOT)
        combined = generator.combined_schema(generator.ROOT)
        self.assertIn("    msg: AnyMessage (required);", combined)
        self.assertIn("    metadata: [ubyte];", combined)
        self.assertIn("    Yield,\n    Heartbeat\n", combined)
        self.assertNotIn('include "', combined)

    def test_heartbeat_preserves_nullable_control_presence(self):
        combined = generator.combined_schema(generator.ROOT)
        heartbeat = combined.split("table Heartbeat {", 1)[1].split("}", 1)[0]
        self.assertIn("presence: ubyte = 7;", heartbeat)

    def test_custom_challenge_method_is_an_append_only_string(self):
        combined = generator.combined_schema(generator.ROOT)
        challenge = combined.split("table Challenge\n{", 1)[1].split("}", 1)[0]
        self.assertLess(challenge.index("extra: Map;"), challenge.index("method_name: string;"))
        upstream = generator.combined_schema(generator.ROOT, extensions=False)
        self.assertNotIn("method_name: string;", upstream)

    def test_changed_upstream_input_is_rejected_before_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(generator.ROOT / generator.SCHEMA, root / generator.SCHEMA)
            path = root / generator.SCHEMA / "upstream/rpc.fbs"
            path.write_text(path.read_text().replace("table Call", "table BrokenCall"))
            with self.assertRaisesRegex(ValueError, "rpc.fbs"):
                generator.verify_inputs(root)

    def test_compiler_version_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(generator, "compiler_version", return_value="flatc version 1.0"):
                with self.assertRaisesRegex(ValueError, "Expected flatc version 25.9.23"):
                    generator.generate(generator.ROOT, "flatc", Path(directory))

    def test_fixture_discriminators_are_independent_of_wamp_ids(self):
        cases = json.loads((generator.ROOT / generator.SCHEMA / "fixtures.json").read_text())
        tags = {case["name"]: (case["union_tag"], case["wamp_id"]) for case in cases}
        self.assertEqual(tags["error"], (7, 8))
        self.assertEqual(tags["publish"], (8, 16))
        self.assertEqual(tags["call"], (16, 48))
        self.assertEqual(tags["heartbeat"], (26, 7))
        self.assertEqual({tag for tag, _ in tags.values()}, set(range(1, 27)))

    def test_validation_schema_preserves_union_slots_and_qualified_types(self):
        source = '''
            namespace wamp;
            table Map { key: string (key, required); }
            namespace wamp.proto;
            enum Method: uint8 { NONE = 0, TICKET = 4 }
            table Hello {
                roles: wamp.Map (required);
                authmethods: [Method];
                sessions: [uint64];
            }
            union AnyMessage { Hello }
            table Message { msg: AnyMessage (required); metadata: [ubyte]; }
        '''
        result = generator.validation_schema(source)
        self.assertIn("FlatBufferFieldSpec('key', FlatBufferFieldKind.string, 4, required: true)", result)
        self.assertIn("FlatBufferFieldSpec('roles', FlatBufferFieldKind.table, 4, required: true, reference: 0)", result)
        self.assertIn("FlatBufferFieldSpec('authmethods', FlatBufferFieldKind.scalarVector, 1, values: [0, 4])", result)
        self.assertIn("FlatBufferFieldSpec('sessions', FlatBufferFieldKind.scalarVector, 8, wampInteger: true)", result)
        self.assertIn("FlatBufferFieldSpec('msg_type', FlatBufferFieldKind.scalar, 1, values: [0, 1])", result)
        self.assertIn("FlatBufferFieldSpec('msg', FlatBufferFieldKind.union, 4, required: true, values: [-1, 1])", result)
        self.assertIn("const wampRootTable = 2;", result)
        self.assertLess(result.index("'msg_type'"), result.index("'msg'"))
        self.assertLess(result.index("'msg'"), result.index("'metadata'"))

    def test_validation_schema_rejects_unsupported_field_types(self):
        with self.assertRaisesRegex(ValueError, "Unsupported validation type"):
            generator.validation_schema("table Message { future: UnknownType; }")

    def test_validation_schema_rejects_unsupported_union_vectors(self):
        source = "table Hello {} union AnyMessage { Hello } table Message { msg: [AnyMessage]; }"
        with self.assertRaisesRegex(ValueError, "Union vectors"):
            generator.validation_schema(source)


if __name__ == "__main__":
    unittest.main()

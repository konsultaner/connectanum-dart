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


if __name__ == "__main__":
    unittest.main()

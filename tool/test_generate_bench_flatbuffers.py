import unittest

from generate_bench_flatbuffers import PROJECT_IGNORES, project_lint_header, project_byte_views


class ProjectLintHeaderTest(unittest.TestCase):
    def test_byte_views_are_regenerated_idempotently(self):
        source = "import 'package:flat_buffers/flat_buffers.dart' as fb;\n" \
            "fb.BufferContext.fromBytes(bytes);\nconst fb.Uint8ListReader();\n"
        result = project_byte_views(source)
        self.assertIn("byte_views.flatBufferContext(bytes)", result)
        self.assertIn("byte_views.FlatBufferUint8ListReader()", result)
        self.assertEqual(project_byte_views(result), result)
        with self.assertRaisesRegex(ValueError, "missing its FlatBuffers import"):
            project_byte_views("class UnsupportedCompilerOutput {}")
    def test_replaces_the_compiler_ignore_line_idempotently(self):
        source = (
            "// generated\n"
            "// ignore_for_file: unused_import, unused_field\n"
            "class Generated {}\n"
        )

        generated = project_lint_header(source)

        self.assertEqual(generated.splitlines()[1], PROJECT_IGNORES)
        self.assertEqual(project_lint_header(generated), generated)
        self.assertIn("class Generated {}", generated)

    def test_rejects_unrecognized_compiler_output(self):
        with self.assertRaisesRegex(ValueError, "missing its Dart lint directive"):
            project_lint_header("// generated\nclass Generated {}\n")


if __name__ == "__main__":
    unittest.main()

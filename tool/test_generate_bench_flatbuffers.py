import unittest

from generate_bench_flatbuffers import PROJECT_IGNORES, project_lint_header


class ProjectLintHeaderTest(unittest.TestCase):
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

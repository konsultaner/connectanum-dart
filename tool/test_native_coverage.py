from pathlib import Path
import os
import subprocess
import tempfile
import unittest

from native_coverage import REPO, filter_lcov, snapshot


class NativeCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.target = REPO / "out/rust-coverage-scope-target"
        subprocess.run([
            "cargo", "build", "--quiet", "--manifest-path",
            str(REPO / "tool/rust_coverage_scope/Cargo.toml"),
            "--target-dir", str(cls.target), "--locked",
        ], check=True)
        cls.analyzer = cls.target / "debug/connectanum-coverage-scope"

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name).resolve()
        self.roots = {"core": "core/src/lib.rs"}

    def write(self, path, text):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return target

    def capture(self):
        return snapshot(self.repo, self.roots, self.analyzer)

    def test_only_production_lines_contribute_and_llvm_function_totals_are_not_reused(self):
        self.write("core/src/lib.rs", "fn public() {}\nfn missed() {}\n#[cfg(test)]\nmod tests { fn test() {} }\n")
        raw = "SF:core/src/lib.rs\nFN:1,public\nFNF:2\nFNH:2\nBRF:9\nBRH:9\nDA:1,1\nDA:2,0\nDA:4,10\nLF:3\nLH:2\nend_of_record\n"
        output, report = filter_lcov(self.repo, self.capture(), raw)
        self.assertEqual(output, "SF:core/src/lib.rs\nDA:1,1\nDA:2,0\nLF:2\nLH:1\nend_of_record\n")
        component = report["components"]["core"]
        self.assertEqual(component["percent"], 50)
        self.assertEqual(component["excludedTestLines"], 1)

    def test_test_only_external_module_graph_and_path_override(self):
        self.write("core/src/lib.rs", '#[cfg(test)]\n#[path="suite.rs"] mod tests;\nmod production;\n')
        self.write("core/src/suite.rs", 'mod child;\nfn fixture() {}\n')
        self.write("core/src/child.rs", 'fn test() {}\n')
        self.write("core/src/production.rs", 'pub fn production() {}\n')
        scope = self.capture()
        self.assertEqual(scope["sources"]["core/src/suite.rs"]["classification"], "test-only")
        self.assertEqual(scope["sources"]["core/src/child.rs"]["classification"], "test-only")
        raw = "".join(f"SF:{source}\nDA:1,1\nend_of_record\n" for source in scope["sources"])
        _, report = filter_lcov(self.repo, scope, raw)
        self.assertEqual(report["components"]["core"]["found"], 1)
        self.assertEqual(report["components"]["core"]["excludedTestLines"], 3)

    def test_shared_test_and_production_module_keeps_production_scope(self):
        self.write("core/src/lib.rs", '#[path="shared.rs"] mod production;\n#[cfg(test)] #[path="shared.rs"] mod tests;\n')
        self.write("core/src/shared.rs", 'pub fn shared() {}\n')
        scope = self.capture()
        self.assertEqual(scope["sources"]["core/src/shared.rs"]["classification"], "production-candidate")

    def test_nested_inline_and_external_directories(self):
        self.write("core/src/lib.rs", 'mod outer { mod inner; }\n')
        self.write("core/src/outer/inner.rs", 'mod child { #[path="custom.rs"] mod leaf; }\n')
        self.write("core/src/outer/inner/child/custom.rs", 'pub fn leaf() {}\n')
        self.assertEqual(len(self.capture()["sources"]), 3)

    def test_path_override_module_resolution_agrees_with_rustc(self):
        self.write("core/src/lib.rs", '#[path="suite.rs"] mod renamed;\n')
        self.write("core/src/suite.rs", 'mod child;\n')
        self.write("core/src/child.rs", 'pub fn child() {}\n')
        scope = self.capture()
        result = subprocess.run(["rustc", "--crate-type", "lib", "--emit", "metadata",
                                 "--out-dir", str(self.repo), str(self.repo / "core/src/lib.rs")],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(scope["sources"]), 3)

    def test_changed_source_and_build_inputs_fail_closed(self):
        source = self.write("core/src/lib.rs", "fn production() {}\n")
        manifest = self.write("core/Cargo.toml", "[package]\n")
        scope = self.capture()
        raw = "SF:core/src/lib.rs\nDA:1,1\nend_of_record\n"
        source.write_text("fn changed() {}\n")
        with self.assertRaisesRegex(ValueError, "Stale coverage source"):
            filter_lcov(self.repo, scope, raw)
        source.write_text("fn production() {}\n")
        manifest.write_text("[changed]\n")
        with self.assertRaisesRegex(ValueError, "Stale coverage source"):
            filter_lcov(self.repo, scope, raw)

    def test_added_source_and_added_build_input_fail_closed(self):
        self.write("core/src/lib.rs", "fn production() {}\n")
        scope = self.capture()
        raw = "SF:core/src/lib.rs\nDA:1,1\nend_of_record\n"
        added = self.write("core/src/new.rs", "fn new() {}\n")
        with self.assertRaisesRegex(ValueError, "Source inventory changed"):
            filter_lcov(self.repo, scope, raw)
        added.unlink()
        self.write("core/Cargo.toml", "[package]\n")
        with self.assertRaisesRegex(ValueError, "Build input inventory changed"):
            filter_lcov(self.repo, scope, raw)

    def test_mixed_measured_lines_fail_closed_but_unmeasured_mixed_attributes_do_not(self):
        self.write("core/src/lib.rs", "fn production() {} #[cfg(test)] fn test() {}\nfn other() {}\n")
        scope = self.capture()
        with self.assertRaisesRegex(ValueError, "Ambiguous production/test"):
            filter_lcov(self.repo, scope, "SF:core/src/lib.rs\nDA:1,1\nend_of_record\n")
        _, report = filter_lcov(self.repo, scope, "SF:core/src/lib.rs\nDA:2,1\nend_of_record\n")
        self.assertEqual(report["components"]["core"]["found"], 1)

    def test_unmeasured_platform_module_is_not_silently_excluded(self):
        self.write("core/src/lib.rs", '#[cfg(target_os="linux")] mod platform;\nfn production() {}\n')
        self.write("core/src/platform.rs", 'pub fn platform() {}\n')
        _, report = filter_lcov(self.repo, self.capture(), "SF:core/src/lib.rs\nDA:2,1\nend_of_record\n")
        self.assertEqual(report["components"]["core"]["unmeasuredSources"], ["core/src/platform.rs"])

    def test_unreachable_missing_ambiguous_and_opaque_sources_are_rejected(self):
        root = self.write("core/src/lib.rs", 'fn production() {}\n')
        orphan = self.write("core/src/orphan.rs", 'fn hidden() {}\n')
        with self.assertRaisesRegex(ValueError, "Unreachable"):
            self.capture()
        orphan.unlink()
        root.write_text("mod missing;\n")
        with self.assertRaisesRegex(ValueError, "Unresolved or ambiguous"):
            self.capture()
        self.write("core/src/missing.rs", "")
        self.write("core/src/missing/mod.rs", "")
        with self.assertRaisesRegex(ValueError, "Unresolved or ambiguous"):
            self.capture()
        root.write_text('include!("generated.rs");\n')
        with self.assertRaisesRegex(ValueError, "Unclassified source scopes"):
            self.capture()

    def test_duplicate_records_union_hits_without_inflating_denominator(self):
        self.write("core/src/lib.rs", "fn production() {}\nfn other() {}\n")
        raw = "SF:core/src/lib.rs\nDA:1,0\nDA:2,0\nend_of_record\nSF:core/src/lib.rs\nDA:1,3\nend_of_record\n"
        _, report = filter_lcov(self.repo, self.capture(), raw)
        self.assertEqual(report["components"]["core"]["percent"], 50)

    def test_invalid_empty_or_out_of_bounds_lcov_is_rejected(self):
        self.write("core/src/lib.rs", "fn production() {}\n")
        scope = self.capture()
        for raw in ("", "DA:1,1", "end_of_record", "SF:core/src/lib.rs\nDA:1,1",
                    "SF:core/src/lib.rs\nDA:1,-1\nend_of_record",
                    "SF:core/src/lib.rs\nDA:2,1\nend_of_record",
                    "SF:core/src/lib.rs\nSF:core/src/lib.rs\nend_of_record"):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                filter_lcov(self.repo, scope, raw)

    @unittest.skipUnless(os.environ.get("CONNECTANUM_TEST_LLVM_COVERAGE") == "1",
                         "requires cargo-llvm-cov and llvm-tools-preview")
    def test_real_llvm_coverage_separates_inline_and_external_test_bodies(self):
        self.write("core/Cargo.toml", '[package]\nname="coverage-fixture"\nversion="0.0.0"\nedition="2021"\n[features]\nffi-test=[]\n')
        self.write("core/src/lib.rs", '''pub fn production(input: bool) -> u32 {
    if input { 7 } else { 9 }
}
#[cfg(feature="ffi-test")]
pub fn fixture_helper() -> u32 {
    31
}
#[cfg(test)]
mod tests;
#[cfg(test)]
mod inline {
    #[test]
    fn check() {
        // LLVM may count comment/blank lines in an executable region.

        assert_eq!(super::production(true), 7);
        assert_eq!(super::fixture_helper(), 31);
    }
}
''')
        self.write("core/src/tests.rs", '#[test]\nfn check() { assert_eq!(super::production(false), 9); }\n')
        subprocess.run(["cargo", "generate-lockfile", "--manifest-path", str(self.repo / "core/Cargo.toml")], check=True, capture_output=True)
        scope = self.capture()
        lcov = self.repo / "raw.info"
        subprocess.run([
            "cargo", "llvm-cov", "--manifest-path", str(self.repo / "core/Cargo.toml"),
            "--features", "ffi-test", "--lcov", "--output-path", str(lcov),
        ], cwd=self.repo, env={**os.environ, "CARGO_LLVM_COV_TARGET_DIR": str(self.repo / "llvm-target")},
            check=True, capture_output=True)
        output, report = filter_lcov(self.repo, scope, lcov.read_text())
        component = report["components"]["core"]
        self.assertEqual(component["percent"], 100)
        self.assertGreaterEqual(component["excludedTestLines"], 5)
        measured = [int(line.split(":")[1].split(",")[0]) for line in output.splitlines() if line.startswith("DA:")]
        self.assertEqual(measured, [1, 2, 3])


if __name__ == "__main__":
    unittest.main()

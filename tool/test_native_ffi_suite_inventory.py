import unittest

from native_ffi_coverage import suites


class NativeSuiteInventoryTests(unittest.TestCase):
    def test_live_client_transports_are_instrumented_individually(self):
        selected = suites()
        for path in (
            "test/transport/socket/socket_transport_test.dart",
            "test/transport/websocket/websocket_transport_io_test.dart",
        ):
            with self.subTest(path=path):
                matching = [suite for suite in selected
                            if suite[1] == "packages/connectanum_client"
                            and path in suite[2]]
                self.assertEqual(len(matching), 1)
                self.assertEqual(matching[0][2], [path])
                self.assertEqual(matching[0][3], {})

    def test_live_router_boundaries_are_instrumented_individually(self):
        selected = suites()
        for path in (
            "test/router_runtime_test.dart",
            "test/authorization_integration_test.dart",
            "test/meta_discovery_authorization_test.dart",
            "test/publish_ack_test.dart",
            "test/router_integration_cancel_test.dart",
            "test/router_integration_websocket_test.dart",
            "test/native/ffi_test_mode_test.dart",
        ):
            with self.subTest(path=path):
                matching = [suite for suite in selected
                            if suite[1] == "packages/connectanum_router"
                            and path in suite[2]]
                self.assertEqual(len(matching), 1)
                self.assertEqual(matching[0][2], [path])
                self.assertEqual(matching[0][3], {})

    def test_suite_labels_are_unique_and_cannot_override_profile_ownership(self):
        selected = suites()
        self.assertEqual(len(selected), len({suite[0] for suite in selected}))
        for label, package, arguments, environment in selected:
            with self.subTest(label=label):
                self.assertNotIn("/", label)
                self.assertTrue(arguments)
                self.assertIn(package, (
                    "packages/connectanum_client", "packages/connectanum_router"))
                self.assertTrue(set(environment) <= {"CONNECTANUM_FORWARD_NATIVE_PUBLISH"})
                self.assertNotIn("test/native/message_handle_abi_test.dart", arguments)
                self.assertNotIn("test/transport/native/message_handle_abi_test.dart", arguments)

    def test_zero_copy_profiles_remain_separate_from_the_default_route(self):
        selected = {suite[0]: suite for suite in suites()}
        files = ["test/router_integration_native_test.dart", "test/router_worker_session_test.dart"]
        self.assertEqual(selected["router-integration"], (
            "router-integration", "packages/connectanum_router",
            [*files, "--exclude-tags", "zero_copy_publish"], {}))
        self.assertEqual(selected["router-zero-copy"], (
            "router-zero-copy", "packages/connectanum_router",
            [*files, "--tags", "zero_copy_publish"], {"CONNECTANUM_FORWARD_NATIVE_PUBLISH": "1"}))


if __name__ == "__main__":
    unittest.main()

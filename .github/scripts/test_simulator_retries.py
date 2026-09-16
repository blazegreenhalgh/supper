"""Keep simulator recovery separate from assertions and incomplete test runs."""

import unittest

from simulator_retries import retry_tests


class SimulatorRetriesTests(unittest.TestCase):
    def log(self, issue):
        return "\n".join([
            "Test Case '-[SupperUITests.SupperUITests testLaunch]' started.",
            f"error: -[SupperUITests.SupperUITests testLaunch] : {issue}",
            "Test Case '-[SupperUITests.SupperUITests testLaunch]' failed (74.426 seconds).",
            "Test Case '-[SupperUITests.SupperUITests testPreview]' started.",
            "Test Case '-[SupperUITests.SupperUITests testPreview]' passed (67.374 seconds).",
        ])

    def test_retries_only_launch_progress_timeout_for_supper(self):
        issue = (
            "Failed to get launch progress for <XCUIApplicationImpl: 0x600000c24090 "
            "com.blazegreenhalgh.Supper at /tmp/Supper - Shared Cookbook.app>: "
            "Timed out while requesting launch progress."
        )
        self.assertEqual(retry_tests(self.log(issue), {"testLaunch", "testPreview"}),
                         ["SupperUITests/SupperUITests/testLaunch"])
        for other in [issue.replace("com.blazegreenhalgh.Supper", "com.example.Other"),
                      issue.replace("Timed out while requesting launch progress.", "Unknown error.")]:
            with self.assertRaises(ValueError):
                retry_tests(self.log(other), {"testLaunch", "testPreview"})

    def test_assertions_and_unclassified_errors_are_not_retried(self):
        for issue in ["XCTAssertTrue failed", "Unknown error"]:
            with self.assertRaises(ValueError):
                retry_tests(self.log(issue), {"testLaunch", "testPreview"})

    def test_incomplete_and_repeated_runs_are_not_retried(self):
        log = self.log("Failed to terminate com.blazegreenhalgh.Supper")
        with self.assertRaises(ValueError):
            retry_tests(log, {"testLaunch", "testPreview", "testMissing"})
        with self.assertRaises(ValueError):
            retry_tests(log + "\n" + log, {"testLaunch", "testPreview"})

    def test_lifecycle_error_does_not_hide_an_assertion(self):
        log = self.log("Failed to terminate com.blazegreenhalgh.Supper")
        log += "\nerror: -[SupperUITests.SupperUITests testLaunch] : XCTAssertTrue failed"
        with self.assertRaises(ValueError):
            retry_tests(log, {"testLaunch", "testPreview"})


if __name__ == "__main__":
    unittest.main()

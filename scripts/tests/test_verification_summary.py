import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "summarize_verification.py"
spec = importlib.util.spec_from_file_location("summary", SCRIPT)
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


class VerificationSummaryTests(unittest.TestCase):
    def test_success_requires_marker_and_successful_step(self):
        self.assertEqual(summary.summarize("** TEST SUCCEEDED **", "success")["category"], "success")
        self.assertEqual(summary.summarize("** TEST SUCCEEDED **", "failure")["category"], "unknown_failure")
        self.assertEqual(summary.summarize("", "success")["category"], "unknown_failure")

    def test_compiler_failure(self):
        result = summary.summarize("App.swift:42:9: error: cannot find symbol\n** TEST FAILED **", "failure")
        self.assertEqual(result["category"], "build_failure")

    def test_assertion_is_not_a_compiler_failure(self):
        result = summary.summarize("Flow.swift:132: error: -[Tests testNote] : XCTAssertTrue failed", "failure")
        self.assertEqual(result["category"], "test_failure")
        self.assertFalse(result["signals"]["build_failure"])

    def test_assertion_timeout_is_not_an_infrastructure_timeout(self):
        result = summary.summarize("Flow.swift:29: error: -[Tests testNote] : Asynchronous wait failed: Exceeded timeout of 5 seconds", "failure")
        self.assertEqual(result["category"], "test_failure")
        self.assertFalse(result["signals"]["timeout"])

    def test_runner_failure(self):
        result = summary.summarize("Failed to establish a connection to the test runner", "failure")
        self.assertEqual(result["category"], "runner_failure")

    def test_infrastructure_timeout_requires_explicit_evidence(self):
        self.assertEqual(summary.summarize("Timed out waiting for simulator to boot", "failure")["category"], "timeout")
        self.assertEqual(summary.summarize("a slow run", "failure")["category"], "unknown_failure")

    def test_cancelled_without_claiming_timeout(self):
        result = summary.summarize("", "cancelled", "cancelled")
        self.assertEqual(result["category"], "cancelled")
        self.assertFalse(result["signals"]["timeout"])

    def test_failure_cannot_be_hidden_by_cancelled_job(self):
        result = summary.summarize("Test Case '-[Tests testNote]' failed\nThe operation was canceled", "failure", "cancelled")
        self.assertEqual(result["category"], "test_failure")
        self.assertTrue(result["signals"]["cancelled"])

    def test_missing_log_does_not_infer_test_results(self):
        self.assertEqual(summary.summarize("", "skipped", "failure", False)["category"], "no_log")

    def test_totals_are_deduplicated_not_summed(self):
        line = "Executed 82 tests, with 0 failures (0 unexpected)"
        result = summary.summarize(line + "\n" + line + "\nExecuted 9 tests, with 1 failure (0 unexpected)")
        self.assertEqual(len(result["suite_totals_not_additive"]), 2)
        self.assertEqual(result["suite_totals_not_additive"][0], line)

    def test_summary_does_not_copy_private_text(self):
        secret = "private book excerpt and note"
        result = summary.summarize("Test Case '-[Tests " + secret + "]' failed\n" + secret, "failure")
        self.assertNotIn(secret, json.dumps(result))
        self.assertNotIn(secret, summary.markdown(result))

    def test_cli_outputs_and_step_summary(self):
        with tempfile.TemporaryDirectory(prefix="interline-summary-test-") as directory:
            root = Path(directory)
            log = root / "build.log"
            log.write_text("** TEST SUCCEEDED **", encoding="utf-8")
            step = root / "job.md"
            environment = dict(os.environ, GITHUB_STEP_SUMMARY=str(step), GITHUB_SHA="a" * 40,
                               GITHUB_REPOSITORY="example/reader", GITHUB_RUN_ID="123")
            subprocess.run([sys.executable, str(SCRIPT), "--log", str(log), "--outcome", "success",
                            "--output-directory", str(root / "out")], check=True, env=environment)
            result = json.loads((root / "out/summary.json").read_text())
            self.assertEqual(result["category"], "success")
            self.assertEqual(result["source"]["commit_sha"], "a" * 40)
            self.assertEqual(result["source"]["workflow_run_url"], "https://github.com/example/reader/actions/runs/123")
            self.assertEqual(step.read_text(), (root / "out/summary.md").read_text())


if __name__ == "__main__":
    unittest.main()

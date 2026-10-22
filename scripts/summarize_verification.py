#!/usr/bin/env python3
"""Classify observed build/test evidence without retrying or changing its result."""
import argparse
import json
import os
from pathlib import Path
import re


def summarize(log, outcome="unknown", job_status="unknown", log_present=True):
    patterns = {
        "test_failure": r"Test Case .* failed|error:.*(?:XCTAssert|Asynchronous wait failed| -\[)",
        "build_failure": r"\*\* BUILD FAILED \*\*|(?:\.swift|\.m|\.mm|\.h):\d+:\d*: error:|error: (?:emit-module|compilation) command failed|fatal error:.*file not found",
        "runner_failure": r"Failed to (?:launch|establish a connection)|Unable to (?:launch|boot)|test runner.*(?:crashed|unexpectedly exited)|Simulator.*failed to boot",
        "timeout": r"Timed out waiting for.*(?:simulator|test runner|boot)|job.*(?:exceeded|reached).*time limit|operation was timed out",
        "cancelled": r"The operation was canceled|The operation was cancelled|job was canceled|job was cancelled",
        "test_succeeded": r"\*\* TEST SUCCEEDED \*\*",
    }
    signals = {name: bool(re.search(pattern, log, re.I)) for name, pattern in patterns.items()}
    # A Swift file/line prefix on an XCTest assertion is not a compiler error.
    compiler_lines = [line for line in log.splitlines()
                      if re.search(patterns["build_failure"], line, re.I)
                      and not re.search(patterns["test_failure"], line, re.I)]
    signals["build_failure"] = bool(compiler_lines)
    if not log_present:
        category = "no_log"
    elif signals["test_failure"]:
        category = "test_failure"
    elif signals["build_failure"]:
        category = "build_failure"
    elif signals["timeout"]:
        category = "timeout"
    elif signals["runner_failure"]:
        category = "runner_failure"
    elif signals["cancelled"] or job_status == "cancelled" or outcome == "cancelled":
        category = "cancelled"
    elif signals["test_succeeded"] and outcome == "success":
        category = "success"
    else:
        category = "unknown_failure"
    # Preserve suite totals separately. Never sum nested/duplicated XCTest totals.
    totals = list(dict.fromkeys(re.findall(
        r"Executed \d+ tests?, with \d+ failures? \(\d+ unexpected\)", log)))
    guidance = {
        "success": "Build/test step passed. This does not establish visual, device, or release acceptance.",
        "test_failure": "Inspect the assertion and attachments; fix or explain it before any rerun. Do not waive tests.",
        "build_failure": "Fix the compiler/build error before rerunning.",
        "runner_failure": "Inspect launch/runner evidence; rerun only if an infrastructure cause is established.",
        "timeout": "Inspect where time was spent; timeout alone does not prove an infrastructure fault.",
        "cancelled": "Inspect cancellation reason and preceding evidence. Do not report tests as passed.",
        "unknown_failure": "Insufficient classification evidence. Inspect the original job log and result bundle.",
        "no_log": "No build log was produced or retained. Inspect earlier job steps; no test result is inferred.",
    }
    return {"schema_version": 1, "scope": "build_and_test_step", "category": category,
            "step_outcome": outcome, "job_status_at_summary": job_status,
            "signals": signals, "suite_totals_not_additive": totals,
            "guidance": guidance[category]}


def markdown(result):
    totals = "\n".join("- " + line for line in result["suite_totals_not_additive"]) or "- No suite totals available."
    detected = ", ".join(key for key, value in result["signals"].items() if value) or "none"
    source = result.get("source", {})
    revision = source.get("commit_sha") or "not supplied"
    run = source.get("workflow_run_url") or "not supplied"
    return ("# Build/test evidence summary\n\n"
            f"Category: `{result['category']}`\n\n"
            f"Checkout commit: `{revision}`; workflow run: {run}.\n\n"
            f"Step outcome: `{result['step_outcome']}`; job status at summary: `{result['job_status_at_summary']}`.\n\n"
            f"Observed signals: {detected}.\n\n"
            "## Suite totals (nested totals must not be added)\n\n" + totals + "\n\n"
            "## Review guidance\n\n" + result["guidance"] + "\n\n"
            "Original build.log, xcresult and UI attachments remain the primary evidence. "
            "This summary does not retry, skip tests, or override the test exit status.\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--outcome", default="unknown", choices=["success", "failure", "cancelled", "skipped", "unknown"])
    parser.add_argument("--job-status", default="unknown", choices=["success", "failure", "cancelled", "unknown"])
    parser.add_argument("--output-directory", type=Path, required=True)
    args = parser.parse_args()
    present = args.log.is_file()
    log = args.log.read_text(encoding="utf-8", errors="replace") if present else ""
    result = summarize(log, args.outcome, args.job_status, present)
    sha = os.environ.get("GITHUB_SHA", "")
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    result["source"] = {
        "commit_sha": sha if re.fullmatch(r"[a-fA-F0-9]{40}", sha) else None,
        "workflow_run_url": (f"https://github.com/{repository}/actions/runs/{run_id}"
                             if re.fullmatch(r"[\w.-]+/[\w.-]+", repository) and run_id.isdigit() else None),
    }
    args.output_directory.mkdir(parents=True, exist_ok=True)
    (args.output_directory / "summary.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    report = markdown(result)
    (args.output_directory / "summary.md").write_text(report, encoding="utf-8")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as stream:
            stream.write(report)


if __name__ == "__main__":
    main()

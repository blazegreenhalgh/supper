"""Select one retry only when a complete UI run failed on simulator lifecycle errors."""

import re
import sys
from pathlib import Path

CASE = re.compile(r"Test Case '-\[SupperUITests\.SupperUITests (test\w+)\]' (started|passed|failed)")
ISSUE = re.compile(r"error: -\[SupperUITests\.SupperUITests (test\w+)\] : (.*)")
LIFECYCLE_ERRORS = (
    "Failed to launch <XCUIApplication",
    "Failed to terminate com.blazegreenhalgh.Supper",
    "Failed to get background assertion for target app",
)


def retry_tests(log: str, expected: set[str]) -> list[str]:
    started, passed, failed = set(), set(), set()
    issues: dict[str, list[str]] = {}
    for line in log.splitlines():
        if match := CASE.search(line):
            name, state = match.groups()
            bucket = {"started": started, "passed": passed, "failed": failed}[state]
            if name in bucket:
                raise ValueError("Repeated test results require review.")
            bucket.add(name)
        if match := ISSUE.search(line):
            name, message = match.groups()
            issues.setdefault(name, []).append(message)
        elif "error:" in line and "IDELaunchReport:" not in line:
            raise ValueError("An unclassified error requires review.")
    if not expected or started != expected or passed | failed != expected or passed & failed:
        raise ValueError("The UI run is incomplete; do not replace its result with a partial retry.")
    if not failed or set(issues) != failed:
        raise ValueError("Every failed test must have a classified simulator lifecycle error.")
    for name in failed:
        if any(not message.startswith(LIFECYCLE_ERRORS) for message in issues[name]):
            raise ValueError(f"{name} has an assertion or other failure requiring review.")
    return sorted(f"SupperUITests/SupperUITests/{name}" for name in failed)


if __name__ == "__main__":
    log_path, *selection = sys.argv[1:]
    source = Path("Tests/UI/SupperUITests.swift").read_text()
    all_tests = set(re.findall(r"\bfunc (test\w+)\(", source))
    only, skipped = set(), set()
    for argument in selection:
        match = re.fullmatch(r"-(only|skip)-testing:SupperUITests/SupperUITests/(test\w+)", argument)
        if not match or match[2] not in all_tests:
            sys.exit("Unknown test selection; retry requires review.")
        (only if match[1] == "only" else skipped).add(match[2])
    try:
        tests = retry_tests(Path(log_path).read_text(), (only or all_tests) - skipped)
    except ValueError as error:
        sys.exit(str(error))
    print("\n".join(tests))

#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
# Catch release-note upload failures before spending time on the archive.
python3 - <<'PYTHON'
from pathlib import Path
for path in Path("TestFlight").glob("WhatToTest.*.txt"):
    count = len(path.read_text())
    if count > 4000:
        raise SystemExit(f"{path}: {count} characters exceeds TestFlight's 4000-character limit")
    print(f"{path}: {count}/4000 characters")
PYTHON
swift test

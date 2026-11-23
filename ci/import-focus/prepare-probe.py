#!/usr/bin/env python3
"""Create a temporary baseline + XCTest-only probe; do not modify the release."""
from pathlib import Path
import shutil
import sys

if len(sys.argv) != 3:
    sys.exit("usage: prepare-probe.py ORIGINAL_SNAPSHOT NEW_DIRECTORY")
base = Path(sys.argv[1]).resolve(strict=True)
target = Path(sys.argv[2]).absolute()
assert not target.exists() and base != target and base not in target.parents
shutil.copytree(base, target)
original = base / "tests/UITestSuperTV.swift"
test = target / "tests/UITestSuperTV.swift"
text = original.read_text()
stamp = "    private enum ProbeFailure:"
assert text.count(stamp) == 1
patch = Path(__file__).with_name("probe-fragment.swift.txt").read_text()
test.write_text(text.replace(stamp, patch + "\n" + stamp))
before = {str(p.relative_to(base)): p.read_bytes() for p in base.rglob("*") if p.is_file()}
after = {str(p.relative_to(target)): p.read_bytes() for p in target.rglob("*") if p.is_file()}
assert before.keys() == after.keys()
assert {p for p in before if before[p] != after[p]} == {"tests/UITestSuperTV.swift"}
print(target)

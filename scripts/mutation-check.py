#!/usr/bin/env python3
"""Three disposable wrong implementations must fail independent fixture assertions.
Copies only project source/tests into local private test workspaces. No production mutation.
"""
import json, shutil, subprocess, uuid
from pathlib import Path
root = Path(__file__).resolve().parent.parent
base = root / ".local/verification/mutations"
base.mkdir(parents=True, exist_ok=True, mode=0o700)
variants = [
    ("protect-priority", "Sources/CleanerCore/Rules.swift", "        let parts = absolutePath.split", "        return nil\n        let parts = absolutePath.split", "protectionAndThresholdIndependentTable"),
    ("identity-bypass", "Sources/CleanerExecution/AnchoredProbe.swift", "guard chainMatches(newChain, expected.ancestors), try leaf(fd,name) == expected.identity else", "guard chainMatches(newChain, expected.ancestors) else", "leafReplacementRejectedWithoutTouchingReplacement"),
    ("trash-is-release", "Sources/CleanerDomain/Models.swift", "estimate = action == .purge ? entry.allocatedBytes : nil", "estimate = entry.allocatedBytes", "planSelectionTTLAndHash")
]
results = []
for name, file, old, new, case in variants:
    directory = base / (name + "-" + str(uuid.uuid4()))
    directory.mkdir(mode=0o700)
    (directory / ".lmc-mutation-owned").write_text(directory.name)
    shutil.copy2(root / "Package.swift", directory / "Package.swift")
    for source in ["Sources", "Tests", "TestSupport", "Packages"]:
        shutil.copytree(root / source, directory / source)
    path = directory / file
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError("mutation anchor must occur exactly once: " + name)
    path.write_text(text.replace(old, new, 1))
    command = ["xcrun", "swift", "test", "--filter", case]
    with (directory / "test.log").open("w") as log:
        process = subprocess.run(command, cwd=directory, stdout=log, stderr=subprocess.STDOUT)
    output = (directory / "test.log").read_text()
    detected = process.returncode != 0 and "recorded an issue" in output and "Test run" in output
    results.append({"variant": name, "command": command, "exit": process.returncode, "detected_by_assertion": detected, "log": str(directory / "test.log")})
    print(json.dumps(results[-1]), flush=True)
(base / "results.json").write_text(json.dumps(results, indent=2))
raise SystemExit(0 if all(row["detected_by_assertion"] for row in results) else 1)

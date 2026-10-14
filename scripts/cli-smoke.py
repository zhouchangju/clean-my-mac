#!/usr/bin/env python3
import hashlib, json, os, stat, subprocess, tempfile, uuid
from pathlib import Path
root = Path(__file__).resolve().parent.parent
log = root / ".local/verification/cli"
log.mkdir(parents=True, exist_ok=True, mode=0o700)
fixture = Path(os.path.realpath(tempfile.mkdtemp(prefix="LMC-CLI-")))
marker = uuid.uuid4().hex
(fixture / ".lmc-fixture-marker").write_text(marker)
(fixture / "plain").write_bytes(b"fixture-readonly" * 100)
with (fixture / "large.sparse").open("wb") as output:
    output.truncate(536870912)
(fixture / ".ssh").mkdir()
(fixture / ".ssh" / "sentinel").write_text("protected-do-not-enumerate")

def snapshot():
    return {str(p.relative_to(fixture)): {"inode": p.lstat().st_ino, "size":p.lstat().st_size, "mtimeNs":str(p.lstat().st_mtime_ns), "hash":hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() and p.name != "large.sparse" else None} for p in fixture.rglob("*")}

before = snapshot()
binary = root / ".build/debug/lmc"
commands = [
    [str(binary), "scan", "--json"],
    [str(binary), "scan", "--root", str(fixture), "--json"],
    [str(binary), "purge", "--root", str(fixture)],
]
results = []
for index, command in enumerate(commands):
    process = subprocess.run(command, cwd=root, capture_output=True, text=True)
    (log / f"command-{index}.stdout").write_text(process.stdout)
    (log / f"command-{index}.stderr").write_text(process.stderr)
    results.append({"command":command,"exit":process.returncode})
assert [r["exit"] for r in results] == [2,0,2], results
run = json.loads((log / "command-1.stdout").read_text())
assert run["scope"]["rootPath"] == str(fixture)
assert run["state"] == "partial"
after = snapshot()
assert before == after, "read-only smoke mutated fixture"
(log / "fixture-before.json").write_text(json.dumps(before,indent=2))
(log / "fixture-after.json").write_text(json.dumps(after,indent=2))
(log / "results.json").write_text(json.dumps({"fixture":str(fixture),"marker":marker,"commands":results,"runID":run["id"],"unchanged":True}, indent=2))
print(json.dumps(results))
# Evidence fixture is intentionally retained, never deleting an unverified root.

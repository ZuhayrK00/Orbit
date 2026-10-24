#!/usr/bin/env python3
"""Test with synthetic events; never start an AI provider. Python is test-only.
Writes uniquely named disposable status cards and removes only those fixtures.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

binary = Path(sys.argv[1] if len(sys.argv) > 1 else "build/Orbit.app/Contents/MacOS/Orbit").resolve()
directory = Path.home() / "Library/Application Support/Orbit/agents"
nonce = "orbit-smoke-" + str(uuid.uuid4())
ids = ["claude-" + nonce, "codex-" + nonce, "codex-" + nonce + "-incomplete", nonce, "claude-" + nonce + "/child/one", "codex-" + nonce + "/child/one"]
metrics_directory = directory.parent / "agent-metrics"
metrics_file = metrics_directory / (hashlib.sha256(ids[0].encode()).hexdigest() + ".json")

def path(agent_id):
    return directory / (hashlib.sha256(agent_id.encode()).hexdigest() + ".json")

def run(flag, value):
    return subprocess.run([str(binary), flag], input=value, text=True, capture_output=True, timeout=10)

def status(agent_id):
    return json.loads(path(agent_id).read_text())

try:
    secret = "PRIVATE-TRANSCRIPT-MUST-NOT-BE-STORED"
    for event, phase in [("UserPromptSubmit", "running"), ("PermissionRequest", "waiting"), ("Stop", "completed"), ("StopFailure", "failed")]:
        result = run("--claude-hook", json.dumps(dict(hook_event_name=event, session_id=nonce, cwd="/synthetic/Orbit", prompt=secret, last_assistant_message=secret)))
        assert result.returncode == 0 and result.stdout == ""
        assert status(ids[0])["phase"] == phase
        assert secret not in path(ids[0]).read_text()
    assert run("--claude-hook", "malformed").returncode == 0
    for event, phase in [("UserPromptSubmit", "running"), ("PermissionRequest", "waiting"), ("Stop", "completed"), ("Interrupt", "idle"), ("SessionEnd", "offline")]:
        result = run("--codex-hook", json.dumps(dict(hook_event_name=event, session_id=nonce, cwd="/synthetic/Orbit", prompt=secret, last_assistant_message=secret)))
        assert result.returncode == 0 and result.stdout == ""
        assert status(ids[1])["phase"] == phase
        assert secret not in path(ids[1]).read_text()
    assert run("--codex-hook", "malformed").returncode == 0
    events = [dict(type="thread.started", thread_id=nonce), dict(type="turn.started"), dict(type="item.completed", item=dict(type="agent_message", text=secret)), dict(type="turn.completed")]
    lines = "\n".join(json.dumps(event) for event in events) + "\ninvalid-line\n"
    result = run("--codex-stream", lines)
    assert result.returncode == 0 and result.stdout == lines
    assert status(ids[1])["phase"] == "completed"
    assert secret not in path(ids[1]).read_text()
    unfinished = dict(type="thread.started", thread_id=nonce + "-incomplete")
    assert run("--codex-stream", json.dumps(unfinished) + "\n").returncode == 0
    assert status(ids[2])["phase"] == "offline"
    generic = dict(id=nonce, provider="Test", title="Fixture", detail="x" * 800, phase="running", updatedAt="2026-10-06T20:00:00Z", progress=4)
    assert run("--agent-event", json.dumps(generic)).returncode == 0
    assert status(ids[3])["progress"] == 1 and len(status(ids[3])["detail"]) == 512
    assert run("--agent-event", "invalid").returncode != 0
    assert run("--agent-event", " " * 65537).returncode != 0
    for flag, child_id in [("--claude-hook", ids[4]), ("--codex-hook", ids[5])]:
        result = run(flag, json.dumps(dict(hook_event_name="SubagentStop", session_id=nonce, agent_id="one", agent_type="Reviewer", cwd="/synthetic/Orbit")))
        assert result.returncode == 0 and result.stdout == ""
        assert status(child_id)["phase"] == "completed" and status(child_id)["parentID"]
    metrics = dict(session_id=nonce, model=dict(display_name="Synthetic model"), workspace=dict(project_dir="/synthetic/Orbit"),
                   context_window=dict(used_percentage=42, total_input_tokens=1200, total_output_tokens=45),
                   rate_limits=dict(five_hour=dict(used_percentage=19, resets_at=1800000000)), prompt=secret)
    result = run("--claude-metrics", json.dumps(metrics))
    assert result.returncode == 0 and result.stdout.strip() == "Synthetic model · 42% context"
    saved = json.loads(metrics_file.read_text())
    assert saved["inputTokens"] == 1200 and saved["limits"][0]["usedPercent"] == 19
    assert secret not in metrics_file.read_text()
    assert run("--claude-metrics", "malformed").returncode == 0
    assert run("--claude-metrics", " " * 1048577).returncode == 0
    if len(sys.argv) > 2:
        wrapper = Path(sys.argv[2]).resolve()
        with tempfile.TemporaryDirectory(prefix="orbit-codex-fixture-") as fixture:
            stub = Path(fixture) / "codex-stub"
            stub.write_text("#!/bin/bash\n[ \"$1\" = exec ] && [ \"$2\" = --json ] && [ \"$3\" = fixture ] || exit 99\nprintf '%s\\n' '{\"type\":\"thread.started\",\"thread_id\":\"" + nonce + "\"}' '{\"type\":\"turn.failed\"}'\nexit 7\n")
            stub.chmod(0o755)
            result = subprocess.run([str(wrapper), "fixture"], env={**os.environ, "ORBIT_CODEX_BIN": str(stub)}, capture_output=True, text=True, timeout=10)
            assert result.returncode == 7 and '"turn.failed"' in result.stdout
            assert status(ids[1])["phase"] == "failed"
    print("PASS: Claude states, Codex lifecycle hooks, quiet hooks, Codex forwarding, interrupted stream, summary privacy, input limits, child sessions, Claude metrics" + (", wrapper arguments and pipefail" if len(sys.argv) > 2 else ""))
finally:
    metrics_file.unlink(missing_ok=True)
    for agent_id in ids:
        path(agent_id).unlink(missing_ok=True)

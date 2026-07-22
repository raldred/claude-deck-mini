"""Tests for the write-status hook script. Run: python3 plugin/test_write_status.py"""

import json
import os
import subprocess
import sys
import tempfile

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "write-status")


def _check(cond, msg):
    if not cond:
        print(f"FAIL: {msg}")
        sys.exit(1)


def _run(payload, home):
    env = dict(os.environ, HOME=home)
    return subprocess.run([sys.executable, SCRIPT], input=json.dumps(payload),
                          text=True, env=env).returncode


def _status_path(home, session_id):
    return os.path.join(home, ".claude-deck", "status", f"{session_id}.json")


def test_working_event_writes_status():
    with tempfile.TemporaryDirectory() as home:
        rc = _run({"session_id": "s1", "hook_event_name": "PostToolUse", "cwd": "/x"}, home)
        _check(rc == 0, "should exit 0")
        rec = json.load(open(_status_path(home, "s1")))
        _check(rec["sessionId"] == "s1", "wrong sessionId")
        _check(rec["status"] == "working", f"wrong status {rec['status']}")
        _check(rec["cwd"] == "/x", "wrong cwd")
        _check(rec["timestamp"].endswith("Z"), "timestamp not ISO8601 Z")


def test_waiting_event_writes_waiting():
    with tempfile.TemporaryDirectory() as home:
        _run({"session_id": "s2", "hook_event_name": "Stop"}, home)
        rec = json.load(open(_status_path(home, "s2")))
        _check(rec["status"] == "waiting", f"wrong status {rec['status']}")
        _check(rec["cwd"] is None, "cwd should be null when absent")


def test_session_end_deletes_file():
    with tempfile.TemporaryDirectory() as home:
        _run({"session_id": "s3", "hook_event_name": "PreToolUse"}, home)
        _check(os.path.exists(_status_path(home, "s3")), "precondition: file exists")
        _run({"session_id": "s3", "hook_event_name": "SessionEnd"}, home)
        _check(not os.path.exists(_status_path(home, "s3")), "SessionEnd should delete")


def test_missing_session_id_is_noop():
    with tempfile.TemporaryDirectory() as home:
        rc = _run({"hook_event_name": "PostToolUse"}, home)
        _check(rc == 0, "should exit 0")
        d = os.path.join(home, ".claude-deck", "status")
        _check(not os.path.isdir(d) or not os.listdir(d), "wrote a file without session_id")


def test_unknown_event_is_noop():
    with tempfile.TemporaryDirectory() as home:
        _run({"session_id": "s4", "hook_event_name": "Wibble"}, home)
        _check(not os.path.exists(_status_path(home, "s4")), "unknown event wrote a file")


def test_malformed_json_exits_zero():
    with tempfile.TemporaryDirectory() as home:
        env = dict(os.environ, HOME=home)
        rc = subprocess.run([sys.executable, SCRIPT], input="not json{", text=True, env=env).returncode
        _check(rc == 0, "malformed JSON should still exit 0")


if __name__ == "__main__":
    test_working_event_writes_status()
    test_waiting_event_writes_waiting()
    test_session_end_deletes_file()
    test_missing_session_id_is_noop()
    test_unknown_event_is_noop()
    test_malformed_json_exits_zero()
    print("write-status tests passed")

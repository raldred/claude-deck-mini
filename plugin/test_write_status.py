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


def _run(payload, home, pid=None):
    env = dict(os.environ, HOME=home)
    if pid is not None:
        env["CLAUDE_DECK_PID_OVERRIDE"] = str(pid)
    return subprocess.run([sys.executable, SCRIPT], input=json.dumps(payload),
                          text=True, env=env).returncode


def _status_path(home, session_id):
    return os.path.join(home, ".claude-deck", "status", f"{session_id}.json")


def _sidecar_path(home, agent_id):
    return os.path.join(home, ".claude-deck", "subagents", f"{agent_id}.json")


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


def test_main_event_records_pid():
    with tempfile.TemporaryDirectory() as home:
        _run({"session_id": "s1", "hook_event_name": "PostToolUse", "cwd": "/x"}, home, pid=4242)
        rec = json.load(open(_status_path(home, "s1")))
        _check(rec.get("pid") == 4242, f"expected pid 4242, got {rec.get('pid')}")


def test_subagent_event_writes_sidecar_not_status():
    with tempfile.TemporaryDirectory() as home:
        transcript = "/Users/x/.claude/projects/-Users-x-Code-proj/PARENT-ID.jsonl"
        _run({"session_id": "SUB-ID", "agent_id": "AG-1", "agent_type": "Explore",
              "hook_event_name": "SubagentStart", "transcript_path": transcript}, home, pid=99)
        # No status file keyed by the subagent's own session id.
        _check(not os.path.exists(_status_path(home, "SUB-ID")),
               "subagent must not write a status file")
        # A sidecar keyed by agent_id, with parent id parsed from transcript_path.
        side = json.load(open(_sidecar_path(home, "AG-1")))
        _check(side.get("parentId") == "PARENT-ID", f"wrong parentId {side.get('parentId')}")
        _check(side.get("agentId") == "AG-1", "wrong agentId")
        _check(side.get("pid") == 99, "sidecar missing pid")


def test_subagent_tool_event_also_writes_sidecar():
    with tempfile.TemporaryDirectory() as home:
        transcript = "/p/PARENT.jsonl"
        _run({"session_id": "SUB", "agent_id": "AG-2",
              "hook_event_name": "PostToolUse", "transcript_path": transcript}, home)
        _check(os.path.exists(_sidecar_path(home, "AG-2")),
               "subagent tool event should keep the sidecar alive")
        _check(not os.path.exists(_status_path(home, "SUB")),
               "subagent tool event must not write a status file")


def test_pid_walk_climbs_past_shell_and_returns_int():
    # Fake `ps` forcing a 2-level walk: any starting pid resolves to a non-claude
    # shell whose ppid is 2000; pid 2000 resolves to "claude". The walk must climb
    # past the shell and return pid 2000 as an INT — a string pid (the bug) decodes
    # to null in Swift and defeats the reaper.
    with tempfile.TemporaryDirectory() as home, tempfile.TemporaryDirectory() as bindir:
        ps = os.path.join(bindir, "ps")
        with open(ps, "w") as f:
            f.write(
                "#!/usr/bin/env python3\n"
                "import sys\n"
                "pid = sys.argv[-1]\n"
                "print('3000 claude' if pid == '2000' else '2000 zsh')\n"
            )
        os.chmod(ps, 0o755)
        env = dict(os.environ, HOME=home, PATH=bindir + os.pathsep + os.environ["PATH"])
        env.pop("CLAUDE_DECK_PID_OVERRIDE", None)
        subprocess.run([sys.executable, SCRIPT],
                       input=json.dumps({"session_id": "s", "hook_event_name": "PostToolUse"}),
                       text=True, env=env)
        rec = json.load(open(_status_path(home, "s")))
        _check(rec.get("pid") == 2000,
               f"walk should return int 2000, got {type(rec.get('pid')).__name__}: {rec.get('pid')!r}")


def test_subagent_stop_deletes_sidecar():
    with tempfile.TemporaryDirectory() as home:
        transcript = "/p/PARENT.jsonl"
        _run({"session_id": "SUB", "agent_id": "AG-3",
              "hook_event_name": "SubagentStart", "transcript_path": transcript}, home)
        _check(os.path.exists(_sidecar_path(home, "AG-3")), "precondition: sidecar exists")
        _run({"session_id": "SUB", "agent_id": "AG-3",
              "hook_event_name": "SubagentStop", "transcript_path": transcript}, home)
        _check(not os.path.exists(_sidecar_path(home, "AG-3")),
               "SubagentStop should delete the sidecar")


if __name__ == "__main__":
    test_working_event_writes_status()
    test_waiting_event_writes_waiting()
    test_session_end_deletes_file()
    test_missing_session_id_is_noop()
    test_unknown_event_is_noop()
    test_malformed_json_exits_zero()
    test_main_event_records_pid()
    test_pid_walk_climbs_past_shell_and_returns_int()
    test_subagent_event_writes_sidecar_not_status()
    test_subagent_tool_event_also_writes_sidecar()
    test_subagent_stop_deletes_sidecar()
    print("write-status tests passed")

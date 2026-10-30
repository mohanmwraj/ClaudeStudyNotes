"""audit_log.py - PostToolUse(*): append one JSON line per tool call to .claude/audit/<session>.jsonl - tool,
command or file, duration - with secrets redacted, so an unattended run can be reconstructed afterwards.
Never blocks (a logging failure is a non-blocking error). Set CLAUDE_HOOK_NOW to pin the timestamp in tests.
"""
import datetime
import json
import os
import re
import sys

REDACT = re.compile(r"(AKIA[0-9A-Z]{16}|sk-ant-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9]{20,}|"
                    r"(?i:(password|token|secret)=)\S+)")


def main():
    data = json.load(sys.stdin)
    project = os.environ.get("CLAUDE_PROJECT_DIR", data.get("cwd", "."))
    ti = data.get("tool_input", {})
    entry = {
        "ts": os.environ.get("CLAUDE_HOOK_NOW") or datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "session": data.get("session_id"),
        "tool": data.get("tool_name"),
        "target": REDACT.sub("[REDACTED]", str(ti.get("command") or ti.get("file_path") or ti.get("url") or "")),
        "duration_ms": data.get("duration_ms"),
        "permission_mode": data.get("permission_mode"),
    }
    folder = os.path.join(project, ".claude", "audit")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, f"{data.get('session_id', 'unknown')}.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, sort_keys=True) + "\n")
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"audit_log: {e}", file=sys.stderr)
        sys.exit(1)

"""protect_paths.py - PreToolUse(Edit|Write|NotebookEdit): deny edits to generated code, build output, .git/,
and Flyway migrations that are already committed (an applied migration must never change - add a new V<n+1>).
Creating a NEW migration is allowed. Paths arrive absolute, and on Windows with backslashes even under Git
Bash, so they are normalised before matching. Answers with a JSON `deny` (Claude sees the reason).
"""
import json
import os
import re
import subprocess
import sys

DENY = [(re.compile(r"/(generated|target|build|\.gradle)/"), "generated or build output - change the source (e.g. api/openapi.yaml) and regenerate"),
        (re.compile(r"/\.git/"), "the .git directory is managed by git")]
MIGRATION = re.compile(r"/db/migration/V\d+__[^/]+\.sql$")


def committed(path, project):
    rel = os.path.relpath(path, project).replace("\\", "/")
    r = subprocess.run(["git", "-C", project, "cat-file", "-e", f"HEAD:{rel}"], capture_output=True)
    return r.returncode == 0


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                             "permissionDecisionReason": f"protect_paths: {reason}"}}))
    sys.exit(0)


def main():
    data = json.load(sys.stdin)
    raw = data.get("tool_input", {}).get("file_path") or data.get("tool_input", {}).get("notebook_path") or ""
    path = raw.replace("\\", "/")
    project = os.environ.get("CLAUDE_PROJECT_DIR", data.get("cwd", "."))
    for rx, why in DENY:
        if rx.search(path):
            deny(why)
    if MIGRATION.search(path) and os.path.exists(raw) and committed(raw, project):
        deny("this Flyway migration is committed (and may be applied) - add a new V<n+1>__*.sql instead")
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"protect_paths: internal error ({e}); blocking for safety.", file=sys.stderr)
        sys.exit(2)

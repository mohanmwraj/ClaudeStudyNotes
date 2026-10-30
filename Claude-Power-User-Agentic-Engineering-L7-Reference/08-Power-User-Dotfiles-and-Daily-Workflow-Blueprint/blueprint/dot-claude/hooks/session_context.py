"""session_context.py - SessionStart(startup|resume|clear|compact): give Claude the facts it would otherwise
rediscover every session - branch, uncommitted changes, recent commits, and the last surefire failures.
On SessionStart, plain-text stdout is added to Claude's context; keep it short (it costs tokens every session).
"""
import glob
import json
import os
import re
import subprocess
import sys


def git(project, *args):
    r = subprocess.run(["git", "-C", project, *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def main():
    data = json.load(sys.stdin)
    project = os.environ.get("CLAUDE_PROJECT_DIR", data.get("cwd", "."))
    lines = [f"Session context ({data.get('source', 'startup')}):",
             f"- branch: {git(project, 'rev-parse', '--abbrev-ref', 'HEAD') or 'unknown'}",
             f"- uncommitted files: {len([l for l in git(project, 'status', '--porcelain').splitlines() if l])}"]
    log = git(project, "log", "--oneline", "-5")
    if log:
        lines.append("- recent commits:\n" + "\n".join("    " + l.split(" ", 1)[-1] for l in log.splitlines()))
    failures = []
    for report in glob.glob(os.path.join(project, "**", "target", "surefire-reports", "*.txt"), recursive=True):
        text = open(report, encoding="utf-8", errors="replace").read()
        if re.search(r"(Failures|Errors): [1-9]", text):
            failures.append(os.path.basename(report)[:-4])
    if failures:
        lines.append(f"- last test run had failures in: {', '.join(sorted(failures))}")
    print("\n".join(lines))
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"session_context: skipped ({e})", file=sys.stderr)
        sys.exit(1)

"""verify_build.py - Stop: Claude may not finish while the build is red. If the working tree has changed Java,
SQL, XML or Gradle files, run the fast verification (default: ./mvnw -q -o verify -DskipITs) and, on failure,
exit 2 with the failing lines on stderr - Claude Code sends Claude back to work with that as the reason.
No relevant changes -> allow the stop immediately. Claude Code caps this at 8 consecutive continuations.
Override the command with CLAUDE_HOOK_VERIFY_CMD (a JSON list).
"""
import json
import os
import re
import subprocess
import sys

RELEVANT = re.compile(r"\.(java|sql|xml|gradle|kts|yml|yaml|properties)$")


def main():
    data = json.load(sys.stdin)
    project = os.environ.get("CLAUDE_PROJECT_DIR", data.get("cwd", "."))
    # --untracked-files=all: plain --porcelain collapses a new directory to "?? src/main/java/", hiding new .java files
    st = subprocess.run(["git", "-C", project, "status", "--porcelain", "--untracked-files=all"], capture_output=True, text=True)
    changed = [l[3:].strip() for l in st.stdout.splitlines() if RELEVANT.search(l.strip())]
    if not changed:
        sys.exit(0)
    wrapper = "mvnw.cmd" if os.name == "nt" else "./mvnw"
    cmd = json.loads(os.environ["CLAUDE_HOOK_VERIFY_CMD"]) if os.environ.get("CLAUDE_HOOK_VERIFY_CMD") \
        else [wrapper, "-q", "-o", "verify", "-DskipITs"]
    r = subprocess.run(cmd, cwd=project, capture_output=True, text=True, timeout=540)
    if r.returncode == 0:
        sys.exit(0)
    lines = (r.stdout + r.stderr).splitlines()
    key = [l for l in lines if re.search(r"ERROR|FAIL|Tests run:.*Failures: [1-9]|expected", l)] or lines[-20:]
    print(f"verify_build: `{' '.join(cmd)}` failed after your changes to {len(changed)} file(s). Fix these before "
          "finishing:\n" + "\n".join(key[:25]), file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except subprocess.TimeoutExpired:
        print("verify_build: verification timed out; report that the build could not be verified.", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"verify_build: could not run ({e})", file=sys.stderr)
        sys.exit(1)

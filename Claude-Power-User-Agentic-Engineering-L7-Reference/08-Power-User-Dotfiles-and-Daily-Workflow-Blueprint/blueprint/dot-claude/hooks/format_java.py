"""format_java.py - PostToolUse(Edit|Write): run Spotless on the Java file Claude just changed, so formatting is
deterministic and never argued about in review. Only the edited file is formatted (`-DspotlessFiles=<regex>`).
PostToolUse can't undo the edit, so on formatter failure it exits 2: Claude sees the stderr and fixes the code.
Override the command with CLAUDE_HOOK_FORMAT_CMD (a JSON list; `{file}` is replaced) - used by the tests,
or for Gradle: ["./gradlew","spotlessApply","-PspotlessIdeHook={file}"].
"""
import json
import os
import re
import subprocess
import sys


def main():
    data = json.load(sys.stdin)
    path = str(data.get("tool_input", {}).get("file_path", ""))
    if not path.endswith(".java"):
        sys.exit(0)
    project = os.environ.get("CLAUDE_PROJECT_DIR", data.get("cwd", "."))
    wrapper = "mvnw.cmd" if os.name == "nt" else "./mvnw"
    default = [wrapper, "-q", "spotless:apply", "-DspotlessFiles=" + re.escape(path.replace("\\", "/")).replace("/", "[\\\\/]")]
    cmd = [c.replace("{file}", path) for c in json.loads(os.environ["CLAUDE_HOOK_FORMAT_CMD"])] \
        if os.environ.get("CLAUDE_HOOK_FORMAT_CMD") else default
    r = subprocess.run(cmd, cwd=project, capture_output=True, text=True, timeout=110)
    if r.returncode != 0:
        tail = "\n".join((r.stdout + r.stderr).strip().splitlines()[-15:])
        print(f"format_java: Spotless failed on {os.path.basename(path)} - the file likely does not compile:\n{tail}",
              file=sys.stderr)
        sys.exit(2)
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:                    # never block on our own bug here: the edit already happened
        print(f"format_java: skipped ({e})", file=sys.stderr)
        sys.exit(1)

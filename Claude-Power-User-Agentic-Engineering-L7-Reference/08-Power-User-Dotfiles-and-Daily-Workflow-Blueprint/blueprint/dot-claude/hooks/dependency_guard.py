"""dependency_guard.py - PreToolUse(Edit|Write) on pom.xml / build.gradle(.kts): defend against hallucinated or
typosquatted dependencies. Every NEW coordinate written must be on .claude/allowed-deps.txt (lines like
`org.springframework.boot:*` or `com.zaxxer:HikariCP`), and dynamic versions (LATEST, RELEASE, '+', open
ranges) are refused. Unknown coordinates get `ask`, so a human approves them (in `-p` runs, ask = denied).
"""
import fnmatch
import json
import os
import re
import sys

MAVEN = re.compile(r"<dependency>.*?<groupId>([^<]+)</groupId>.*?<artifactId>([^<]+)</artifactId>(?:.*?<version>([^<]+)</version>)?.*?</dependency>", re.S)
GRADLE = re.compile(r"""(?:implementation|api|compileOnly|runtimeOnly|testImplementation)\s*\(?\s*["']([\w.-]+):([\w.-]+)(?::([^"']+))?["']""")
DYNAMIC = re.compile(r"^(LATEST|RELEASE)$|\+$|^[\[(][^,]*,\s*[)\]]$")


def decide(kind, reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": kind,
                                             "permissionDecisionReason": f"dependency_guard: {reason}"}}))
    sys.exit(0)


def main():
    data = json.load(sys.stdin)
    ti = data.get("tool_input", {})
    path = str(ti.get("file_path", "")).replace("\\", "/")
    if not re.search(r"(^|/)(pom\.xml|build\.gradle(\.kts)?)$", path):
        sys.exit(0)
    text = str(ti.get("content") or ti.get("new_string") or "")
    coords = MAVEN.findall(text) + GRADLE.findall(text)
    if not coords:
        sys.exit(0)
    project = os.environ.get("CLAUDE_PROJECT_DIR", data.get("cwd", "."))
    allow_file = os.path.join(project, ".claude", "allowed-deps.txt")
    allowed = [l.strip() for l in open(allow_file, encoding="utf-8")] if os.path.exists(allow_file) else []
    for g, a, v in coords:
        if v and DYNAMIC.search(v.strip()):
            decide("deny", f"{g}:{a} uses a dynamic version '{v}'; pin an exact version")
        if not any(fnmatch.fnmatch(f"{g}:{a}", pat) for pat in allowed if pat and not pat.startswith("#")):
            decide("ask", f"{g}:{a} is not on .claude/allowed-deps.txt - confirm it exists on Maven Central and is the intended artifact")
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"dependency_guard: internal error ({e}); blocking for safety.", file=sys.stderr)
        sys.exit(2)

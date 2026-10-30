"""guard_bash.py - PreToolUse(Bash): block destructive git, unsafe rm -rf, production data/infra commands,
Flyway clean, curl|sh and hook-bypassing commits. Splits compound commands (&&, ||, ;, |, newlines, $(...),
backticks) and strips env assignments and wrappers, so `FOO=1 sudo git push -f` is caught. Exits 2 with the
reason on stderr (Claude reads it and adapts); fails CLOSED on any internal error.
"""
import json
import re
import shlex
import sys

PROTECTED = re.compile(r"^(main|master|release/.+|prod.*)$")
BUILD_DIRS = re.compile(r"^(\./)?(target|build|out|\.gradle|node_modules|tmp)(/.*)?$")
WRAPPERS = {"sudo", "env", "nohup", "time", "nice", "command", "exec"}
PROD = re.compile(r"(^|[^a-z])(prod|production|prd)([^a-z]|$)", re.I)


def subcommands(cmd):
    inner = re.findall(r"\$\(([^()]*)\)|`([^`]*)`", cmd)
    parts = re.split(r"&&|\|\||;|\||\n", re.sub(r"\$\([^()]*\)|`[^`]*`", " ", cmd))
    parts += [a or b for a, b in inner]
    for p in parts:
        try:
            toks = shlex.split(p, posix=True)
        except ValueError:
            toks = p.split()
        while toks and (re.match(r"^\w+=", toks[0]) or toks[0] in WRAPPERS):
            toks = toks[1:]
        if toks:
            yield toks


def check(toks, raw):
    prog, args = toks[0].rsplit("/", 1)[-1], toks[1:]
    a = " ".join(args)
    if prog == "git":
        sub = next((x for x in args if not x.startswith("-")), "")
        if sub == "push" and (re.search(r"(^|\s)(-f|--force)(\s|$)|--force-with-lease|--mirror|--delete|\s:\S", " " + a)):
            return "force/destructive push - push a branch normally and open a PR"
        if sub == "push" and any(PROTECTED.match(x.split(":")[-1]) for x in args[1:] if not x.startswith("-")):
            return "direct push to a protected branch - push a feature branch and open a PR"
        if sub == "reset" and "--hard" in args:
            return "git reset --hard discards work - use git stash or a new branch"
        if sub == "clean" and re.search(r"-\w*f", a):
            return "git clean -f deletes untracked files - list them with git clean -n first"
        if sub in ("checkout", "restore") and re.search(r"(^|\s)(--\s+)?\.(\s|$)", a):
            return "discarding all working-tree changes - restore specific files instead"
        if sub == "branch" and re.search(r"(^|\s)-D(\s|$)", a):
            return "force-deleting a branch - use git branch -d (merged only)"
        if sub == "commit" and "--no-verify" in args:
            return "--no-verify bypasses the repo's checks - fix what the hook reports"
    if prog == "rm" and re.search(r"-\w*r\w*f|-\w*f\w*r|--recursive", a):
        targets = [x for x in args if not x.startswith("-")]
        if not targets or any(not BUILD_DIRS.match(t) for t in targets):
            return f"rm -rf outside build output ({' '.join(targets) or 'no target'}) - only target/, build/, out/, .gradle/ may be removed"
    if prog in ("psql", "mysql", "mongosh", "redis-cli", "sqlcmd") and PROD.search(raw):
        return "direct access to a production database - use the read replica runbook"
    if prog in ("kubectl", "helm") and PROD.search(raw) and re.search(r"\b(delete|apply|scale|rollout|exec|uninstall|upgrade)\b", a):
        return "mutating production Kubernetes - changes go through the deploy pipeline"
    if prog == "terraform" and re.search(r"\b(apply|destroy|import|state\s+rm)\b", a):
        return "terraform apply/destroy - plan only; applies go through CI"
    if prog in ("mvn", "mvnw", "./mvnw", "mvnw.cmd", "gradle", "gradlew", "./gradlew") or toks[0].endswith(("mvnw", "gradlew")):
        if re.search(r"flyway:clean|flywayClean", a):
            return "flyway clean drops every object in the schema - never run it from an agent"
    if prog in ("sh", "bash", "zsh", "python", "python3") and re.search(r"\b(curl|wget)\b", raw) and "|" in raw:
        return "piping a download into a shell - download, inspect, then run"
    if prog == "chmod" and re.search(r"-R\s+0?777|777\s+-R", a):
        return "chmod -R 777 - grant the specific permission needed"
    return None


def main():
    data = json.load(sys.stdin)
    cmd = data.get("tool_input", {}).get("command", "")
    for toks in subcommands(cmd):
        reason = check(toks, cmd)
        if reason:
            print(f"Blocked by guard_bash: {reason}.", file=sys.stderr)
            sys.exit(2)
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:                                   # fail closed
        print(f"guard_bash: internal error ({e}); blocking for safety.", file=sys.stderr)
        sys.exit(2)

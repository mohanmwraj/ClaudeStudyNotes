"""readonly_git.py - PreToolUse(Bash) guard for reviewer/auditor subagents: allow only read-only git and
listing commands (every subcommand of a compound command must be allowed; output redirection is refused).
Wire it in the agent's frontmatter `hooks:` (Folder 04 file 02). Exits 2 with the reason; fails closed.
"""
import json
import re
import shlex
import sys

GIT_READ = {"diff", "log", "show", "blame", "status", "ls-files", "grep", "rev-parse", "merge-base", "describe",
            "shortlog", "cat-file", "branch"}
READ_TOOLS = {"ls", "cat", "head", "tail", "wc", "grep", "rg", "find", "sort", "uniq", "cut", "awk", "sed", "jq", "tree"}


def allowed(toks):
    prog, args = toks[0], toks[1:]
    if prog == "git":
        sub = next((a for a in args if not a.startswith("-")), "")
        if sub == "branch" and any(a in ("-d", "-D", "-m", "-M", "--delete", "--move") for a in args):
            return False
        return sub in GIT_READ
    if prog == "find":
        return not any(a in ("-delete", "-exec", "-execdir", "-ok") for a in args)
    if prog == "sed":
        return not any(a.startswith("-i") for a in args)
    return prog in READ_TOOLS


def main():
    cmd = json.load(sys.stdin).get("tool_input", {}).get("command", "")
    if re.search(r"(^|[^2&])>|>>|\btee\b", cmd):
        print("readonly_git: output redirection is not allowed for a read-only reviewer.", file=sys.stderr)
        sys.exit(2)
    for part in re.split(r"&&|\|\||;|\||\n", cmd):
        toks = shlex.split(part) if part.strip() else []
        if toks and not allowed(toks):
            print(f"readonly_git: '{toks[0]} {' '.join(toks[1:2])}' is not read-only; reviewers report, they don't change code.",
                  file=sys.stderr)
            sys.exit(2)
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"readonly_git: internal error ({e}); blocking.", file=sys.stderr)
        sys.exit(2)

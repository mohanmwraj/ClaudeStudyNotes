"""block_secret_reads.py - PreToolUse(Read|Grep|Bash): keep credential files out of Claude's context.
Read deny rules already cover Read and Bash commands that NAME a file (cat, head, sed, redirections), but not
commands that read files without naming them as an argument Claude Code recognises (e.g. python -c "open(...)",
xargs, find -exec). This hook is the second layer: any mention of a secret path in a Bash command, or a
Read/Grep of one, is blocked. Java-specific: ~/.m2/settings.xml often holds repository passwords.
"""
import json
import re
import sys

SECRET_PATH = re.compile(r"""(^|[\s'"=/\\(:])(\.env(\.[\w.-]+)?|[\w.-]+\.(pem|key|p12|jks|keystore)|id_(rsa|ed25519|ecdsa)"""
                         r"""|\.aws[/\\]credentials|\.m2[/\\]settings(-security)?\.xml|\.npmrc|\.netrc|\.pgpass)"""
                         r"""(?=$|[\s'")])""")
ALLOWED = re.compile(r"\.env\.(example|sample|template)\b")


def main():
    data = json.load(sys.stdin)
    ti = data.get("tool_input", {})
    target = " ".join(str(ti.get(k, "")) for k in ("command", "file_path", "path", "pattern", "glob"))
    target = target.replace("\\", "/")
    m = SECRET_PATH.search(target)
    if m and not ALLOWED.search(target):
        print(f"block_secret_reads: '{m.group(2)}' holds credentials and must not enter the conversation. "
              "Ask the user for the specific non-secret value you need.", file=sys.stderr)
        sys.exit(2)
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"block_secret_reads: internal error ({e}); blocking for safety.", file=sys.stderr)
        sys.exit(2)

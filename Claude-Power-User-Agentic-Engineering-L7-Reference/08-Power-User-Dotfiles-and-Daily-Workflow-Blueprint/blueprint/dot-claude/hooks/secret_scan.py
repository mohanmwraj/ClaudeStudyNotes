"""secret_scan.py - PreToolUse(Write|Edit): refuse to write secrets into the repository. Scans the content being
written (Write `content`, Edit `new_string`) for credential patterns and denies with the secret TYPES found -
never echoing the values. Placeholders (${VAR}, changeme, <redacted>, example) are allowed.
"""
import json
import re
import sys

PATTERNS = [
    ("AWS access key id", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("private key block", re.compile(r"-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----")),
    ("Anthropic API key", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{20,}")),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}")),
    ("Slack token", re.compile(r"\bxox[abpr]-[A-Za-z0-9-]{10,}")),
    ("JWT", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
    ("password/secret assignment", re.compile(
        r"(?i)\b(password|passwd|secret|api[_-]?key|token)\b\s*[:=]\s*[\"']?(?!\$\{|<|changeme|example|redacted|\*{3})[^\s\"'#]{8,}")),
]


def main():
    ti = json.load(sys.stdin).get("tool_input", {})
    text = "\n".join(str(ti.get(k, "")) for k in ("content", "new_string"))
    found = sorted({name for name, rx in PATTERNS if rx.search(text)})
    if found:
        reason = (f"secret_scan: the content contains {', '.join(found)}. Do not commit secrets; reference an "
                  "environment variable or the secret store (e.g. ${DB_PASSWORD}) instead.")
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                                 "permissionDecisionReason": reason}}))
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"secret_scan: internal error ({e}); blocking for safety.", file=sys.stderr)
        sys.exit(2)

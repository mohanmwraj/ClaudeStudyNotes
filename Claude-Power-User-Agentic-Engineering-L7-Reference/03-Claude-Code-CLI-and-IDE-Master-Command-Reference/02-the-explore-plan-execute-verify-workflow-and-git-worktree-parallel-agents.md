# The Explore → Plan → Execute → Verify Workflow, and Git-Worktree Parallel Agents

> **Folder 03 · File 2 of 3** · verified 2026-10-30 against code.claude.com (best-practices, permission-modes, permissions, settings, sub-agents, worktrees, checkpointing)
> **Listings:** `settings_validator.py` (official JSON schema plus permission-rule traps) · `worktree_cleanup.sh` + `test_worktree_cleanup.sh` (safe cleanup of agent worktrees, tested on a throwaway repo)

---

## 0. Orientation

Claude Code's own diagnosis of failed sessions comes down to four causes [doc]:

1. Claude was missing information it couldn't see.
2. It had no check to run, so "looks done" was all it had.
3. A rule that can't have exceptions was only written down, not enforced.
4. The defaults cost more than the task was worth.

The four-phase loop below is how a staff engineer removes all four on every non-trivial change:

| Phase | Goal | Claude Code levers |
|---|---|---|
| **Explore** | Claude learns what it can't see: the code paths, the conventions, the traps | `/plan`, read-only exploration (the Explore subagent), `@path`, `/btw` |
| **Plan** | You approve *what* will change and *how it will be checked*, before any edit | Plan mode, `Ctrl+G` to edit the plan, an explicit verification section |
| **Execute** | Small, reviewable steps with checkpoints | `acceptEdits`/`auto`, `Esc` to steer, git commits, `/rewind` |
| **Verify** | A pass/fail check closes the loop, with evidence | Tests and builds, a `Stop` hook, `/code-review` in a fresh subagent, `/verify` |

The second half of the file scales this to parallel agents in git worktrees, and validates the permission settings that make unattended work safe.

### 0.1 The twelve rules

1. **Never let Claude start a multi-file change outside plan mode.** Auto mode is the default for new sessions, so planning is your choice to make. [doc]
2. **Explore in a read-only context.** In plan mode, Claude delegates research to the built-in *Plan* subagent, which can't write or edit and keeps exploration output out of your main context. [doc]
3. **Reject a plan that has no verification section.** Name the tests, commands and invariants that prove the change. [inference]
4. **Edit the plan, don't argue with it.** `Ctrl+G` opens it in your editor. [doc]
5. **Watch the first minute; `Esc` the moment it drifts.** After two failed corrections, `/clear` and write one better prompt. [doc]
6. **Commit before risky steps.** `/rewind` doesn't restore Bash-only changes or most subagent edits. [doc]
7. **Give Claude a check that returns pass or fail,** and ask for evidence (the command and its output), not "all tests pass". [doc]
8. **Enforce "done" with a `Stop` hook** when it must hold. The hook exits with code 2 to send Claude back to work. [doc]
9. **Review in a context that didn't write the code** (`/code-review`, or a second session). [doc]
10. **One task per worktree:** `claude -w <name>`. Copy small gitignored files with `.worktreeinclude`. Clean up `-p --worktree` runs yourself. [doc + measured: L2]
11. **Deny rules are evaluated first and block in every mode.** An allow rule can't carve an exception out of a deny. [doc + measured: L1]
12. **Validate settings in CI** against the official schema, *and* for the traps no schema catches. [measured: L1]

---

## 1. First principles

### 1.1 Why the loop exists: "Claude stops when the work looks done" [doc]

> "If it has nothing to run that tells it whether the work actually is done, 'looks done' is all it has to go on. In practice that makes you the test suite."

Every phase exists to remove one way the agent can be confidently wrong. Explore removes missing context. Plan removes building the wrong thing. Small execution steps remove unrecoverable drift. Verification removes "done" claims without evidence. Folder 02 file 02 gives the mathematics of the last one: a verifier-gated loop only ever adds correct answers.

### 1.2 Explore: let Claude read before it writes

- **Plan mode is read-only for your source.** Claude reads files and runs exploratory commands but makes no edits until you approve. Research is delegated to the built-in **Plan** subagent, which runs with read-only tools (Write and Edit denied), so that exploration output stays in a separate context [doc]. The built-in **Explore** subagent does the same outside plan mode. Both "start without your CLAUDE.md files and the git status snapshot to keep research fast and inexpensive" [doc].
- **Point at what matters.** `@src/main/java/com/acme/order/OrderService.java` includes a file (it also pulls in that directory's CLAUDE.md), and `@src/main/java/com/acme/order/` shows a listing [doc].
- **Ask for a map, not code.** For example: "List the classes involved in order creation, the transactions they open, and every outbound call. No code yet."
- **Keep side questions out of the trajectory** with `/btw` [doc].

### 1.3 Plan: approve the change *and* its check

Enter plan mode with `Shift+Tab`, `/plan <task>` or `claude --permission-mode plan`. When the plan is ready you choose [doc]:

- **Yes, and use auto mode** (or *Yes, auto-accept edits* when auto mode isn't available)
- **Yes, manually approve edits**
- **No, keep planning**

`Ctrl+G` opens the plan in your editor first. A setting (`showClearContextOnPlanAccept`) adds an option that approves the plan and clears the planning context.

What a staff-grade plan must contain [inference]:

1. The files to change, and the ones that must *not* change.
2. The invariants (Folder 02 file 01) and how each will be checked.
3. The test plan, with named tests including the edge cases.
4. Migration and rollout order (Flyway first; feature flag).
5. Risks, and what would make Claude stop and ask.

If the plan lacks items 2–3, reply "No, keep planning", and say which.

The `opusplan` model alias runs Opus for planning and Sonnet for execution. Each switch starts a fresh cache (Folder 01 file 03 §1.7), which is worth it for a short plan and a long execution.

### 1.4 Execute: small steps, checkpoints, steering

- **Mode.** `acceptEdits` auto-approves edits and common filesystem commands. `auto` adds classifier-reviewed commands. Both are fine *after* plan approval [doc].
- **Steer early.** "Watch the first minute, press `Esc` the moment Claude drifts" [doc].
- **Checkpoints.**
  - `/rewind` restores code, conversation or both to any prompt.
  - Bash-only changes are not restored, nor are most subagent edits, so `git commit` before a migration or a scripted refactor [doc].
- **Restart cleanly.** After two failed corrections, `/clear` and fold what you learned into one prompt. A third correction "mostly adds to a conversation that already contains two failed attempts" [doc].

### 1.5 Verify: deterministic where it must be

| Strength | How | Who enforces it |
|---|---|---|
| Prompt | "run `./mvnw -q verify` after, and keep going until it passes" | Claude |
| Goal | `/goal all tests in order-service pass and spotless is clean`: a separate model checks after every turn | Claude Code plus a model |
| **Stop hook** | A script runs when Claude tries to end its turn; **exit code 2** sends it back, with stderr as the reason | **Claude Code (deterministic)** |
| Fresh review | `/code-review` in a subagent that never saw the conversation; `/security-review` | Separate context |
| Runtime check | `/verify` builds and runs the app | Claude |

Always ask for **evidence**: the command that ran and its output [doc]. A Stop hook can block up to eight consecutive stops with no tool call between them, and then Claude Code lets the turn end [doc], so design the check to converge. Folder 05 builds `verify_build.py`.

### 1.6 Permissions and settings: the deterministic guardrails [doc]

**Settings precedence**, highest first:
1. Managed settings
2. Command line (`--settings`)
3. `.claude/settings.local.json` (personal, per project)
4. `.claude/settings.json` (shared, committed)
5. `~/.claude/settings.json` (user)

**List keys such as `permissions.allow` merge across files** rather than override. Environment variables are decided per key pair, not by level.

**Rule evaluation is deny → ask → allow, and the first match wins.** A broad `Bash(aws *)` deny blocks `aws s3 ls` even if that is explicitly allowed. Deny rules block in every mode including `bypassPermissions`, where allow rules have no effect.

**Bash rule syntax traps** (each is checked by L1):

| You write | What happens |
|---|---|
| `Bash(git log *)` | `git log` and every `git log …`; `*` after the subcommand is the safe form |
| `Bash(git * main)` | Every git subcommand ending in `main`, including `git -c core.fsmonitor=<script> diff main` |
| `Bash(ls*)` | Also matches `lsof`: no space before `*` |
| `Bash(git:* push)` | The colon is literal; `:*` is a wildcard only at the end |
| `Bash(command:rm *)` | Ignored: parameter rules can't target a tool's primary field |
| `mcp__github__create_issue(repo:x)` in settings | Skipped at load; MCP parameter denies go through `--disallowedTools` |

**Paths.** In `Read`/`Edit` rules, `/path` anchors to the primary working directory for project and local settings, but to `~/.claude/` for user settings. A leading `!` in a deny list is a gitignore-style negation (`Read(*.env)` then `Read(!sample.env)`) [doc].

**A rule that can't bend belongs here, not in CLAUDE.md.** "Never edit `src/gen/`" becomes `"deny": ["Edit(./src/gen/**)"]`, and "always format after editing" becomes a PostToolUse hook (Folder 05).

### 1.7 Parallel agents in worktrees [doc, measured: L2]

- **`claude -w <name>`** creates `<repo>/.claude/worktrees/<name>` on a new branch and starts there. `#<number>` or a PR/MR URL fetches that PR. `--tmux` opens panes [doc].
- **A worktree is a fresh checkout.** Gitignored files (`.env`) and dependencies aren't there:
  - List small gitignored files in **`.worktreeinclude`** (gitignore syntax). It *copies*, so keep it to small files.
  - Large directories go in `worktree.symlinkDirectories` [doc].
- **Cleanup.**
  - When you exit an unnamed worktree session with nothing in it, Claude Code removes the worktree; named or changed ones prompt you.
  - Subagent worktrees vanish when the subagent finishes without changes.
  - Leftover subagent and background-session worktrees are swept after `cleanupPeriodDays`.
  - **A `claude -p --worktree` run "is one you clean up yourself"**, and git refuses to remove a locked worktree until it is unlocked [doc].

  L2 is a cleanup script that removes only worktrees that are clean, merged and unlocked. Its test builds five worktrees and asserts that exactly one is removed.
- **Subagent isolation.** A subagent can request `isolation: worktree` and gets a temporary worktree (Folder 04).
- **Big mechanical changes.** `/batch <instruction>` plans 5–30 units, then runs each in its own worktree with its own PR [doc].
- **The second session is the cheapest independent reviewer.** One session writes the code; another reviews `@src/...` without having watched it being written [doc].
- **Cost.** Each parallel session builds its own context and cache (Folder 01 file 03 §1.6). Parallelise *independent* work only.

---

## 2. Practice

### 2.1 The four prompts for a Java feature

```text
[Explore - in plan mode]
/plan Map how order creation works today: entry points, transactions opened, outbound calls (Kafka, HTTP),
and the tests that cover it. Read docs/specs/order-idempotency.md. No code yet; end with open questions.

[Plan - still in plan mode]
Propose the change for docs/specs/order-idempotency.md. The plan must list: files to change and files that must not
change; each invariant INV-n with its check; named tests for EC-1..EC-4; migration order; what would make you stop.

[Execute - after approving with "Yes, manually approve edits" or auto]
Implement step 1 of the plan only (the Flyway migration and the repository). Run ./mvnw -q test -Dtest=OrderRepositoryIT
and show me the command output. Then stop.

[Verify]
Run ./mvnw -q verify. Paste the summary lines. Then fill in the spec's traceability table with the real test names.
```

Then run `/code-review` before you push.

### 2.2 The plan review checklist

- [ ] Does it touch only the files the spec allows?
- [ ] Is every invariant paired with a check, and every edge case with a named test?
- [ ] Does it do Flyway first, never edit an applied migration, and include a rollback note?
- [ ] Is there no transaction spanning Kafka/HTTP, and no `@Transactional` self-invocation?
- [ ] Does it say what would make Claude stop and ask?

### 2.3 Project permissions for a Java monorepo (`.claude/settings.json`)

This is the GOOD fixture from L1, validated against the official schema:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": ["Bash(./mvnw *)", "Bash(git status)", "Bash(git diff *)", "Bash(git log *)", "Bash(docker compose ps)"],
    "ask":   ["Bash(git push *)", "Bash(docker compose down *)"],
    "deny":  ["Read(./.env)", "Read(./.env.*)", "Read(./secrets/**)",
              "Bash(git push --force *)", "Bash(git reset --hard *)", "Bash(rm -rf *)"]
  },
  "hooks": { "...": "see Folder 05" },
  "effortLevel": "medium",
  "cleanupPeriodDays": 30
}
```

Two caveats from the permissions docs:
- Bash rules match the command *as written*. `git -C . push` isn't matched by `Bash(git push *)` [doc]. Deny rules are a strong first line; the PreToolUse hook in Folder 05 is the second.
- Personal tweaks go in `.claude/settings.local.json`, which is gitignored.

### 2.4 The parallel-worktree playbook

```bash
# one session per independent task, each in its own worktree and branch
claude -w order-idempotency          # interactive, at .claude/worktrees/order-idempotency
claude -w payment-retries
# headless runs: you own the cleanup afterwards
claude -p --worktree flaky-outbox "Fix OutboxIT flakiness; run ./mvnw -q verify -Pit and report the output"
# copy small gitignored files into every new worktree
printf '.env\napplication-local.yml\n' > .worktreeinclude
# later: classify and remove only clean, merged, unlocked worktrees
bash worktree_cleanup.sh --base=main            # dry run
bash worktree_cleanup.sh --base=main --apply
```

---

## 3. Verified listings

### L1 · `settings_validator.py`: official schema plus the traps the docs describe

**What it shows.**
- The official schemastore schema (142 top-level properties) plus 247 keys from the settings reference, giving 251 known keys.
- Ten checks (SV01–SV10). The BAD settings trip all ten, including two real schema errors: `effortLevel: max` (the schema enum is `low`…`xhigh`, matching the docs) and `cleanupPeriodDays: 0`.
- The GOOD Java-monorepo settings are clean.

**What it does not show.** Runtime behaviour. A rule can be valid and still not match the command Claude writes (`git -C . push`).

Run: `pip install jsonschema`, download the schema, then `CLAUDE_SETTINGS_SCHEMA=claude-code-settings.json python settings_validator.py`.

```python
"""settings_validator.py - validate .claude/settings.json the way CI should: against the official JSON
schema (https://json.schemastore.org/claude-code-settings.json, referenced by the settings docs) PLUS the
semantic traps the permissions docs describe, which no schema can catch:

  SV01 schema violation                   SV06 parameter rule on a tool's primary field (ignored)
  SV02 unknown top-level key (typo)        SV07 prefix rule without a space (`Bash(ls*)` also matches lsof)
  SV03 allow rule shadowed by a deny rule  SV08 bypassPermissions as defaultMode in shared settings
       (deny is evaluated first; an allow  SV09 no deny rule protecting secrets (.env, keys)
       cannot carve an exception out)      SV10 hook command not anchored at ${CLAUDE_PROJECT_DIR}
  SV04 `:*` before the end of a pattern (the colon is then literal)
  SV05 mcp__ rule with parentheses (skipped when settings load)

Needs: pip install jsonschema; CLAUDE_SETTINGS_SCHEMA=<path to the schemastore file>; optional
CLAUDE_DOCS_DIR=<folder with settings-reference.md> to accept keys the docs list but the schema lacks.
Run: python settings_validator.py   (prints ALL ASSERTIONS PASSED)
"""
import json
import os
import pathlib
import re

from jsonschema import Draft7Validator

SCHEMA = json.loads(pathlib.Path(os.environ["CLAUDE_SETTINGS_SCHEMA"]).read_text(encoding="utf-8"))
KNOWN = set(SCHEMA["properties"]) | {"$schema"}
docs = os.environ.get("CLAUDE_DOCS_DIR")
if docs and (pathlib.Path(docs) / "settings-reference.md").exists():
    ref = (pathlib.Path(docs) / "settings-reference.md").read_text(encoding="utf-8")
    KNOWN |= set(re.findall(r"^### `([A-Za-z][\w.]*)`", ref, flags=re.M))
VALIDATOR = Draft7Validator(SCHEMA)
PRIMARY_FIELDS = ("command", "file_path", "path", "notebook_path", "url")


def literal_prefix(rule):
    """'Bash(git push *)' -> 'git push '; rules without '*' are exact, prefix = whole command."""
    m = re.fullmatch(r"Bash\((.*)\)", rule)
    if not m:
        return None
    body = m.group(1)
    if body.endswith(":*"):
        body = body[:-2] + " *"
    return body.split("*", 1)[0]


def validate(doc, shared=True):
    f = []
    for e in sorted(VALIDATOR.iter_errors(doc), key=lambda e: list(e.path)):
        where = "/".join(str(p) for p in e.path) or "(root)"
        f.append(("SV01", f"{where}: {e.message[:110]}"))
    for key in doc:
        if key not in KNOWN:
            f.append(("SV02", f"unknown top-level key '{key}' - ignored by Claude Code (typo?)"))
    perms = doc.get("permissions", {})
    allow, deny = perms.get("allow", []), perms.get("deny", [])
    for a in allow:
        pa = literal_prefix(a)
        for d in deny:
            pd = literal_prefix(d)
            if pa is not None and pd is not None and pa.startswith(pd) and d.endswith("*)"):
                f.append(("SV03", f"allow {a} is shadowed by deny {d} - deny is evaluated first"))
    for r in allow + deny + perms.get("ask", []):
        if re.search(r":\*.", r.split("(", 1)[-1][:-1]) if "(" in r else False:
            f.append(("SV04", f"{r}: ':*' is only a wildcard at the end of a pattern; here the colon is literal"))
        if r.startswith("mcp__") and "(" in r:
            f.append(("SV05", f"{r}: mcp__ rules with parentheses are skipped when settings load; use --disallowedTools"))
        if re.match(r"\w+\((" + "|".join(PRIMARY_FIELDS) + r")\s*:", r):
            f.append(("SV06", f"{r}: a parameter rule on the tool's primary field is ignored"))
        m = re.fullmatch(r"Bash\(([A-Za-z][\w.-]*)\*\)", r)
        if m:
            f.append(("SV07", f"{r}: no space before '*' - also matches '{m.group(1)}of'-style commands; write Bash({m.group(1)} *)"))
    if shared and perms.get("defaultMode") == "bypassPermissions":
        f.append(("SV08", "defaultMode bypassPermissions in shared settings - docs: isolated containers and VMs only"))
    if shared and not any(re.match(r"Read\(.*(\.env|secret|\.pem|credentials)", d, re.I) for d in deny):
        f.append(("SV09", "no deny rule for secrets - add Read(./.env), Read(./.env.*), Read(./secrets/**)"))
    for event, groups in doc.get("hooks", {}).items():
        for g in groups:
            for h in g.get("hooks", []):
                cmd = h.get("command", "")
                if h.get("type") == "command" and re.search(r"(^|\s)(\./|\.\.?/)?[\w-]+/[\w./-]+\.(sh|py|ps1)", cmd) \
                        and "CLAUDE_PROJECT_DIR" not in cmd:
                    f.append(("SV10", f"hooks.{event}: '{cmd}' is a relative path - anchor it at ${{CLAUDE_PROJECT_DIR}}"))
    return f


GOOD = {
    "$schema": "https://json.schemastore.org/claude-code-settings.json",
    "permissions": {
        "allow": ["Bash(./mvnw *)", "Bash(git status)", "Bash(git diff *)", "Bash(git log *)", "Bash(docker compose ps)"],
        "ask": ["Bash(git push *)", "Bash(docker compose down *)"],
        "deny": ["Read(./.env)", "Read(./.env.*)", "Read(./secrets/**)", "Bash(git push --force *)",
                 "Bash(git reset --hard *)", "Bash(rm -rf *)"],
    },
    "hooks": {
        "PreToolUse": [{"matcher": "Bash", "hooks": [
            {"type": "command", "command": "python \"${CLAUDE_PROJECT_DIR}/.claude/hooks/guard_bash.py\"", "timeout": 10}]}],
        "PostToolUse": [{"matcher": "Edit|Write", "hooks": [
            {"type": "command", "command": "python \"${CLAUDE_PROJECT_DIR}/.claude/hooks/format_java.py\"", "timeout": 120}]}],
        "Stop": [{"hooks": [
            {"type": "command", "command": "python \"${CLAUDE_PROJECT_DIR}/.claude/hooks/verify_build.py\"", "timeout": 600}]}],
    },
    "env": {"MAVEN_OPTS": "-Xmx2g"},
    "effortLevel": "medium",
    "cleanupPeriodDays": 30,
}

BAD = {
    "permission": {"allow": ["Bash"]},
    "permissions": {
        "defaultMode": "bypassPermissions",
        "allow": ["Bash(git push origin feature/*)", "Bash(ls*)", "Bash(git:* status)",
                  "mcp__github__create_issue(repo:acme)"],
        "deny": ["Bash(git push *)", "Bash(command:rm *)"],
    },
    "effortLevel": "max",
    "cleanupPeriodDays": 0,
    "hooks": {"PostToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": "./scripts/format.sh"}]}]},
}

print(f"schema: {len(SCHEMA['properties'])} properties; known keys incl. settings reference: {len(KNOWN)}")
for label, doc, expected in [("BAD project settings", BAD, {f"SV{i:02d}" for i in range(1, 11)}),
                             ("GOOD project settings (Java 21 monorepo)", GOOD, set())]:
    found = validate(doc)
    codes = {c for c, _ in found}
    print(f"--- {label}: {len(found)} finding(s) {sorted(codes)}")
    for code, msg in found:
        print(f"  {code} {msg}")
    assert codes == expected, (label, sorted(codes))
print("--- GOOD settings, as committed to .claude/settings.json:")
print(json.dumps(GOOD, indent=2))
print("ALL ASSERTIONS PASSED")
```

**Output (verified):**

```text
schema: 142 properties; known keys incl. settings reference: 251
--- BAD project settings: 11 finding(s) ['SV01', 'SV02', 'SV03', 'SV04', 'SV05', 'SV06', 'SV07', 'SV08', 'SV09', 'SV10']
  SV01 cleanupPeriodDays: 0 is less than the minimum of 1
  SV01 effortLevel: 'max' is not one of ['low', 'medium', 'high', 'xhigh']
  SV02 unknown top-level key 'permission' - ignored by Claude Code (typo?)
  SV03 allow Bash(git push origin feature/*) is shadowed by deny Bash(git push *) - deny is evaluated first
  SV07 Bash(ls*): no space before '*' - also matches 'lsof'-style commands; write Bash(ls *)
  SV04 Bash(git:* status): ':*' is only a wildcard at the end of a pattern; here the colon is literal
  SV05 mcp__github__create_issue(repo:acme): mcp__ rules with parentheses are skipped when settings load; use --disallowedTools
  SV06 Bash(command:rm *): a parameter rule on the tool's primary field is ignored
  SV08 defaultMode bypassPermissions in shared settings - docs: isolated containers and VMs only
  SV09 no deny rule for secrets - add Read(./.env), Read(./.env.*), Read(./secrets/**)
  SV10 hooks.PostToolUse: './scripts/format.sh' is a relative path - anchor it at ${CLAUDE_PROJECT_DIR}
--- GOOD project settings (Java 21 monorepo): 0 finding(s) []
--- GOOD settings, as committed to .claude/settings.json:
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(./mvnw *)",
      "Bash(git status)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(docker compose ps)"
    ],
    "ask": [
      "Bash(git push *)",
      "Bash(docker compose down *)"
    ],
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)",
      "Bash(git push --force *)",
      "Bash(git reset --hard *)",
      "Bash(rm -rf *)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python \"${CLAUDE_PROJECT_DIR}/.claude/hooks/guard_bash.py\"",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python \"${CLAUDE_PROJECT_DIR}/.claude/hooks/format_java.py\"",
            "timeout": 120
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python \"${CLAUDE_PROJECT_DIR}/.claude/hooks/verify_build.py\"",
            "timeout": 600
          }
        ]
      }
    ]
  },
  "env": {
    "MAVEN_OPTS": "-Xmx2g"
  },
  "effortLevel": "medium",
  "cleanupPeriodDays": 30
}
ALL ASSERTIONS PASSED
```

### L2 · `worktree_cleanup.sh` and its test

**What it shows.** A cleanup script that classifies the worktrees under `.claude/worktrees/` as DIRTY, UNMERGED, LOCKED or REMOVABLE, and removes only the removable ones (worktree plus merged branch). The test builds five worktrees in a throwaway repo:
- merged and clean
- dirty (untracked file)
- ahead (unmerged commit)
- locked (as Claude Code locks a running agent's worktree)
- outside `.claude/worktrees/`

It then asserts that only the first is removed.

**What it does not show.** Worktrees made by non-git VCS hooks.

Run: `bash test_worktree_cleanup.sh` (git ≥ 2.28; tested with git 2.54).

```bash
# worktree_cleanup.sh - classify the git worktrees under .claude/worktrees/ and remove only the safe ones.
#
# Claude Code cleans up most worktrees itself, but a `claude -p --worktree` run "is one you clean up yourself"
# (code.claude.com best practices). This script never removes work: a worktree is removed only if it has no
# uncommitted or untracked changes, its branch has no commits missing from the base branch, and it is not
# locked (Claude Code holds a `git worktree lock` while an agent runs in it).
#
# Usage: bash worktree_cleanup.sh [--base=<branch>] [--apply]     (dry run unless --apply)
set -euo pipefail

apply=0
base=""
for arg in "$@"; do
  case "$arg" in
    --apply) apply=1 ;;
    --base=*) base="${arg#--base=}" ;;
    *) echo "unknown argument: $arg" >&2; exit 64 ;;
  esac
done

root="$(git rev-parse --show-toplevel)"
[ -n "$base" ] || base="$(git -C "$root" symbolic-ref --quiet --short HEAD)"

classify() {  # path branch locked -> prints STATUS
  local path="$1" branch="$2" locked="$3"
  if [ -n "$(git -C "$path" status --porcelain)" ]; then echo DIRTY; return; fi
  if [ -n "$branch" ] && [ "$(git -C "$root" rev-list --count "$base..$branch")" != "0" ]; then echo UNMERGED; return; fi
  if [ "$locked" = "1" ]; then echo LOCKED; return; fi
  echo REMOVABLE
}

report() {  # path branch locked
  local path="$1" branch="$2" locked="$3" status action
  case "$path" in */.claude/worktrees/*) ;; *) return ;; esac
  status="$(classify "$path" "$branch" "$locked")"
  case "$status" in
    DIRTY) action="keep (uncommitted or untracked files)" ;;
    UNMERGED) action="keep (commits not in $base)" ;;
    LOCKED) action="keep (locked - an agent may be running; unlock only after it ends)" ;;
    REMOVABLE)
      if [ "$apply" = "1" ]; then
        git -C "$root" worktree remove "$path"
        [ -z "$branch" ] || git -C "$root" branch -q -d "$branch"
        action="removed worktree and merged branch"
      else
        action="would remove (pass --apply)"
      fi ;;
  esac
  printf '%-10s %-10s %s\n' "$(basename "$path")" "$status" "$action"
}

path="" branch="" locked=0
while IFS= read -r line || [ -n "$path" ]; do
  case "$line" in
    "worktree "*) path="${line#worktree }"; branch=""; locked=0 ;;
    "branch refs/heads/"*) branch="${line#branch refs/heads/}" ;;
    "locked"*) locked=1 ;;
    "")
      [ -z "$path" ] || report "$path" "$branch" "$locked"
      path="" ;;
  esac
done < <(git -C "$root" worktree list --porcelain; echo)
```

```bash
# test_worktree_cleanup.sh - build a throwaway repo with five worktrees (merged, dirty, ahead, locked, and one
# outside .claude/worktrees/), run worktree_cleanup.sh dry and with --apply, and assert that only the clean,
# merged, unlocked worktree under .claude/worktrees/ is removed.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

git init -q -b main "$tmp/repo"
cd "$tmp/repo"
echo a > a.txt && git add a.txt && git commit -qm init
git worktree add -q -b wt-merged .claude/worktrees/merged main
git worktree add -q -b wt-dirty .claude/worktrees/dirty main
echo scratch > .claude/worktrees/dirty/notes.txt
git worktree add -q -b wt-ahead .claude/worktrees/ahead main
( cd .claude/worktrees/ahead && echo b > b.txt && git add b.txt && git commit -qm "agent work" )
git worktree add -q -b wt-locked .claude/worktrees/locked main
git worktree lock --reason "claude agent running" .claude/worktrees/locked
git worktree add -q -b manual "$tmp/manual-checkout" main

echo "--- dry run"
bash "$here/worktree_cleanup.sh" --base=main
echo "--- --apply"
bash "$here/worktree_cleanup.sh" --base=main --apply
echo "--- worktrees left"
left="$(git worktree list --porcelain | sed -n 's#^worktree .*/##p' | sort | tr '\n' ' ')"
echo "$left"

[[ "$left" == *dirty* && "$left" == *ahead* && "$left" == *locked* && "$left" == *manual-checkout* ]]
[[ "$left" != *merged* ]]
! git show-ref --verify --quiet refs/heads/wt-merged
git show-ref --verify --quiet refs/heads/wt-ahead
git worktree unlock .claude/worktrees/locked
echo "ALL ASSERTIONS PASSED"
```

**Output (verified):**

```text
--- dry run
ahead      UNMERGED   keep (commits not in main)
dirty      DIRTY      keep (uncommitted or untracked files)
locked     LOCKED     keep (locked - an agent may be running; unlock only after it ends)
merged     REMOVABLE  would remove (pass --apply)
--- --apply
ahead      UNMERGED   keep (commits not in main)
dirty      DIRTY      keep (uncommitted or untracked files)
locked     LOCKED     keep (locked - an agent may be running; unlock only after it ends)
merged     REMOVABLE  removed worktree and merged branch
--- worktrees left
ahead dirty locked manual-checkout repo 
ALL ASSERTIONS PASSED
```

---

## 4. Failure modes

| # | Symptom | Root cause | Fix | Prevention |
|---|---|---|---|---|
| F1 | A sprawling change you didn't expect | No plan approval; the auto mode default | `/plan` first; reject plans without verification | Team norm; `defaultMode: plan` per project if wanted |
| F2 | "Done", but CI is red | No check, or claims without evidence | Ask for command output; a Stop hook | Folder 05 `verify_build.py` |
| F3 | `/rewind` left the DB migration applied | Bash changes aren't checkpointed | Commit before risky steps; down-migrations | Plan item: rollback |
| F4 | Allowed command still blocked | A broader deny matches first | Narrow the deny | L1 SV03 |
| F5 | Permission rule silently ignored | Typo key, `:*` mid-pattern, primary-field parameter rule, MCP rule in settings | Fix the syntax | L1 in CI |
| F6 | Parallel agents trample each other | Same checkout | One worktree per task | `claude -w` |
| F7 | A worktree session fails on startup | Missing `.env` or dependencies | `.worktreeinclude`; install command in CLAUDE.md | — |
| F8 | Disk fills with old worktrees | `-p --worktree` runs are never cleaned | L2 cleanup in a scheduled job | L2 |
| F9 | Reviewer agrees with the author | Same context reviewed its own work | `/code-review` or a second session | Folder 02 file 02 |

---

## 5. Staff-level drills

<details><summary><b>D1 · "Plan mode slows us down. Why not let auto mode just do it?"</b></summary>

**Staff answer.** For one-file changes, do let it. For multi-file changes, the plan is the cheapest review you'll ever do: about a page instead of a diff. It catches wrong-design errors before they cost an execution run.

Plan research runs in the read-only Plan subagent, so it doesn't pollute your context. Approve with "Yes, and use auto mode" and you lose nothing afterwards.
</details>

<details><summary><b>D2 · "Our CLAUDE.md says 'never edit src/gen', and Claude edited it anyway."</b></summary>

**Staff answer.** CLAUDE.md is context, not enforced configuration [doc]. Make it deterministic with `"deny": ["Edit(./src/gen/**)"]`, and optionally a PreToolUse hook with a helpful message pointing at `api/openapi.yaml`. Remove the line from CLAUDE.md or keep it as an explanation, because the deny rule is now the guarantee.
</details>

<details><summary><b>D3 · "We allowed <code>Bash(git push origin feature/*)</code> but pushes still prompt or fail."</b></summary>

**Staff answer.** A deny such as `Bash(git push *)` matches first: deny → ask → allow, first match wins, and an allow can't carve an exception out of a deny. Replace the broad deny with targeted ones (`Bash(git push --force *)`, `Bash(git push * main)`), or move push to `ask`. L1's SV03 flags this.
</details>

<details><summary><b>D4 · "How do we run five agents on five tickets safely?"</b></summary>

**Staff answer.**
- Give each its own worktree (`claude -w <ticket>`) or background session.
- Copy small gitignored config via `.worktreeinclude`.
- Make each task carry its own check (a test command), and ask for evidence.
- Review each in a fresh context (`/code-review`).
- Clean up headless worktrees with a script that never deletes work (L2).
- Budget tokens: each session pays for its own context.
- Don't parallelise dependent changes; serialise them, or use `/batch` for mechanical ones.
</details>

<details><summary><b>D5 · "Which settings file should a rule go in?"</b></summary>

**Staff answer.**
- **Team rules** (deny secrets, allow the build) go in `.claude/settings.json`, committed.
- **Personal** preferences go in `.claude/settings.local.json`.
- **Cross-project personal** settings go in `~/.claude/settings.json`.
- **Organisation-wide** rules that nobody may override go in managed settings.

Lists merge across files, so a team deny can't be removed by a personal allow.
</details>

---

## 6. Checklist

- [ ] Multi-file work starts in plan mode, and plans carry a verification section.
- [ ] Every task has a pass/fail check, and Claude reports the command output.
- [ ] Must-hold rules are deny rules or hooks; `.claude/settings.json` is validated in CI (L1).
- [ ] Risky Bash steps are preceded by a commit.
- [ ] Parallel work uses one worktree per task; headless worktrees are cleaned by a safe script (L2).
- [ ] Reviews run in a fresh context.

---

## 7. References

- Best practices: <https://code.claude.com/docs/en/best-practices>
- Permission modes (plan, auto, dontAsk, bypassPermissions): <https://code.claude.com/docs/en/permission-modes>
- Configure permissions (rule syntax, evaluation order, paths): <https://code.claude.com/docs/en/permissions>
- Settings files and precedence: <https://code.claude.com/docs/en/settings>
- Settings reference (every key): <https://code.claude.com/docs/en/settings-reference>
- JSON schema for settings: <https://json.schemastore.org/claude-code-settings.json>
- Subagents (built-in Explore, Plan, general-purpose): <https://code.claude.com/docs/en/sub-agents>
- Worktrees: <https://code.claude.com/docs/en/worktrees>
- Checkpointing: <https://code.claude.com/docs/en/checkpointing>
- Common workflows: <https://code.claude.com/docs/en/common-workflows>

Previous: [01 · Cheat sheet](01-complete-slash-commands-cli-flags-and-keyboard-shortcuts-cheat-sheet.md) · Next: [03 · CLAUDE.md and memory](03-crafting-the-perfect-under-200-line-claude-md-and-hierarchical-memory.md) · [KB README](../README.md)

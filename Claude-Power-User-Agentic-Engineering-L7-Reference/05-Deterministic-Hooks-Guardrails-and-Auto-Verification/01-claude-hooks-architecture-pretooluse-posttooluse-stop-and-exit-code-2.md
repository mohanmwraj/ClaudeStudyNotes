# Claude Hooks Architecture: PreToolUse, PostToolUse, Stop, and Exit Code 2

> **Folder 05 · File 1 of 2** · verified 2026-10-30 against code.claude.com `hooks.md` (the 4,244-line reference), `hooks-guide.md`, `best-practices.md`, `permissions.md`
> **Listing:** `hook_contract_lab.py` (the documented decision contract as executable test vectors)

---

## 0. Orientation

CLAUDE.md, prompts and skills are *non-deterministic*: the model reads them and usually complies. **Hooks are deterministic**: the harness runs your program at fixed points in the agent loop, and your program's exit code and JSON decide what happens next, whatever the model intended.

Claude Code's own rule of thumb: "If you keep adding emphasis to a CLAUDE.md line and Claude still misses it, that's a sign the line belongs in a hook. The reverse holds too: if you have hooks for things that are only preferences, delete them" [doc].

This file is the contract: events, configuration, input, output, exit-code semantics, precedence with permission rules, loop limits, the trust model and Windows specifics. File 02 is the implementation: ten production hooks for a Java monorepo, each tested.

### 0.1 The twelve rules

1. **Exit 0 = proceed (and apply any JSON). Exit 2 = block (on events that can block), with stderr as the reason. Any other exit = non-blocking error: the action proceeds.** "Exit 1 blocks" is folklore. [doc + measured: L1]
2. **A crashing security hook fails *open* by default.** Set `"onFailure": "block"` on guards (v2.1.295+), and make the script itself exit 2 on internal errors. [doc + measured: L1]
3. **PreToolUse decides through `hookSpecificOutput.permissionDecision`** (`allow`/`deny`/`ask`/`defer`, plus `updatedInput`). The old top-level `decision: approve/block` is deprecated for this event. [doc]
4. **Several hooks combine as deny > defer > ask > allow, and permission rules still apply:** a deny or ask rule wins even when your hook says `allow`. [doc + measured: L1]
5. **PostToolUse can't undo a tool call.** Exit 2 shows stderr to Claude; `decision: "block"` adds a reason; `updatedToolOutput` replaces the output. [doc]
6. **A Stop hook exiting 2 sends Claude back to work.** After 8 consecutive continuations with no tool call in between, Claude Code overrides the next block. [doc + measured: L1]
7. **Matchers:** names-only text is an exact list (`Edit|Write`, `Edit, Write`); anything else is an *unanchored* regex (`Edit.*` also matches `NotebookEdit`; use `^Edit$`). [doc + measured: L1]
8. **The default timeout is 600 s for command hooks** (30 s on `UserPromptSubmit` and model-switch events; 30 s for prompt hooks; 60 s for agent hooks). Set tight explicit timeouts on hot-path hooks. [doc]
9. **Use exec form** (`"command": "python", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/x.py"]`) so placeholder paths need no quoting. [doc]
10. **On Windows, `tool_input.file_path` arrives absolute with backslashes,** even under Git Bash. Normalise before matching, or your `/src/` check silently never fires. [doc + measured: file 02]
11. **Interactive sessions hold back all settings-file hooks until workspace trust is accepted.** `claude -p` never asks and treats the folder as trusted. Use `--bare` or `disableAllHooks` for untrusted repos. [doc]
12. **Hooks are code on the hot path:** each PreToolUse hook runs on every matching tool call. Keep them fast, deterministic and tested (file 02 has 40 cases). [inference + measured]

---

## 1. First principles

### 1.1 Where hooks sit in the loop [doc]

Events fire at three cadences:
- **Per session:** `SessionStart`, `SessionEnd`.
- **Per turn:** `UserPromptSubmit`, `Stop`, `StopFailure`.
- **Per tool call:** `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PostToolUseFailure`, and `PostToolBatch` after a batch of parallel calls.

Others cover subagents, compaction, configuration, files, worktrees, model switches and MCP elicitation.

| Event | Matcher filters on | Can exit 2 block? | Typical use |
|---|---|---|---|
| `PreToolUse` | tool name | **Yes**: blocks the call | Guards: destructive commands, protected paths, secrets |
| `PermissionRequest` | tool name | No (use its `decision` object) | Auto-answer permission prompts in your own UI |
| `PostToolUse` | tool name | No: Claude sees stderr | Format, lint, annotate, audit |
| `PostToolBatch` | — | Yes: stops the loop before the next model call | Batch-level checks |
| `UserPromptSubmit` | — | **Yes**: rejects the prompt | Block pasted secrets; add context |
| `Stop` / `SubagentStop` | — | **Yes**: Claude keeps working | "Done" gates: build, tests |
| `SessionStart` | `startup`, `resume`, `clear`, `compact`, `fork` | No | Inject context (plain stdout becomes context) |
| `PreCompact` | `manual`, `auto` | Yes: blocks compaction | Save state before compaction |
| `InstructionsLoaded` | — | No | Audit which CLAUDE.md and rules loaded |
| `ConfigChange` | — | Yes (except policy settings) | Prevent mid-session config tampering |
| `WorktreeCreate` / `WorktreeRemove` | — | Any non-zero fails the operation | Non-git VCS |
| `PreModelSwitch` | model name | Yes | Forbid expensive models on a route |

### 1.2 Configuration: event → matcher group → handlers [doc]

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "python",
            "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/guard_bash.py"],
            "timeout": 10, "onFailure": "block" }
        ] }
    ]
  }
}
```

**Locations:** `~/.claude/settings.json`, `.claude/settings.json` (committed), `.claude/settings.local.json`, managed policy, a plugin's `hooks/hooks.json`, skill frontmatter (active after the skill is invoked) and subagent frontmatter (active while the agent runs).

**Handler types:**
- `command`: stdin JSON; exit code plus stdout.
- `http`: POSTs the JSON; the response body uses the same JSON format.
- `mcp_tool`: calls a tool on a configured server.
- `prompt`: single-turn LLM evaluation returning JSON.
- `agent`: a subagent with Read/Grep/Glob that verifies a condition (experimental).

**Common fields:**
- `if`: permission-rule syntax filter, such as `"Bash(git *)"`. It checks every subcommand, `$()`, and leading env assignments.
- `timeout` (seconds) and `statusMessage`.
- `once`: honoured only in skill frontmatter.

**Command fields:**
- `command`, and `args` (exec form, with no shell).
- `async` (background; results delivered next turn) and `asyncRewake` (wakes Claude on exit 2).
- `shell` (`bash` or `powershell`).
- `onFailure` (`continue` or `block`).

### 1.3 Input [doc]

Every handler receives these common fields:
- `session_id`, `prompt_id`, `transcript_path` (written asynchronously, so it may lag)
- `cwd`, `scratchpad_dir`
- `permission_mode` (Manual arrives as `"default"`)
- `effort.level`, `hook_event_name`
- inside subagents, `agent_id` and `agent_type`

Event-specific fields:

| Event | Adds |
|---|---|
| `PreToolUse` | `tool_name`, `tool_input` (Bash: `command`, `description`, `timeout`, `run_in_background`; file tools: **absolute** `file_path`), `tool_use_id`; MCP tools: `mcp_server` |
| `PostToolUse` | `tool_input`, `tool_response`, `tool_use_id`, `duration_ms` |
| `Stop` | `stop_hook_active`, `last_assistant_message`, `background_tasks`, `session_crons` |
| `SessionStart` | `source`, optionally `model`, `agent_type`, `session_title` |
| `UserPromptSubmit` | `prompt` |

### 1.4 Output: the exit-code × stdout table [doc, measured: L1]

| Stdout | Exit 0 | Exit 2 | Any other exit |
|---|---|---|---|
| JSON object that passes validation | Success; the fields apply | **Blocking error**; fields read but *can't override the block* (even `"allow"`) | Success; the exit code is ignored and the fields decide |
| JSON that fails to parse or validate | Non-blocking error | Blocking error; stderr is the reason | Non-blocking error |
| Plain text or nothing | Success | Blocking error; stderr is the reason | Non-blocking error (first stderr line in the notice) |

Consequences:
- **Pick one channel.** Either exit 2 with stderr, or exit 0 with a JSON decision. Mixing them is legal, but exit 2 always wins.
- **Claude never sees stderr from an exit-0 hook.** To warn Claude from PostToolUse, exit 2.
- **Plain stdout is context only on `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart` and `PostModelSwitch`.** Elsewhere it goes to the debug log.
- **Universal JSON fields:** `continue: false` (stop processing; takes precedence) plus `stopReason`; `systemMessage` (a warning to the user); `terminalSequence` (OSC notifications). `suppressOutput` is accepted but has no effect.

### 1.5 Event-specific decisions [doc]

| Event | Decision fields |
|---|---|
| `PreToolUse` | `hookSpecificOutput.permissionDecision`: `allow` (skips the prompt, but not deny/ask rules or protected paths), `deny`, `ask` (prompt the user, labelled `[settings]`/`[plugin:…]`/`[skill]`), `defer`; plus `permissionDecisionReason`, `updatedInput` (replaces the entire input), `additionalContext` |
| `PostToolUse` | `decision: "block"` + `reason` (added next to the result), `additionalContext`, `updatedToolOutput`, `classifierContext` (a note for auto mode's classifier) |
| `Stop` / `SubagentStop` | `decision: "block"` + `reason` (required), or `hookSpecificOutput.additionalContext` (feedback without an error) |
| `UserPromptSubmit` | `decision: "block"` + `reason` (shown to the user, not added to context), `additionalContext`, `sessionTitle`, `suppressOriginalPrompt` |

**Precedence:** across several PreToolUse hooks, **deny > defer > ask > allow**. Hooks don't bypass permission rules: "a matching deny rule blocks the call, and a matching ask rule still prompts even when the hook returned `allow`" [doc]. L1 encodes all six combinations.

### 1.6 Loop protection on Stop [doc, measured: L1]

A Stop hook that blocks forever would trap the session. Claude Code protects against that two ways:
- Input carries `stop_hook_active: true` when the current continuation came from a Stop hook.
- There is an **8-consecutive-continuation cap**: after eight continuations in a row, the next block is overridden. The count resets whenever Claude calls a tool.

Design Stop checks that converge: a real build or test command whose failure Claude can fix. Never gate on "Claude said the magic word". `/goal` is "a built-in shortcut for a session-scoped prompt-based Stop hook" [doc].

### 1.7 Prompt and agent hooks [doc]

`type: "prompt"` sends the event plus your prompt to a Claude model for a single-turn yes/no decision, returned as JSON (default timeout 30 s). `type: "agent"` spawns a subagent with read tools to verify a condition before deciding (60 s; experimental).

Use them when the condition needs judgment ("is the task in the spec actually done?"). Use command hooks when a program can decide, because programs are cheaper, faster and reproducible.

### 1.8 Async hooks [doc]

`"async": true` (command hooks only) starts the process and continues immediately. `additionalContext` and `systemMessage` arrive on the next turn, and `timeout` isn't enforced. In `-p` mode, async hooks still running at teardown are killed. Use it for slow, non-blocking work like a background test run after edits. **Never** use it for guards.

### 1.9 Trust and security [doc]

- **Interactive sessions:** hooks from *every* settings file, your own included, are held back until you accept the workspace trust dialog. Project *subagent* frontmatter hooks need trust of that folder specifically.
- **`claude -p` and the SDK:** no dialog, and the folder is treated as trusted, so a repository's committed hooks run. Review `.claude/`, start with `--bare`, or set `disableAllHooks`. Managed hooks can only be disabled at the managed level.
- **The docs' practices:** validate inputs, quote variables, block `..` traversal, use absolute paths (exec form), skip sensitive files.
- **Hooks run with your user's privileges.** A malicious hook is malware. Review hook diffs like CI changes.

### 1.10 Windows specifics [doc]

- `file_path` uses backslashes (`C:\project\src\Foo.java`). Normalise: `path.replace("\\", "/")` in Python, or `FILE_PATH="${FILE_PATH//\\//}"` in Bash.
- Hooks run in Git Bash by default. `"shell": "powershell"` runs PowerShell (`pwsh` preferred), and PowerShell is the default when Git Bash isn't installed.
- In PowerShell, write `${CLAUDE_PROJECT_DIR}` or `$env:CLAUDE_PROJECT_DIR`, **never** bare `$CLAUDE_PROJECT_DIR`, which resolves to `$null`.
- `python` vs `python3`: exec form resolves `command` on `PATH`, so pick the name that exists on every developer machine and CI image, or wrap it in a launcher.

### 1.11 Debugging [doc]

- `/hooks` shows the configured hooks.
- `claude --debug` (or `--debug-file`) logs hook execution, parse errors and stdout.
- `Ctrl+O` shows async completions.
- Edits to settings files are picked up by a file watcher.

---

## 2. Practice: minimal recipes

**Block a command family (exit 2):**

```python
import json, sys
cmd = json.load(sys.stdin)["tool_input"]["command"]
if "flyway:clean" in cmd:
    print("flyway:clean drops the schema; never run it from an agent.", file=sys.stderr)
    sys.exit(2)
```

**Deny with a reason (JSON, exit 0):**

```json
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
  "permissionDecisionReason": "applied Flyway migrations are immutable; add V7__...sql"}}
```

**"Done means green" (Stop; the docs' pattern adapted to Maven):**

```json
{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "./mvnw -q -o verify -DskipITs 1>&2 || exit 2"}]}]}}
```

**Context at session start (plain stdout becomes context):**

```bash
echo "branch: $(git rev-parse --abbrev-ref HEAD); failing tests: $(ls target/surefire-reports/*.txt 2>/dev/null | wc -l)"
```

**Reject a prompt containing a pasted key (UserPromptSubmit):**

```json
{"decision": "block", "reason": "Your prompt contains what looks like an AWS key; remove it and rotate the key."}
```

---

## 3. Verified listing

### L1 · `hook_contract_lab.py`

**What it shows.**
- Fourteen outcome-table vectors, covering exit 0/1/2 × JSON / invalid JSON / plain text, `onFailure: block`, PostToolUse and PermissionRequest exit-2 behaviour, a Stop block via exit code and via JSON, and `continue: false`.
- Six precedence vectors, including hook `allow` overridden by a deny or ask rule.
- The Stop cap: 8 continuations then an override, with a reset after a tool call.
- Eight matcher vectors, including `Edit.*` matching `NotebookEdit`.

**What it does not show.** Every event's special cases. Read the event's section in the hooks reference before relying on an edge case.

Run: `python hook_contract_lab.py`.

```python
"""hook_contract_lab.py - Claude Code's hook decision contract as executable test vectors.

Encodes, from the hooks reference (code.claude.com, 2026-10-30): the exit-code x stdout outcome table; which
events exit code 2 can block; onFailure: "block" (fail closed); PreToolUse decision precedence across several
hooks (deny > defer > ask > allow); permission rules still applying after a hook says allow; the Stop hook's
8-consecutive-continuation cap; and matcher semantics (exact names vs unanchored regex). Writing hooks
against this model - not against folklore like "exit 1 blocks" - is what makes them deterministic.

Run: python hook_contract_lab.py   (stdlib only; prints ALL ASSERTIONS PASSED)
"""
import json
import re

CAN_BLOCK = {"PreToolUse", "UserPromptSubmit", "UserPromptExpansion", "Stop", "SubagentStop", "TeammateIdle",
             "TaskCreated", "TaskCompleted", "ConfigChange", "PostToolBatch", "PreCompact", "PreModelSwitch",
             "Elicitation", "ElicitationResult", "WorktreeCreate", "WorktreeRemove"}
STDERR_TO_CLAUDE = {"PostToolUse", "PostToolUseFailure"}          # exit 2 can't block; Claude sees stderr


def classify_stdout(stdout):
    s = stdout.strip()
    if not (s.startswith("{") and s.endswith("}")):
        return "text", None
    try:
        obj = json.loads(s)
        return ("json", obj) if isinstance(obj, dict) else ("text", None)
    except json.JSONDecodeError:
        return "bad_json", None


def outcome(event, code, stdout="", stderr="", on_failure=None):
    kind, obj = classify_stdout(stdout)
    if code == 2:
        if event in CAN_BLOCK:
            reason = (obj or {}).get("reason") or (obj or {}).get("hookSpecificOutput", {}).get(
                "permissionDecisionReason") or stderr.strip()
            return f"BLOCK ({reason})"
        if event in STDERR_TO_CLAUDE:
            return f"PROCEED, Claude sees stderr ({stderr.strip()})"
        return "PROCEED (exit 2 not honored for this event)"
    if kind == "json":                       # exit 0 or any other code: the JSON fields alone decide
        d = obj.get("hookSpecificOutput", {}).get("permissionDecision") or obj.get("decision")
        if obj.get("continue") is False:
            return f"STOP SESSION ({obj.get('stopReason', '')})"
        return f"FIELDS APPLY (decision={d or 'none'})"
    if code == 0 and kind == "text":
        return "PROCEED"
    if on_failure == "block":
        return "BLOCK (hook failed and onFailure=block)"
    return "PROCEED with non-blocking error notice"


def merge_pretooluse(decisions, rule=None):
    """Several PreToolUse hooks: deny > defer > ask > allow. Deny/ask permission rules still apply after allow."""
    order = ["deny", "defer", "ask", "allow"]
    hook = next((d for d in order if d in decisions), None)
    if hook == "deny" or rule == "deny":
        return "deny"
    if hook == "ask" or rule == "ask":
        return "ask"
    return hook or "normal permission flow"


def stop_cap(blocks_with_tool_calls):
    """Each entry: (hook_blocks, tool_called_before_next_stop). After 8 consecutive continuations, the next block
    is overridden and the turn ends; a tool call resets the count."""
    streak, log = 0, []
    for blocks, tool_called in blocks_with_tool_calls:
        if not blocks:
            log.append("stop")
            break
        if streak >= 8:
            log.append("override->stop")
            break
        streak += 1
        log.append(f"continue#{streak}")
        if tool_called:
            streak = 0
    return log


def matches(matcher, value):
    if matcher in (None, "", "*"):
        return True
    if re.fullmatch(r"[A-Za-z0-9_\- ,|]+", matcher):
        return value in {m.strip() for m in re.split(r"[|,]", matcher)}
    return re.search(matcher, value) is not None            # JavaScript RegExp.test: unanchored


TABLE = [  # (event, exit, stdout, stderr, onFailure, expected prefix) - rows of the docs' outcome table
    ("PreToolUse", 0, '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}', "", None, "FIELDS APPLY (decision=deny)"),
    ("PreToolUse", 2, "", "rm -rf blocked", None, "BLOCK (rm -rf blocked)"),
    ("PreToolUse", 2, '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}', "x", None, "BLOCK"),
    ("PreToolUse", 1, "", "Traceback ...", None, "PROCEED with non-blocking error"),
    ("PreToolUse", 1, "", "Traceback ...", "block", "BLOCK (hook failed and onFailure=block)"),
    ("PreToolUse", 1, '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}', "", None, "FIELDS APPLY (decision=deny)"),
    ("PreToolUse", 0, "{not json}", "", None, "PROCEED with non-blocking error"),
    ("PreToolUse", 0, "all good", "", None, "PROCEED"),
    ("PostToolUse", 2, "", "spotless failed: Foo.java", None, "PROCEED, Claude sees stderr"),
    ("PermissionRequest", 2, "", "no", None, "PROCEED (exit 2 not honored"),
    ("Stop", 2, "", "3 tests failing", None, "BLOCK (3 tests failing)"),
    ("Stop", 0, '{"decision":"block","reason":"run the tests first"}', "", None, "FIELDS APPLY (decision=block)"),
    ("UserPromptSubmit", 0, '{"continue":false,"stopReason":"secret in prompt"}', "", None, "STOP SESSION"),
    ("SessionStart", 2, "", "x", None, "PROCEED (exit 2 not honored"),
]

print("--- outcome table (event, exit, stdout -> outcome)")
for event, code, out, err, onf, want in TABLE:
    got = outcome(event, code, out, err, onf)
    shown = (out[:38] + "...") if len(out) > 41 else (out or "(empty)")
    print(f"  {event:<17} exit {code}  {shown:<44} {('onFailure=' + onf) if onf else '':<16} -> {got}")
    assert got.startswith(want), (event, code, got, want)

print("--- PreToolUse precedence and permission rules")
for decisions, rule, want in [(["allow", "ask"], None, "ask"), (["allow", "deny", "ask"], None, "deny"),
                              (["defer", "allow"], None, "defer"), (["allow"], "deny", "deny"),
                              (["allow"], "ask", "ask"), ([], None, "normal permission flow")]:
    got = merge_pretooluse(decisions, rule)
    print(f"  hooks={decisions!s:<26} rule={rule!s:<5} -> {got}")
    assert got == want

print("--- Stop hook continuation cap")
nine_blocks = stop_cap([(True, False)] * 10)
reset = stop_cap([(True, False)] * 7 + [(True, True)] + [(True, False)] * 3 + [(False, False)])
print("  10 blocks, no tool calls:", nine_blocks)
print("  7 blocks, a tool call, 3 blocks, allow:", reset)
assert nine_blocks[-1] == "override->stop" and nine_blocks.count("override->stop") == 1 and len(nine_blocks) == 9
assert reset[-1] == "stop" and "override->stop" not in reset

print("--- matcher semantics")
for m, v, want in [("Bash", "Bash", True), ("Edit|Write", "Write", True), ("Edit, Write", "Edit", True),
                   ("Edit", "NotebookEdit", False), ("Edit.*", "NotebookEdit", True), ("^Edit$", "NotebookEdit", False),
                   ("mcp__memory__.*", "mcp__memory__create_entities", True), ("*", "Anything", True)]:
    got = matches(m, v)
    print(f"  matcher {m!r:<20} tool {v!r:<30} -> {got}")
    assert got == want
print("ALL ASSERTIONS PASSED")
```

**Output (verified):**

```text
--- outcome table (event, exit, stdout -> outcome)
  PreToolUse        exit 0  {"hookSpecificOutput":{"hookEventName"...                     -> FIELDS APPLY (decision=deny)
  PreToolUse        exit 2  (empty)                                                       -> BLOCK (rm -rf blocked)
  PreToolUse        exit 2  {"hookSpecificOutput":{"hookEventName"...                     -> BLOCK (x)
  PreToolUse        exit 1  (empty)                                                       -> PROCEED with non-blocking error notice
  PreToolUse        exit 1  (empty)                                      onFailure=block  -> BLOCK (hook failed and onFailure=block)
  PreToolUse        exit 1  {"hookSpecificOutput":{"hookEventName"...                     -> FIELDS APPLY (decision=deny)
  PreToolUse        exit 0  {not json}                                                    -> PROCEED with non-blocking error notice
  PreToolUse        exit 0  all good                                                      -> PROCEED
  PostToolUse       exit 2  (empty)                                                       -> PROCEED, Claude sees stderr (spotless failed: Foo.java)
  PermissionRequest exit 2  (empty)                                                       -> PROCEED (exit 2 not honored for this event)
  Stop              exit 2  (empty)                                                       -> BLOCK (3 tests failing)
  Stop              exit 0  {"decision":"block","reason":"run the ...                     -> FIELDS APPLY (decision=block)
  UserPromptSubmit  exit 0  {"continue":false,"stopReason":"secret...                     -> STOP SESSION (secret in prompt)
  SessionStart      exit 2  (empty)                                                       -> PROCEED (exit 2 not honored for this event)
--- PreToolUse precedence and permission rules
  hooks=['allow', 'ask']           rule=None  -> ask
  hooks=['allow', 'deny', 'ask']   rule=None  -> deny
  hooks=['defer', 'allow']         rule=None  -> defer
  hooks=['allow']                  rule=deny  -> deny
  hooks=['allow']                  rule=ask   -> ask
  hooks=[]                         rule=None  -> normal permission flow
--- Stop hook continuation cap
  10 blocks, no tool calls: ['continue#1', 'continue#2', 'continue#3', 'continue#4', 'continue#5', 'continue#6', 'continue#7', 'continue#8', 'override->stop']
  7 blocks, a tool call, 3 blocks, allow: ['continue#1', 'continue#2', 'continue#3', 'continue#4', 'continue#5', 'continue#6', 'continue#7', 'continue#8', 'continue#1', 'continue#2', 'continue#3', 'stop']
--- matcher semantics
  matcher 'Bash'               tool 'Bash'                         -> True
  matcher 'Edit|Write'         tool 'Write'                        -> True
  matcher 'Edit, Write'        tool 'Edit'                         -> True
  matcher 'Edit'               tool 'NotebookEdit'                 -> False
  matcher 'Edit.*'             tool 'NotebookEdit'                 -> True
  matcher '^Edit$'             tool 'NotebookEdit'                 -> False
  matcher 'mcp__memory__.*'    tool 'mcp__memory__create_entities' -> True
  matcher '*'                  tool 'Anything'                     -> True
ALL ASSERTIONS PASSED
```

---

## 4. Failure modes

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| F1 | The guard "blocks" with exit 1, and the command still runs | Exit 1 is a non-blocking error | Exit 2, or a JSON `deny` |
| F2 | Guard crashed (missing python) and nothing was blocked | Fail-open default | `"onFailure": "block"`; the script catches exceptions and exits 2 |
| F3 | Hook says `allow`, user still prompted | An `ask` rule matched; or a protected path | Rules apply after hooks; adjust the rule |
| F4 | Path rule never fires on Windows | Backslash paths | Normalise separators |
| F5 | `Edit.*` hook fires on notebooks | Unanchored regex | `^Edit$`, or the exact list `Edit` |
| F6 | Stop hook loops, then "gives up" | 8-continuation cap; a non-converging check | Make the check fixable; use `stop_hook_active` |
| F7 | PostToolUse formatter errors invisible to Claude | Exit 0 hides stderr | Exit 2 on formatter failure |
| F8 | Every tool call feels slow | Heavy PreToolUse hooks, default 600 s timeout | Fast scripts; `timeout: 5–10`; `if:` filters |
| F9 | Hooks didn't run in a cloned repo | Trust not accepted | Accept the trust dialog; `-p` runs them without asking, so review first |
| F10 | `$CLAUDE_PROJECT_DIR` empty in a PowerShell hook | Bare spelling resolves to `$null` | `${CLAUDE_PROJECT_DIR}` or `$env:CLAUDE_PROJECT_DIR` |

---

## 5. Staff-level drills

<details><summary><b>D1 · "Our guard hook exits 1 on dangerous commands. Why did a force push go through?"</b></summary>

**Staff answer.** Exit 1 is a *non-blocking* error, so the action proceeds with a notice. Only exit 2 (or a JSON `deny`) blocks on PreToolUse. Also check what happens when the hook itself fails (python missing, a syntax error): that is fail-open too unless `"onFailure": "block"` is set. Write guards to exit 2 on internal errors, and set `onFailure: block`.
</details>

<details><summary><b>D2 · "Hook or deny rule?"</b></summary>

**Staff answer.** Use both, for different jobs.
- **Deny rules** are declarative, cheap, evaluated first in every mode (including bypass), and cover Read/Edit and recognised Bash file commands.
- **Hooks** handle logic a pattern can't express: compound-command parsing, "committed migrations only", secret scanning of new content, dependency allowlists.

Rules are the floor, and hooks are the logic on top. Neither replaces branch protection and CI.
</details>

<details><summary><b>D3 · "How do we make 'done' mean 'build green' without Claude looping forever?"</b></summary>

**Staff answer.** Use a Stop hook that runs a fast, deterministic verification (compile plus unit tests, offline) and exits 2 with the failing lines on stderr. Claude gets the reason and fixes it. Loop protection is built in (`stop_hook_active`, and the 8-continuation cap that resets on tool calls).

Keep integration tests out of the Stop hook if they're slow; run those in CI. Skip the check when no relevant file changed, so Q&A turns aren't taxed.
</details>

<details><summary><b>D4 · "A hook returned <code>updatedInput</code> and now the tool behaves strangely."</b></summary>

**Staff answer.** `updatedInput` *replaces the entire input object*, so a hook that returns only the field it changed drops the rest. Echo every field you received, modified. Permission rules are evaluated against the updated input.
</details>

<details><summary><b>D5 · "Are hooks a security boundary?"</b></summary>

**Staff answer.** They are a strong guardrail, not a sandbox. They see only what passes through tool calls. A Bash rule matches the command as written, so obfuscation can slip past a naive parser. And they fail open unless configured otherwise. For hard isolation, use the sandbox (strict mode), containers, least-privilege credentials, and managed settings. Treat hooks as defence in depth that also gives Claude actionable feedback.
</details>

---

## 6. Checklist

- [ ] Guards block via exit 2 or a JSON `deny`, never exit 1; they set `onFailure: block` and exit 2 on internal errors.
- [ ] Matchers are exact lists, or anchored regexes.
- [ ] Hot-path hooks have explicit short timeouts and `if:` filters.
- [ ] File-path logic normalises Windows separators.
- [ ] Exec form with `${CLAUDE_PROJECT_DIR}` for script paths.
- [ ] Stop gates converge, and skip when nothing relevant changed.
- [ ] Hook changes are reviewed like CI changes; untrusted repos run with `--bare` or `disableAllHooks`.

---

## 7. References

- Hooks reference (events, configuration, input, output, exit codes, decision control, async, security, Windows, debugging): <https://code.claude.com/docs/en/hooks>
- Hooks guide: <https://code.claude.com/docs/en/hooks-guide>
- Best practices ("Enforce the rules that can't have exceptions", "Enforce the check with a Stop hook"): <https://code.claude.com/docs/en/best-practices>
- Configure permissions ("Precedence among rules, hooks, and mods"): <https://code.claude.com/docs/en/permissions>
- Goal (a prompt-based Stop hook): <https://code.claude.com/docs/en/goal>

Next: [02 · Ten production hooks](02-10-production-hook-scripts-for-java-maven-gradle-git-safety-and-secret-blocking.md) · [KB README](../README.md)

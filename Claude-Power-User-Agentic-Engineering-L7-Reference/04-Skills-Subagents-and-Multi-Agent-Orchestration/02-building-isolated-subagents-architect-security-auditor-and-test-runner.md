# Building Isolated Subagents: Architect, Security Auditor, Test Runner (and Code Reviewer)

> **Folder 04 · File 2 of 3** · verified 2026-10-30 against code.claude.com `sub-agents.md`, `workflows.md`, `agent-teams.md`, `tools-reference.md`
> **Listing:** `agent_lint.py` (lints `.claude/agents/*.md` against the frontmatter reference plus role policy; its GOOD fixtures are the four agents in this file)

---

## 0. Orientation

A **subagent** is a worker with its own context window, its own system prompt, and optionally its own tools, model, effort, permission mode, MCP servers, hooks, memory and git worktree. Claude delegates to it, it works, and only its result returns to the main conversation.

That isolation buys three things:
- **Noise stays out.** Test logs and search results don't fill your context.
- **Specialisation.** A security auditor with a security prompt and read-only tools.
- **Independence.** A reviewer that never saw the reasoning that produced the code.

It does *not* buy a better answer for the same task. Claude Code's own guidance lists "delegate to a subagent for a better answer" as obsolete advice: "a fresh reviewer does help, because it hasn't seen your reasoning, which is a different thing from delegating" [doc].

### 0.1 The twelve rules

1. **Use subagents for parallel work, noisy output, and independent review**, not to "protect context" by default. Each one costs its own tokens. [doc]
2. **Know the built-ins.** *Explore* (read-only, fast research), *Plan* (read-only research in plan mode) and *general-purpose*. Explore and Plan start **without your CLAUDE.md**. [doc]
3. **`name` and `description` are required**, and the description is how Claude decides to delegate, so say *when*. [doc + measured: L1]
4. **Reviewers and auditors don't get `Edit`/`Write`.** If they need Bash (for `git diff`), guard it with a PreToolUse hook. [inference + measured: L1]
5. **`disallowedTools: Bash(git push *)` removes the whole Bash tool,** not just pushes. Use permission rules or a hook for command-level control. [doc]
6. **Pick the model per role:** `opus` for review and architecture, `haiku` for running tests and summarising. [doc + Folder 01]
7. **A subagent starts a fresh prefix, so there is no cache shared with the parent.** Keep its prompt tight. [doc + Folder 01]
8. **Background subagents get a narrower built-in tool set,** and subagents spawned from the main conversation start in the background by default. [doc]
9. **Project subagents' frontmatter hooks run only after you trust the folder.** Until then the agent runs *without* its guard. [doc]
10. **`isolation: worktree`** gives a subagent its own checkout. It is cleaned up automatically if it made no changes. [doc]
11. **Scope MCP servers to the subagent that needs them** (`mcpServers:`), so their schemas don't tax every main-thread turn (Folder 06). [doc]
12. **Lint agent files in CI** (L1). [measured]

---

## 1. First principles

### 1.1 What a subagent is, mechanically

A subagent is another model conversation:
- its system prompt is the agent file's body, plus Claude Code's subagent scaffolding
- its user prompt is the task Claude hands it
- its tools are the agent's tool list after filters

Consequences, all from Folder 01:
- **Its prefix is fresh**, so the first call writes a new cache and shares nothing with the parent.
- **It doesn't see your conversation** unless it was forked from it.
- **Its result is a summary.** The parent sees what the agent returns, not what it read.

So a subagent pays off when the work is self-contained, produces a lot of intermediate tokens, or benefits from not knowing the parent's reasoning.

### 1.2 Built-in subagents [doc]

| Agent | Tools | Model | Notes |
|---|---|---|---|
| **Explore** | Read-only (Write and Edit denied) | The main model (with a Fable main model on a subscription or the Console, it runs on the `opus` alias) | Starts without CLAUDE.md and the git status snapshot; thoroughness levels quick / medium / very thorough |
| **Plan** | Read-only | Inherits | Used in plan mode to gather context |
| **general-purpose** | All tools available to subagents | `CLAUDE_CODE_SUBAGENT_MODEL` if set, else the main model | Exploration plus modification |

A project or user agent named `Explore` overrides the built-in, for example with `model: haiku` to make exploration cheaper.

### 1.3 Where agents live, and precedence [doc]

Highest priority first:
1. Managed settings (organisation)
2. `--agents '<json>'` (this session)
3. `.claude/agents/` (project; commit it)
4. `~/.claude/agents/` (all your projects)
5. A plugin's `agents/`

`/agents` reminds you how to create and manage them. `claude --agent <name>` runs an agent *as* the main session.

### 1.4 The frontmatter reference (the fields you'll use) [doc]

| Field | Notes |
|---|---|
| `name` (required) | ≤ 256 chars; no `:` (reserved for plugin scope); hooks see it as `agent_type` |
| `description` (required) | When Claude should delegate |
| `tools` / `disallowedTools` | Inherits all subagent tools if `tools` is omitted. An unresolvable list can make the agent fail to launch. **A `disallowedTools` entry with a specifier still removes the whole tool** |
| `model` | `sonnet`, `opus`, `haiku`, `fable`, a full id (`claude-opus-5-5`), or `inherit` |
| `effort` | `low` … `max`, depending on the model |
| `permissionMode` | `default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, `plan` (`manual` = `default`); ignored for plugin agents |
| `maxTurns` | When reached, output is returned marked partial and Claude can resume the agent |
| `skills` | Preload full skill bodies at startup |
| `mcpServers` | Names of configured servers, or inline definitions, for this agent only |
| `hooks` | Lifecycle hooks while the agent is active (a `Stop` hook becomes `SubagentStop`) |
| `memory` | `user`, `project` or `local` persistent memory |
| `background`, `isolation: worktree`, `color`, `omitClaudeMd`, `initialPrompt`, `autoCompactWindow` | As named |

### 1.5 Tool filters you must know about [doc]

- **Every subagent** loses `AskUserQuestion`, `EnterPlanMode`, `ScheduleWakeup`, `Workflow` and some others. It also loses `ExitPlanMode` unless its `permissionMode` is `plan`, and `Agent` at the depth limit.
- **Background subagents** keep every MCP tool but only these built-ins:
  - `Read`, `Grep`, `Glob`, `LSP`, `Bash`, `PowerShell`
  - `Edit`, `Write`, `NotebookEdit`
  - `WebFetch`, `WebSearch`, `TodoWrite`, `Skill`, `ToolSearch`
  - `EnterWorktree`, `ExitWorktree`, `Monitor`, `TaskStop`, `SendMessage`, `Artifact`

  Everything else is removed "whether inherited or listed".
- Subagents spawned from the main conversation **start in the background** by default.

### 1.6 Guarding read-only roles [doc, inference]

`tools: Read, Grep, Glob, Bash` lets a reviewer run `git diff`, and also `git checkout .` or `rm`. The documented pattern is a PreToolUse hook in the agent's frontmatter that validates each Bash command and **exits 2** to block it. Folder 05 builds `readonly_git.py`, which allows only `git diff | log | show | blame | status` and read-only file listing.

Note the trust rule: a *project* agent's frontmatter hooks are skipped until you accept the workspace trust dialog for that folder. The agent still runs, without its guard [doc]. Pair the hook with project deny rules for the destructive commands, which apply regardless.

### 1.7 Subagents vs skills vs agent teams vs workflows [doc]

| | Subagents | Skills | Agent teams | Dynamic workflows |
|---|---|---|---|---|
| What it is | A worker Claude spawns | Instructions Claude follows | A lead supervising peer sessions | A script the runtime executes |
| Who decides what runs next | Claude, turn by turn | Claude, following the prompt | The lead agent | The script |
| Intermediate results | Claude's context | Claude's context | A shared task list | Script variables |
| Repeatable | The worker definition | The instructions | The team definition | The orchestration itself |
| Scale | A few per turn | Same | A handful of long-running peers | Dozens to hundreds per run |
| Interruption | Restarts the turn | Restarts the turn | Teammates keep running | Resumable in the same session |

Agent teams are experimental and off by default (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). Dynamic workflows are "a JavaScript script that orchestrates many subagents … for codebase audits, large migrations, and cross-checked research" [doc].

---

## 2. Practice: the four agents

All four are GOOD fixtures in L1 and lint clean. The code reviewer and security auditor guard Bash with the Folder 05 hook.

### 2.1 `.claude/agents/code-reviewer.md`

```markdown
---
name: code-reviewer
description: Reviews the current branch diff for production defects in Java/Spring code (N+1 queries, races, transactions spanning I/O, missing timeouts, resource leaks). Use after code changes and before opening a PR.
tools: Read, Grep, Glob, Bash
model: opus
effort: high
color: red
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "python \"${CLAUDE_PROJECT_DIR}/.claude/hooks/readonly_git.py\""
---
You review a diff you did not write, for defects that fail in production. You never edit files.

Get the diff with `git diff --merge-base origin/main` and read every changed file in full.
Check each change for:
- N+1: repository or lazy-collection access inside loops or streams; missing fetch joins or batch loads.
- Races: check-then-act (exists-then-insert), unsynchronized shared state, inconsistent lock order,
  @Transactional self-invocation (no proxy, no transaction).
- Transactions: Kafka or HTTP calls inside a transaction; missing outbox.
- Timeouts: RestClient/HttpClient/WebClient/JDBC/Kafka calls without connect and read timeouts.
- Resources: streams, connections, executors not closed; unbounded queries or caches.
For each finding give: file:line, the defect, a concrete failing scenario, and the minimal fix.
Order by severity. If you find nothing, say "No findings" and list what you checked.
```

### 2.2 `.claude/agents/security-auditor.md`

```markdown
---
name: security-auditor
description: Audits changed Java code and configuration for exploitable security defects (injection, broken authorization, SSRF, secrets, unsafe deserialization). Use before merging changes that touch controllers, queries, HTTP clients or configuration.
tools: Read, Grep, Glob, Bash
model: opus
effort: high
color: orange
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "python \"${CLAUDE_PROJECT_DIR}/.claude/hooks/readonly_git.py\""
---
You audit for vulnerabilities an attacker could exploit. You never edit files.
Scope: `git diff --merge-base origin/main` plus every file it touches.
Look for: SQL/JPQL built by string concatenation; endpoints missing method-level authorization; tenant id taken
from the request body instead of the token; RestClient URLs built from user input (SSRF); secrets or tokens in code,
config or logs; Java deserialization of untrusted data; disabled TLS verification; verbose error bodies.
Report each finding as: severity (critical/high/medium/low), CWE id, file:line, exploit scenario, fix.
Report only findings with a concrete exploit path; say "No findings" otherwise.
```

### 2.3 `.claude/agents/test-runner.md`

```markdown
---
name: test-runner
description: Runs the Maven test suites and returns only the failures with their root-cause lines. Use when tests need to run, so their output stays out of the main conversation.
tools: Read, Grep, Glob, Bash
model: haiku
maxTurns: 15
color: green
---
Run `./mvnw -q verify -Pit` (or the module/test the request names). Do not modify any file.
Return: the command, pass/fail counts, and for each failing test the class, method, assertion message and the
first stack frame in our code (com.acme.*). Nothing else - no passing tests, no full logs.
```

### 2.4 `.claude/agents/architect.md`

```markdown
---
name: architect
description: Designs and critiques service-level changes (boundaries, data ownership, consistency, failure modes) and writes ADR drafts. Use before implementing anything that adds a service, a table shared across modules, or a new integration.
tools: Read, Grep, Glob
model: opus
effort: xhigh
memory: project
color: purple
---
You are the principal architect for order-platform. You never edit code; you produce decisions.
For every proposal: state the problem and constraints (load, SLOs, consistency), give two or three options with
their failure modes at 10x load, recommend one, and list what would change the recommendation.
Assume the proposed design fails in production first; name the top three failure modes before any strengths.
Write the result as an ADR draft in your reply (Context, Decision, Consequences, Alternatives).
```

### 2.5 Orchestration patterns that pay

| Pattern | How | Why it pays |
|---|---|---|
| Writer → reviewer | Main thread implements; "use the code-reviewer subagent on this branch"; fix the findings | Independent context; Folder 02's verifier gate |
| Test runner | "Run the tests with the test-runner subagent" | Megabytes of Maven output stay out of your context; Haiku is cheap |
| Architect before code | "Have the architect subagent critique docs/specs/X.md" | Adversarial design review in a fresh context (Folder 02 file 03) |
| Parallel research | Several Explore runs on independent questions | Wall-clock time; cheap model |
| Isolated experiment | An agent with `isolation: worktree` tries a risky refactor | Main checkout untouched; auto-cleaned if there are no changes |

---

## 3. Verified listing

### L1 · `agent_lint.py`

**What it shows.** Ten checks (AG01–AG10) from the frontmatter reference plus role policy:
- required fields
- the reserved `:`
- unknown fields
- tools that resolve to nothing
- reviewers with edit tools
- the `disallowedTools` whole-tool trap
- enum values (permission mode, model, memory, isolation, colour, effort)
- bypass mode
- descriptions without *when*
- read-only roles with unguarded Bash

The four agents above are clean, and the BAD agent trips nine checks.

**What it does not show.** Review quality. Measure that with a seeded-defect eval (Folder 02 file 03, L3 pattern).

Run: `pip install pyyaml && python agent_lint.py`.

```python
"""agent_lint.py - lint .claude/agents/*.md subagent files against the frontmatter reference in Claude Code's
subagent docs (2026-10-30), plus role policy for reviewers and auditors.

  AG01 missing name or description          AG06 disallowedTools entry with a specifier (it removes
  AG02 invalid name (':' is reserved for          the WHOLE tool, not just the matching calls)
       plugin scope; max 256 chars)         AG07 invalid enum (permissionMode, model, memory,
  AG03 unknown frontmatter field                  isolation, color, effort)
  AG04 tool name that resolves to no tool   AG08 permissionMode bypassPermissions
       (the subagent may fail to launch)    AG09 description says nothing about WHEN to delegate
  AG05 reviewer/auditor/architect role with AG10 read-only role with Bash but no PreToolUse Bash
       Edit, Write or NotebookEdit               guard hook (a shell can still write)

Run: python agent_lint.py   (needs pyyaml; prints ALL ASSERTIONS PASSED)
"""
import re

import yaml

FIELDS = {"name", "description", "tools", "disallowedTools", "model", "permissionMode", "maxTurns",
          "autoCompactWindow", "skills", "mcpServers", "hooks", "memory", "background", "omitClaudeMd", "effort",
          "isolation", "color", "initialPrompt", "experimental"}
TOOLS = set("Agent Artifact AskUserQuestion Bash CronCreate CronDelete CronList Edit EnterWorktree ExitWorktree Glob "
            "Grep LSP ListMcpResourcesTool Monitor NotebookEdit PowerShell Read ReadMcpResourceTool SendMessage Skill "
            "TaskCreate TaskGet TaskList TaskOutput TaskStop TaskUpdate TodoWrite ToolSearch WebFetch WebSearch Write".split())
ENUMS = {"permissionMode": {"default", "acceptEdits", "auto", "dontAsk", "bypassPermissions", "plan", "manual"},
         "memory": {"user", "project", "local"}, "isolation": {"worktree"},
         "color": {"red", "blue", "green", "yellow", "purple", "orange", "pink", "cyan"},
         "effort": {"low", "medium", "high", "xhigh", "max"}}
MODEL = re.compile(r"^(sonnet|opus|haiku|fable|inherit|claude-[a-z0-9-]+)$")
READ_ONLY_ROLE = re.compile(r"review|audit|architect", re.I)
WHEN = re.compile(r"\b(use (it |this )?(when|after|before|proactively|for)|after code changes|before (a|opening))\b", re.I)


def split_tools(v):
    if v is None:
        return []
    items = v if isinstance(v, list) else re.split(r",\s*(?![^()]*\))", str(v))
    return [str(t).strip() for t in items if str(t).strip()]


def lint(text):
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    fm = yaml.safe_load(m.group(1)) or {}
    f = []
    if not fm.get("name") or not fm.get("description"):
        f.append(("AG01", "name and description are required"))
    name = str(fm.get("name", ""))
    if ":" in name or len(name) > 256:
        f.append(("AG02", f"name '{name}': ':' is reserved for plugin-scoped agents"))
    for k in sorted(set(fm) - FIELDS):
        f.append(("AG03", f"unknown field '{k}'"))
    tools = split_tools(fm.get("tools"))
    for t in tools:
        base = t.split("(", 1)[0]
        if base not in TOOLS and not base.startswith("mcp__"):
            f.append(("AG04", f"tool '{t}' resolves to no tool"))
    if READ_ONLY_ROLE.search(name) and {"Edit", "Write", "NotebookEdit"} & {t.split("(")[0] for t in tools}:
        f.append(("AG05", f"'{name}' is a review role but can edit files - reviewers report, they don't change code"))
    for t in split_tools(fm.get("disallowedTools")):
        if "(" in t:
            f.append(("AG06", f"disallowedTools '{t}' removes the whole {t.split('(')[0]} tool, not only matching calls"))
    for k, allowed in ENUMS.items():
        if k in fm and str(fm[k]) not in allowed:
            f.append(("AG07", f"{k}: '{fm[k]}' not in {sorted(allowed)}"))
    if "model" in fm and not MODEL.match(str(fm["model"])):
        f.append(("AG07", f"model: '{fm['model']}' is not an alias or a claude-* id"))
    if fm.get("permissionMode") == "bypassPermissions":
        f.append(("AG08", "permissionMode bypassPermissions in a subagent"))
    if fm.get("description") and not WHEN.search(str(fm["description"])):
        f.append(("AG09", "description should say when Claude should delegate ('Use after ...', 'Use when ...')"))
    guarded = any(g.get("matcher") in ("Bash", "Bash|PowerShell") for g in (fm.get("hooks") or {}).get("PreToolUse", []))
    if READ_ONLY_ROLE.search(name) and "Bash" in tools and not guarded:
        f.append(("AG10", f"'{name}' has Bash but no PreToolUse Bash guard - a shell can still write"))
    return f


GUARD = """hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "python \\"${CLAUDE_PROJECT_DIR}/.claude/hooks/readonly_git.py\\""
"""

AGENTS = {
    "code-reviewer.md": f"""---
name: code-reviewer
description: Reviews the current branch diff for production defects in Java/Spring code (N+1 queries, races, transactions spanning I/O, missing timeouts, resource leaks). Use after code changes and before opening a PR.
tools: Read, Grep, Glob, Bash
model: opus
effort: high
color: red
{GUARD}---
You review a diff you did not write, for defects that fail in production. You never edit files.

Get the diff with `git diff --merge-base origin/main` and read every changed file in full.
Check each change for:
- N+1: repository or lazy-collection access inside loops or streams; missing fetch joins or batch loads.
- Races: check-then-act (exists-then-insert), unsynchronized shared state, inconsistent lock order,
  @Transactional self-invocation (no proxy, no transaction).
- Transactions: Kafka or HTTP calls inside a transaction; missing outbox.
- Timeouts: RestClient/HttpClient/WebClient/JDBC/Kafka calls without connect and read timeouts.
- Resources: streams, connections, executors not closed; unbounded queries or caches.
For each finding give: file:line, the defect, a concrete failing scenario, and the minimal fix.
Order by severity. If you find nothing, say "No findings" and list what you checked.
""",
    "security-auditor.md": f"""---
name: security-auditor
description: Audits changed Java code and configuration for exploitable security defects (injection, broken authorization, SSRF, secrets, unsafe deserialization). Use before merging changes that touch controllers, queries, HTTP clients or configuration.
tools: Read, Grep, Glob, Bash
model: opus
effort: high
color: orange
{GUARD}---
You audit for vulnerabilities an attacker could exploit. You never edit files.
Scope: `git diff --merge-base origin/main` plus every file it touches.
Look for: SQL/JPQL built by string concatenation; endpoints missing method-level authorization; tenant id taken
from the request body instead of the token; RestClient URLs built from user input (SSRF); secrets or tokens in code,
config or logs; Java deserialization of untrusted data; disabled TLS verification; verbose error bodies.
Report each finding as: severity (critical/high/medium/low), CWE id, file:line, exploit scenario, fix.
Report only findings with a concrete exploit path; say "No findings" otherwise.
""",
    "test-runner.md": """---
name: test-runner
description: Runs the Maven test suites and returns only the failures with their root-cause lines. Use when tests need to run, so their output stays out of the main conversation.
tools: Read, Grep, Glob, Bash
model: haiku
maxTurns: 15
color: green
---
Run `./mvnw -q verify -Pit` (or the module/test the request names). Do not modify any file.
Return: the command, pass/fail counts, and for each failing test the class, method, assertion message and the
first stack frame in our code (com.acme.*). Nothing else - no passing tests, no full logs.
""",
    "architect.md": """---
name: architect
description: Designs and critiques service-level changes (boundaries, data ownership, consistency, failure modes) and writes ADR drafts. Use before implementing anything that adds a service, a table shared across modules, or a new integration.
tools: Read, Grep, Glob
model: opus
effort: xhigh
memory: project
color: purple
---
You are the principal architect for order-platform. You never edit code; you produce decisions.
For every proposal: state the problem and constraints (load, SLOs, consistency), give two or three options with
their failure modes at 10x load, recommend one, and list what would change the recommendation.
Assume the proposed design fails in production first; name the top three failure modes before any strengths.
Write the result as an ADR draft in your reply (Context, Decision, Consequences, Alternatives).
""",
}

BAD = """---
name: team:reviewer
description: Reviewer.
tools: Read, Edit, Bash, Grepp
disallowedTools: Bash(git push *)
permissionMode: bypassPermissions
model: gpt-4
color: magenta
temperature: 0.2
---
Review things.
"""

for fname, text in AGENTS.items():
    found = lint(text)
    print(f"--- {fname}: {sorted({c for c, _ in found}) or 'clean'}")
    assert not found, (fname, found)
found = lint(BAD)
codes = {c for c, _ in found}
print(f"--- BAD agent: {sorted(codes)}")
for c, msg in found:
    print(f"  {c} {msg}")
assert codes == {f"AG{i:02d}" for i in range(2, 11)}, sorted(codes)
print("--- .claude/agents/code-reviewer.md")
print(AGENTS["code-reviewer.md"])
print("ALL ASSERTIONS PASSED")
```

**Output (verified):**

```text
--- code-reviewer.md: clean
--- security-auditor.md: clean
--- test-runner.md: clean
--- architect.md: clean
--- BAD agent: ['AG02', 'AG03', 'AG04', 'AG05', 'AG06', 'AG07', 'AG08', 'AG09', 'AG10']
  AG02 name 'team:reviewer': ':' is reserved for plugin-scoped agents
  AG03 unknown field 'temperature'
  AG04 tool 'Grepp' resolves to no tool
  AG05 'team:reviewer' is a review role but can edit files - reviewers report, they don't change code
  AG06 disallowedTools 'Bash(git push *)' removes the whole Bash tool, not only matching calls
  AG07 color: 'magenta' not in ['blue', 'cyan', 'green', 'orange', 'pink', 'purple', 'red', 'yellow']
  AG07 model: 'gpt-4' is not an alias or a claude-* id
  AG08 permissionMode bypassPermissions in a subagent
  AG09 description should say when Claude should delegate ('Use after ...', 'Use when ...')
  AG10 'team:reviewer' has Bash but no PreToolUse Bash guard - a shell can still write
--- .claude/agents/code-reviewer.md
---
name: code-reviewer
description: Reviews the current branch diff for production defects in Java/Spring code (N+1 queries, races, transactions spanning I/O, missing timeouts, resource leaks). Use after code changes and before opening a PR.
tools: Read, Grep, Glob, Bash
model: opus
effort: high
color: red
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "python \"${CLAUDE_PROJECT_DIR}/.claude/hooks/readonly_git.py\""
---
You review a diff you did not write, for defects that fail in production. You never edit files.

Get the diff with `git diff --merge-base origin/main` and read every changed file in full.
Check each change for:
- N+1: repository or lazy-collection access inside loops or streams; missing fetch joins or batch loads.
- Races: check-then-act (exists-then-insert), unsynchronized shared state, inconsistent lock order,
  @Transactional self-invocation (no proxy, no transaction).
- Transactions: Kafka or HTTP calls inside a transaction; missing outbox.
- Timeouts: RestClient/HttpClient/WebClient/JDBC/Kafka calls without connect and read timeouts.
- Resources: streams, connections, executors not closed; unbounded queries or caches.
For each finding give: file:line, the defect, a concrete failing scenario, and the minimal fix.
Order by severity. If you find nothing, say "No findings" and list what you checked.

ALL ASSERTIONS PASSED
```

---

## 4. Failure modes

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| F1 | Claude never delegates to your agent | Description lacks *when* | "Use after code changes and before opening a PR" |
| F2 | Reviewer "fixed" code | It had Edit/Write | Remove them; read-only roles report |
| F3 | Reviewer ran `git checkout .` | Unguarded Bash | PreToolUse guard hook + deny rules |
| F4 | Agent has no Bash at all | `disallowedTools: Bash(git push *)` removed the whole tool | Use permission rules or a hook for command-level control |
| F5 | Guard hook never fired | Project folder not trusted | Accept the trust dialog; keep deny rules as a backstop |
| F6 | Explore missed a convention | Explore starts without CLAUDE.md | State it in the request |
| F7 | Subagent costs surprise | Fresh prefix per agent; large prompts; Opus for trivial work | Tight prompts; Haiku for mechanical roles |
| F8 | Background agent can't use a tool it lists | Background tool filter | Run in the foreground, or redesign |
| F9 | Agent fails to launch | No entry in `tools` resolves | Fix the names (L1 AG04) |

---

## 5. Staff-level drills

<details><summary><b>D1 · "Should we create a subagent for every task type?"</b></summary>

**Staff answer.** No. Create agents for roles that need *different context or tools*: a reviewer that must not see the author's reasoning, a test runner whose output would flood context, an auditor with a narrow mandate. For "do X better", improve the prompt or skill instead. Every agent is another prompt to maintain and another fresh prefix to pay for.
</details>

<details><summary><b>D2 · "How do we keep the security auditor read-only but still let it run git?"</b></summary>

**Staff answer.** Use `tools: Read, Grep, Glob, Bash`, plus a frontmatter PreToolUse hook on `Bash` that allows only read-only git and listing commands and exits 2 otherwise (Folder 05 `readonly_git.py`). Back it with project deny rules (`Bash(git push *)`, `Bash(git reset --hard *)`, `Bash(rm -rf *)`) that apply even if the folder isn't trusted yet. Don't use `disallowedTools: Bash(...)`, which would remove Bash entirely.
</details>

<details><summary><b>D3 · "Subagents vs /batch vs dynamic workflows for migrating 40 services from RestTemplate to RestClient?"</b></summary>

**Staff answer.**
- **`/batch migrate … to RestClient with timeouts`** for an interactive run. It researches, splits the work into 5–30 units, shows the plan, then runs one background subagent per unit in its own worktree. Each unit implements, tests and publishes its change.
- **A dynamic workflow** if you want the orchestration codified and rerunnable at hundreds of units.
- **A headless batch** (file 03) if it must run in CI.

Plain subagents from the main thread are the wrong tool at that scale.
</details>

<details><summary><b>D4 · "Why is our reviewer weaker than /code-review?"</b></summary>

**Staff answer.** Check three things. Is it running in a fresh context? Spawning it from a thread that argued for the design isn't independent if you paste that reasoning in. Does it have the full files or only the diff? And is its model and effort adequate (opus/high)? `/code-review` is a bundled, maintained skill. Use it as the baseline, and give your agent the repo-specific checklist that `/code-review` doesn't know.
</details>

---

## 6. Checklist

- [ ] Each agent has a role-specific prompt, a description with *when*, minimal tools, and a model and effort suited to the role.
- [ ] Review and audit roles are read-only, with Bash guarded by a PreToolUse hook and backed by deny rules.
- [ ] No `disallowedTools` entries with specifiers.
- [ ] MCP servers are scoped to the agents that need them.
- [ ] L1 lints `.claude/agents/*.md` in CI.

---

## 7. References

- Create custom subagents (built-ins, scopes, frontmatter, tool filters, hooks, memory, isolation): <https://code.claude.com/docs/en/sub-agents>
- Dynamic workflows: <https://code.claude.com/docs/en/workflows>
- Agent teams (experimental): <https://code.claude.com/docs/en/agent-teams>
- Tools reference: <https://code.claude.com/docs/en/tools-reference>
- Best practices ("Know what subagents cost", "What you can stop doing"): <https://code.claude.com/docs/en/best-practices>

Previous: [01 · Skills](01-designing-reusable-skills-and-custom-slash-commands-with-frontmatter.md) · Next: [03 · Batch, background and headless CI](03-batch-migrations-background-agents-and-headless-ci-cd-automation.md) · [KB README](../README.md)

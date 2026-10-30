# Claude Code: Complete Slash Commands, CLI Flags and Keyboard Shortcuts Cheat Sheet

> **Folder 03 · File 1 of 3** · verified 2026-10-30 against a snapshot of code.claude.com (`commands.md`, `cli-reference.md`, `interactive-mode.md`, `permission-modes.md`, `checkpointing.md`, `vs-code.md`). Every `/command` and `--flag` named in this file was machine-checked against that snapshot (§3).
> Claude Code changes weekly. Commands marked *removed* are listed so you recognise stale advice. Run `/release-notes` for what changed since this date.

---

## 0. Orientation

Most cheat sheets are lists. This one is organised by **what you are trying to control**: context, reasoning, permissions, memory, review, parallelism. For each control it gives the deterministic lever (enforced by the harness) and the non-deterministic one (followed by the model), because confusing the two is the root of most "Claude ignored my rule" incidents (§1.2).

### 0.1 The twelve things to know by heart

1. **`Esc` stops Claude mid-action and keeps the work done so far. `Esc` `Esc` on an empty prompt opens the rewind menu.** [doc]
2. **`Shift+Tab` cycles permission modes:** `default` (shown as *Manual*) → `acceptEdits` → `plan` → (`bypassPermissions` if enabled) → `auto`. On some Windows terminals the key is `Alt+M`. [doc]
3. **New terminal and VS Code sessions start in auto mode,** where a classifier reviews risky actions. Plan mode is opt-in, via `Shift+Tab`, `/plan <task>` or `--permission-mode plan`. [doc]
4. **`/rewind` restores code, conversation, or both, to any prompt in the session.** It does *not* restore files that only Bash commands changed, or most subagent edits. Keep git. [doc]
5. **`/clear` between tasks, and after two failed corrections.** Its successor, `/compact [focus]`, summarises instead of discarding. [doc]
6. **`/btw <question>`** answers a side question without adding it to the conversation. It has no tools. [doc]
7. **`/context`** shows what fills the window. **`/usage`** (aliases `/cost`, `/stats`) shows spend and limits. [doc]
8. **`/model`, `/effort`, `/advisor`, `/fast`** set the model, reasoning depth, a consulting model and output speed. **`ultrathink`** in a prompt deepens one turn. "think hard" is plain text. [doc]
9. **`/code-review`** (alias `/review`) reviews the diff in a fresh subagent. **`/security-review`** reviews the branch against the default branch. [doc]
10. **`/batch <instruction>`** splits a large mechanical change into 5–30 units, each in its own worktree, with its own PR. **`/loop [interval] [prompt]`** repeats a prompt while the session is open. [doc]
11. **`@path` includes a file (directory references show listings), and `!cmd` runs a shell command into the conversation.** Pipe input into `claude -p` for one-shot jobs. [doc]
12. **`claude -w <name>`** starts an isolated git-worktree session, and **`claude --bg "<task>"`** starts a background agent. **`claude agents`** opens the agent view. [doc]

---

## 1. First principles

### 1.1 Four kinds of "slash command"

Typing `/` opens one menu, but the items behind it behave differently [doc]:

| Kind | Examples | What it is |
|---|---|---|
| **Built-in command** | `/clear`, `/compact`, `/rewind`, `/model`, `/permissions` | Harness actions: deterministic, implemented by Claude Code |
| **Bundled skill** | `/batch`, `/loop`, `/code-review`, `/simplify`, `/verify`, `/debug`, `/doctor` | Instructions plus files Claude loads and follows: model-driven |
| **Bundled workflow** | `/deep-research` | A multi-agent orchestration script |
| **Your skills and plugins, MCP prompts** | `/new-slice` (Folder 04), `/mcp__github__…` | Whatever you or a server defined |

The practical difference is that a built-in command always does the same thing, while a skill is a prompt the model executes with judgment. Folder 04 covers writing your own.

### 1.2 Deterministic vs. non-deterministic levers

Claude Code's own best-practices page frames everything in two columns, and this cheat sheet uses the same framing [doc]:

| Control | Non-deterministic (Claude decides) | Deterministic (Claude Code enforces) |
|---|---|---|
| What to do | Your prompt, CLAUDE.md, skills Claude picks up itself | Hooks; skills only you can start |
| What it can touch | Auto mode's classifier | Deny rules, the sandbox in strict mode, managed settings |
| When it is done | A request for evidence, `/goal`, `/code-review` | Tests, typecheck, a `Stop` hook, CI |
| How much it spends | Effort level | `--max-turns`, `--max-budget-usd` (with `-p`), spend limits |
| Who has the last word | Claude's summary | Branch protection, a human approving the merge |

"If you keep adding emphasis to a CLAUDE.md line and Claude still misses it, that's a sign the line belongs in a hook" [doc].

### 1.3 Permission modes in one table [doc]

| Mode (config value) | Runs without asking | Use for |
|---|---|---|
| `default` (*Manual*; the CLI also accepts `manual`) | Reads only | Sensitive work; reviewing every action |
| `acceptEdits` | Reads, file edits, common filesystem commands (`mkdir`, `touch`, `mv`, `cp`) | Iterating on code you review |
| `plan` | Reads (plus classifier-approved commands when auto mode is available) | Exploring before changing; edits stay blocked until you approve the plan |
| `auto` | Everything, with background safety checks | Long tasks; fewer prompts. **The default for new terminal and VS Code sessions.** |
| `dontAsk` | Reads inside working directories plus pre-approved tools; everything else denied | Locked-down CI and scripts |
| `bypassPermissions` | Everything | Isolated containers and VMs only |

Two rules hold in every mode. **Deny rules block in every mode, including `bypassPermissions`**. Allow rules have no effect in `bypassPermissions`. Permission rules are evaluated **deny, then ask, then allow**, and the first match wins, so a broad deny can't be carved out by a narrower allow [doc].

### 1.4 What `/rewind` can and can't undo [doc]

- **What it captures:** a checkpoint is taken before every prompt that starts a turn. File snapshots are kept for the 100 most recent checkpoints, and they persist across `--resume`. They are swept about 30 days after last use (`cleanupPeriodDays`).
- **Menu actions:** *Restore code and conversation*, *Restore conversation*, *Restore code*, *Summarize from here*, *Summarize up to here*.
- **Not restored:**
  - files that only Bash commands changed
  - most subagent edits (a foreground `context: fork` skill is the exception)
  - external changes
  - messages sent mid-turn
  - symlinked and hard-linked paths

  "Not a replacement for version control."

---

## 2. The cheat sheet

### 2.1 Context and session control

| Command / key | Does | Notes |
|---|---|---|
| `Esc` | Interrupt Claude or close a dialog | Keeps the work done so far; queued messages send next |
| `Esc` `Esc` (empty prompt) | Open the rewind menu | With text in the prompt, it clears the draft (recover with `Up`) |
| `/rewind` | Rewind code and/or conversation, or summarise from/up to a message | §1.4 limits |
| `/clear [name]` | New conversation, empty context | Name labels the old one in `/resume` |
| `/compact [instructions]` | Summarise so far to free context | Folder 02 file 03 §2.1 has a keep/drop template |
| `/autocompact [auto\|<tokens>]` | Set the auto-compact window | e.g. `500k`; the default is near the model's limit |
| `/context [all]` | Coloured grid of context usage, plus suggestions | Confirms CLAUDE.md loaded |
| `/btw [question]` | Side question; not added to history; no tools | Press `f` to fork it into a background subagent with tools |
| `/branch [name]` | Branch the conversation at this point | Try another direction without losing this one |
| `/fork [prompt]` | Copy the conversation into a new background session | Keep working here |
| `/resume [session]`, `/rename [name]` | Resume a conversation by id or name, or name this one | `claude --resume <name>` from the shell |
| `/recap` | One-line summary of the session | |
| `/diff` | Review working-tree changes, including Claude's edits | |
| `/export [filename]`, `/copy [N]` | Export the conversation; copy the Nth-latest response | |
| `/focus` | Focus view: last prompt, a one-line tool summary, the final response | |
| `/goal [condition\|clear]` | Claude keeps working across turns until the condition holds | A separate model checks the condition each turn |

### 2.2 Model, reasoning and speed

| Command / key | Does | Notes (Folder 01 file 03) |
|---|---|---|
| `/model [model]` | Switch the model and save it as the default | Aliases `opus` (Opus 5.5), `sonnet` (Sonnet 5.5), `haiku` (Haiku 5.5), `fable`, `opusplan`, `[1m]` |
| `Alt+P` (Win/Linux), `Option+P` (Mac) | Switch model without clearing the prompt | |
| `/effort [level\|auto\|status\|ultracode [on\|off]]` | Set effort: `low`…`xhigh`, `max` (session-only), `auto` | Default `medium` on Opus 5.5 / Sonnet 5.5 / Haiku 5.5 |
| `ultrathink` (in a prompt) | Deeper reasoning for that turn only | "think hard" is just text |
| `Alt+T` / `Option+T` | Toggle extended thinking | **No effect on Opus 5.5, Sonnet 5.5, Haiku 5.5 or Fable**: always on |
| `/advisor [model\|off]` | Consult a stronger model at key moments | API only; experimental |
| `/fast [on\|off]`, `Alt+O` / `Option+O` | Fast mode (Opus 5.5 / 5 / 4.8) | About 2× price, up to 2.5× faster output |
| `Ctrl+O` | Transcript viewer: tool detail, per-message model, thinking | |

### 2.3 Planning and permissions

| Command / key | Does | Notes |
|---|---|---|
| `Shift+Tab` (or `Alt+M` on some Windows terminals) | Cycle modes: `default` → `acceptEdits` → `plan` → (`bypassPermissions`) → `auto` | From `auto`, the next press goes to `default` |
| `/plan [description]` | Enter plan mode, optionally starting a task | `/plan fix the flaky OutboxIT` |
| `Ctrl+G` | Open the prompt, or a proposed plan, in your editor | Edit the plan before approving it |
| `/permissions` | Manage allow/ask/deny rules by scope | Folder 03 file 02 §2.3 |
| `/sandbox` | Toggle sandbox mode (supported platforms) | |
| `/fewer-permission-prompts` | Scan transcripts; propose an allowlist of read-only commands | A bundled skill |

### 2.4 Memory, configuration and extensions

| Command | Does | Notes |
|---|---|---|
| `/init` | Generate a starting CLAUDE.md | `CLAUDE_CODE_NEW_INIT=1` gives an interactive flow covering skills and hooks too |
| `/memory` | Edit CLAUDE.md files; toggle and view auto memory | File 03 |
| `/doctor [prompt-audit [path]]` | Setup checkup; prompt audit of instruction files | Finds stale and contradictory instructions |
| `/config [key=value …]` | Settings UI (theme, model, output style, editor mode …) | Vim mode now lives here (`/vim` was removed in v2.1.92) |
| `/status` | Version, model, account, connectivity | |
| `/usage` (`/cost`, `/stats`) | Session cost, plan limits, activity | |
| `/hooks` | View hook configuration | Folder 05 |
| `/mcp [reconnect\|enable\|disable …]` | Manage MCP servers and OAuth | Folder 06 |
| `/agents` | Reminder to create or manage subagents (or edit `.claude/agents/`) | Folder 04 |
| `/skills`, `/reload-skills`, `/skill-doctor` | List skills; re-scan after edits; see each skill's context cost and usage | Folder 04 |
| `/plugin [subcommand]`, `/reload-plugins` | Manage plugins | |
| `/statusline`, `/output-style [style]`, `/theme`, `/keybindings`, `/terminal-setup` | Status line, output style, theme, key bindings, Shift+Enter setup | |
| `/add-dir <path>`, `/cd <path>` | Add a working directory; move the session | |
| `/ide` | Manage IDE integration | |
| `/insights`, `/team-onboarding` | Reports on your usage; a team onboarding guide | |

### 2.5 Review, verification and quality

| Command | Does |
|---|---|
| `/code-review [low…max\|ultra] [--fix] [--comment] [--max-findings n] [pr#\|branch\|path]` (alias `/review`) | Bug-focused review in a fresh subagent; `--fix` applies findings, `--comment` posts PR comments |
| `/security-review` | Security review of the branch diff against origin's default branch |
| `/simplify [target]` | Cleanup review of changed code, then apply |
| `/verify`, `/run` | Build and run the app to confirm a change works, beyond the tests |
| `/ultrareview [PR or branch]` | Deep multi-agent review in a cloud sandbox |

### 2.6 Parallel, background and scheduled work

| Command / flag | Does |
|---|---|
| `/batch <instruction>` | Plan a large change into 5–30 units; run each in its own worktree; open a PR per unit |
| `/loop [interval] [prompt]` | Repeat a prompt while the session stays open (self-paced if no interval) |
| `/background [prompt]`, `/tasks`, `/stop` | Detach this session to run in the background; view background work; stop it |
| `/subtask <task>` | Spawn a forked background subagent that inherits the conversation |
| `Ctrl+B` | Background running Bash commands and agents (tmux: press twice) |
| `Ctrl+X Ctrl+K` | Stop all background subagents in this session |
| `/schedule [description]` | Create and manage cloud scheduled tasks (formerly routines) |
| `claude -w <name>` / `--worktree` | Start in an isolated worktree at `<repo>/.claude/worktrees/<name>` |
| `claude --bg "<task>"`, `claude agents`, `claude attach <id>` | Background agent; agent view; attach to one |
| `/teleport`, `--teleport`, `/remote-control` | Move cloud sessions to the terminal; control a local session from claude.ai |

### 2.7 Input prefixes and editing

| Key / prefix | Does |
|---|---|
| `/` at the start | Command or skill |
| `!` at the start | Shell mode: run a command, add its output, have Claude respond to it |
| `@path` | Include a file (≤ 25,000 tokens by default; text files > 256 KB are not included); `@dir/` shows a listing; `@server:resource` reads an MCP resource. Also loads the CLAUDE.md of that file's directory |
| `?` on an empty prompt | Shortcut help |
| `\` + `Enter`, `Ctrl+J`, `Shift+Enter` (native in Windows Terminal, iTerm2, WezTerm …) | Newline |
| `Ctrl+R` | Reverse-search history |
| `Ctrl+S` | Stash or restore the prompt |
| `Ctrl+V` (`Alt+V` on Windows/WSL) | Paste an image |
| `Ctrl+T` | Toggle Claude's task checklist |
| `Ctrl+L` | Redraw the screen (keeps the conversation) |
| `Ctrl+C` | Interrupt, or clear input; twice to exit |
| `Ctrl+D` | Exit (twice within 800 ms) |
| `Ctrl+Enter` | Send queued messages now |

### 2.8 VS Code extension [doc]

| Shortcut (Windows/Linux · Mac) | Does |
|---|---|
| `Ctrl+Esc` · `Cmd+Esc` | Toggle focus between the editor and Claude |
| `Ctrl+Shift+Esc` · `Cmd+Shift+Esc` | Open a new conversation in an editor tab |
| `Alt+K` · `Option+K` | Insert an @-mention of the current file and selection (e.g. `@app.ts#5-10`) |
| `Ctrl+Alt+F` · `Ctrl+Option+F` | Toggle focus view |
| `Ctrl+Shift+T` · `Cmd+Shift+T` | Reopen the last closed Claude tab |

### 2.9 CLI: subcommands and the flags worth knowing

| Invocation | Does |
|---|---|
| `claude`, `claude "query"` | Interactive session, optionally with a first prompt |
| `claude -p "query"` | One-shot (print) mode; exits after the answer |
| `cat build-error.txt \| claude -p 'explain the root cause'` | Pipe content in (the documented pattern) |
| `claude -c`, `claude -r <id\|name> "query"` | Continue the latest conversation here; resume a specific one |
| `claude update`, `claude doctor`, `claude auth status` | Update; read-only diagnostics; auth status as JSON (exit code 0 if logged in) |
| `claude mcp …`, `claude plugin …` | Configure MCP servers; manage plugins |
| `claude setup-token` | Long-lived OAuth token for CI (subscription) |
| `claude agents`, `claude attach`, `claude logs`, `claude stop`, `claude rm` | Manage background sessions |

| Flag | Use |
|---|---|
| `--model`, `--effort`, `--advisor <model>`, `--fallback-model` | Model, effort, advisor and fallback for this session |
| `--permission-mode <mode>` | Start in `plan`, `acceptEdits`, `auto`, `dontAsk` … |
| `--allowedTools`, `--disallowedTools`, `--tools` | Pre-approve; deny or remove; restrict the available built-ins |
| `--add-dir` | Extra working directories |
| `--append-system-prompt[-file]`, `--system-prompt[-file]` | Add to, or replace, the system prompt |
| `-p` with `--output-format text\|json\|stream-json`, `--json-schema`, `--max-turns`, `--max-budget-usd`, `--no-session-persistence` | Headless runs with structured output and hard limits (Folder 04 file 03) |
| `--mcp-config`, `--strict-mcp-config` | Load MCP servers from files; ignore all others |
| `--settings <file\|json>`, `--setting-sources user,project,local` | Per-session settings; choose which files load |
| `-w`, `--worktree [name]`, `--tmux` | Isolated worktree session; tmux panes |
| `--bg`, `--background` | Start as a background agent |
| `-n`, `--name` | Name the session |
| `--bare`, `--safe-mode` | Skip auto-discovery of hooks, skills, MCP and CLAUDE.md; start with customisations disabled (troubleshooting) |
| `--debug [filter]`, `--debug-file`, `--verbose` | Diagnostics |
| `--dangerously-skip-permissions` | Equals `--permission-mode bypassPermissions`; containers only |

### 2.10 Removed or renamed (don't follow old guides)

| Old | Now |
|---|---|
| `/vim` | Removed in v2.1.92; use `/config` → Editor mode |
| `/pr-comments` | Removed in v2.1.91; ask Claude directly |
| `/ultraplan` | Removed; use plan mode |
| `--enable-auto-mode` | Removed in v2.1.111; auto mode is in the `Shift+Tab` cycle; `--permission-mode auto` |
| `/review` as a separate command | Now an alias of `/code-review` |
| "think", "think hard", "megathink" keywords | Plain text; use `/effort` or `ultrathink` |

---

## 3. Verification

This file is reference material, so instead of a code listing its claims were checked mechanically. A harness script extracted every backticked `/command` and `--flag` from this file and confirmed each appears in the code.claude.com snapshot taken on 2026-10-30: the `commands.md` "All commands" table and the `cli-reference.md` commands and flags tables. The result is recorded in the [KB README](../README.md#where-this-kb-refines-the-brief). The same check runs on every file in Folders 03–08.

---

## 4. Failure modes

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| F1 | "`/rewind` didn't undo the migration Claude ran" | Bash-only changes are not checkpointed | Use git; commit before risky Bash steps |
| F2 | Ten-file change you never reviewed | Auto mode is the default; you never entered plan mode | `/plan <task>` or `--permission-mode plan` for anything multi-file; set `defaultMode: plan` per project if your team wants it always |
| F3 | Allow rule "doesn't work" | A broader deny rule matches first | Rules evaluate deny → ask → allow; narrow the deny instead |
| F4 | `Alt+T` does nothing | Opus 5.5 / Sonnet 5.5 / Haiku 5.5 / Fable always think | Use `/effort` |
| F5 | "think harder" had no effect | Not a keyword anymore | `/effort high` or `ultrathink` |
| F6 | Shift+Tab doesn't cycle on Windows | The runtime didn't enable VT input mode | `Alt+M` |
| F7 | Side question derailed the task | Asked in the main conversation | `/btw` |
| F8 | A third correction still fails | The context now holds two failed attempts | `/clear` and one better prompt |
| F9 | A guide's command errors | Removed command | §2.10; `/release-notes` |

---

## 5. Staff-level drills

<details><summary><b>D1 · "Should my team turn auto mode off?"</b></summary>

**Staff answer.** Auto mode is the default because a classifier reviews risky actions, and it blocks production deploys and force pushes by default [doc]. Keep it for day-to-day work, but layer **deny rules** for what must never happen (they block in every mode, including bypass) and **hooks** for what must always happen.

Use `plan` for multi-file changes you want to review first, and `dontAsk` with a tight allowlist for CI. Disable a mode org-wide through managed settings (`disableAutoMode`, `disableBypassPermissionsMode`), not by asking people.
</details>

<details><summary><b>D2 · "What's the difference between /clear, /compact and /rewind?"</b></summary>

**Staff answer.**
- **`/clear`** discards the context and starts fresh. Use it between tasks, and after failed corrections.
- **`/compact [focus]`** replaces history with a summary. Use it to continue the same task with less context.
- **`/rewind`** goes back to a checkpoint: the code, the conversation, or both. It can also *summarise* from or up to a point. Use it when a direction failed and you want the earlier state, not a summary of the failure.
</details>

<details><summary><b>D3 · "Why does /btw exist if I can just ask?"</b></summary>

**Staff answer.** Anything you ask in the main thread becomes part of the trajectory the model re-reads every turn. `/btw` answers from the conversation so far without adding to it, and it has no tools. A quick "what does this flag do?" then doesn't steer the task or bloat the context. Press `f` to promote it into a background subagent if it turns out to need tools.
</details>

<details><summary><b>D4 · "How do I run Claude on a log file without an interactive session?"</b></summary>

**Staff answer.** Use `cat crash.log | claude -p 'concisely explain the root cause' > out.txt`, the documented piping pattern. Add these as needed:
- `--output-format json` for machine-readable output
- `--json-schema` for validated structure
- `--max-turns` / `--max-budget-usd` as hard limits
- `--permission-mode dontAsk` with `--allowedTools` for a locked-down tool set

Folder 04 file 03 builds the CI version.
</details>

---

## 6. Checklist

- [ ] You know `Esc`, `Esc Esc`, `Shift+Tab`, `/clear`, `/compact`, `/rewind`, `/btw`, `/context`, `/model`, `/effort` without looking.
- [ ] Multi-file changes start in plan mode.
- [ ] Rules that can't bend are deny rules or hooks, not CLAUDE.md lines.
- [ ] Risky Bash steps are preceded by a commit, because checkpoints don't cover Bash.
- [ ] Stale guidance (§2.10) has been removed from team docs.

---

## 7. References

- Commands: <https://code.claude.com/docs/en/commands>
- CLI reference: <https://code.claude.com/docs/en/cli-reference>
- Interactive mode (shortcuts, input prefixes): <https://code.claude.com/docs/en/interactive-mode>
- Permission modes: <https://code.claude.com/docs/en/permission-modes>
- Checkpointing: <https://code.claude.com/docs/en/checkpointing>
- Best practices: <https://code.claude.com/docs/en/best-practices>
- VS Code extension: <https://code.claude.com/docs/en/vs-code>
- Docs index for agents (the source of this file's snapshot): <https://code.claude.com/docs/llms.txt>

Next: [02 · Explore → plan → execute → verify, and worktrees](02-the-explore-plan-execute-verify-workflow-and-git-worktree-parallel-agents.md) · [03 · CLAUDE.md and memory](03-crafting-the-perfect-under-200-line-claude-md-and-hierarchical-memory.md) · [KB README](../README.md)

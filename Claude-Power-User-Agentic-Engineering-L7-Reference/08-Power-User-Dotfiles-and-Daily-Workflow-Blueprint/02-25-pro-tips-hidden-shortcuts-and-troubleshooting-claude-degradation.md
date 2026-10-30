# 25 Pro Tips, Hidden Shortcuts and Troubleshooting Claude "Degradation"

> **Folder 08 · File 2 of 2** · verified 2026-10-30. Every command, flag, shortcut and environment variable on this page is checked against the code.claude.com docs snapshot (`interactive-mode.md`, `commands.md`, `context-window.md`, `memory.md`, `checkpointing.md`, `cli-reference.md`).
> **Listing:** `session_health.py`, a degradation doctor that reads a session transcript. Run here on a synthetic session (shown) and on two real long sessions from this machine (quoted).

---

## 0. Orientation

"Claude got worse this afternoon" is the most common complaint about agentic coding. It almost never means the model changed. It usually means **the session changed**:
- the context filled with stale tool output;
- compaction summarised away a decision;
- a config change broke the prompt cache;
- the same failing command ran five times;
- one file was rewritten in circles.

All of those leave traces in the session transcript, and L1 reads them.

The tips are numbered so L1's fixes can point at them. Tips 1–6 are about context and cache; 7–12 about steering; 13–16 about recovery; 17–20 about keyboard and interaction; 21–25 about automation and hygiene.

### 0.1 The physics behind every "degradation" [Folder 01]

- **Attention is finite.** More tokens means each relevant token gets a smaller share, and the middle of a long context is the least attended (lost in the middle).
- **Compaction is lossy by design.** Something summarised is gone in detail.
- **The cache is a prefix.** Change anything near the front, and everything after it is re-processed and re-billed.

Everything below follows from those three facts.

---

## 1. The 25 tips

### Context and cache (1–6)

**1. `/clear` between unrelated tasks.** A new task carrying the last task's 300K tokens of file reads is paying, in attention and money, for history it doesn't need. CLAUDE.md, rules, skills and hooks all reload, so `/clear` costs you nothing you configured. [doc]

**2. `/compact` with a focus, before the automatic one.** `/compact keep the failing test names, the outbox design decision and the remaining TODO list` keeps what *you* choose. Automatic compaction keeps what a summary picks. [doc]

**3. Send exploration to subagents.** "Find every caller of `OrderService.place`" reads dozens of files. In a subagent (the built-in Explore agent, or your own from Folder 04) only the answer returns to your context. [doc + Folder 04]

**4. Keep state in files, and start fresh after the second compaction.** `docs/plan.md` and `progress.md` survive anything (Folder 02). After compaction, Claude Code:
- re-reads the project-root CLAUDE.md;
- re-runs `compact`-matched SessionStart hooks, which is why `session_context.py` matches `compact`;
- re-reads up to five recently modified files; files over 5,000 tokens come back as references only.

Conversation-only instructions don't come back. Put durable ones in CLAUDE.md. [doc]

**5. Keep the prefix stable.** Tools, system prompt and CLAUDE.md come first in every request. These rewrite the cache from that point on:
- switching models mid-task (Folder 01 measured 7× the cost of one turn at 120K tokens when switching Opus → Sonnet);
- reconnecting MCP servers with tools loaded upfront;
- editing settings that change the tool list.

Decide the model and servers at the start. [doc + measured: Folder 01]

**6. Leave MCP tool search on.** Deferred tool definitions keep a 5-server fleet's ~55K tokens out of every request (Folder 06 L2: $3.02 → $0.25 per Opus session). They also keep server churn from busting the prefix. [doc + measured: Folder 06]

### Steering (7–12)

**7. Plan before touching more than a few files.** `/plan fix the outbox relay ordering bug` (or Shift+Tab to plan mode, or Alt+M on Windows terminals where Shift+Tab doesn't cycle) gets a reviewed plan before any edit. [doc + Folder 03]

**8. Put a verification command in every task, then make it mandatory.**
- "Done when `./mvnw -q verify` passes."
- Folder 05's `verify_build.py` Stop hook turns the request into a gate.

The biggest single quality lever is giving Claude a way to check its own work. [doc + Folder 05]

**9. Parallelise with worktrees, not with one crowded session.** `claude --worktree` gives each task its own checkout and context. Two half-finished tasks in one context degrade both. [doc + Folder 03]

**10. Spend effort where it pays.**
- `/effort` sets the default; medium is the 5.5 models' default.
- `ultrathink` in a prompt raises one hard turn (v2.1.311+).
- Mechanical edits don't need high effort; a race-condition diagnosis does.
- Alt+T (the thinking toggle) has no effect on Opus 5.5 / Sonnet 5.5, where effort is the control.

[doc + Folder 01]

**11. Ask side questions with `/btw`.** It answers from what's already in context, with no tools, and never enters the conversation history, so "what was that config file called?" costs no context. Press `f` to fork it into a background subagent if it needs tools. [doc]

**12. Make Claude interview you before big work.** "Ask me up to six questions you need answered before writing the spec" is cheaper than a wrong spec. T1 (Folder 07) builds it in. [doc + Folder 07]

### Recovery (13–16)

**13. After two failed attempts, stop the loop.** A third identical retry rarely succeeds; the missing piece is usually a fact, not effort. Interrupt with `Esc`, read the error yourself, and give the fact: "the test DB is on port 5433", or "that API was removed in Boot 4". [practice + L1 retry-loop signal]

**14. Turn every correction you give twice into configuration.**
- A fact goes in CLAUDE.md.
- A path-specific convention goes in `.claude/rules/`.
- Anything that must never happen goes in a hook.

Corrections in conversation disappear at the next `/clear` or compaction. [doc + Folder 05]

**15. Rewind instead of arguing.**
- `Esc` `Esc` (or `/rewind`) restores code and conversation to an earlier checkpoint.
- `/branch` forks the conversation to try another direction while keeping the original.

Caveat: `/rewind` undoes Bash changes only to files Claude also edited with its edit tools. A file changed only by a Bash command isn't tracked. Commit before risky shell work. [doc]

**16. Cap tool output at the source.** `./mvnw -q`, `| tail -50`, `LIMIT 50`, `git log --oneline -20`. A 120K-character log is ~30K tokens of mostly noise, sitting in context until compaction. `MAX_MCP_OUTPUT_TOKENS` (default 25,000) is a backstop for MCP output, not a design. [doc + Folder 06]

### Keyboard and interaction (17–20)

**17. `@` and `!` beat pasting.**
- `@src/main/java/…/OrderService.java` mentions a file with autocomplete.
- `!./mvnw -q test -Dtest=OrderServiceTest` runs a command in shell mode and adds its output to the session for Claude to respond to.
- `?` on an empty prompt shows the shortcut panel.

[doc]

**18. Write long prompts in your editor.**
- `Ctrl+G` (or `Ctrl+X Ctrl+E`) opens the prompt in your default editor, ideal for Folder 07's templates.
- `Ctrl+S` stashes a half-written prompt and restores it later.
- `Alt+V` on Windows pastes a screenshot from the clipboard as an `[Image #N]` chip.

[doc]

**19. Watch work without interrupting it.**
- `Ctrl+O` opens the transcript viewer: tool calls, timestamps, model per message.
- `Ctrl+T` toggles Claude's task checklist.
- `Ctrl+B` backgrounds a running Bash command or agent.
- `Ctrl+X Ctrl+K` stops all background subagents.
- `Ctrl+Enter` sends queued messages immediately.

[doc]

**20. Switch quickly, deliberately.**
- `Alt+P` switches model without clearing the prompt.
- `Alt+O` toggles fast mode.
- `/goal <condition>` keeps Claude working across turns until a condition holds, for example `/goal ./mvnw -q verify passes`. Prefer a Stop hook for permanent gates.

Remember tip 5 before switching model mid-task. [doc]

### Automation and hygiene (21–25)

**21. Headless runs need three flags.** `claude -p … --output-format json --max-turns 30`, plus `--bare` when the repository isn't yours. JSON gives you `result`, `total_cost_usd` and `permission_denials` to assert on. The turn cap bounds cost. `--bare` skips auto-discovery of hooks, skills, subagents, MCP servers, auto memory and CLAUDE.md, which is what you want for a checkout you don't trust. [doc + Folder 04]

**22. Package repeated prompts as skills.** Folder 04's `/new-slice` is Folder 07's T2 behind one command. If you paste the same prompt three times a week, it's a skill. [doc + Folders 04, 07]

**23. Review before you push.** `/code-review` (alias `/review`) for correctness, `/security-review` for the security pass. Folder 04's read-only `code-reviewer` subagent checks your team's own invariants. [doc + Folder 04]

**24. Audit what Claude is loading.**
- `/context` shows what fills the window.
- `/usage` shows session cost, plan limits and activity (`/cost` is an alias).
- `/memory` edits the memory files.
- `/doctor` runs a setup checkup; `/doctor prompt-audit` audits CLAUDE.md, rules, skills and subagents.
- `/fewer-permission-prompts` scans your transcripts for read-only calls and proposes an allowlist.
- When a config change breaks sessions, `claude --safe-mode` starts with every customization off.

[doc]

**25. Measure degradation instead of guessing.** Run L1 on the session that "went bad" and read which signal fired. Then apply the tip it names. [measured: L1]

---

## 2. Troubleshooting matrix: "Claude got worse"

| Symptom | Measure | Likely cause | Fix (tip) |
|---|---|---|---|
| Ignores a rule it followed this morning | L1 compactions; was the rule only said in chat? | The rule was lost in compaction, or lives in a path rule that hasn't matched | Put it in CLAUDE.md or `.claude/rules/` (4, 14) |
| Re-reads files it already read; forgets decisions | L1 context ≥ 80%, compactions ≥ 2 | Context pressure, lossy summaries | State files, fresh session (1, 4) |
| Slower and more expensive per turn | L1 prompt cache: hit share, prefix busts | Model switch, MCP reconnect, tool-list change | Stable prefix, tool search on (5, 6) |
| Same command fails again and again | L1 retry loops | A missing fact (port, version, credential) | Interrupt, give the fact, add it to config (13, 14) |
| Edits one file in circles | L1 edit churn | Contradictory constraints or a moving target | Rewind, restate the constraint once (15) |
| Answers lose detail after a big command | L1 output floods | A huge tool result crowded the context | Cap output at the source (16) |
| An MCP tool "doesn't exist" | `/mcp` | The server failed to connect (with tool search on, Claude is told) | Fix the server; check `claude mcp list` warnings (Folder 06) |
| Hallucinated an API | Ask for the version and source | The library version isn't in context | Docs MCP with the version named; check against the jar (Folder 06 file 02) |
| Hook "doesn't work" | `/hooks`; run the hook by hand | Exit 1 (non-blocking), a matcher regex, a Windows path | Folder 05 failure-mode table |
| Sessions broken right after a config change | `claude --safe-mode` reproduces cleanly? | A hook, skill, plugin or MCP server in the new config | Bisect `.claude/**` changes with `git log -p`; `/doctor` (24) |

---

## 3. Verified listing

### L1 · `session_health.py`

**What it shows.** It parses a Claude Code session transcript (JSONL) and reports seven measurements:
- requests, prompts, tool calls, duration;
- **context pressure:** peak, and requests at ≥ 50% and ≥ 80% of the window;
- **compactions** (`compact_boundary` events);
- **prompt cache:** the share of input tokens read from cache, and *prefix busts* (requests that re-wrote over half their context);
- **retry loops:** the same command or file operation failing ≥ 3 times;
- **edit churn:** one file edited ≥ 6 times;
- **output floods:** tool results over 40,000 characters.

Each warning names the tip that fixes it. Assistant usage is de-duplicated by message id, because streamed blocks repeat it. Subagent (sidechain) traffic is excluded.

**What it does not show.** Quality directly; these are leading indicators. The transcript format is internal to Claude Code (observed in v2.1.312), so a future version may rename fields; the parser skips what it doesn't recognise. The thresholds are heuristics; tune them to your sessions.

Run: `python session_health.py ~/.claude/projects/<project>/<session>.jsonl [window]`. With no argument it analyses the built-in synthetic session.

```python
"""session_health.py - a degradation doctor for Claude Code sessions. Reads a session transcript (the JSONL Claude Code
writes under ~/.claude/projects/<project>/<session>.jsonl; an internal format observed in v2.1.312, not a public
contract) and reports the signals behind "Claude got worse": context pressure, compactions, prompt-cache busts, retry
loops, edit churn, tool-output floods and session length, each mapped to the fix in file 02's tips.
Usage: python session_health.py <session.jsonl> [window_tokens]   (no argument: a synthetic demo session)
"""
import collections
import json
import sys
from datetime import datetime

FLOOD_CHARS = 40_000          # ~10K tokens: where Claude Code starts warning about MCP output
CHURN_EDITS = 6               # edits to one file in one session
RETRY_ERRORS = 3              # failures of the same command or file operation


def base(path):
    """File name only (transcripts carry absolute paths, with backslashes on Windows); commands pass through."""
    is_path = ("/" in path or "\\" in path) and " " not in path
    return path.replace("\\", "/").rsplit("/", 1)[-1] if is_path else path


def text_size(content):
    if isinstance(content, str):
        return len(content)
    return sum(len(b.get("text", "")) for b in content or [] if isinstance(b, dict))


def analyse(lines, window):
    usage, order, tools, results, prompts, compactions, stamps = {}, [], {}, [], 0, 0, []
    for d in lines:
        if d.get("isSidechain"):
            continue                                              # subagent traffic has its own context
        if d.get("timestamp"):
            stamps.append(datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00")))
        if d.get("type") == "system" and d.get("subtype") == "compact_boundary":
            compactions += 1
            order.append(("compact", None))
        msg = d.get("message") if isinstance(d.get("message"), dict) else {}
        content = msg.get("content")
        if d.get("type") == "assistant":
            mid = msg.get("id")
            if mid and msg.get("usage"):
                if mid not in usage:
                    order.append(("request", mid))
                usage[mid] = msg["usage"]                         # streamed blocks repeat the usage: keep the last
            for b in content if isinstance(content, list) else []:
                if b.get("type") == "tool_use":
                    inp = b.get("input", {})
                    tools[b["id"]] = (b["name"], inp.get("file_path") or inp.get("command") or inp.get("pattern") or "")
        elif d.get("type") == "user" and not d.get("isMeta") and not d.get("isCompactSummary"):
            blocks = content if isinstance(content, list) else []
            tool_results = [b for b in blocks if isinstance(b, dict) and b.get("type") == "tool_result"]
            if not tool_results and (isinstance(content, str) or blocks):
                prompts += 1
            for b in tool_results:
                results.append((b.get("tool_use_id"), bool(b.get("is_error")), text_size(b.get("content"))))

    contexts, busts, first = [], 0, True
    read = write = fresh = 0
    for kind, mid in order:
        if kind == "compact":
            first = True                                          # the request after a compaction rebuilds the cache
            continue
        u = usage[mid]
        c_read, c_write, c_in = (u.get("cache_read_input_tokens", 0), u.get("cache_creation_input_tokens", 0),
                                 u.get("input_tokens", 0))
        ctx = c_read + c_write + c_in
        contexts.append(ctx)
        read, write, fresh = read + c_read, write + c_write, fresh + c_in
        if not first and ctx >= 20_000 and c_write >= 0.5 * ctx:
            busts += 1                                            # most of the prefix re-written: something changed early
        first = False
    errors = collections.Counter(tools.get(t, ("?", ""))[0:2] for t, err, _ in results if err)
    edits = collections.Counter(tools[t][1] for t, _, _ in results
                                if t in tools and tools[t][0] in ("Edit", "Write", "MultiEdit", "NotebookEdit"))
    floods = sorted(size for _, _, size in results if size > FLOOD_CHARS)
    hours = (max(stamps) - min(stamps)).total_seconds() / 3600 if stamps else 0
    return {
        "requests": len(contexts), "prompts": prompts, "tool_calls": len(results), "hours": hours,
        "peak": max(contexts, default=0), "last": contexts[-1] if contexts else 0,
        "over50": sum(c >= 0.5 * window for c in contexts), "over80": sum(c >= 0.8 * window for c in contexts),
        "compactions": compactions, "hit": read / max(1, read + write + fresh), "busts": busts,
        "loops": [(k, n) for k, n in errors.most_common() if n >= RETRY_ERRORS],
        "churn": [(f, n) for f, n in edits.most_common() if n >= CHURN_EDITS],
        "floods": floods,
    }


def report(name, r, window):
    print(f"== {name}: {r['requests']} model requests, {r['prompts']} prompts, {r['tool_calls']} tool calls, "
          f"{r['hours']:.1f} h ==")
    rows = [
        ("context", r["over80"] == 0, f"peak {r['peak']:,} tokens ({r['peak'] / window:.0%} of {window:,}); "
                                      f"{r['over50']} requests >= 50%, {r['over80']} >= 80%", "tips 1-3: /clear between tasks, "
                                      "/compact with a focus, subagents for exploration"),
        ("compactions", r["compactions"] <= 1, f"{r['compactions']} automatic or manual compactions",
         "tip 4: state files (plan.md, progress.md) so compaction loses nothing; start fresh after 2"),
        ("prompt cache", r["hit"] >= 0.8 and r["busts"] <= 2, f"{r['hit']:.1%} of input tokens read from cache; "
                                                              f"{r['busts']} prefix busts", "tips 5-6: stable CLAUDE.md, "
                                                              "MCP tool search on, no mid-session config churn"),
        ("retry loops", not r["loops"], f"{len(r['loops'])} commands failing >= {RETRY_ERRORS}x: "
                                        f"{[f'{t}:{base(k)[:40]} x{n}' for (t, k), n in r['loops']][:3]}",
         "tips 13-14: stop, read the error yourself, add the missing fact to the prompt or a hook"),
        ("edit churn", not r["churn"], f"{len(r['churn'])} files edited >= {CHURN_EDITS}x: "
                                       f"{[f'{base(f)}:{n}' for f, n in r['churn']][:3]}",
         "tip 15: Esc Esc / rewind to the last good checkpoint, then restate the constraint"),
        ("output floods", not r["floods"], f"{len(r['floods'])} tool results over {FLOOD_CHARS:,} chars "
                                           f"(largest {max(r['floods'], default=0):,})",
         "tip 16: cap outputs (head, LIMIT, quiet flags); MAX_MCP_OUTPUT_TOKENS is a backstop"),
    ]
    for label, ok, evidence, fix in rows:
        print(f"  {'ok  ' if ok else 'WARN'} {label:<14} {evidence}" + ("" if ok else f"\n       fix -> {fix}"))


def demo():
    """A synthetic session that shows every signal: growth to 85% of the window, two compactions, two cache busts,
    a build failing four times, one file edited eight times, a 120K-char tool output, 14 prompts over 5.5 hours."""
    lines, t0 = [], datetime(2026, 10, 30, 9, 0)

    def stamp(minutes):
        return (t0.replace(hour=9 + minutes // 60, minute=minutes % 60)).isoformat() + "Z"
    ctx = 20_000
    for i in range(60):
        if i in (25, 45):
            lines.append({"type": "system", "subtype": "compact_boundary", "timestamp": stamp(i * 5)})
            ctx = 120_000
        if i % 4 == 0 and len([d for d in lines if d.get("type") == "user" and isinstance(d["message"]["content"], str)]) < 14:
            lines.append({"type": "user", "timestamp": stamp(i * 5), "message": {"role": "user", "content": f"prompt {i}"}})
        ctx += 34_000 if i < 25 else 22_000
        write = int(ctx * 0.7) if i in (10, 50) else 3_000
        lines.append({"type": "assistant", "timestamp": stamp(i * 5 + 1), "message": {
            "id": f"msg_{i}", "usage": {"input_tokens": 50, "cache_creation_input_tokens": write,
                                        "cache_read_input_tokens": ctx - write - 50, "output_tokens": 800},
            "content": [{"type": "tool_use", "id": f"tu_{i}",
                         "name": "Bash" if i in (30, 31, 32, 33) else "Edit" if i % 7 == 0 or i in (36, 37) else "Read",
                         "input": {"command": "./mvnw -q verify"} if i in (30, 31, 32, 33) else
                         {"file_path": "src/main/java/com/acme/orders/application/PlaceOrderUseCase.java"}}]}})
        lines.append({"type": "user", "timestamp": stamp(i * 5 + 2), "message": {"role": "user", "content": [
            {"type": "tool_result", "tool_use_id": f"tu_{i}", "is_error": i in (30, 31, 32, 33),
             "content": "x" * (120_000 if i == 20 else 900)}]}})
    lines.append({"type": "user", "timestamp": stamp(330), "message": {"role": "user", "content": "final prompt"}})
    return lines


if __name__ == "__main__":
    window = int(sys.argv[2]) if len(sys.argv) > 2 else 1_000_000
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf-8") as fh:
            data = [json.loads(line) for line in fh if line.strip()]
        report(sys.argv[1].replace("\\", "/").split("/")[-1], analyse(data, window), window)
    else:
        report("synthetic demo session", analyse(demo(), window), window)
```

**Output (verified, synthetic session):**

```text
== synthetic demo session: 60 model requests, 15 prompts, 60 tool calls, 5.5 h ==
  WARN context        peak 870,000 tokens (87% of 1,000,000); 14 requests >= 50%, 3 >= 80%
       fix -> tips 1-3: /clear between tasks, /compact with a focus, subagents for exploration
  WARN compactions    2 automatic or manual compactions
       fix -> tip 4: state files (plan.md, progress.md) so compaction loses nothing; start fresh after 2
  ok   prompt cache   97.3% of input tokens read from cache; 2 prefix busts
  WARN retry loops    1 commands failing >= 3x: ['Bash:./mvnw -q verify x4']
       fix -> tips 13-14: stop, read the error yourself, add the missing fact to the prompt or a hook
  WARN edit churn     1 files edited >= 6x: ['PlaceOrderUseCase.java:11']
       fix -> tip 15: Esc Esc / rewind to the last good checkpoint, then restate the constraint
  WARN output floods  1 tool results over 40,000 chars (largest 120,000)
       fix -> tip 16: cap outputs (head, LIMIT, quiet flags); MAX_MCP_OUTPUT_TOKENS is a backstop
```

**On real sessions [measured].** Two earlier long Claude Code sessions on this machine, each an autonomous build of one of this KB's sibling references, analysed with the same script. Aggregates only; no content was read beyond tool names and file names.

| | Session A | Session B |
|---|---|---|
| Model requests / prompts / tool calls | 1,088 / 8 / 1,452 | 1,209 / 8 / 1,562 |
| Duration | 18.3 h | 35.4 h |
| Peak context | 965,696 tokens | 965,869 tokens |
| Requests ≥ 50% / ≥ 80% of 1M | 508 / 175 | 589 / 240 |
| Compactions | 4 | 4 |
| Input read from cache | 99.2% | 99.1% |
| Prefix busts | 0 | 2 |
| Files edited ≥ 6 times | 12 (a README 20×) | 3 |
| Output floods | 0 | 1 (40,893 chars) |

Three readings:
- **Both peaks sit just under ~967K tokens**, where automatic compaction fires (Folder 01). Long autonomous sessions live at the edge of the window, which is exactly when tips 1–4 matter.
- **99%+ of input came from cache.** A long session with a stable prefix is cheap. The cost risk is the bust, not the length.
- **Edit churn was mostly deliberate:** status tables in README files updated after each step. The signal flags it; you decide. A 20× README is a habit; a 20× `OrderService.java` is a problem.

---

## 4. Failure modes of the tips themselves

| # | Misuse | What happens | Do instead |
|---|---|---|---|
| F1 | `/clear` mid-task without a state file | The plan and decisions are gone | Write `plan.md` first (4) |
| F2 | `/compact` with no focus | The summary keeps the wrong details | State what to keep (2) |
| F3 | Switching models to save money mid-task | The cache is rewritten; the turn costs more | Route at task start (5) |
| F4 | `ultrathink` on every prompt | Cost and latency up, quality flat for routine edits | Use it per hard turn (10) |
| F5 | Trusting `/rewind` after shell edits | Bash-only file changes stay | Commit before risky shell work (15) |
| F6 | `/goal` as a permanent quality gate | Lasts one session | A Stop hook in settings (8, 20) |

---

## 5. Staff-level drills

<details><summary><b>D1 · "The team says Claude is worse since last week. How do you investigate?"</b></summary>

**Naive answer.** The model got nerfed; switch models.

**Why it fails.** Nothing was measured. The usual causes are local: a bigger CLAUDE.md, a new MCP server with tools upfront, a hook that floods output, longer sessions.

**Staff answer.**
1. Collect three "bad" transcripts and three from before.
2. Run L1 on all six.
3. Diff the signals: context peak, compactions, cache share, floods.
4. Diff `.claude/**`, `.mcp.json` and CLAUDE.md over the same week (`git log -p`).

The cause is almost always visible in one of those two diffs. Only if both are clean, test the model with your Folder 02 eval set.
</details>

<details><summary><b>D2 · "Long autonomous sessions are cheap thanks to caching. Why not run everything in one?"</b></summary>

**Staff answer.** Cheap per token isn't good per decision.
- L1's real sessions ran 175–240 requests above 80% of the window: the regime where attention is thinnest and compaction is imminent.
- Cost stayed low (99% cache) while the risk of losing a decision grew.

Split the work into tasks with state files and fresh sessions (tips 1, 4), and parallelise with worktrees (9). You keep the cache benefit inside each task and lose the context-rot tail.
</details>

<details><summary><b>D3 · "Should we enforce these tips?"</b></summary>

**Staff answer.** Enforce the ones that are invariants. Coach the ones that are judgement.
- **Enforce, via hooks:** the verification gate (8), secret and destructive-command guards (14), output caps for known noisy commands (16).
- **Coach:** `/clear` timing, effort choices, when to plan.

Publish L1's signals per team as a weekly digest, if anything. Never as a leaderboard.
</details>

---

## 6. Checklist

- [ ] New task → `/clear` (or a new worktree); long task → `plan.md` / `progress.md`.
- [ ] Model and MCP servers chosen at the start; tool search on.
- [ ] Every task names its verification command; the Stop hook enforces it.
- [ ] Two failures → stop, diagnose, add the missing fact to config.
- [ ] Outputs capped at the source.
- [ ] When quality drops: run `session_health.py` before blaming the model.

---

## 7. References

- Interactive mode (keyboard shortcuts, `/btw`, shell mode, transcript viewer): <https://code.claude.com/docs/en/interactive-mode>
- Commands reference: <https://code.claude.com/docs/en/commands>
- Context window and what survives compaction: <https://code.claude.com/docs/en/context-window>
- Memory (CLAUDE.md after compaction, `/memory`, `/doctor` audit): <https://code.claude.com/docs/en/memory>
- Checkpointing (`/rewind`, what isn't tracked): <https://code.claude.com/docs/en/checkpointing>
- Best practices: <https://code.claude.com/docs/en/best-practices> · Costs: <https://code.claude.com/docs/en/costs>

Previous: [01 · The `.claude/` blueprint](01-complete-production-dot-claude-folder-blueprint-for-java-monorepos.md) · [KB README](../README.md)

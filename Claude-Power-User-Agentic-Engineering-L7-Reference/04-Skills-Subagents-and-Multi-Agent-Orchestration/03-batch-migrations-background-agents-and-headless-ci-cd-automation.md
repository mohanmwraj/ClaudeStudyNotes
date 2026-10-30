# Batch Migrations, Background Agents and Headless CI/CD Automation

> **Folder 04 · File 3 of 3** · verified 2026-10-30 against code.claude.com `headless.md`, `cli-reference.md`, `commands.md`, `github-actions.md`, `workflows.md`, `scheduled-tasks.md`, `permission-modes.md`
> **Listings:** `headless_batch.py` + `fake_claude.py` + `test_headless_batch.py` (a guarded `claude -p` batch driver, tested against a documented-shape test double) · `ci_workflow_check.py` (GitHub workflows validated against the official schema plus security and cost policy)

---

## 0. Orientation

Interactive sessions don't scale to "migrate 40 services" or "triage every failing nightly test". Claude Code has five ways to run work without you at the keyboard:

| Mechanism | Who holds the plan | Where it runs | Use for |
|---|---|---|---|
| **`/batch <instruction>`** | Claude: researches, splits into 5–30 units, shows a plan you approve | One background subagent per unit, each in its own worktree; each tests and publishes its change | Large mechanical changes, started interactively |
| **Background sessions** (`claude --bg`, `/background`, `claude agents`) | Each session | Your machine, detached from the terminal | Long tasks you check on later |
| **`/loop` / `/schedule`** | A prompt on an interval (local, while the session is open) or a cloud scheduled task | Local session / cloud | Polling ("is the deploy done?"), recurring maintenance |
| **Dynamic workflows** | A script Claude writes, which the runtime executes | Background, resumable | Dozens to hundreds of agents: audits, 500-file migrations |
| **Headless `claude -p`** (CI) | Your pipeline | CI runners | Deterministic, auditable jobs: PR review, nightly bumps, batch fixes |

This file goes deep on the last one, because it's where staff engineers own the reliability, cost and security of agent runs. It also covers GitHub Actions.

### 0.1 The twelve rules

1. **Exit code is the contract.** `claude -p` exits 0 on success and non-zero on failure; SIGTERM gives 143. [doc]
2. **Ask for structure:** `--output-format json --json-schema '<schema>'`. **Check that `structured_output` exists** before using it, because it is absent when the run ends without valid output. [doc + measured: L1]
3. **Cap every run:** `--max-turns`, `--max-budget-usd`, plus a wall-clock timeout in your runner. [doc + measured: L1]
4. **Lock permissions down:** `--permission-mode dontAsk` plus an `--allowedTools` allowlist, or `--permission-mode auto --permission-prompts none` for classifier-reviewed unattended runs. [doc]
5. **Read `permission_denials`**, because a run can "succeed" having been blocked from the work. [doc + measured: L1]
6. **Retry only transient API errors, once.** Never retry a deterministic failure. [inference + measured: L1]
7. **Use `--bare` in CI for reproducibility and safety.** Without it, `-p` runs the project's hooks and connects its `.mcp.json` servers "even in a folder you've never trusted", and no trust dialog appears. [doc]
8. **One worktree per unit** (`--worktree <id>`). Clean up `-p --worktree` runs yourself (Folder 03 L2). [doc]
9. **Bound concurrency** to what your runner (and your rate limits) can take. [inference]
10. **GitHub Actions:** `anthropics/claude-code-action@v1`, least-privilege `permissions`, an `if:` guard for `@claude`, secrets only through `${{ secrets.* }}`, and a turn cap in `claude_args`. [doc + measured: L2]
11. **Never combine `pull_request_target` with a checkout of the PR head.** That runs untrusted code with your secrets. [inference, a well-known GitHub Actions pitfall + measured: L2]
12. **Report cost per unit** (`total_cost_usd`) and fail the job if any unit isn't DONE. [doc + measured: L1]

---

## 1. First principles

### 1.1 The print-mode contract [doc]

| Aspect | Behaviour |
|---|---|
| Exit status | 0 on success, non-zero on failure; an invalid flag errors on stderr before the run starts; SIGTERM → exit 143 |
| Input | Prompt argument, plus optional stdin (`cat log \| claude -p '…'`). Piped stdin is capped at **10 MB** |
| `--output-format` | `text` (default), `json` (result plus session id plus metadata, including `total_cost_usd` and a per-model cost breakdown), `stream-json` (newline-delimited events) |
| `--json-schema` | Validated structured output in `structured_output`. **Absent** if the run didn't produce valid output (for example, Claude declined), so check before use. `format` keywords are annotations, not enforced |
| Limits | `--max-turns` (exits with an error at the limit), `--max-budget-usd` (stops when estimated spend reaches the cap) |
| Permissions | `--allowedTools` (permission-rule syntax), `--permission-mode dontAsk` / `auto` / `acceptEdits`, `--permission-prompts none` for unattended runs (denials show up as `permission_denials`) |
| Reproducibility | `--bare` skips auto-discovery of hooks, skills, commands, subagents, plugins, MCP servers, auto memory and CLAUDE.md; needs `ANTHROPIC_API_KEY` (no OAuth/keychain) |
| Sessions | `--continue` / `--resume <id>`; `--no-session-persistence` for throwaway runs |

### 1.2 The security model of a CI agent [doc, inference]

A CI agent is untrusted-input processing with write access. The threats, and the controls:

| Threat | Control |
|---|---|
| The repo's own `.claude/settings.json` hooks or `.mcp.json` servers run in CI, even for a fork PR | `--bare`, or `--setting-sources` limited to what you control; review `.claude/` changes like CI config |
| Prompt injection from issue or PR text steers the agent | Least-privilege tools (`dontAsk` plus an allowlist); no secrets in reach; deny rules; the action's trigger checks |
| Untrusted PR code runs with secrets (`pull_request_target` plus checking out head) | Don't. Use `pull_request` for untrusted code; keep secrets out of jobs that run PR code |
| Runaway cost | `--max-turns`, `--max-budget-usd`, job `timeout-minutes`, spend limits |
| An agent loop triggers itself | The action rejects bot actors unless listed in `allowed_bots` [doc] |
| Silent partial success | Structured output plus exit code plus `permission_denials` checks (L1) |

### 1.3 GitHub Actions: modes and gates [doc]

- **Interactive mode** (no `prompt` input): Claude responds to `@claude` (the trigger phrase is configurable) in issue and PR comments, reviews, and new issue titles and bodies.
- **Automation mode** (`prompt` set): it runs without a mention. The prompt can be a skill invocation (`/bump-deps`), or a plugin skill installed via `plugin_marketplaces` and `plugins`.
- **Who can trigger:**
  - On issue and PR events, the actor needs write access (`allowed_non_write_users` with your own `github_token` overrides this).
  - Bot actors are rejected unless listed in `allowed_bots`. This applies to scheduled runs too.
- **Key inputs:** `prompt`, `claude_args` (CLI flags), `anthropic_api_key` or `claude_code_oauth_token` (from `claude setup-token`), `github_token`, `settings`, `plugins`, `trigger_phrase`, `use_bedrock` / `use_vertex` / `use_foundry`.

### 1.4 `/batch` and dynamic workflows, for when you're at the keyboard [doc]

**`/batch <instruction>`** researches the codebase and decomposes the work into 5–30 independent units, then presents a plan. Once you approve, it spawns one background subagent per unit in an isolated worktree, and each "implements its unit, runs tests, and publishes its change". It requires git, or a `WorktreeCreate` hook.

**Dynamic workflows** go beyond that: Claude writes a JavaScript orchestration script, and the runtime executes it in the background ("dozens to hundreds of agents per run", resumable in the same session). Pick by who should own the plan:
- You and Claude, interactively: `/batch`.
- A rerunnable script: a workflow.
- Your CI: headless.

---

## 2. Practice

### 2.1 A Java fleet migration, three ways

Goal: every service moves from `RestTemplate` to `RestClient` with connect and read timeouts from `HttpClientsConfig`, with tests green.

```text
[interactive, one repo]
/batch migrate every RestTemplate usage under */src/main/java to RestClient built from HttpClientsConfig
(connect 300 ms, read 2 s); each unit must pass ./mvnw -q -pl <module> verify

[background, check later]
claude --bg "Migrate payment-service from RestTemplate to RestClient per docs/specs/http-clients.md; run ./mvnw -q -pl payment-service verify"
claude agents          # watch, attach, or stop

[CI, many repos or modules, auditable]
CLAUDE_BIN="claude --bare" python headless_batch.py units.json report.json
```

`units.json`:

```json
[
  {"id": "billing", "prompt": "Migrate billing-service from RestTemplate to RestClient per docs/specs/http-clients.md. Run ./mvnw -q -pl billing-service verify. Report per the JSON schema.", "max_turns": 40, "max_budget_usd": 3},
  {"id": "catalog", "prompt": "Migrate catalog-service ... (same)"}
]
```

### 2.2 The two workflows (both pass schema plus policy, L2)

`.github/workflows/claude.yml`: interactive `@claude`, least privilege, turn cap.

```yaml
name: Claude Code
on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
jobs:
  claude:
    if: contains(github.event.comment.body, '@claude')
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
      id-token: write
      actions: read
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 1
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          claude_args: "--max-turns 30 --model opus"
```

`.github/workflows/nightly-migration.yml`: automation mode running a repository skill.

```yaml
name: Nightly dependency migration
on:
  schedule:
    - cron: "0 2 * * 1-5"
  workflow_dispatch:
permissions:
  contents: write
  pull-requests: write
  id-token: write
jobs:
  migrate:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: "21"
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: "/bump-deps order-service"
          claude_args: "--max-turns 40 --allowedTools Read,Edit,Bash(./mvnw *),Bash(git *)"
```

The PR-review workflow from the docs installs the official `code-review` plugin and runs `/code-review:code-review --comment <repo>/pull/<n>` on `pull_request` events [doc].

### 2.3 A local cron alternative

For polling during a session: `/loop 10m check whether the order-service deploy finished and summarise errors from its logs`. For recurring cloud jobs: `/schedule` [doc].

---

## 3. Verified listings

### L1 · `headless_batch.py`, `fake_claude.py`, `test_headless_batch.py`

**What it shows.** A batch driver that builds, per unit, a guarded `claude -p` invocation:
- `--output-format json`
- `--json-schema` (status / tests / summary)
- `--max-turns`, `--max-budget-usd`
- `--permission-mode dontAsk` plus an allowlist
- `--worktree <id>`

It runs units with bounded concurrency and a timeout, retries a 529 "overloaded" once, and classifies each outcome. The test double asserts that the runner passes the guard rails, then emits the documented result shapes. Seven units produce seven distinct, correct classifications:
- DONE
- FAILED (tests failing despite "done")
- NO_RESULT (no `structured_output`)
- BLOCKED (with `permission_denials` = Bash)
- DONE after one retry
- ERROR (invalid API key, not retried)
- TIMEOUT

Spend sums to $1.75.

**What it does not show.** Real model behaviour. Run it against the real CLI on a scratch repository first: it spends tokens.

```python
"""headless_batch.py - drive `claude -p` over a list of work units (modules to migrate, flaky tests to fix)
with the guard rails a CI job needs: one worktree per unit, structured output validated by --json-schema,
hard limits (--max-turns, --max-budget-usd, a wall-clock timeout), a locked-down permission set
(dontAsk + an allowlist), one retry for transient API errors, bounded concurrency, and a JSON report.

Uses only documented print-mode behaviour: exit code 0 on success; with --output-format json the result has
`type`/`subtype`, `result`, `session_id`, `total_cost_usd`, `permission_denials`, and `structured_output` -
which is ABSENT when the run ends without valid structured output, so it must be checked before use.

Usage: CLAUDE_BIN=claude python headless_batch.py units.json report.json
"""
import json
import os
import shlex
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

RESULT_SCHEMA = {
    "type": "object",
    "properties": {
        "status": {"type": "string", "enum": ["done", "blocked", "failed"]},
        "files_changed": {"type": "integer"},
        "tests": {"type": "string", "enum": ["passed", "failed", "not_run"]},
        "summary": {"type": "string"},
    },
    "required": ["status", "tests", "summary"],
}
TRANSIENT = ("overloaded", "rate limit", "529", "timed out connecting")


def command(unit, claude_bin):
    return claude_bin + [
        "-p", unit["prompt"],
        "--output-format", "json",
        "--json-schema", json.dumps(RESULT_SCHEMA, separators=(",", ":")),
        "--max-turns", str(unit.get("max_turns", 40)),
        "--max-budget-usd", str(unit.get("max_budget_usd", 3)),
        "--permission-mode", "dontAsk",
        "--allowedTools", unit.get("allowed_tools", "Read,Edit,Write,Glob,Grep,Bash(./mvnw *),Bash(git diff *)"),
        "--worktree", unit["id"],
    ]


def run_unit(unit, claude_bin, timeout_s):
    attempts, last = 0, None
    while attempts < 2:
        attempts += 1
        try:
            p = subprocess.run(command(unit, claude_bin), capture_output=True, text=True, timeout=timeout_s)
        except subprocess.TimeoutExpired:
            return dict(id=unit["id"], status="TIMEOUT", attempts=attempts, cost=0.0, detail=f"exceeded {timeout_s}s")
        if p.returncode != 0:
            last = (p.stderr or p.stdout).strip().splitlines()[-1] if (p.stderr or p.stdout).strip() else "no output"
            if attempts < 2 and any(t in last.lower() for t in TRANSIENT):
                continue
            return dict(id=unit["id"], status="ERROR", attempts=attempts, cost=0.0, detail=f"exit {p.returncode}: {last}")
        try:
            out = json.loads(p.stdout)
        except json.JSONDecodeError:
            return dict(id=unit["id"], status="ERROR", attempts=attempts, cost=0.0, detail="stdout is not JSON")
        cost = float(out.get("total_cost_usd", 0.0))
        denials = out.get("permission_denials") or []
        so = out.get("structured_output")
        if out.get("subtype") != "success" or so is None:
            return dict(id=unit["id"], status="NO_RESULT", attempts=attempts, cost=cost, session=out.get("session_id"),
                        detail="no structured_output (declined or did not finish)")
        status = {"done": "DONE", "blocked": "BLOCKED", "failed": "FAILED"}[so["status"]]
        if status == "DONE" and so["tests"] != "passed":
            status = "FAILED"
        return dict(id=unit["id"], status=status, attempts=attempts, cost=cost, session=out.get("session_id"),
                    denials=[d.get("tool_name") for d in denials], detail=so["summary"])
    return dict(id=unit["id"], status="ERROR", attempts=attempts, cost=0.0, detail=last)


def run_batch(units, claude_bin, max_workers=2, timeout_s=1800):
    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        results = list(pool.map(lambda u: run_unit(u, claude_bin, timeout_s), units))
    return sorted(results, key=lambda r: r["id"])


if __name__ == "__main__":
    units = json.load(open(sys.argv[1], encoding="utf-8"))
    results = run_batch(units, shlex.split(os.environ.get("CLAUDE_BIN", "claude")))
    json.dump(results, open(sys.argv[2], "w", encoding="utf-8"), indent=2)
    bad = [r for r in results if r["status"] != "DONE"]
    print(f"{len(results) - len(bad)}/{len(results)} units done; ${sum(r['cost'] for r in results):.2f}")
    sys.exit(1 if bad else 0)
```

```python
"""fake_claude.py - a test double for `claude -p ... --output-format json` that emits the documented result
shapes, so headless_batch.py can be tested without spending tokens. Behaviour is chosen by a marker in the
prompt: [ok] [nostruct] [fail] [flaky] [denied] [slow] [testsfail]. State for [flaky] lives in FAKE_STATE_DIR.
"""
import json
import os
import pathlib
import sys
import time

args = sys.argv[1:]
prompt = args[args.index("-p") + 1]
unit = args[args.index("--worktree") + 1]
assert "--json-schema" in args and "--max-turns" in args and "dontAsk" in args, "runner must pass the guard rails"
base = {"type": "result", "subtype": "success", "session_id": f"sess-{unit}", "result": "done",
        "total_cost_usd": 0.42, "permission_denials": []}


def emit(obj):
    print(json.dumps(obj))
    sys.exit(0)


if "[ok]" in prompt:
    emit(dict(base, structured_output={"status": "done", "files_changed": 3, "tests": "passed",
                                       "summary": f"{unit}: migrated to RestClient; 41 tests pass"}))
if "[testsfail]" in prompt:
    emit(dict(base, total_cost_usd=0.77, structured_output={"status": "done", "files_changed": 5, "tests": "failed",
                                                            "summary": f"{unit}: OutboxIT still failing"}))
if "[nostruct]" in prompt:
    emit(dict(base, total_cost_usd=0.05))
if "[denied]" in prompt:
    emit(dict(base, total_cost_usd=0.11, permission_denials=[{"tool_name": "Bash", "tool_input": {"command": "rm -rf build"}}],
              structured_output={"status": "blocked", "tests": "not_run", "summary": f"{unit}: needs rm, denied"}))
if "[flaky]" in prompt:
    marker = pathlib.Path(os.environ["FAKE_STATE_DIR"], f"{unit}.seen")
    if not marker.exists():
        marker.write_text("1")
        print("API Error: 529 overloaded_error", file=sys.stderr)
        sys.exit(1)
    emit(dict(base, total_cost_usd=0.40, structured_output={"status": "done", "files_changed": 2, "tests": "passed",
                                                            "summary": f"{unit}: fixed after retry"}))
if "[slow]" in prompt:
    time.sleep(5)
print("Error: Invalid API key", file=sys.stderr)
sys.exit(1)
```

```python
"""test_headless_batch.py - run headless_batch against fake_claude.py and assert every outcome is classified
correctly: success, tests failing despite "done", missing structured_output, a permission denial, a transient
529 retried once, a hard failure, and a timeout. Costs and statuses must add up.

Run: python test_headless_batch.py   (stdlib only; prints ALL ASSERTIONS PASSED)
"""
import os
import pathlib
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from headless_batch import command, run_batch  # noqa: E402

FAKE = [sys.executable, str(pathlib.Path(__file__).parent / "fake_claude.py")]
UNITS = [
    {"id": "billing", "prompt": "[ok] Migrate billing-service from RestTemplate to RestClient with timeouts."},
    {"id": "catalog", "prompt": "[testsfail] Migrate catalog-service."},
    {"id": "gateway", "prompt": "[nostruct] Migrate gateway."},
    {"id": "inventory", "prompt": "[denied] Clean the build directory and migrate."},
    {"id": "orders", "prompt": "[flaky] Migrate order-service."},
    {"id": "payments", "prompt": "[fail] Migrate payment-service."},
    {"id": "search", "prompt": "[slow] Migrate search-service."},
]

with tempfile.TemporaryDirectory() as state:
    os.environ["FAKE_STATE_DIR"] = state
    argv = command(UNITS[0], ["claude"])
    print("argv for one unit:", " ".join(a if " " not in a else repr(a) for a in argv[:3]), "...",
          " ".join(argv[5:]).replace(argv[6], "<schema>"))
    results = run_batch(UNITS, FAKE, max_workers=2, timeout_s=2)

print(f"{'unit':<10} {'status':<10} {'tries':>5} {'cost':>6}  detail")
for r in results:
    print(f"{r['id']:<10} {r['status']:<10} {r['attempts']:>5} {r['cost']:>6.2f}  {r['detail']}"
          + (f"  denials={r['denials']}" if r.get("denials") else ""))
by = {r["id"]: r for r in results}
expected = {"billing": "DONE", "catalog": "FAILED", "gateway": "NO_RESULT", "inventory": "BLOCKED",
            "orders": "DONE", "payments": "ERROR", "search": "TIMEOUT"}
assert {k: v["status"] for k, v in by.items()} == expected, by
assert by["orders"]["attempts"] == 2 and by["payments"]["attempts"] == 1, "retry only transient errors"
assert by["inventory"]["denials"] == ["Bash"]
total = sum(r["cost"] for r in results)
print(f"done {sum(r['status'] == 'DONE' for r in results)}/{len(results)}; spend ${total:.2f}; the job exits non-zero")
assert abs(total - (0.42 + 0.77 + 0.05 + 0.11 + 0.40)) < 1e-9
print("ALL ASSERTIONS PASSED")
```

**Output (verified):**

```text
argv for one unit: claude -p '[ok] Migrate billing-service from RestTemplate to RestClient with timeouts.' ... --json-schema <schema> --max-turns 40 --max-budget-usd 3 --permission-mode dontAsk --allowedTools Read,Edit,Write,Glob,Grep,Bash(./mvnw *),Bash(git diff *) --worktree billing
unit       status     tries   cost  detail
billing    DONE           1   0.42  billing: migrated to RestClient; 41 tests pass
catalog    FAILED         1   0.77  catalog: OutboxIT still failing
gateway    NO_RESULT      1   0.05  no structured_output (declined or did not finish)
inventory  BLOCKED        1   0.11  inventory: needs rm, denied  denials=['Bash']
orders     DONE           2   0.40  orders: fixed after retry
payments   ERROR          1   0.00  exit 1: Error: Invalid API key
search     TIMEOUT        1   0.00  exceeded 2s
done 2/7; spend $1.75; the job exits non-zero
ALL ASSERTIONS PASSED
```

### L2 · `ci_workflow_check.py`

**What it shows.** GitHub workflows validated against the official schemastore schema, plus eight policy checks (WF01–WF08):
- the "pwn request" (`pull_request_target` plus checking out the head)
- unpinned action refs
- inlined API keys
- `--dangerously-skip-permissions`
- no `--max-turns`
- no `if:` guard on interactive triggers
- no permissions block

Both production workflows are clean, and the BAD one trips all eight. Its schema error names the exact field (`timeout-minutes: 'forever'`).

**What it does not show.** Organisation-level controls such as required reviewers, environment protection and OIDC trust policies.

Run: `pip install pyyaml jsonschema`, download the schema, then `GITHUB_WORKFLOW_SCHEMA=github-workflow.json python ci_workflow_check.py`.

```python
"""ci_workflow_check.py - validate Claude Code GitHub Actions workflows against the official workflow JSON schema
(https://json.schemastore.org/github-workflow.json) and against the security and cost policy a staff engineer
would enforce in review:

  WF01 schema violation                       WF05 claude_args with --dangerously-skip-permissions
  WF02 claude-code-action not pinned to a      WF06 claude_args without --max-turns (no turn cap)
       release tag (@v1) or a commit SHA       WF07 interactive (@claude) workflow without an `if:`
  WF03 pull_request_target + checkout of the        guard (every comment starts a runner)
       PR head: untrusted code runs with       WF08 workflow without a top-level or job-level
       secrets ("pwn request")                      `permissions` block (defaults can be broad)
  WF04 API key inlined instead of ${{ secrets.* }}

Needs pyyaml + jsonschema and GITHUB_WORKFLOW_SCHEMA=<path to the schemastore file>.
Run: python ci_workflow_check.py   (prints ALL ASSERTIONS PASSED)
"""
import json
import os
import pathlib
import re

import yaml
from jsonschema import Draft7Validator
from jsonschema.exceptions import best_match

VALIDATOR = Draft7Validator(json.loads(pathlib.Path(os.environ["GITHUB_WORKFLOW_SCHEMA"]).read_text(encoding="utf-8")))
ACTION = "anthropics/claude-code-action"


def load(text):
    doc = yaml.safe_load(text)
    if True in doc:                      # YAML 1.1 reads the key `on` as boolean true
        doc["on"] = doc.pop(True)
    return doc


def check(text):
    doc, f = load(text), []
    for e in VALIDATOR.iter_errors(doc):
        # anyOf/oneOf (normal job vs reusable-workflow job): report the deepest sub-error, the concrete field at fault
        leaf = max(e.context, key=lambda x: (len(x.absolute_path), x is best_match(e.context))) if e.context else e
        f.append(("WF01", f"{'/'.join(map(str, leaf.absolute_path)) or '(root)'}: {leaf.message[:100]}"))
    triggers = doc.get("on") if isinstance(doc.get("on"), dict) else {k: None for k in ([doc.get("on")] if isinstance(doc.get("on"), str) else doc.get("on") or [])}
    interactive = any(t in triggers for t in ("issue_comment", "pull_request_review_comment", "pull_request_review"))
    if "permissions" not in doc and not all("permissions" in j for j in doc.get("jobs", {}).values()):
        f.append(("WF08", "no permissions block - set least-privilege permissions per job"))
    for jname, job in doc.get("jobs", {}).items():
        steps = job.get("steps", [])
        checks_out_head = any("actions/checkout" in str(s.get("uses", "")) and
                              re.search(r"pull_request\.head\.(sha|ref)|github\.head_ref", json.dumps(s.get("with", {})))
                              for s in steps)
        if "pull_request_target" in triggers and checks_out_head:
            f.append(("WF03", f"job {jname}: pull_request_target checks out the PR head - untrusted code runs with secrets"))
        for s in steps:
            uses = str(s.get("uses", ""))
            if uses.startswith(ACTION):
                ref = uses.split("@", 1)[1] if "@" in uses else ""
                if not re.fullmatch(r"v\d+(\.\d+)*|[0-9a-f]{40}", ref):
                    f.append(("WF02", f"job {jname}: {uses} - pin to a release tag or a commit SHA"))
                w = s.get("with", {})
                key = str(w.get("anthropic_api_key", ""))
                if key and not key.startswith("${{ secrets."):
                    f.append(("WF04", f"job {jname}: anthropic_api_key is not a secrets reference"))
                args = str(w.get("claude_args", ""))
                if "--dangerously-skip-permissions" in args:
                    f.append(("WF05", f"job {jname}: --dangerously-skip-permissions on a shared runner"))
                if "--max-turns" not in args:
                    f.append(("WF06", f"job {jname}: no --max-turns in claude_args - no cap on a runaway run"))
        if interactive and "if" not in job:
            f.append(("WF07", f"job {jname}: no `if:` guard - every comment on every issue starts a runner"))
    return f


CLAUDE_YML = """
name: Claude Code
on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
jobs:
  claude:
    if: contains(github.event.comment.body, '@claude')
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
      id-token: write
      actions: read
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 1
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          claude_args: "--max-turns 30 --model opus"
"""

NIGHTLY_YML = """
name: Nightly dependency migration
on:
  schedule:
    - cron: "0 2 * * 1-5"
  workflow_dispatch:
permissions:
  contents: write
  pull-requests: write
  id-token: write
jobs:
  migrate:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: "21"
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: "/bump-deps order-service"
          claude_args: "--max-turns 40 --allowedTools Read,Edit,Bash(./mvnw *),Bash(git *)"
"""

BAD_YML = """
name: Claude on every PR
on:
  pull_request_target:
  issue_comment:
    types: [created]
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          ref: ${{ github.event.pull_request.head.sha }}
      - uses: anthropics/claude-code-action@main
        with:
          anthropic_api_key: sk-ant-api03-example
          claude_args: "--dangerously-skip-permissions"
    timeout-minutes: "forever"
"""

for label, text, expected in [(".github/workflows/claude.yml", CLAUDE_YML, set()),
                              (".github/workflows/nightly-migration.yml", NIGHTLY_YML, set()),
                              ("BAD workflow", BAD_YML, {f"WF0{i}" for i in range(1, 9)})]:
    found = check(text)
    codes = {c for c, _ in found}
    print(f"--- {label}: {sorted(codes) or 'clean (schema + policy)'}")
    for c, m in found:
        print(f"  {c} {m}")
    assert codes == expected, (label, sorted(codes))
print("ALL ASSERTIONS PASSED")
```

**Output (verified):**

```text
--- .github/workflows/claude.yml: clean (schema + policy)
--- .github/workflows/nightly-migration.yml: clean (schema + policy)
--- BAD workflow: ['WF01', 'WF02', 'WF03', 'WF04', 'WF05', 'WF06', 'WF07', 'WF08']
  WF01 jobs/review/timeout-minutes: 'forever' is not valid under any of the given schemas
  WF08 no permissions block - set least-privilege permissions per job
  WF03 job review: pull_request_target checks out the PR head - untrusted code runs with secrets
  WF02 job review: anthropics/claude-code-action@main - pin to a release tag or a commit SHA
  WF04 job review: anthropic_api_key is not a secrets reference
  WF05 job review: --dangerously-skip-permissions on a shared runner
  WF06 job review: no --max-turns in claude_args - no cap on a runaway run
  WF07 job review: no `if:` guard - every comment on every issue starts a runner
ALL ASSERTIONS PASSED
```

---

## 4. Failure modes

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| F1 | CI job green, nothing changed | Run declined or stopped; script read `.result` text | Require `structured_output` and exit 0; check `permission_denials` |
| F2 | Nightly bill spike | No turn or budget cap; retries on deterministic failures | `--max-turns`, `--max-budget-usd`, retry transient errors only |
| F3 | Fork PR's hooks ran in CI | `-p` loads project hooks and `.mcp.json` without trust | `--bare`; treat `.claude/` as CI config |
| F4 | Secrets exfiltrated | `pull_request_target` checked out PR code | Never combine the two; separate trusted and untrusted jobs |
| F5 | Agent loop | A bot comment triggered Claude again | The action rejects bots by default; keep `allowed_bots` empty |
| F6 | Disk full on runners | `-p --worktree` runs never cleaned | Clean up in the job (Folder 03 L2) |
| F7 | Units collide on files | Same checkout | `--worktree <unit>` per unit |
| F8 | `--json-schema` error at start | Invalid schema | Validate the schema in unit tests; `claude` reports the validator's diagnostic |
| F9 | Run hangs forever | No wall-clock timeout | Runner timeout plus job `timeout-minutes` (SIGTERM → 143) |

---

## 5. Staff-level drills

<details><summary><b>D1 · "Our CI agent reported success but the PR is empty."</b></summary>

**Staff answer.** A `-p` run can finish "successfully" without doing the work. Claude may have declined, been denied the tools it needed, or hit `--max-turns`.
- Ask for `--json-schema` structured output and treat a missing `structured_output` as failure.
- Read `permission_denials`.
- Make the schema include a `tests` field, and refuse "done" without "passed".

L1 classifies these as NO_RESULT, BLOCKED and FAILED instead of DONE.
</details>

<details><summary><b>D2 · "Why --bare? Our hooks and CLAUDE.md make Claude better."</b></summary>

**Staff answer.** In CI, reproducibility and safety come first. Without `--bare`, `-p` loads whatever `.claude/settings.json`, hooks, `.mcp.json` and the user-level `~/.claude` on the runner say, "even in a folder you've never trusted", with no dialog [doc]. For trusted, first-party jobs you can deliberately load project settings, using `--setting-sources project` and reviewing `.claude/` changes as CI config. For anything touching external contributions, use `--bare` and pass exactly what the job needs via `--settings`, `--mcp-config` and `--append-system-prompt-file`.
</details>

<details><summary><b>D3 · "dontAsk or auto for unattended runs?"</b></summary>

**Staff answer.**
- **`dontAsk`** plus an explicit `--allowedTools` allowlist gives the narrowest, most predictable behaviour: everything not allowed is denied. Use it when you can enumerate the commands (Maven, git diff/commit).
- **`auto` with `--permission-prompts none`** lets a classifier approve a broader set and denies whatever would have prompted. Use it for open-ended tasks where an allowlist would be impractical, and pair it with deny rules for the dangerous commands.

Either way, log `permission_denials`.
</details>

<details><summary><b>D4 · "How many units in parallel?"</b></summary>

**Staff answer.** Use the minimum of three limits:
- **Runner capacity.** Each unit runs a JVM build plus the agent.
- **API rate limits.** Requests per minute and tokens per minute for your tier and model.
- **Cache economics.** Parallel units with a shared prefix each write their own cache (Folder 01 file 03); stagger starts if they share a big prefix.

Start at 2–4, measure wall-clock time and cost per unit, then raise. L1 defaults to 2.
</details>

---

## 6. Checklist

- [ ] Every CI invocation has `--output-format json`, `--json-schema`, `--max-turns`, `--max-budget-usd`, a runner timeout, and a locked-down permission mode.
- [ ] Success requires exit 0, `structured_output` present, tests passed, and no unexpected `permission_denials`.
- [ ] CI uses `--bare` (or explicitly reviewed setting sources).
- [ ] Workflows pass L2 (schema plus policy); no `pull_request_target` plus head checkout.
- [ ] Headless worktrees are cleaned up; cost per unit is reported.

---

## 7. References

- Run Claude Code programmatically (print mode, output formats, json-schema, bare mode, permissions): <https://code.claude.com/docs/en/headless>
- CLI reference: <https://code.claude.com/docs/en/cli-reference>
- Claude Code GitHub Actions: <https://code.claude.com/docs/en/github-actions>
- GitLab CI/CD: <https://code.claude.com/docs/en/gitlab-ci-cd>
- Dynamic workflows: <https://code.claude.com/docs/en/workflows>
- Run prompts on a schedule (`/loop`): <https://code.claude.com/docs/en/scheduled-tasks>
- Cloud scheduled tasks (`/schedule`): <https://code.claude.com/docs/en/routines>
- Permission modes: <https://code.claude.com/docs/en/permission-modes>
- GitHub workflow JSON schema: <https://json.schemastore.org/github-workflow.json>
- GitHub Security Lab, "Keeping your GitHub Actions and workflows secure: Preventing pwn requests": <https://securitylab.github.com/resources/github-actions-preventing-pwn-requests/>

Previous: [02 · Subagents](02-building-isolated-subagents-architect-security-auditor-and-test-runner.md) · [01 · Skills](01-designing-reusable-skills-and-custom-slash-commands-with-frontmatter.md) · [KB README](../README.md)

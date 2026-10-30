# MCP Client Configuration: stdio vs SSE vs HTTP, and Preventing Tool-Schema Bloat

> **Folder 06 · File 1 of 3** · verified 2026-10-30 against code.claude.com `mcp.md` (the 1,900-line MCP reference), `permissions.md` and `settings.md`; Anthropic engineering "advanced tool use"; pricing as in Folder 01
> **Listings:** `mcp_config_lint.py` (12 rules for `.mcp.json` / `~/.claude.json`), `mcp_token_tax.py` (the token tax priced per session, tool search off vs on)

---

## 0. Orientation

The Model Context Protocol (MCP) is how Claude Code reaches anything outside your working tree: GitHub, a database, your docs, a build server, your own team's knowledge. Claude Code is the **client**. Each configured **server** contributes three kinds of primitive:
- **tools**, which the model calls;
- **resources**, which you @-mention;
- **prompts**, which become slash commands.

This file covers the client side: transports, scopes, environment expansion, approval, output and time limits, and the cost of tool definitions in context. File 02 covers which servers a backend team should run and how to lock them down. File 03 builds a custom server three ways: Python, the plain MCP Java SDK, and Spring AI.

**What changed since the brief was written.** The brief's "MCP token tax" is that every server's tool schemas sit in context on every turn: 10 servers × 20 tools ≈ 30K tokens. That is still true *when tools load upfront*. But Claude Code now defers MCP tools by default ("tool search"): only tool names and server instructions load at session start [doc].

So the tax no longer comes from having many servers. It comes from three things:
- the configurations that switch deferral off;
- server instructions and tool descriptions that are long or vague;
- tool *outputs* that are too large.

L2 prices the tax both ways. When it does apply, it is much larger than the brief's estimate.

### 0.1 The twelve rules

1. **Transport: `http` for remote servers, `stdio` for local processes.** SSE is deprecated. WebSocket (`ws`) is only for servers that push events unprompted. [doc]
2. **An entry with a `url` but no `type` is a configuration error.** Claude Code reads a missing `type` as stdio and skips the server. [doc + L1 MC01]
3. **Scopes: local (default, private, `~/.claude.json` under the project path), project (`.mcp.json`, checked in), user (`~/.claude.json`, all projects).** Precedence is local > project > user > plugin > claude.ai connectors. The winning entry is used *whole*; fields are never merged. [doc + L1 MC11]
4. **Tool search is on by default:** MCP tool definitions are deferred and loaded on demand. They load upfront only when one of these holds: `ENABLE_TOOL_SEARCH=false`; `auto` mode below its threshold; the server or tool sets `alwaysLoad`; the model is too old; or the deployment is Microsoft Foundry on Azure. [doc]
5. **When tools do load upfront, the tax is bigger than the brief says.** Anthropic's published five-server example is 58 tools ≈ 55K tokens; GitHub's 35 tools ≈ 26K, or about 743 tokens per tool. The brief assumed 150. [research + L2]
6. **Server instructions are your discovery surface under tool search.** They are cut at 4,096 characters (so are upfront tool descriptions; deferred descriptions are cut at 16,384). Put the keywords Claude would search for first. [doc]
7. **`${VAR}` and `${VAR:-default}` expand in `command`, `args`, `env`, `url` and `headers`.**
   - An unset variable with no default stays as literal `${VAR}` text, with a warning, and the server still loads.
   - A variable set to `""` counts as set, so its `:-default` never applies. [doc + L1 MC06]
8. **Covered credentials read as *empty* in a remote server's `url` and `headers`.** These include `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `AWS_BEARER_TOKEN_BEDROCK`, `HTTPS_PROXY` and `NPM_TOKEN`, and a `:-default` doesn't help. Copy the value into a variable with your own name. [doc + L1 MC04]
9. **`CLAUDE_PROJECT_DIR` is set in the *server's* environment, not Claude Code's.** Referencing it in `.mcp.json` `command`/`args` needs `${CLAUDE_PROJECT_DIR:-.}`. [doc + L1 MC05]
10. **Interactive sessions ask before using `.mcp.json` servers; `claude -p`, the Agent SDK and cloud sessions load them *without asking*.** In automation on untrusted repos, use `disabledMcpjsonServers`, `--setting-sources`, or `--strict-mcp-config` with `--mcp-config`. [doc]
11. **Output limits: a warning at 10,000 tokens, a default cap of 25,000 (`MAX_MCP_OUTPUT_TOKENS`).** A text result longer than 50,000 characters is saved to a file. A server can declare `_meta["anthropic/maxResultSizeChars"]` per tool. [doc]
12. **Lint MCP config in CI like any other code** (L1): pinned launchers, no literal secrets, read-only database roles, no reserved names. A `.mcp.json` is an executable supply chain that every teammate runs.

---

## 1. First principles

### 1.1 The three primitives, as Claude Code exposes them [doc]

| Primitive | Who triggers it | How it appears in Claude Code | Permission-rule name |
|---|---|---|---|
| Tool | the model | `mcp__<server>__<tool>` (`.` or spaces in a server name become `_`) | `mcp__github`, `mcp__github__*`, `mcp__github__get_issue` |
| Resource | you | `@server:protocol://path`, e.g. `@github:issue://123` | — |
| Prompt | you | `/mcp__<server>__<prompt> args` (listed as `/server:prompt (MCP)`) | — |

Two consequences for design:
- **Tools are the only primitive the model chooses.** Each one's name, description and schema are prompt text that competes for attention like any other prompt text (Folder 01).
- **Resources and prompts cost nothing until you invoke them.** Read-mostly reference material, such as a schema dump or a runbook, is often better exposed as a resource you @-mention than as a tool the model may or may not call.

### 1.2 Transports [doc]

| | `stdio` | `http` (streamable HTTP; `streamable-http` is an alias) | `sse` | `ws` |
|---|---|---|---|---|
| Runs | a child process Claude Code spawns | a remote endpoint | a remote endpoint | a remote endpoint |
| Status | current | **recommended for remote** | **deprecated** | current, niche |
| Auth | process env (`--env KEY=value`) | OAuth (`/mcp` sign-in), `headers`, `headersHelper` | headers / OAuth | headers / `headersHelper` only, no OAuth |
| Add with | `claude mcp add [opts] name -- cmd args` | `claude mcp add --transport http name url` | `--transport sse` | `claude mcp add-json` only |
| Shutdown | Windows: stdin closed, process tree killed 300 ms later. macOS/Linux: SIGINT → SIGTERM after 100 ms → SIGKILL after a further 400 ms | connection closed | — | — |

The `--` in `claude mcp add` matters: everything after it goes to the server untouched. Without it, the server's `--port` would be parsed as Claude Code's own flag.

The shutdown row is a contract your server must meet. File 03's conformance client checks that each server exits within 300 ms of stdin EOF. All three implementations do.

### 1.3 Scopes, storage and precedence [doc]

| Scope | Loads in | Shared | Stored in | Use for |
|---|---|---|---|---|
| local (default) | this project | no | `~/.claude.json`, under the project's path | personal or experimental servers, your own credentials |
| project | this project | **yes** (VCS) | `.mcp.json` at the repo root | the team's standard servers, with `${VAR}` placeholders for secrets |
| user | all your projects | no | `~/.claude.json`, top level | personal cross-project tools (a docs server, your notes) |

Above all three sits `managedMcpServers` (organization policy). Below them sit plugin servers and claude.ai connectors, which are matched by *endpoint*: two URLs that differ only in scheme/host case, a default port or a trailing slash count as the same server.

Duplicates across the three scopes are matched by *name*, and the highest scope's entry wins whole. A local `github` entry with no `headers` silently replaces a project `github` entry that had them [doc]. OAuth sign-ins are stored per endpoint, so the same name pointing at two endpoints needs two sign-ins (L1 MC11).

### 1.4 Why tool definitions are a caching problem, not just a context problem [doc + inference]

Folder 01's cache-prefix order is tools → system → messages. Tools that load upfront sit at the **very front** of every request. So:
- every request re-reads them, at the cache-read price if the cache is warm;
- **any change to the tool list invalidates the entire cached conversation behind it**: a server reconnecting with a different `tools/list`, a `notifications/tools/list_changed`, or adding a server mid-session. The next request re-writes the whole context at the write price.

With tool search, deferred definitions are not in that prefix. Requests carry `defer_loading` tool fields, and discovered tools come back as `tool_reference` blocks [doc: gateway section]. When a server finishes connecting mid-turn, Claude Code lists its tool *names* on the next request [doc]. A late server therefore adds a small block instead of rewriting the prefix [inference from the documented mechanism; measure with `/context` and your usage logs].

L2 models both effects. Two prefix busts per session cost more than the 150 cache reads of a 30K-token tool block, because the bust re-writes the 60K-token conversation behind the tools too.

### 1.5 Tool search: the switches [doc]

| `ENABLE_TOOL_SEARCH` | Behaviour |
|---|---|
| unset / `true` | All MCP tools deferred, loaded on demand. Upfront on models older than Opus 4/Sonnet 4, on older Google Cloud Agent Platform models, and on Microsoft Foundry on Azure (which rejects it server-side) |
| `auto` | Upfront while the definitions total under 10% of the context window; tool search once they reach 10% |
| `auto:N` | The same with an N% threshold (`auto:5`) |
| `false` | Everything upfront |

The other levers:
- **Per server:** `"alwaysLoad": true` loads that server's tools upfront regardless of tool search. It also makes startup wait for them, capped at the 5-second connect timeout. `"alwaysLoad": false` defers even the tools whose author marked them upfront (v2.1.287+).
- **Per tool (server author):** `_meta: {"anthropic/alwaysLoad": true}`. The user's server-level setting overrides it.
- `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` keeps tool search off and can't be overridden by `ENABLE_TOOL_SEARCH`.
- Denying `ToolSearch`, or leaving it out of `--tools`, loads MCP tools upfront.
- Through an LLM gateway (`ANTHROPIC_BASE_URL`), tool search stays on and the gateway must forward `defer_loading` and `tool_reference` (v2.1.305+ retries without it on an unrecognised 400/422).

Two consequences that are easy to miss:
- **With tool search on, Claude Code tells Claude which configured servers failed to connect.** Without it, a dead server is silently absent. So tool search also makes failures visible.
- **Under `auto`, a fleet below 10% of a 1M window (under 100K tokens) loads upfront.** That covers both of L2's first two fleets. `auto` is a context-share policy, not a cost policy.

### 1.6 Where tool search does not save you [doc + inference]

Tool search defers *definitions*. It does nothing about:
1. **Server instructions.** They always load, and Claude matches against them to decide when to search. Vague instructions mean missed tools; 4,000-character instructions are an upfront tax of their own.
2. **Tool outputs.** A 20K-token `SELECT *` result lands in the conversation and stays there until compaction. That is why rule 11 exists, and why file 02's database guidance caps rows.
3. **Selection quality among loaded tools.** Anthropic reports that the Tool Search Tool raised MCP-eval accuracy from 49% to 74% on Opus 4 and from 79.5% to 88.1% on Opus 4.5 [research]. That is a large gain, and it says definitions crowding the context hurt accuracy, not only cost.
4. **Tools you force upfront** with `alwaysLoad`. Reserve it for the one or two tools used on nearly every turn.

### 1.7 Environment expansion [doc]

| Form | Unset | Set to `""` | Set |
|---|---|---|---|
| `${VAR}` | warning; the literal text `${VAR}` is used and the server still loads | `""` | value |
| `${VAR:-default}` | `default` | **`""`** (empty counts as set) | value |

Expansion applies to `command`, `args`, `env`, `url` and `headers`.

In a remote server's `url` and `headers`, covered credential variables always read as empty, whatever their value or default. This stops a malicious `.mcp.json` from shipping your `ANTHROPIC_API_KEY` to a server it names. `ANTHROPIC_BASE_URL` still expands unless it embeds userinfo. A `headersHelper` from a repo or plugin runs with credential-looking variables (`TOKEN`, `SECRET`, `PASSWORD`, `KEY`, `AUTH`) stripped.

Claude Code also warns about **hidden whitespace** in `command`, `url`, `args` and the keys and values of `env`/`headers`: typically a pasted token with a trailing newline (L1 MC08). It warns about **reserved names** too (`workspace`, `claude-in-chrome`, `computer-use`, `Claude Preview`, `Claude Browser`), which it skips at load time (L1 MC09).

### 1.8 Time and size limits [doc]

| Limit | Default | Control |
|---|---|---|
| Server startup | — | `MCP_TIMEOUT` (ms), e.g. `MCP_TIMEOUT=10000` |
| Tool call wall clock | about 28 h | `MCP_TOOL_TIMEOUT` (ms). Per server: `"timeout": 600000`; values under 1000 ignored; progress notifications do **not** extend it |
| Tool call idle (no response, no progress) | 5 min for HTTP/SSE/WebSocket/connectors; 30 min for stdio | `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT` (ms; `0` disables). A per-server `timeout` ≥ 1000 is a floor |
| Output tokens | warn at 10,000, cap 25,000 | `MAX_MCP_OUTPUT_TOKENS`; per tool `_meta["anthropic/maxResultSizeChars"]` for text |
| Output characters | a result over 50,000 chars is saved to a file | the same `_meta` key |
| Description and instructions length | 4,096 chars (instructions, upfront descriptions); 16,384 (deferred descriptions) | `CLAUDE_CODE_MAX_MCP_DESCRIPTION_LENGTH` |

The 28-hour default means a stdio tool that keeps sending progress notifications can run for a day, and a silent one still holds the turn for 30 minutes. Set a per-server `timeout` on anything that talks to a database or a build system.

### 1.9 Trust: who approved this server? [doc]

- **Interactive.** `.mcp.json` servers show `⏸ Pending approval` until you approve them in a `claude` session. A cloned repo can't approve its own servers: `enableAllProjectMcpServers` or `enabledMcpjsonServers` committed to its `.claude/settings.json` is ignored until you accept workspace trust. Your user settings, managed settings and `--settings` still apply. `claude mcp reset-project-choices` resets your choices.
- **Headless.** `claude -p`, the Agent SDK, cloud sessions outside a project's threads, and bypass mode with the skip-prompt setting all **load project servers without asking**. A cloned repo's `.mcp.json` therefore *runs* in your CI job. Defend in this order:
  1. `--strict-mcp-config --mcp-config ci-mcp.json` (only the servers you name);
  2. `--setting-sources` without project;
  3. `disabledMcpjsonServers`;
  4. `--bare` (Folder 04).
- **Organization.** `managedMcpServers` provides servers that outrank every scope. `managed-mcp.json` takes exclusive control, and allowlists and denylists show up as `✘ Blocked by enterprise managed policy`.

---

## 2. Practice

### 2.1 Adding servers: the four shapes

```bash
# Remote HTTP with OAuth (sign in via /mcp, or `claude mcp login sentry` for headless prep)
claude mcp add --transport http sentry https://mcp.sentry.dev/mcp

# Remote HTTP with a header; single quotes store the ${VAR} placeholder, expanded from YOUR env at connect time
claude mcp add --transport http github https://api.githubcopilot.com/mcp/readonly \
  --header 'Authorization: Bearer ${GITHUB_MCP_PAT}' --header 'X-MCP-Toolsets: repos,issues,pull_requests,actions'

# Local stdio: everything after -- is the server command, untouched
claude mcp add --transport stdio --scope project order-platform -- python tools/mcp/order_platform_mcp.py

# Raw JSON (the only way to add ws; also the easiest way to port a Claude Desktop entry - pass the inner object)
claude mcp add-json docs '{"type":"http","url":"https://mcp.context7.com/mcp","headers":{"Authorization":"Bearer ${CONTEXT7_API_KEY}"}}'
```

Double quotes would let *your shell* expand `${GITHUB_MCP_PAT}` before Claude Code sees it, and the literal token would be stored in the config. Single quotes, or editing `.mcp.json` directly, keep the placeholder [inference from shell semantics].

Then check what you made:
- `claude mcp list` shows status and warnings (missing variables, whitespace, conflicts);
- `claude mcp get <name>` shows one entry with its approval state;
- `/mcp` in-session shows connection state, sign-in and per-tool details.

### 2.2 The team's `.mcp.json` (passes all twelve L1 rules)

```json
{
  "mcpServers": {
    "order-platform": { "type": "stdio", "command": "python",
                        "args": ["${CLAUDE_PROJECT_DIR:-.}/tools/mcp/order_platform_mcp.py"], "timeout": 60000 },
    "github": { "type": "http", "url": "https://api.githubcopilot.com/mcp/readonly",
                "headers": { "Authorization": "Bearer ${GITHUB_MCP_PAT}",
                             "X-MCP-Toolsets": "repos,issues,pull_requests,actions" } },
    "db": { "type": "stdio", "command": "npx", "args": ["-y", "@bytebase/dbhub@1.5.0", "--dsn", "${ORDERS_RO_DSN}"],
            "timeout": 30000 },
    "docs": { "type": "http", "url": "https://mcp.context7.com/mcp",
              "headers": { "Authorization": "Bearer ${CONTEXT7_API_KEY}" } },
    "docker": { "type": "stdio", "command": "docker", "args": ["mcp", "gateway", "run", "--profile", "order-platform"] }
  }
}
```

Every secret is a `${VAR}` with a name of your own. The database DSN points at a read-only role on a replica. Launchers are pinned. No server forces itself upfront. File 02 justifies each entry.

### 2.3 Keep the tax visible

- `/context` shows what occupies the window, including MCP tools, labelled `(deferred)` or `(loaded on-demand)` when tool search is on [doc].
- `/mcp` shows per-server status.
- Under `ENABLE_TOOL_SEARCH=false`, the L2 arithmetic is your monthly bill.
- In CI, run L1 against `.mcp.json` on every change. `python mcp_config_lint.py .mcp.json` exits 1 on any ERROR.

### 2.4 Headless and CI: an explicit server list

```bash
# Only the servers in ci-mcp.json; the repo's .mcp.json is ignored entirely
claude -p "Summarise failing tests from build_health and propose fixes" \
  --strict-mcp-config --mcp-config ci-mcp.json --output-format json
```

---

## 3. Verified listings

### L1 · `mcp_config_lint.py`

**What it shows.** Twelve rules, each traceable to the docs [doc] or to standard supply-chain and least-privilege practice [practice]. It runs against a BAD project + user config (seven servers, every common mistake) and the GOOD team config from §2.2.
- MC01 url without type
- MC02 SSE
- MC03 literal credential in a checked-in file
- MC04 covered credential in a remote header
- MC05 `${CLAUDE_PROJECT_DIR}` without a default
- MC06 unset or empty-with-default variables
- MC07 unpinned `npx`/`uvx`/`docker run`
- MC08 hidden whitespace
- MC09 reserved name
- MC10 non-read-only database role (prod host flagged)
- MC11 the same name in two scopes with different endpoints
- MC12 `alwaysLoad` sprawl

The BAD config triggers all twelve; the GOOD config triggers none.

**What it does not show.** Whether a server is trustworthy. A pinned, well-configured malicious server still passes. Review the server's code or provenance before it enters `.mcp.json` (file 02 §1.1). The covered-credential list is the docs' examples ("such as"), not an exhaustive list.

Run: `python mcp_config_lint.py` (fixtures) or `python mcp_config_lint.py path/to/.mcp.json` (CI; exit 1 on ERROR).

```python
"""mcp_config_lint.py - lint Claude Code MCP configuration (.mcp.json, ~/.claude.json) for the failure modes the Claude Code
docs describe plus the supply-chain and least-privilege ones they imply. Each rule cites its basis: [doc] = stated in the
Claude Code MCP docs (snapshot 2026-10-30), [practice] = security practice. Run on a BAD and a GOOD Java-team config.
Usage as a tool: python mcp_config_lint.py path/to/.mcp.json  (env is read from the real environment).
"""
import json
import os
import re
import sys

RESERVED = {"workspace", "claude-in-chrome", "computer-use", "Claude Preview", "Claude Browser"}               # [doc]
COVERED_CREDENTIALS = {"ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "AWS_BEARER_TOKEN_BEDROCK", "HTTPS_PROXY", "NPM_TOKEN"}
SECRET = re.compile(r"(?i)(bearer\s+(?!\$\{)[A-Za-z0-9._~+/-]{12,}|sk-ant-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}"
                    r"|://[^:/@\s]+:(?!\$\{)[^@\s]+@)")
VAR = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(:-([^}]*))?\}")
DSN = re.compile(r"postgres(?:ql)?://([^:@/\s]+)(?::[^@\s]*)?@([^:/\s]+)")
LAUNCHERS = {"npx": r"@[\w.-]+/[\w.-]+@\d|^(?!@)[\w.-]+@\d", "uvx": r"==\d|@\d", "bunx": r"@\d", "pipx": r"==\d"}


def strings(entry, fields):
    """Yield (field, value) for every string the given fields hold (scalars, lists, dict values and keys)."""
    for f in fields:
        v = entry.get(f)
        if isinstance(v, str):
            yield f, v
        elif isinstance(v, list):
            yield from ((f"{f}[{i}]", x) for i, x in enumerate(v) if isinstance(x, str))
        elif isinstance(v, dict):
            for k, x in v.items():
                yield f"{f} key", k
                if isinstance(x, str):
                    yield f"{f}.{k}", x


def lint(configs, env):
    """configs: {scope: {"mcpServers": {...}}} for scopes 'local', 'project', 'user'. Returns [(severity, server, rule, msg)]."""
    out, seen = [], {}
    for scope in ("local", "project", "user"):                                   # [doc] precedence local > project > user
        for name, e in (configs.get(scope) or {}).get("mcpServers", {}).items():
            add = lambda sev, rule, msg: out.append((sev, f"{scope}:{name}", rule, msg))
            kind = e.get("type", "stdio")
            remote = kind in ("http", "sse", "ws")
            if "url" in e and "type" not in e:
                add("ERROR", "MC01", "has a url but no type: Claude Code reads it as stdio and skips it - add \"type\": \"http\"")
            if kind == "sse":
                add("WARN", "MC02", "SSE transport is deprecated - use \"type\": \"http\" (streamable HTTP) where the server offers it")
            if name in RESERVED:
                add("ERROR", "MC09", f"'{name}' is a reserved built-in server name - Claude Code skips it at load time")
            fields = ["url", "headers"] if "url" in e else ["command", "args", "env"]
            for field, value in strings(e, fields):
                if value != value.strip():
                    add("WARN", "MC08", f"{field} has hidden leading/trailing whitespace (often a pasted token's newline)")
                if SECRET.search(value) and scope == "project":
                    add("ERROR", "MC03", f"{field} holds a literal credential in a checked-in file - use ${{VAR}} expansion")
                for var, has_default, default in VAR.findall(value):
                    if remote and field.split(".")[0].split(" ")[0] in ("url", "headers") and var in COVERED_CREDENTIALS:
                        add("ERROR", "MC04", f"{field} uses ${{{var}}}: a covered credential reads as EMPTY in a remote url/header"
                                             " (a :-default is ignored) - copy it to a variable with your own name")
                    elif var == "CLAUDE_PROJECT_DIR" and not has_default:
                        add("ERROR", "MC05", f"{field} uses ${{CLAUDE_PROJECT_DIR}} without a default: it is set in the server's"
                                             " env, not Claude Code's - write ${CLAUDE_PROJECT_DIR:-.}")
                    elif var not in env and not has_default and var != "CLAUDE_PROJECT_DIR":
                        add("WARN", "MC06", f"{field}: ${{{var}}} is unset and has no :-default - the server loads with the "
                                            "literal text")
                    elif var in env and env[var] == "" and has_default:
                        add("WARN", "MC06", f"{field}: {var} is set to '' so ${{{var}:-{default}}} expands to '' (unset it to "
                                            "get the default)")
                expanded = VAR.sub(lambda m: env.get(m.group(1), m.group(3) or ""), value)
                for user, host in DSN.findall(expanded):
                    if not re.search(r"(^|_)(ro|readonly|read_only|reader)($|_)", user):
                        where = " on a production host" if "prod" in host else ""
                        add("WARN", "MC10", f"{field}: database user '{user}'{where} is not a read-only role - give the MCP "
                                            "server a SELECT-only role (see sql_readonly_gate_lab.py)")
            cmd, args = e.get("command", ""), [a for a in e.get("args", []) if isinstance(a, str)]
            if cmd in LAUNCHERS:
                pkg = next((a for a in args if not a.startswith("-")), "")
                if pkg and not re.search(LAUNCHERS[cmd], pkg):
                    add("WARN", "MC07", f"{cmd} runs '{pkg}' unpinned: every start may fetch a new release - pin an exact "
                                        "version (@x.y.z / ==x.y.z)")
            if cmd == "docker" and args[:1] == ["run"]:
                image = next((a for a in args[1:] if not a.startswith("-") and ("/" in a or ":" in a)), "")
                if image and (":" not in image.split("/")[-1] or image.endswith(":latest")) and "@sha256:" not in image:
                    add("WARN", "MC07", f"docker image '{image}' is not pinned - use a version tag or @sha256 digest")
            if e.get("alwaysLoad") is True:
                add("INFO", "MC12", "alwaysLoad: true - this server's tools load upfront even with tool search on")
            endpoint = e.get("url") or " ".join([cmd] + args)
            if name in seen and seen[name][1] != endpoint:
                add("WARN", "MC11", f"also defined in {seen[name][0]} scope with a different endpoint - the {seen[name][0]} entry "
                                    "wins whole (entries are not merged) and OAuth sign-ins are per endpoint")
            seen.setdefault(name, (scope, endpoint))
    always = [s for s, _, r, _ in out if r == "MC12"]
    if len(always) > 1:
        out.append(("WARN", "*", "MC12", f"{len(always)} servers set alwaysLoad - keep upfront tools to the few used every turn"))
    return out


BAD = {
    "project": {"mcpServers": {
        "github": {"url": "https://api.githubcopilot.com/mcp/", "headers": {"Authorization": "Bearer live-3f9a2c7e51b84d06a1c9e2f7"}},
        "jira": {"type": "sse", "url": "https://jira-mcp.example.com/sse", "headers": {"Authorization": "Bearer ${ANTHROPIC_API_KEY}"}},
        "db": {"command": "npx", "args": ["-y", "@bytebase/dbhub", "--dsn",
                                          "postgresql://app_admin:${DB_PASSWORD}@orders-prod.internal:5432/orders"]},
        "order-platform": {"command": "python", "args": ["${CLAUDE_PROJECT_DIR}/tools/mcp/order_platform_mcp.py"]},
        "docs": {"type": "http", "url": "${DOCS_MCP_URL}/mcp ", "alwaysLoad": True},
        "workspace": {"type": "http", "url": "https://mcp.example.com/mcp", "alwaysLoad": True},
        "grafana": {"command": "docker", "args": ["run", "-i", "--rm", "grafana/mcp-grafana"]},
    }},
    "user": {"mcpServers": {"github": {"type": "http", "url": "https://api.githubcopilot.com/mcp/x/issues"}}},
}
GOOD = {
    "project": {"mcpServers": {
        "order-platform": {"type": "stdio", "command": "python",
                           "args": ["${CLAUDE_PROJECT_DIR:-.}/tools/mcp/order_platform_mcp.py"]},
        "github": {"type": "http", "url": "https://api.githubcopilot.com/mcp/readonly",
                   "headers": {"Authorization": "Bearer ${GITHUB_MCP_PAT}", "X-MCP-Toolsets": "repos,issues,pull_requests,actions"}},
        "db": {"type": "stdio", "command": "npx", "args": ["-y", "@bytebase/dbhub@1.5.0", "--dsn", "${ORDERS_RO_DSN}"]},
        "docs": {"type": "http", "url": "https://mcp.context7.com/mcp", "headers": {"Authorization": "Bearer ${CONTEXT7_API_KEY}"}},
        "docker": {"type": "stdio", "command": "docker", "args": ["mcp", "gateway", "run", "--profile", "order-platform"]},
    }},
}
ENV = {"DB_PASSWORD": "x", "GITHUB_MCP_PAT": "x", "CONTEXT7_API_KEY": "x",
       "ORDERS_RO_DSN": "postgresql://mcp_ro:x@orders-replica.internal:5432/orders"}


def report(title, configs, env):
    findings = lint(configs, env)
    print(f"== {title}: {len(findings)} finding(s) ==")
    for sev, server, rule, msg in sorted(findings, key=lambda f: (f[2], f[1])):
        print(f"  {sev:<5} {rule} {server}: {msg}")
    return findings


if __name__ == "__main__":
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf-8") as f:
            sys.exit(1 if any(s == "ERROR" for s, *_ in report(sys.argv[1], {"project": json.load(f)}, dict(os.environ))) else 0)
    bad = report("BAD .mcp.json + ~/.claude.json", BAD, ENV)
    good = report("GOOD .mcp.json", GOOD, ENV)
    rules = sorted({r for _, _, r, _ in bad})
    print(f"\nBAD triggers {len(rules)} distinct rules ({', '.join(rules)}); GOOD triggers {len(good)}.")
```

**Output (verified):**

```text
== BAD .mcp.json + ~/.claude.json: 15 finding(s) ==
  ERROR MC01 project:github: has a url but no type: Claude Code reads it as stdio and skips it - add "type": "http"
  WARN  MC02 project:jira: SSE transport is deprecated - use "type": "http" (streamable HTTP) where the server offers it
  ERROR MC03 project:github: headers.Authorization holds a literal credential in a checked-in file - use ${VAR} expansion
  ERROR MC04 project:jira: headers.Authorization uses ${ANTHROPIC_API_KEY}: a covered credential reads as EMPTY in a remote url/header (a :-default is ignored) - copy it to a variable with your own name
  ERROR MC05 project:order-platform: args[0] uses ${CLAUDE_PROJECT_DIR} without a default: it is set in the server's env, not Claude Code's - write ${CLAUDE_PROJECT_DIR:-.}
  WARN  MC06 project:docs: url: ${DOCS_MCP_URL} is unset and has no :-default - the server loads with the literal text
  WARN  MC07 project:db: npx runs '@bytebase/dbhub' unpinned: every start may fetch a new release - pin an exact version (@x.y.z / ==x.y.z)
  WARN  MC07 project:grafana: docker image 'grafana/mcp-grafana' is not pinned - use a version tag or @sha256 digest
  WARN  MC08 project:docs: url has hidden leading/trailing whitespace (often a pasted token's newline)
  ERROR MC09 project:workspace: 'workspace' is a reserved built-in server name - Claude Code skips it at load time
  WARN  MC10 project:db: args[3]: database user 'app_admin' on a production host is not a read-only role - give the MCP server a SELECT-only role (see sql_readonly_gate_lab.py)
  WARN  MC11 user:github: also defined in project scope with a different endpoint - the project entry wins whole (entries are not merged) and OAuth sign-ins are per endpoint
  WARN  MC12 *: 2 servers set alwaysLoad - keep upfront tools to the few used every turn
  INFO  MC12 project:docs: alwaysLoad: true - this server's tools load upfront even with tool search on
  INFO  MC12 project:workspace: alwaysLoad: true - this server's tools load upfront even with tool search on
== GOOD .mcp.json: 0 finding(s) ==

BAD triggers 12 distinct rules (MC01, MC02, MC03, MC04, MC05, MC06, MC07, MC08, MC09, MC10, MC11, MC12); GOOD triggers 0.
```

### L2 · `mcp_token_tax.py`

**What it shows.** Per-session cost of tool definitions over a 150-request session with a 60K-token average context, for three fleets × three models, tool search off vs on.
- **Upfront** counts cache reads of the tool block on every request, plus the initial write and two prefix busts. A bust re-writes the *whole* conversation behind the tools.
- **Tool search** counts tool names (12 tokens each, an assumption), server instructions (250 tokens each, an assumption), eight tools' definitions loaded halfway through, and five search round trips.

It also prints which fleets `ENABLE_TOOL_SEARCH=auto` would load upfront, which fleets push every Haiku 5.5 request past the 100K-token price tier, and a 100-engineer annual figure.

**What it does not show.**
- Real tokenization: the 150 and ~743 tokens-per-tool densities come from the brief and from Anthropic's published example, not from counting.
- Your session shape: change `SESSION`.
- The accuracy effect (§1.6).
- File 03's measured definitions (465–579 chars/4-tokens for three small tools) sit at the brief's density. Real servers with long descriptions sit at the GitHub density.

Run: `python mcp_token_tax.py`.

```python
"""mcp_token_tax.py - the MCP "token tax" priced properly: context share and dollars per session for three tool fleets, with
tool search off (every definition upfront in the cached prefix) and on (Claude Code's default: tool names and server
instructions upfront, a definition loaded only when Claude searches for it). Fleets: the brief's 10 servers x 20 tools at
150 tokens/tool; Anthropic's published 5-server example (58 tools, ~55K tokens); 10 x 20 at that example's GitHub density
(26K tokens / 35 tools). Prices = Folder 01 table (pricing page 2026-10-30). The session shape is an assumption: edit it.
"""
PRICES = {  # model: (5m cache write, cache read, output) USD per million tokens
    "opus-5.5": (5.00, 0.20, 20.00), "sonnet-5.5": (2.50, 0.10, 10.00),
    "haiku-5.5": (0.125, 0.01, 0.50), "haiku-5.5>100K": (0.625, 0.05, 2.50),   # Haiku 5.5: whole request > 100K tokens
}
CONTEXT_WINDOW = 1_000_000
FLEETS = [("brief 10x20 @150", 10, 200, 200 * 150),
          ("published 5-server", 5, 58, 55_000),
          ("10x20 @GitHub density", 10, 200, round(200 * 26_000 / 35))]
NAME_TOKENS = 12          # one deferred tool's upfront cost: its name ('mcp__github__create_pull_request') + framing [assumption]
INSTRUCTION_TOKENS = 250  # one server's instructions (Claude Code cuts them at 4,096 chars, ~1K tokens) [assumption]
SESSION = {"requests": 150, "context": 60_000, "busts": 2, "tools_used": 8, "searches": 5, "search_output": 60}
ORG = {"engineers": 100, "sessions_per_day": 6, "days": 230}


def request(model, read=0, write=0, out=0):
    if model == "haiku-5.5" and read + write > 100_000:
        model = "haiku-5.5>100K"
    w, r, o = PRICES[model]
    return (write * w + read * r + out * o) / 1e6


def session(model, upfront, loaded=0, searches=0, busts=0):
    """150 requests over a 60K-token average context. Request 0 writes the prefix; each bust (a server reconnect or
    tools/list_changed while tools sit at the front of the prefix) rewrites it. Searched-for definitions join halfway."""
    s, n = SESSION, SESSION["requests"]
    bust_at = {round(n * (k + 1) / (busts + 1)) for k in range(busts)}
    usd = 0.0
    for i in range(n):
        prefix = s["context"] + upfront + (loaded if i >= n // 2 else 0)
        usd += request(model, write=prefix) if i == 0 or i in bust_at else request(model, read=prefix)
    for _ in range(searches):                                    # each search is one more round trip over the context
        usd += request(model, read=s["context"] + upfront + loaded // 2, out=s["search_output"])
    return usd


def main():
    base = {m: session(m, 0) for m in PRICES if ">" not in m}
    print(f"session: {SESSION['requests']} requests, {SESSION['context']:,}-token average context, "
          f"{SESSION['busts']} prefix busts (upfront only), {SESSION['tools_used']} tools used, {SESSION['searches']} searches")
    print(f"{'fleet':<22}{'tools':>6}{'upfront tok':>12}{'of 1M':>7}{'search tok':>11}   per-session tax: upfront -> tool search")
    for name, servers, tools, upfront in FLEETS:
        per_tool = upfront / tools
        deferred = tools * NAME_TOKENS + servers * INSTRUCTION_TOKENS
        loaded = round(SESSION["tools_used"] * per_tool)
        cells = []
        for m in base:
            up = session(m, upfront, busts=SESSION["busts"]) - base[m]
            ts = session(m, deferred, loaded=loaded, searches=SESSION["searches"]) - base[m]
            cells.append(f"{m} ${up:.3f}->${ts:.3f}")
        print(f"{name:<22}{tools:>6}{upfront:>12,}{upfront / CONTEXT_WINDOW:>7.1%}{deferred:>11,}   " + ", ".join(cells))
    print()
    for name, servers, tools, upfront in FLEETS:
        auto = "upfront" if upfront < 0.10 * CONTEXT_WINDOW else "tool search"
        over = SESSION["context"] + upfront > 100_000
        print(f"{name:<22} ENABLE_TOOL_SEARCH=auto -> {auto:<11} | Haiku 5.5 upfront: "
              f"{'every request crosses 100K -> 5x tier' if over else 'stays under the 100K tier'}")
    sessions = ORG["engineers"] * ORG["sessions_per_day"] * ORG["days"]
    name, servers, tools, upfront = FLEETS[2]
    up = session("opus-5.5", upfront, busts=SESSION["busts"]) - base["opus-5.5"]
    ts = session("opus-5.5", tools * NAME_TOKENS + servers * INSTRUCTION_TOKENS,
                 loaded=round(SESSION["tools_used"] * upfront / tools), searches=SESSION["searches"]) - base["opus-5.5"]
    print(f"\norg: {sessions:,} sessions/yr on Opus 5.5 with the '{name}' fleet: upfront ${up * sessions:,.0f}/yr, "
          f"tool search ${ts * sessions:,.0f}/yr")


if __name__ == "__main__":
    main()
```

**Output (verified):**

```text
session: 150 requests, 60,000-token average context, 2 prefix busts (upfront only), 8 tools used, 5 searches
fleet                  tools upfront tok  of 1M search tok   per-session tax: upfront -> tool search
brief 10x20 @150         200      30,000   3.0%      4,900   opus-5.5 $1.908->$0.260, sonnet-5.5 $0.954->$0.130, haiku-5.5 $0.069->$0.012
published 5-server        58      55,000   5.5%      1,946   opus-5.5 $3.018->$0.253, sonnet-5.5 $1.509->$0.127, haiku-5.5 $0.964->$0.012
10x20 @GitHub density    200     148,571  14.9%      4,900   opus-5.5 $7.173->$0.334, sonnet-5.5 $3.586->$0.167, haiku-5.5 $1.827->$0.016

brief 10x20 @150       ENABLE_TOOL_SEARCH=auto -> upfront     | Haiku 5.5 upfront: stays under the 100K tier
published 5-server     ENABLE_TOOL_SEARCH=auto -> upfront     | Haiku 5.5 upfront: every request crosses 100K -> 5x tier
10x20 @GitHub density  ENABLE_TOOL_SEARCH=auto -> tool search | Haiku 5.5 upfront: every request crosses 100K -> 5x tier

org: 138,000 sessions/yr on Opus 5.5 with the '10x20 @GitHub density' fleet: upfront $989,812/yr, tool search $46,028/yr
```

How to read it:
- With tools upfront, the published five-server fleet costs about **$3.02 per Opus 5.5 session**. With tool search it costs **$0.25**.
- At GitHub density, a 10×20 fleet takes **14.9% of a 1M window** before you type, and costs **$7.17 per session** upfront.
- The Haiku column is the trap. A 55K-token tool block on a 60K-token conversation puts every request in Haiku 5.5's >100K tier, so the *whole* request bills at 5×. The tax there is 80× the tool-search cost ($0.964 vs $0.012).
- The annual line ($990K vs $46K for 138,000 sessions) is only as good as the session assumptions. Its direction is not in doubt.

---

## 4. Failure modes

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| F1 | Server never appears; `claude mcp list` reports it skipped | `url` without `type` | `"type": "http"` (MC01) |
| F2 | 401 from a server whose header "has the key" | A covered credential (`ANTHROPIC_API_KEY`, …) reads as empty in remote headers | Copy it to your own variable name (MC04) |
| F3 | Server path resolves to `/tools/...` or the literal `${CLAUDE_PROJECT_DIR}` | The variable is set in the server's env, not Claude Code's | `${CLAUDE_PROJECT_DIR:-.}` (MC05) |
| F4 | URL becomes `/mcp`; "'url' is not a valid URL" | The variable is set to `""`, so `:-default` is skipped | Unset it (MC06) |
| F5 | Teammate's server works, yours uses another endpoint | Same name in local and project scope; local wins whole | Remove the local entry, or rename (MC11) |
| F6 | CI job talks to a server nobody approved | `-p` loads `.mcp.json` without asking | `--strict-mcp-config --mcp-config`, `disabledMcpjsonServers`, `--bare` |
| F7 | Startup slow; the context already 15% full | `ENABLE_TOOL_SEARCH=false`/`auto` or `alwaysLoad` on big servers | Default tool search; `alwaysLoad` only for one or two hot tools (MC12) |
| F8 | Cache hit rate collapses mid-session | Upfront tool list changed (reconnect, `list_changed`) and busted the prefix | Tool search; stable tool lists; avoid mid-session server churn |
| F9 | Claude never uses an installed server | Vague server instructions; tool search can't match them | Keywords first in instructions, under 4,096 chars |
| F10 | A query result floods the context | No row cap; 25K-token default cap reached | Cap rows server-side; `maxResultSizeChars` deliberately (file 02) |
| F11 | Tool call hangs for 30 minutes, or for hours with progress pings | stdio idle window is 30 min; wall clock is ~28 h and progress doesn't extend it | Per-server `"timeout"` |
| F12 | "Works on my machine" on a new laptop | Unpinned `npx -y pkg` fetched a new major version | Pin `@x.y.z` (MC07) |

---

## 5. Staff-level drills

<details><summary><b>D1 · "We have 12 MCP servers. Should we cut them to save tokens?"</b></summary>

**Naive answer.** Yes: every server costs ~3K tokens per turn.

**Why it fails.** With tool search on (the default), an idle server costs its name list plus its instructions, roughly a few hundred tokens. The real costs are:
- servers forced upfront;
- vague instructions that make Claude miss tools;
- outputs that flood the context;
- the supply-chain surface of 12 processes with credentials.

**Staff answer.**
1. Measure with `/context`.
2. Keep tool search on. Audit `alwaysLoad` and any `ENABLE_TOOL_SEARCH` overrides.
3. Rewrite instructions so they say *when* to use each server.
4. Cap outputs.
5. Remove servers for security and maintenance reasons, not token reasons. Every server is a credential holder and a process you run.
</details>

<details><summary><b>D2 · "Why not set <code>ENABLE_TOOL_SEARCH=false</code> so Claude always sees every tool?"</b></summary>

**Staff answer.** L2's published fleet costs 12× more per Opus session upfront ($3.02 vs $0.25). It also pushes Haiku requests into the 5× tier. Every reconnect re-writes the conversation's cache.

Anthropic's published evaluation also found accuracy *improved* with tool search (49%→74% Opus 4; 79.5%→88.1% Opus 4.5) [research]. "Seeing everything" is not "choosing better".

If one tool must be visible every turn, give that server `alwaysLoad: true`, or have its author set `anthropic/alwaysLoad` on that tool alone.
</details>

<details><summary><b>D3 · "A contractor's PR added a server to <code>.mcp.json</code>. What's the risk?"</b></summary>

**Staff answer.**
- Interactive teammates get an approval prompt. Many will click through.
- `claude -p` jobs, the Agent SDK and cloud sessions run it **without asking** [doc].
- A stdio entry is arbitrary code execution on every developer machine and CI runner.
- A remote entry can receive whatever variables the headers reference. Covered credentials are blanked, but `${GITHUB_TOKEN}`-style names you chose are not.

Treat `.mcp.json` changes like changes to a build script:
- CODEOWNERS review, plus the L1 lint;
- pinned versions;
- CI on `--strict-mcp-config` with a CI-owned server list.
</details>

<details><summary><b>D4 · "Our gateway returns 400 since we upgraded Claude Code."</b></summary>

**Staff answer.** With `ANTHROPIC_BASE_URL` set, tool search is still on. Requests carry `defer_loading` tool fields and `tool_reference` blocks, which the gateway must forward [doc]. v2.1.305+ retries without tool search after an unrecognised 400/422.

Fix the gateway so it forwards those fields. Don't disable tool search for everyone: you would turn D2's costs back on.
</details>

<details><summary><b>D5 · "Where should a schema dump live: a tool, a resource, or CLAUDE.md?"</b></summary>

**Staff answer.**
- **CLAUDE.md:** no. It loads on every turn, and a schema churns.
- **Resource** (`@db:schema://orders`): when a human knows the session needs it.
- **Tool** (`describe_table`, file 03): when the model must decide mid-task. A tool returns only the table asked for, keeping the output small.

The rule: *always-needed, small, stable* goes in CLAUDE.md; *human-chosen* is a resource; *model-chosen, query-shaped* is a tool.
</details>

---

## 6. Checklist

- [ ] Remote servers use `"type": "http"`; no `url` without a `type`; no SSE where HTTP exists.
- [ ] Team servers live in `.mcp.json` with `${VAR}` secrets under names you own; personal ones in local or user scope.
- [ ] `${CLAUDE_PROJECT_DIR:-.}` in project-scoped stdio paths.
- [ ] Tool search left on. `alwaysLoad` only on one or two hot servers or tools. `/context` checked after adding a server.
- [ ] Server instructions say when to use the server, keywords first, under 4,096 chars.
- [ ] Per-server `timeout` on database and build tools. Outputs capped server-side.
- [ ] `.mcp.json` changes need CODEOWNERS review plus the L1 lint. CI uses `--strict-mcp-config --mcp-config`.

---

## 7. References

- Connect Claude Code to tools via MCP (transports, scopes, expansion, approval, limits, tool search, output): <https://code.claude.com/docs/en/mcp>
- Configure permissions (MCP rule names and globs): <https://code.claude.com/docs/en/permissions>
- Managed MCP configuration: <https://code.claude.com/docs/en/managed-mcp>
- CLI reference (`--mcp-config`, `--strict-mcp-config`, `--setting-sources`): <https://code.claude.com/docs/en/cli-reference>
- Anthropic engineering, "Introducing advanced tool use" (58 tools ≈ 55K tokens; 134K observed; accuracy with tool search): <https://www.anthropic.com/research/advanced-tool-use>
- MCP specification: <https://modelcontextprotocol.io/specification>
- Folder 01 cache-prefix order and prices: [03 · Token economics](../01-First-Principles-of-Claude-Attention-and-Prompt-Physics/03-model-routing-limits-token-economics-opus-vs-sonnet-vs-haiku-and-advisor-mode.md)

Next: [02 · Essential MCP servers for backend engineers](02-essential-mcp-servers-for-backend-engineers-postgres-github-docker-and-docs.md) · [KB README](../README.md)

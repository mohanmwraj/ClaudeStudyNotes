# Essential MCP Servers for Backend Engineers: PostgreSQL, GitHub, Docker and Docs

> **Folder 06 · File 2 of 3** · verified 2026-10-30 against code.claude.com `mcp.md` and `permissions.md`; github/github-mcp-server `docs/remote-server.md` and README; docs.docker.com MCP Gateway and docker/mcp-gateway README; upstash/context7 README; bytebase/dbhub README; npm registry (dbhub 1.5.0, context7-mcp 4.4.4)
> **Listing:** `sql_readonly_gate_lab.py` (three "read-only" gates against a real database, damage measured)

---

## 0. Orientation

A backend engineer's daily MCP set is small:
- **the database**, to answer "what is actually in there?";
- **GitHub**, for PRs, issues, Actions and code search across repos;
- **Docker**, for the containerised servers and tools you don't want installed on the host;
- **a documentation source**, for version-specific library docs the model's training predates (Spring Boot 4.1, Spring AI 2.0, Kafka 4.x).

Add your own server (file 03) for the project knowledge nobody else can serve.

Each one is a **credential holder that reads untrusted content**: issue bodies, table rows, web docs. That shapes every decision below. "Can Claude use it?" is easy. The Staff question is *what is the worst thing this server can do with what it reads*.

### 0.1 The twelve rules

1. **Every server is code you run plus a credential you hand over.** Pick by provenance (vendor-official, then established open source, then everything else). Pin the version. Review `.mcp.json` changes like build-script changes. [practice]
2. **Database "read-only" is a property of the role and the connection, never of the SQL text.** L1 shows why:
   - a SELECT/WITH prefix filter let **7/7** attacks do damage;
   - a write-keyword denylist let **3/7** through and refused a benign query;
   - engine-enforced controls let **0/7** through and refused nothing. [measured: L1]
3. **Give the MCP server its own PostgreSQL role, with SELECT grants on named tables and columns, a `statement_timeout`, and a replica.** `default_transaction_read_only` is defence in depth: a session can turn it off. [doc: PostgreSQL]
4. **Cap rows and time on the server side.** Claude Code's 25K-token output cap is a backstop, not a design (file 01). [doc + measured: L1]
5. **Grant columns, not tables, around PII.** The model doesn't need `email` to debug an order state machine, and anything returned is in the transcript. [practice + L1 "out-of-scope read"]
6. **GitHub: use the remote server's read-only mode and named toolsets.**
   - `https://api.githubcopilot.com/mcp/readonly`, or `X-MCP-Readonly: true`;
   - `X-MCP-Toolsets: repos,issues,pull_requests,actions`;
   - authenticate with a **fine-grained PAT** scoped to the repos and permissions the task needs. [doc: GitHub]
7. **Assume tool output is attacker-controlled.** A public issue, a PR description, a table row or a docs page can carry instructions. Private data, untrusted content and a write/egress path in the same session is the "lethal trifecta". Remove one leg. [research]
8. **`X-MCP-Lockdown` hides public issue content from users without push access, but GitHub calls it "best-effort … not a security boundary".** Read-only tokens and toolsets are the boundary. [doc: GitHub]
9. **Docker: one gateway entry instead of N stdio servers.**
   - `docker mcp gateway run --profile <p>` runs catalog servers in isolated containers, and profile tools can be enabled one by one.
   - Never give an agent a server that holds the Docker socket outside a sandbox: socket access is root on the host. [doc: Docker + practice]
10. **Docs: Context7's remote server answers version-specific library questions** with two tools, `resolve-library-id` and `query-docs`. Name the version in the question ("Spring AI 2.0.2 `@McpTool`"), or you get the most popular version's docs. [doc: Context7 + inference]
11. **Layer permission rules on top:** allow the read tools by name, `ask` for anything that executes SQL, deny merges and deletes. Rules apply even where a server's read-only mode already removed the tool. [doc]
12. **No production credentials in the project `.mcp.json`.** The checked-in file names variables. Each engineer's environment or secret manager supplies replica credentials, and CI gets its own CI-only role. [practice + file 01 MC03/MC10]

---

## 1. First principles

### 1.1 Threat model: the lethal trifecta, per server [research + inference]

An agent becomes exfiltration-capable when one session has all three of:
1. access to private data;
2. exposure to untrusted content;
3. a way to send data out.

The "GitHub MCP" toxic-flow demonstration (Invariant Labs, 2025) used exactly that chain. A malicious issue in a public repo instructed an agent with a broad token to read private repositories and publish their contents in a pull request on the public one. The server had no bug; the token was too broad.

| Server | Private data | Untrusted content | Egress / write | Leg to remove |
|---|---|---|---|---|
| PostgreSQL | rows, PII | row values (user-entered text) | `execute_sql` that writes; or results flowing into a GitHub comment | Writes (role), PII (column grants) |
| GitHub | private repos | public issues and PRs, any comment | create PR/issue/comment, push | Write tools (`/readonly`); token scope; one repo per token |
| Docker | host files, env | container images, logs | network, volume mounts, the socket | Gateway isolation; no socket; pinned images |
| Docs (Context7) | — | the fetched docs | — (read-only tools) | Treat output as data |
| Your server (file 03) | whatever it reads | project files | none if read-only | Keep it read-only (`readOnlyHint` plus no write code) |

The cross-server case is the dangerous one. Database rows read in one call can leave through a GitHub write tool in the next. Read-only modes on *every* write-capable server, plus `ask` rules, break that chain.

### 1.2 PostgreSQL: what L1 measured, mapped to PostgreSQL controls

L1 runs nine agent-written statements through three gates against a real SQLite database, on a fresh copy each time. It counts actual damage: rows deleted, tables dropped, data copied to a new file, SSNs returned, and runaway queries the harness had to kill. The SQLite controls map to PostgreSQL as follows.

| L1 control (SQLite) | Blocks | PostgreSQL equivalent | Notes |
|---|---|---|---|
| `mode=ro` + `PRAGMA query_only` | writes, DDL | a hot-standby replica (rejects writes outright) + `default_transaction_read_only = on` on the role | The role setting is a *default*: `SET default_transaction_read_only = off` or `BEGIN READ WRITE` overrides it. The replica and the grants are the boundary [doc: PostgreSQL] |
| authorizer table/column allowlist | out-of-scope and PII reads, writes | `GRANT SELECT ON app.orders …`, column grants `GRANT SELECT (id, status) ON app.customers`, no other grants | `SELECT … FOR UPDATE` needs `UPDATE` privilege, so a SELECT-only role can't take row locks [doc: PostgreSQL] |
| `execute()` single statement | stacked statements | **driver-dependent**: the extended (parameterised) protocol runs one statement; the simple protocol runs `select 1; delete …` as two | Don't depend on which protocol the MCP server's driver picks. Privileges make the second statement fail |
| step budget (progress handler) | runaway recursion, cartesian joins | `ALTER ROLE mcp_ro SET statement_timeout = '5s'` | Also `lock_timeout` and `idle_in_transaction_session_timeout` (below) |
| row cap (`fetchmany(100)`) | context floods | server-side `LIMIT` or fetch size; DBHub has a row-limit option [doc: DBHub] | `MAX_MCP_OUTPUT_TOKENS` is the backstop |
| function allowlist | side-effect functions | no membership in `pg_signal_backend`, `pg_read_server_files`, `pg_write_server_files`, `pg_execute_server_program`; no `dblink`/`lo_*` grants; no `USAGE` on sequences (`nextval` writes) | Superuser or `pg_write_all_data` on an MCP role defeats everything above |

The `lock_timeout` row is the one production teams miss. An agent's slow `SELECT` holds an `ACCESS SHARE` lock. A migration then queues for `ACCESS EXCLUSIVE` behind it, and every later query on that table queues behind the migration. A five-second `statement_timeout` on the agent's role bounds the outage. A `lock_timeout` stops the agent's own queries piling up behind a migration [doc: PostgreSQL explicit locking + inference].

### 1.3 The role, as SQL (not executed by this KB's harness; ⚠ verify on your PostgreSQL version)

```sql
-- One role per purpose: mcp_ro for agents, never the application's role and never a human's.
CREATE ROLE mcp_ro WITH LOGIN PASSWORD :'mcp_ro_password' CONNECTION LIMIT 5;
ALTER ROLE mcp_ro SET default_transaction_read_only = on;          -- defence in depth, overridable per session
ALTER ROLE mcp_ro SET statement_timeout = '5s';
ALTER ROLE mcp_ro SET lock_timeout = '1s';
ALTER ROLE mcp_ro SET idle_in_transaction_session_timeout = '10s';
GRANT CONNECT ON DATABASE orders TO mcp_ro;
GRANT USAGE ON SCHEMA app TO mcp_ro;
GRANT SELECT ON app.orders, app.order_lines, app.outbox_events TO mcp_ro;
GRANT SELECT (id, status, country, created_at) ON app.customers TO mcp_ro;   -- no email, phone, tax id
-- Point the DSN at a replica: postgresql://mcp_ro:${MCP_RO_PASSWORD}@orders-replica.internal:5432/orders
```

Then the MCP entry needs only a DSN variable (file 01 §2.2). Whatever "read-only mode" the server itself offers is now a third layer, not the only one. DBHub lists read-only mode, row limiting and query timeouts among its features [doc: DBHub].

### 1.4 GitHub: the remote server, narrowed [doc: GitHub]

| Control | How | Effect |
|---|---|---|
| Endpoint | `https://api.githubcopilot.com/mcp/` | the hosted server (no local process) |
| Read-only | append `/readonly` to any URL, or send `X-MCP-Readonly: true` | only read tools are offered |
| Toolsets | `X-MCP-Toolsets: repos,issues,pull_requests,actions`, or the URL form `/x/{toolset}` (one toolset per URL) | fewer tools, so a smaller definition footprint and fewer wrong choices. Defaults are context, repos, issues, pull_requests, users |
| Lockdown | `X-MCP-Lockdown: true` | hides public issue details from users without push access. Best-effort filter, *not* a boundary |
| Credential | fine-grained PAT (or OAuth) limited to the repositories and permissions needed | the real boundary: a read-only token can't write whatever the tool list says |

Tool names follow the pattern:
- `get_file_contents`, `list_pull_requests`, `search_issues`, `pull_request_read`, `issue_read` (reads);
- `create_pull_request`, `merge_pull_request`, `delete_file`, `issue_write` (writes).

That makes permission globs practical (§2.2). GitHub's 35 tools were about 26K tokens of definitions in Anthropic's published example [research]. That is fine deferred under tool search, and the reason not to `alwaysLoad` it.

### 1.5 Docker: the MCP Gateway [doc: Docker]

The gateway is one MCP server that fronts many. Each catalog server runs in its own container with restricted privileges, network access and resources. The gateway injects credentials (Docker Desktop secret management), applies restrictions, forwards the call, and logs and traces it. Profiles choose which servers and tools are exposed:

```bash
docker mcp catalog pull mcp/docker-mcp-catalog                                   # prerequisite
docker mcp profile server add order-platform --server catalog://mcp/docker-mcp-catalog/notion
docker mcp profile tools order-platform --enable notion.search                   # enable one <server>.<tool> (example)
docker mcp gateway run --profile order-platform                                  # stdio (default)
docker mcp gateway run --port 8080 --transport streaming                         # or streamable HTTP
```

In Claude Code that is one entry:

```bash
claude mcp add --transport stdio --scope project docker -- docker mcp gateway run --profile order-platform
```

Docker also documents `docker mcp client connect <client> --profile <id>`. Check `docker mcp client ls` for the exact client name it uses for Claude Code [doc: Docker; ⚠ verify the name].

The gateway is the right default for third-party servers. You get containers instead of `npx` on the host, one credential store, and one log of every call. Its limit is what you grant: a profile server that mounts the Docker socket or your home directory has undone the isolation.

### 1.6 Docs: Context7 and your own [doc: Context7]

The model's training predates the libraries you are upgrading to. Context7 serves current, versioned library documentation through a remote endpoint, `https://mcp.context7.com/mcp` (API key as `Authorization: Bearer …`). It has two tools:
- `resolve-library-id` maps a name to a library ID;
- `query-docs` fetches the relevant sections.

A local package `@upstash/context7-mcp` exists (4.4.4 at the time of writing).

Two practices make it reliable [inference]:
- **Put the version in the request.** "Spring AI **2.0.2** `@McpTool` output schema", not "Spring AI tools".
- **Check generated code against the compiler.** File 03's Spring server was written from `javap` on the resolved 2.0.2 jars, and `-Werror` caught five deprecated APIs in the plain-SDK server. Documentation, MCP-served or not, is a hint; the build is the verdict.

Your own docs (ADRs, runbooks, the outbox contract) belong in your own server or a resource, not a vendor's index. That is file 03.

### 1.7 Honourable mentions [doc]

- **Sentry:** `claude mcp add --transport http sentry https://mcp.sentry.dev/mcp`, OAuth via `/mcp`, for "what is this stack trace in prod?".
- **Issue trackers and observability servers:** the same rules apply, with read-only tokens and outputs treated as untrusted.
- **claude.ai connectors** appear in Claude Code too, ranked below your own scopes. Your organization can set per-tool `ask`/`blocked` controls on them.

---

## 2. Practice

### 2.1 Setup, in order of value for a Java backend team

```bash
# 1. Your own project-knowledge server (file 03): read-only, no credentials
claude mcp add --transport stdio --scope project order-platform -- python tools/mcp/order_platform_mcp.py

# 2. Database: a pinned server, the DSN of the mcp_ro role on a replica, from the environment
claude mcp add-json --scope project db '{"type":"stdio","command":"npx","args":["-y","@bytebase/dbhub@1.5.0","--dsn","${ORDERS_RO_DSN}"],"timeout":30000}'

# 3. GitHub: read-only, four toolsets, fine-grained PAT in your own variable name
claude mcp add-json --scope project github '{"type":"http","url":"https://api.githubcopilot.com/mcp/readonly","headers":{"Authorization":"Bearer ${GITHUB_MCP_PAT}","X-MCP-Toolsets":"repos,issues,pull_requests,actions"}}'

# 4. Library docs
claude mcp add-json --scope project docs '{"type":"http","url":"https://mcp.context7.com/mcp","headers":{"Authorization":"Bearer ${CONTEXT7_API_KEY}"}}'

# 5. Containerised third-party servers
claude mcp add --transport stdio --scope project docker -- docker mcp gateway run --profile order-platform
```

Then run `python mcp_config_lint.py .mcp.json` (file 01 L1; 0 findings for this set) and `/mcp` to confirm each row shows a checkmark.

### 2.2 Permission rules on top (`.claude/settings.json`; validated against the settings schema, 0 errors)

```json
{
  "permissions": {
    "allow": ["mcp__order-platform__*", "mcp__docs__*",
              "mcp__github__get_*", "mcp__github__list_*", "mcp__github__search_*"],
    "ask": ["mcp__db__execute_sql"],
    "deny": ["mcp__github__merge_pull_request", "mcp__github__delete_*"]
  },
  "enabledMcpjsonServers": ["order-platform", "github", "db", "docs", "docker"]
}
```

- **Allow globs need a literal `mcp__<server>__` prefix.** Deny and ask rules accept globs in the tool-name position [doc].
- **The `deny` entries are deliberately redundant with `/readonly`.** If someone later switches the URL to read-write, the merge is still blocked.
- **`ask` on SQL keeps a human on every query** while the read-only role is new. Promote it to `allow` once the role has been audited.
- **`enabledMcpjsonServers` committed to the repo is ignored until a teammate accepts workspace trust** [doc]. It is a convenience, not a bypass.

### 2.3 Daily prompts that use them well

```text
Using describe_table and the db server, explain why order 8812 is stuck in PAYMENT_PENDING.
Query only orders, order_lines and outbox_events; LIMIT 50 per query; show me each SQL before running it.
```

```text
List my open PRs in acme/order-platform with failing Actions checks; for each, summarise the first failing job's error.
```

```text
Use the docs server for Spring Boot 4.1.2 and Spring AI 2.0.2 only: how does @McpTool generate an output schema
from a record return type? Then check the answer against the jar on our classpath.
```

---

## 3. Verified listing

### L1 · `sql_readonly_gate_lab.py`

**What it shows.** The same nine statements (three benign, seven attacks) go through three gates. Each runs against a fresh SQLite database, and the result is measured damage, not a classification:
- **Naive prefix** (allow `SELECT`/`WITH`, hand the string to the driver): all seven attacks do damage.
  - Stacked delete; comment-smuggled drop; CTE-prefixed delete.
  - `ATTACH` + `CREATE TABLE … AS SELECT` that copies the customer table to a new file.
  - An SSN read.
  - Two runaway queries the harness had to kill.
- **Write-keyword denylist:** blocks the writes, but lets the PII read and both runaway queries through. It refuses a benign `LIKE '%update address%'` search.
- **Engine-enforced:**
  - a read-only connection with `query_only`;
  - one statement per call;
  - an authorizer (the GRANT analogue: `orders` only, safe functions only);
  - a 200K-step budget (the `statement_timeout` analogue);
  - a 100-row cap.

  Zero damage, zero false positives. Each attack fails at the layer you'd expect.

**What it does not show.**
- PostgreSQL itself. The mapping in §1.2 is from the PostgreSQL docs, and the role SQL in §1.3 was not executed here.
- Attacks the engine permits *by design*: a granted table's rows are readable. Grants decide scope.
- Prompt injection through row content (§1.1).

Run: `python sql_readonly_gate_lab.py`.

```python
"""sql_readonly_gate_lab.py - why a database MCP server's "read-only" must be enforced by the engine and its grants, not
by filtering the SQL string. Runs the same agent-written statements through three gates against a real SQLite database and
measures the damage: rows deleted, tables dropped, files written, PII returned, or a runaway query the harness had to kill.
Every statement runs on a fresh copy, so one attack cannot hide another. SQLite stands in for PostgreSQL; the mapping of each
control to its PostgreSQL equivalent is in the KB text.
"""
import os
import pathlib
import re
import shutil
import sqlite3
import tempfile

HARNESS_KILL = 5_000    # progress callbacks x 1,000 VM steps = 5M steps: the harness's own guard, not part of any gate
ENGINE_BUDGET = 200     # 200K VM steps: the engine gate's statement budget (PostgreSQL: statement_timeout)
ROW_CAP = 100           # the engine gate's row cap (Claude Code warns at 10K output tokens, truncates at 25K by default)
GRANTED = {"orders"}    # the engine gate's grant: SELECT on orders only (PostgreSQL: GRANT SELECT ON orders TO mcp_ro)
HOME = os.getcwd()
SAFE_FUNCTIONS = {"count", "sum", "min", "max", "avg", "round", "abs", "lower", "upper", "length", "coalesce", "like", "date"}

ATTACKS = [  # (label, sql, benign?)
    ("benign: filtered read", "SELECT id, amount FROM orders WHERE customer_id = 7", True),
    ("benign: text search", "SELECT id FROM orders WHERE note LIKE '%update address%'", True),
    ("benign: aggregate CTE", "WITH big AS (SELECT * FROM orders WHERE amount > 100) SELECT count(*) FROM big", True),
    ("stacked statement", "SELECT 1; DELETE FROM orders", False),
    ("comment-smuggled drop", "SELECT 1 /* report */; DROP TABLE orders", False),
    ("CTE-prefixed write", "WITH t AS (SELECT 1) DELETE FROM orders", False),
    ("attach + copy out", "SELECT 1; ATTACH DATABASE 'loot.db' AS x; CREATE TABLE x.loot AS SELECT * FROM customers", False),
    ("out-of-scope read", "SELECT email, ssn FROM customers", False),
    ("runaway recursion", "WITH RECURSIVE r(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM r) SELECT count(*) FROM r", False),
    ("cartesian blow-up", "SELECT count(*) FROM " + ", ".join(f"orders o{i}" for i in range(14)), False),   # 3^14 rows
]


def fresh_db(folder):
    db = folder / "app.db"
    conn = sqlite3.connect(db)
    conn.executescript("""
        CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, amount REAL, note TEXT);
        CREATE TABLE customers (id INTEGER PRIMARY KEY, email TEXT, ssn TEXT);
        INSERT INTO orders VALUES (1, 7, 120.0, 'please update address'), (2, 7, 80.0, NULL), (3, 9, 300.0, NULL);
        INSERT INTO customers VALUES (7, 'ana@example.com', '123-45-6789'), (9, 'raj@example.com', '987-65-4321');
    """)
    conn.close()
    return db


def guard(conn, limit):
    calls = [0]

    def tick():
        calls[0] += 1
        return 1 if calls[0] > limit else 0                    # non-zero aborts the statement: "interrupted"
    conn.set_progress_handler(tick, 1000)


def naive_gate(db, sql):
    """The common first draft: allow SELECT/WITH prefixes, hand the string to the driver (which runs every statement)."""
    if not re.match(r"\s*(select|with)\b", sql, re.I):
        raise PermissionError("only SELECT allowed")
    conn = sqlite3.connect(db)
    guard(conn, HARNESS_KILL)
    try:
        if sql.strip().rstrip(";").count(";"):
            conn.executescript(sql)                             # PostgreSQL's simple query protocol does the same
            return []
        return conn.execute(sql).fetchall()
    finally:
        conn.commit()
        conn.close()


def denylist_gate(db, sql):
    """The second draft: reject any write keyword anywhere in the text."""
    if re.search(r"\b(insert|update|delete|drop|alter|create|attach|detach|pragma|vacuum|replace|reindex)\b", sql, re.I):
        raise PermissionError("write keyword")
    return naive_gate(db, sql)


def engine_gate(db, sql):
    """Engine-enforced: read-only connection, one statement, a grant (authorizer), a step budget and a row cap."""
    conn = sqlite3.connect(f"{db.as_uri()}?mode=ro", uri=True)
    conn.execute("PRAGMA query_only = ON")
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type IN ('table', 'view')")}

    def authorize(action, arg1, arg2, _db, _trigger):
        if action in (sqlite3.SQLITE_SELECT, sqlite3.SQLITE_RECURSIVE):
            return sqlite3.SQLITE_OK
        if action == sqlite3.SQLITE_READ:
            return sqlite3.SQLITE_OK if arg1 in GRANTED or arg1 not in tables else sqlite3.SQLITE_DENY   # else: a CTE
        if action == sqlite3.SQLITE_FUNCTION:
            return sqlite3.SQLITE_OK if arg2.lower() in SAFE_FUNCTIONS else sqlite3.SQLITE_DENY
        return sqlite3.SQLITE_DENY
    conn.set_authorizer(authorize)
    guard(conn, ENGINE_BUDGET)
    try:
        return conn.execute(sql).fetchmany(ROW_CAP)             # execute() refuses a second statement
    finally:
        conn.close()


def damage(folder, db, rows, killed):
    conn = sqlite3.connect(db)
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    left = conn.execute("SELECT count(*) FROM orders").fetchone()[0] if "orders" in tables else None
    conn.close()
    harm = []
    if left is None:
        harm.append("orders DROPPED")
    elif left < 3:
        harm.append(f"{3 - left} orders DELETED")
    if (folder / "loot.db").exists():
        harm.append("customers copied to loot.db")
    if any("-" in str(v) and str(v).count("-") == 2 and len(str(v)) == 11 for row in rows for v in row):
        harm.append("SSNs returned")
    if killed:
        harm.append("runaway: harness killed it")
    return harm


def run(gate, label, sql):
    folder = pathlib.Path(tempfile.mkdtemp())
    try:
        db = fresh_db(folder)
        rows, killed, refused = [], False, None
        os.chdir(folder)                                        # relative paths in the SQL land in the server's cwd
        try:
            rows = gate(db, sql)
        except PermissionError as e:
            refused = f"gate refused ({e})"
        except sqlite3.ProgrammingError as e:
            refused = f"driver refused ({str(e).split('.')[0]})"
        except sqlite3.DatabaseError as e:                      # OperationalError ("interrupted") is a subclass
            if str(e) == "interrupted":
                killed = gate is not engine_gate
                refused = "step budget exceeded (interrupted)"
            else:
                refused = f"engine refused ({e})"
        return refused, damage(folder, db, rows, killed), len(rows)
    finally:
        os.chdir(HOME)
        shutil.rmtree(folder, ignore_errors=True)


def main():
    gates = [("naive SELECT/WITH prefix", naive_gate), ("keyword denylist", denylist_gate), ("engine-enforced", engine_gate)]
    for name, gate in gates:
        print(f"== {name} ==")
        harmed = blocked_benign = 0
        for label, sql, benign in ATTACKS:
            refused, harm, n = run(gate, label, sql)
            if benign:
                verdict = f"FALSE POSITIVE: {refused}" if refused else f"ok, {n} row(s)"
                blocked_benign += bool(refused)
            elif harm:
                verdict = "HARM: " + ", ".join(harm)
                harmed += 1
            else:
                verdict = f"blocked: {refused or 'no effect'}"
            print(f"  {label:<24} {verdict}")
        attacks = sum(not benign for _, _, benign in ATTACKS)
        print(f"  -> {harmed}/{attacks} attacks did damage, {blocked_benign}/3 benign queries refused\n")


if __name__ == "__main__":
    main()
```

**Output (verified):**

```text
== naive SELECT/WITH prefix ==
  benign: filtered read    ok, 2 row(s)
  benign: text search      ok, 1 row(s)
  benign: aggregate CTE    ok, 1 row(s)
  stacked statement        HARM: 3 orders DELETED
  comment-smuggled drop    HARM: orders DROPPED
  CTE-prefixed write       HARM: 3 orders DELETED
  attach + copy out        HARM: customers copied to loot.db
  out-of-scope read        HARM: SSNs returned
  runaway recursion        HARM: runaway: harness killed it
  cartesian blow-up        HARM: runaway: harness killed it
  -> 7/7 attacks did damage, 0/3 benign queries refused

== keyword denylist ==
  benign: filtered read    ok, 2 row(s)
  benign: text search      FALSE POSITIVE: gate refused (write keyword)
  benign: aggregate CTE    ok, 1 row(s)
  stacked statement        blocked: gate refused (write keyword)
  comment-smuggled drop    blocked: gate refused (write keyword)
  CTE-prefixed write       blocked: gate refused (write keyword)
  attach + copy out        blocked: gate refused (write keyword)
  out-of-scope read        HARM: SSNs returned
  runaway recursion        HARM: runaway: harness killed it
  cartesian blow-up        HARM: runaway: harness killed it
  -> 3/7 attacks did damage, 1/3 benign queries refused

== engine-enforced ==
  benign: filtered read    ok, 2 row(s)
  benign: text search      ok, 1 row(s)
  benign: aggregate CTE    ok, 1 row(s)
  stacked statement        blocked: driver refused (You can only execute one statement at a time)
  comment-smuggled drop    blocked: driver refused (You can only execute one statement at a time)
  CTE-prefixed write       blocked: engine refused (not authorized)
  attach + copy out        blocked: driver refused (You can only execute one statement at a time)
  out-of-scope read        blocked: engine refused (access to customers.email is prohibited)
  runaway recursion        blocked: step budget exceeded (interrupted)
  cartesian blow-up        blocked: step budget exceeded (interrupted)
  -> 0/7 attacks did damage, 0/3 benign queries refused
```

The denylist row is the one to remember. It looks safe in review, because it blocks every write keyword. Yet it still leaks the PII table, can't stop a cartesian join, and annoys users with false refusals. Every control that worked lives in the engine or the credentials.

---

## 4. Failure modes

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| F1 | "Read-only" DB server deleted rows | Read-only enforced by SQL text; the driver ran stacked statements | Role with SELECT grants only; replica (L1) |
| F2 | Agent query took the orders table down during a migration | Long `SELECT` held `ACCESS SHARE`; the migration and everything after it queued | `statement_timeout`, `lock_timeout` on `mcp_ro` |
| F3 | Customer emails in a transcript | Table-level grant on `customers` | Column grants or a view (L1 "out-of-scope read") |
| F4 | Context full after one query | No row cap | Server-side `LIMIT`/row limit; a narrow `describe_table` tool (file 03) |
| F5 | Agent opened a PR leaking private code | Broad PAT plus untrusted issue content plus write tools | `/readonly`, toolsets, a repo-scoped fine-grained PAT |
| F6 | Lockdown on, injection still worked | Lockdown is a best-effort filter | Remove write tools; narrow the token |
| F7 | A Docker-hosted server could read `~/.ssh` | The profile mounted the home directory or the socket | No socket, minimal mounts, pinned images |
| F8 | Docs answer describes Boot 3 APIs | Version not specified; the popular version was served | Version in the prompt; verify against the jar (`javap`) |
| F9 | Teammate's agent can merge PRs | Their local-scope `github` entry overrides the project's read-only one | MC11 lint; deny rules for merges and deletes |

---

## 5. Staff-level drills

<details><summary><b>D1 · "DBHub has a read-only mode. Why do we also need a role?"</b></summary>

**Naive answer.** We don't; the flag blocks writes.

**Why it fails.** A server-side mode is code that inspects or wraps your SQL, and you can't verify it from the outside. L1 shows how easy SQL-text gates are to get subtly wrong. Even a correct implementation can't stop PII reads or runaway joins without a grant model and a time budget.

**Staff answer.** Use three layers, each sufficient on its own for writes:
1. a SELECT-only role on a replica (the boundary);
2. the server's read-only mode and row limit (defence in depth);
3. an `ask` rule on `execute_sql` until the role is audited.

Add `statement_timeout` and `lock_timeout` for availability, and column grants for privacy.
</details>

<details><summary><b>D2 · "Can we let Claude open PRs through the GitHub server?"</b></summary>

**Staff answer.** Yes, in a session that doesn't also read untrusted content with private-repo access. Separate the legs of the trifecta:
- a **triage** profile: read-only, all repos, reads public issues;
- an **authoring** profile: write tools, a token for *one* repo, no public-issue reading.

Often the cleaner path is Claude Code's own `git` and `gh` in the working tree, under Folder 05's hooks, rather than MCP write tools.
</details>

<details><summary><b>D3 · "Why put third-party servers behind the Docker gateway instead of <code>npx</code>?"</b></summary>

**Staff answer.**
- `npx -y` fetches and runs a package on the host with your user's permissions, every start. Pinning (MC07) fixes the version, not the blast radius.
- The gateway runs each server in a container with restricted network and resources, holds the secrets, enables tools individually, and logs every call.

The cost is a Docker dependency on every laptop and CI runner. For your own first-party server (file 03), run it directly: you own its code.
</details>

<details><summary><b>D4 · "How do we give the agent production visibility without production risk?"</b></summary>

**Staff answer.**
- A read replica.
- An `mcp_ro` role with column grants, `statement_timeout`, and no write, sequence or function privileges.
- Credentials from the engineer's environment or secret manager, never `.mcp.json`.
- Row caps, `ask` on SQL at first.
- Audit logging on the role (`log_statement` for it, or pgaudit).

For aggregated, already-sanitised views, prefer an internal read-only API exposed through your own MCP server (file 03) over raw SQL.
</details>

---

## 6. Checklist

- [ ] Each server chosen by provenance, version-pinned, and added through a reviewed `.mcp.json` change.
- [ ] Database: dedicated SELECT-only role, column grants around PII, `statement_timeout` plus `lock_timeout`, replica DSN from the environment.
- [ ] GitHub: `/readonly` (or the header), explicit toolsets, fine-grained repo-scoped token; deny merge and delete anyway.
- [ ] Third-party servers behind the Docker gateway with a profile; no socket or home mounts.
- [ ] Docs queries name the version; generated code verified by the compiler.
- [ ] No session combines private data, untrusted content and write tools without a human `ask` in between.

---

## 7. References

- Claude Code MCP docs (GitHub and PostgreSQL examples, Sentry, connectors, permissions): <https://code.claude.com/docs/en/mcp>
- Configure permissions (MCP rule names; globs): <https://code.claude.com/docs/en/permissions>
- GitHub MCP Server, remote server (read-only, toolsets, lockdown): <https://github.com/github/github-mcp-server/blob/main/docs/remote-server.md>
- GitHub MCP Server README (tool list, default toolsets): <https://github.com/github/github-mcp-server>
- Docker MCP Gateway: <https://docs.docker.com/ai/mcp-catalog-and-toolkit/mcp-gateway/> and <https://github.com/docker/mcp-gateway>
- Context7: <https://github.com/upstash/context7>
- DBHub: <https://github.com/bytebase/dbhub>
- PostgreSQL: privileges <https://www.postgresql.org/docs/current/ddl-priv.html>, client settings (`default_transaction_read_only`, `statement_timeout`, `lock_timeout`) <https://www.postgresql.org/docs/current/runtime-config-client.html>, explicit locking <https://www.postgresql.org/docs/current/explicit-locking.html>, predefined roles <https://www.postgresql.org/docs/current/predefined-roles.html>
- Simon Willison, "The lethal trifecta for AI agents": <https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/>
- Invariant Labs, GitHub MCP toxic agent flow: <https://invariantlabs.ai/blog/mcp-github-vulnerability>

Previous: [01 · MCP client configuration](01-mcp-client-configuration-stdio-vs-sse-http-and-preventing-tool-schema-bloat.md) · Next: [03 · Building a custom MCP server](03-building-a-custom-mcp-server-in-java-spring-ai-and-python-fastmcp.md) · [KB README](../README.md)

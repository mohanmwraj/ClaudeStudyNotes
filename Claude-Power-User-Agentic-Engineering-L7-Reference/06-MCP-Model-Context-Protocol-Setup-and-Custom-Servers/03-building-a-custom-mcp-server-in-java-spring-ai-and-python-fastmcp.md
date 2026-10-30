# Building a Custom MCP Server in Java (MCP SDK and Spring AI) and Python (MCPServer, formerly FastMCP)

> **Folder 06 · File 3 of 3** · verified 2026-10-30 by running all three servers under one conformance client.
> **Libraries:** `mcp` 2.3.0 (Python SDK); `io.modelcontextprotocol.sdk:mcp` 2.1.0 (Java SDK); Spring AI 2.0.2 on Spring Boot 4.1.2 (52 resolved jars). APIs were taken from the installed packages (Python source, `javap`), not from memory.
> **Listings:** `order_platform_mcp.py`, `OrderPlatformMcpServer.java`, `OrderPlatformSpringMcp.java`, `mcp_stdio_conformance.py`.

---

## 0. Orientation

The servers in file 02 give Claude other people's systems. The most valuable server for a Java monorepo is usually your own: a small, read-only server that answers the questions only your repo can answer.

The brief asks for three tools:
- `architecture_rules(topic)`: the team's rules for persistence, messaging and testing, from `.claude/rules/`;
- `describe_table(table)`: a table as the Flyway migrations define it, with no database connection and no credentials;
- `build_health()`: totals and failing classes from the last `surefire-reports`.

Plus one prompt, `review_migration`, which appears as `/mcp__order-platform__review_migration`.

The same contract is built three ways:

| | L1 Python | L2 plain Java | L3 Spring |
|---|---|---|---|
| Stack | official Python SDK, `MCPServer` | official Java SDK, no framework | Spring AI's MCP server starter on Boot 4.1 |
| Fits | you want it in about 100 lines | you want a single-file, framework-free JAR | the knowledge lives in Spring beans you already have |

L4 is a stdlib-only MCP client of about 220 lines that speaks raw JSON-RPC to all three. It checks the behaviours Claude Code depends on and confirms the three return identical structured results.

**Naming.** The brief says "Python FastMCP". The official SDK's high-level server was `mcp.server.fastmcp.FastMCP` in 1.x. In `mcp` 2.x it is **`MCPServer`** in `mcp.server.mcpserver`; `mcp.server.fastmcp` no longer exists in 2.3.0 [measured]. The separately maintained `fastmcp` package is a different project with its own API.

### 0.1 The twelve rules

1. **stdout is the protocol.** One stray line corrupts the JSON-RPC stream.
   - A single `print()` banner produced 1 junk line. Spring Boot's defaults produced **23**: the banner plus console logs.
   - For Spring stdio servers: `spring.main.web-application-type=none`, `spring.main.banner-mode=off`, `logging.pattern.console=` (empty), and a log file. [measured: L4]
2. **Errors the model should read are tool results with `isError: true`.** A protocol error is the wrong channel.
   - Python `mcp` 2.x: `raise ToolError(...)`. **Any other exception reaches the model as just `Error executing tool <name>`**, and your message is lost.
   - Java SDK: return `CallToolResult.builder().isError(true)`.
   - Spring AI: a thrown exception becomes `isError`, though 2.0.2 repeats the message twice. [measured: L4]
3. **Unknown-tool handling differs by SDK.** Python returns an `isError` result naming the tool. The Java SDK and Spring AI return JSON-RPC `-32602 "Unknown tool: invalid_tool_name"`, which does not name it. Don't write clients or tests that assume one. [measured: L4]
4. **Return structured output with an `outputSchema` for data tools.**
   - Python: a `TypedDict` return type generates it.
   - Java SDK: `outputSchema(...)` plus `structuredContent(...)` plus a JSON text fallback.
   - Spring AI: a record plus `generateOutputSchema = true`. [measured]
5. **Spring AI needs `javac -parameters`.** Without it the input schema says `arg0`, and every real call fails validation (`required property 'arg0' not found`). `spring-boot-starter-parent` sets it; a hand-rolled pom must too. [measured]
6. **In Spring AI 2.0.2, a `String`-returning `@McpPrompt` renders as an *assistant* message.** A slash-command prompt must be a user message, so return a `GetPromptResult` with `Role.USER`. [measured: L4 caught it]
7. **Compile the Java SDK server with `-Xlint:all -Werror`.** SDK 2.1.0 deprecated `Tool.builder()` and the `Prompt`, `PromptArgument`, `GetPromptResult` and `TextContent` constructors. The replacements are `Tool.builder(name, mapper, schema)`, `Prompt.builder(name)` and similar. `-Werror` caught five deprecations on the first compile. [measured]
8. **Exit promptly on stdin EOF.** On Windows, Claude Code closes stdin and kills the process tree 300 ms later; macOS and Linux get SIGINT, then SIGTERM, then SIGKILL. All three servers exit within 300 ms. [doc + measured]
9. **Read the project root from `CLAUDE_PROJECT_DIR`**, which Claude Code sets in a stdio server's environment. A server that restricts itself to allowed directories should use `roots/list`, though see rule 12. [doc]
10. **Annotate tools honestly** (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`). They are hints to the client. Being read-only is your code's job, and file 02's permission rules are the user's control. [doc: MCP spec + inference]
11. **Design for tool search.**
    - Server instructions say what and when, keywords first, under 4,096 chars.
    - Few tools, each with a narrow output.
    - `describe_table` returns one table, not the schema.

    [doc + file 01]
12. **Let the SDK negotiate the protocol version.**
    - All three negotiated **2025-11-25** through `initialize`.
    - Python `mcp` 2.3.0 *also* answers the stateless **2026-07-28** revision (`server/discover` with a `_meta` envelope).
    - Java SDK 2.1.0 and Spring AI 2.0.2 return `-32601`.

    In 2026-07-28, the Python SDK source marks `roots` and `sampling` as deprecated and removes `ping` and `resources/subscribe`. [measured + research: SDK source]

---

## 1. First principles

### 1.1 What a stdio MCP server is on the wire [doc: MCP spec + measured]

A stdio server is a child process. It reads newline-delimited JSON-RPC 2.0 from stdin and writes responses to stdout; stderr is free for logs. A session (revision 2025-11-25) runs:

```text
-> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2026-07-28","capabilities":{...},"clientInfo":{...}}}
<- {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{"tools":{...},"prompts":{...}},"serverInfo":{...},"instructions":"..."}}
-> {"jsonrpc":"2.0","method":"notifications/initialized"}
-> {"jsonrpc":"2.0","id":2,"method":"tools/list"}
-> {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"describe_table","arguments":{"table":"orders"}}}
<- {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"{...}"}],"structuredContent":{...},"isError":false}}
```

The client asks for the newest revision it knows, and the server answers with the newest one it speaks: here both asked 2026-07-28 and got 2025-11-25. The server may also send requests the other way (`ping`, `roots/list`), so a client's read loop has to answer those.

L4 implements all of this in about 220 lines of stdlib Python. The protocol is small enough that a hand-rolled client is the best test harness you can have.

### 1.2 Designing the tool surface [inference + file 01]

**Read-only, no credentials.** All three tools read files in the repo. That removes the private-data and egress legs of file 02's trifecta, and the server needs no secret.

**The schema "as migrations define it", not a live connection.**
- It works offline, in CI and in code review.
- It shows what the code will run against *after* the pending migrations, which a dev database often doesn't.
- It gets Flyway ordering right: V10 runs after V2, and a lexical sort would put it first. L4's fixture includes `V10__add_shipped_at.sql`, and the check requires `defined_in` in migration order.
- The regex parser is deliberately simple; it is a model of the idea, not a SQL parser. Swap in a real parser (JSqlParser) or Flyway's own `MigrationInfoService` when your DDL goes beyond `create table` and `alter table … add column`.

**Narrow outputs.** One table, one topic, one summary. Each result is a few hundred tokens, far below the 10K warning and 25K cap.

**Descriptions that say when.** "Describe a table as the applied Flyway migrations define it: columns, nullability, indexes, defining files." Tool search matches on the start of the description.

### 1.3 Error semantics: three SDKs, measured [measured: L4]

| Situation | Python `mcp` 2.3.0 | Java SDK 2.1.0 | Spring AI 2.0.2 |
|---|---|---|---|
| Anticipated failure | `raise ToolError(msg)` → `isError`, text `Error executing tool X: msg` | return `isError(true)` + text → exactly `msg` | `throw` → `isError`, text `msg\r\nmsg` |
| Any other exception | `isError`, text **only** `Error executing tool X`; traceback logged to stderr | your catch decides; uncaught means a protocol error | `isError` with the message |
| Unknown tool | `isError` result `Unknown tool: drop_table` | JSON-RPC `-32602` `Unknown tool: invalid_tool_name` | same as the Java SDK |
| Missing required argument | `isError`, pydantic validation text | `isError`, `input validation failed …` (`validateToolInputs(true)`) | same as the Java SDK |

The first-draft Python server raised `ValueError`. The model got `Error executing tool architecture_rules` and no list of the available topics, so it couldn't recover. Switching to `ToolError` gave it `… no rules for 'security'; available: messaging, persistence`. This is the single most common custom-server bug: the server works, and the model is blind to why it failed.

### 1.4 Structured output: what each SDK emits [measured]

| | Python | Java SDK | Spring AI |
|---|---|---|---|
| Data tools (`describe_table`, `build_health`) | `TypedDict` generates the `outputSchema`; `structuredContent` plus indented JSON text | you write the `outputSchema` JSON; `structuredContent(map)` plus `writeValueAsString` text | the record generates it (`$schema` 2020-12, `int32` formats; **lists omitted from `required`**); `structuredContent` plus compact JSON |
| `str`-returning tool | wrapped: `outputSchema {"result": string}` | text only | text only |
| Field naming | `TypedDict` keys | `LinkedHashMap` keys, insertion order | record components; `@JsonProperty("defined_in")` for snake_case |

L4 compares `structuredContent` across the three, and it is identical (3/3 for each pair).

One trap [measured, separate probe]: **a Python tool annotated `-> dict` generates no output schema.** Use a `TypedDict`.

The same probe also tested the folklore that `from __future__ import annotations` breaks schema generation. In `mcp` 2.3.0 it doesn't: the input and output schemas were identical with and without it, for a module-level `TypedDict`.

### 1.5 Protocol revisions: 2025-11-25 vs 2026-07-28 [measured + research]

Probing each server with `server/discover` and the `_meta` envelope (`io.modelcontextprotocol/protocolVersion`, `io.modelcontextprotocol/clientCapabilities`):
- **Python `mcp` 2.3.0** answers `supportedVersions ['2026-07-28']`, with caching hints (`cacheScope`, `ttlMs`) on results.
- **Java SDK 2.1.0 and Spring AI 2.0.2** answer `-32601 Method not found`.

All three speak 2025-11-25 through `initialize`.

From the Python SDK's own source, 2026-07-28:
- is stateless: no `notifications/initialized`;
- removes `ping` and `resources/subscribe` in favour of `subscriptions/listen` (SEP-2575);
- deprecates `roots` and `sampling` (SEP-2577);
- adds response caching (SEP-2549).

What this means for you:
1. Don't pin a protocol version in server code; the SDKs negotiate.
2. Which revision a given Claude Code build negotiates wasn't observed here. ⚠ Verify with a logging proxy (L4's `StdioClient` wrapped around your server) before you depend on 2026-07-28 features.
3. Prefer `CLAUDE_PROJECT_DIR` over `roots/list` for "where is the repo". Claude Code documents `roots/list` today, but the newer revision deprecates the capability.

### 1.6 Which of the three to choose [measured + inference]

| | Python `MCPServer` | Java MCP SDK | Spring AI starter |
|---|---|---|---|
| Lines for this server (incl. comments) | 112 | 223 | 183 |
| Dependencies | `mcp` (+ pydantic, anyio, …) | `mcp` 2.1.0 + Jackson 3 + reactor; `slf4j-nop` | 52 jars (Boot 4.1.2, Spring 7, Spring AI 2.0.2, MCP SDK 2.1.0) |
| Schemas | from type hints | hand-written JSON | from method parameters (`-parameters`) and records |
| Time to `initialize` response | not timed | not timed | **~3.2 s** (one measurement) |
| Reuses your code | no (another language) | your plain Java classes | your Spring beans: repositories, services, `@ConfigurationProperties` |
| Pick it when | the knowledge is files and scripts | you want a small, framework-free JAR | the knowledge lives in a Spring app you already run, or you need the HTTP transport with Spring Security |

For remote (HTTP) servers, the Spring AI 2.0.2 BOM has `spring-ai-starter-mcp-server-webmvc` and `-webflux` [doc: BOM]. Metadata shows `spring.ai.mcp.server.protocol` defaults to `streamable` and the endpoint to `/mcp`. Then the standard Spring Security, OAuth2 resource-server and rate-limiting tooling applies, and Claude Code connects with `--transport http` and OAuth.

---

## 2. Practice

### 2.1 Register each implementation

```bash
# Python (pin the SDK: pip install "mcp==2.3.0")
claude mcp add --transport stdio --scope project order-platform -- python tools/mcp/order_platform_mcp.py

# Java SDK (a shaded JAR in practice; here the class plus its classpath)
claude mcp add --transport stdio --scope project order-platform -- java -cp "tools/mcp/order-platform-mcp.jar" OrderPlatformMcpServer

# Spring AI (Boot fat JAR)
claude mcp add --transport stdio --scope project order-platform -- java -jar tools/mcp/order-platform-mcp-spring.jar
```

In `.mcp.json`, write project-relative paths as `${CLAUDE_PROJECT_DIR:-.}/tools/mcp/…` (file 01 MC05). Add `"timeout": 60000`.

### 2.2 Maven: what resolved here, plus the compiler flag

```xml
<!-- Resolved in this KB's harness: 52 jars (dependency:build-classpath). The compiler block is standard Maven, not run here. -->
<dependencyManagement>
  <dependencies>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-dependencies</artifactId>
      <version>4.1.2</version><type>pom</type><scope>import</scope></dependency>
    <dependency><groupId>org.springframework.ai</groupId><artifactId>spring-ai-bom</artifactId>
      <version>2.0.2</version><type>pom</type><scope>import</scope></dependency>
  </dependencies>
</dependencyManagement>
<dependencies>
  <dependency><groupId>org.springframework.ai</groupId><artifactId>spring-ai-starter-mcp-server</artifactId></dependency>
</dependencies>
<build><plugins>
  <plugin><groupId>org.apache.maven.plugins</groupId><artifactId>maven-compiler-plugin</artifactId>
    <configuration><release>21</release><parameters>true</parameters></configuration></plugin>  <!-- rule 5 -->
</plugins></build>
```

For the plain Java SDK server: `io.modelcontextprotocol.sdk:mcp:2.1.0` plus `org.slf4j:slf4j-nop:2.0.17`, or a logback configuration with only a file appender.

### 2.3 Spring's stdio properties (`application.properties`; L3 sets the same as defaults in code)

```properties
spring.main.web-application-type=none
spring.main.banner-mode=off
logging.pattern.console=
logging.file.name=${java.io.tmpdir}/order-platform-mcp.log
spring.ai.mcp.server.stdio=true
spring.ai.mcp.server.name=order-platform
spring.ai.mcp.server.instructions=Read-only project knowledge for order-platform: architecture rules, the schema as Flyway migrations define it, and the last build's test results. Use before designing or reviewing changes.
```

The starter's own metadata gives `spring.ai.mcp.server.stdio` as `false` by default. Forget it, and the server never reads stdin.

### 2.4 Make L4 your server's CI gate

```bash
# fails the job on stdout pollution, swallowed errors, a non-user prompt, or a slow exit
python mcp_stdio_conformance.py > conformance.txt
! sed '/negative control/,$d' conformance.txt | grep '^  FAIL'     # the negative controls are expected to FAIL
```

In your own repo, delete the negative controls, and assert on what your tools must return for your fixture project.

### 2.5 Asking Claude to add a tool (a prompt that respects the rules above)

```xml
<task>Add a read-only tool `outbox_backlog()` to tools/mcp/order_platform_mcp.py.</task>
<contract>
  Reads target/outbox-metrics.json (written by OutboxRelayIT). Returns TypedDict {pending:int, oldest_age_s:int, by_type:dict[str,int]}.
  Missing file -> raise ToolError naming the file and the test that writes it. Never print to stdout.
</contract>
<verify>Extend the FIXTURE in mcp_stdio_conformance.py with an outbox-metrics.json and a check row; run it; paste the output.</verify>
```

---

## 3. Verified listings

L1–L3 are servers: they block on stdin, so they have no output of their own. L4 runs them, and its output is the verification for all four.

### L1 · `order_platform_mcp.py` (Python, `mcp` 2.x `MCPServer`)

**What it shows.**
- Three read-only tools with `ToolAnnotations` and `TypedDict` structured output.
- `ToolError` for failures the model must read.
- A prompt.
- `CLAUDE_PROJECT_DIR` for the root, and stderr-only logging.

**What it does not show.** Resources (`@mcp.resource(...)`), progress and logging notifications, or the HTTP transport (`mcp.run("streamable-http")`).

```python
"""order_platform_mcp.py - a read-only MCP server (official Python SDK `mcp` 2.x, MCPServer - formerly FastMCP)
that gives Claude the project knowledge it can't see in one file: architecture rules, the database schema as the
Flyway migrations define it (no DB connection, no credentials), and build health from surefire reports.

Run under Claude Code:  claude mcp add --transport stdio order-platform -- python order_platform_mcp.py
The project root comes from CLAUDE_PROJECT_DIR, which Claude Code sets in a stdio server's environment.
Rules for stdio servers: NEVER print to stdout (it is the JSON-RPC channel) - log to stderr.
Return TypedDicts, not `-> dict`: a bare dict return type generates no outputSchema (measured, mcp 2.3.0).
Raise ToolError for failures the model should read; any other exception reaches it as just 'Error executing tool <name>'.
"""
import os
import pathlib
import re
import sys
from typing import TypedDict

from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError
from mcp.types import ToolAnnotations

ROOT = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR", ".")).resolve()
MIGRATIONS_DIR = "src/main/resources/db/migration"
MIGRATIONS = ROOT / MIGRATIONS_DIR
READ_ONLY = ToolAnnotations(readOnlyHint=True, destructiveHint=False, idempotentHint=True, openWorldHint=False)

mcp = MCPServer(
    name="order-platform",
    instructions="Read-only project knowledge for order-platform: architecture rules, the schema as Flyway "
                 "migrations define it, and the last build's test results. Use before designing or reviewing changes.",
)


class Column(TypedDict):
    name: str
    type: str
    nullable: bool


class TableInfo(TypedDict):
    table: str
    defined_in: list[str]
    columns: list[Column]
    indexes: list[str]


class BuildHealth(TypedDict):
    reports: int
    tests: int
    failures: int
    errors: int
    failing_classes: list[str]


@mcp.tool(annotations=READ_ONLY)
def architecture_rules(topic: str) -> str:
    """Return the team's rules for a topic (e.g. persistence, messaging, testing) from .claude/rules/<topic>.md."""
    rule = ROOT / ".claude" / "rules" / f"{re.sub(r'[^a-z0-9-]', '', topic.lower())}.md"
    if not rule.exists():
        available = sorted(p.stem for p in (ROOT / ".claude" / "rules").glob("*.md"))
        raise ToolError(f"no rules for '{topic}'; available: {', '.join(available) or 'none'}")
    text = rule.read_text(encoding="utf-8")
    return re.sub(r"^---\n.*?\n---\n", "", text, flags=re.S).strip()        # drop the paths: frontmatter


@mcp.tool(annotations=READ_ONLY)
def describe_table(table: str) -> TableInfo:
    """Describe a table as the applied Flyway migrations define it: columns, nullability, indexes, defining files."""
    columns, indexes, files = [], [], []
    for sql in sorted(MIGRATIONS.glob("V*__*.sql"), key=lambda p: int(re.match(r"V(\d+)", p.name).group(1))):
        text = sql.read_text(encoding="utf-8")
        for body in re.findall(rf"create\s+table\s+{re.escape(table)}\s*\((.*?)\)\s*;", text, re.I | re.S):
            files.append(sql.name)
            for col in re.split(r",(?![^(]*\))", body):
                m = re.match(r"\s*(\w+)\s+([\w]+(?:\(\d+(?:,\s*\d+)?\))?)(.*)", col, re.S)
                if m and m.group(1).lower() not in ("primary", "constraint", "unique", "foreign"):
                    columns.append(Column(name=m.group(1), type=m.group(2),
                                          nullable="not null" not in m.group(3).lower() and "primary key" not in m.group(3).lower()))
        for m in re.finditer(rf"alter\s+table\s+{re.escape(table)}\s+add\s+column\s+(\w+)\s+([\w()]+)(.*?);", text, re.I | re.S):
            files.append(sql.name)
            columns.append(Column(name=m.group(1), type=m.group(2), nullable="not null" not in m.group(3).lower()))
        indexes += re.findall(rf"create\s+(?:unique\s+)?index\s+(\w+)\s+on\s+{re.escape(table)}\b", text, re.I)
    if not columns:
        raise ToolError(f"table '{table}' is not created by any migration in {MIGRATIONS_DIR}")
    return TableInfo(table=table, defined_in=list(dict.fromkeys(files)), columns=columns, indexes=indexes)


@mcp.tool(annotations=READ_ONLY)
def build_health() -> BuildHealth:
    """Summarise the last test run from target/surefire-reports (all modules): totals and failing test classes."""
    tests = failures = errors = reports = 0
    failing = []
    for report in ROOT.glob("**/target/surefire-reports/*.txt"):
        m = re.search(r"Tests run: (\d+), Failures: (\d+), Errors: (\d+)", report.read_text(encoding="utf-8", errors="replace"))
        if m:
            reports += 1
            t, f, e = map(int, m.groups())
            tests, failures, errors = tests + t, failures + f, errors + e
            if f or e:
                failing.append(report.stem)
    return BuildHealth(reports=reports, tests=tests, failures=failures, errors=errors, failing_classes=sorted(failing))


@mcp.prompt()
def review_migration(file: str) -> str:
    """Review a Flyway migration against the persistence rules."""
    return (f"Review {file} against architecture_rules('persistence'). Check: immutability of applied versions, an index for "
            "every foreign key, backward compatibility with the previous release, and lock duration on large tables.")


if __name__ == "__main__":
    print(f"order-platform MCP server for {ROOT}", file=sys.stderr)      # stderr only: stdout is the protocol
    mcp.run("stdio")
```

### L2 · `OrderPlatformMcpServer.java` (MCP Java SDK 2.1.0, no framework)

**What it shows.**
- `McpServer.sync(new StdioServerTransportProvider(mapper))` with server info, instructions and capabilities.
- `validateToolInputs(true)`.
- Hand-written input and output schemas, `structuredContent` plus a text fallback, and `isError` results.
- Non-deprecated builders throughout (clean under `-Xlint:all -Werror`).
- `LinkedHashMap`, so the JSON key order matches Python's.

**What it does not show.** The async API (`McpServer.async`), the streamable HTTP transport provider, or resource templates.

```java
// OrderPlatformMcpServer.java - the order-platform server on the official MCP Java SDK 2.1.0 (io.modelcontextprotocol.sdk:mcp,
// the library under Spring AI's MCP server starters), stdio transport, plain Java 21, no framework.
// Same three read-only tools as order_platform_mcp.py; mcp_stdio_conformance.py checks that both answer identically.
// Run: java -cp "classes;<mcp 2.1.0 classpath>" OrderPlatformMcpServer   (Claude Code sets CLAUDE_PROJECT_DIR)
// stdout IS the JSON-RPC channel: no System.out, and no logging backend that writes to stdout (slf4j-nop or a file appender).
import io.modelcontextprotocol.json.McpJsonDefaults;
import io.modelcontextprotocol.json.McpJsonMapper;
import io.modelcontextprotocol.server.McpServer;
import io.modelcontextprotocol.server.McpServerFeatures.SyncPromptSpecification;
import io.modelcontextprotocol.server.McpServerFeatures.SyncToolSpecification;
import io.modelcontextprotocol.server.McpSyncServer;
import io.modelcontextprotocol.server.transport.StdioServerTransportProvider;
import io.modelcontextprotocol.spec.McpSchema.CallToolResult;
import io.modelcontextprotocol.spec.McpSchema.GetPromptResult;
import io.modelcontextprotocol.spec.McpSchema.Prompt;
import io.modelcontextprotocol.spec.McpSchema.PromptArgument;
import io.modelcontextprotocol.spec.McpSchema.PromptMessage;
import io.modelcontextprotocol.spec.McpSchema.Role;
import io.modelcontextprotocol.spec.McpSchema.ServerCapabilities;
import io.modelcontextprotocol.spec.McpSchema.TextContent;
import io.modelcontextprotocol.spec.McpSchema.Tool;
import io.modelcontextprotocol.spec.McpSchema.ToolAnnotations;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.SequencedSet;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.Stream;

public final class OrderPlatformMcpServer {
    static final Path ROOT = Path.of(System.getenv().getOrDefault("CLAUDE_PROJECT_DIR", ".")).toAbsolutePath().normalize();
    static final String MIGRATIONS_DIR = "src/main/resources/db/migration";
    static final McpJsonMapper JSON = McpJsonDefaults.getMapper();
    static final ToolAnnotations READ_ONLY = ToolAnnotations.builder()
            .readOnlyHint(true).destructiveHint(false).idempotentHint(true).openWorldHint(false).build();
    static final int FLAGS = Pattern.CASE_INSENSITIVE | Pattern.DOTALL;

    @FunctionalInterface
    interface Handler { Object apply(Map<String, Object> args) throws IOException; }

    /** One tool = schema + handler. A domain failure is an isError result the model can read and recover from. */
    static SyncToolSpecification tool(String name, String description, String inputSchema, String outputSchema, Handler handler) {
        Tool.Builder tool = Tool.builder(name, JSON, inputSchema).description(description).annotations(READ_ONLY);
        if (outputSchema != null) {
            tool.outputSchema(JSON, outputSchema);
        }
        return SyncToolSpecification.builder().tool(tool.build()).callHandler((exchange, request) -> {
            try {
                Object result = handler.apply(request.arguments() == null ? Map.of() : request.arguments());
                return result instanceof String text
                        ? CallToolResult.builder().addTextContent(text).build()
                        : CallToolResult.builder().addTextContent(JSON.writeValueAsString(result)).structuredContent(result).build();
            } catch (IllegalArgumentException | IOException e) {
                return CallToolResult.builder().addTextContent(e.getMessage()).isError(true).build();
            }
        }).build();
    }

    static String architectureRules(Map<String, Object> args) throws IOException {
        String topic = String.valueOf(args.get("topic"));
        Path rules = ROOT.resolve(".claude/rules");
        Path rule = rules.resolve(topic.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9-]", "") + ".md");
        if (!Files.exists(rule)) {
            String available = "none";
            if (Files.isDirectory(rules)) {
                try (Stream<Path> files = Files.list(rules)) {
                    available = files.map(p -> p.getFileName().toString()).filter(n -> n.endsWith(".md"))
                            .map(n -> n.substring(0, n.length() - 3)).sorted().collect(Collectors.joining(", "));
                }
            }
            throw new IllegalArgumentException("no rules for '" + topic + "'; available: " + (available.isEmpty() ? "none" : available));
        }
        return Files.readString(rule).replaceFirst("(?s)^---\n.*?\n---\n", "").strip();   // drop the paths: frontmatter
    }

    static Map<String, Object> describeTable(Map<String, Object> args) throws IOException {
        String table = String.valueOf(args.get("table"));
        String t = Pattern.quote(table);
        Pattern create = Pattern.compile("create\\s+table\\s+" + t + "\\s*\\((.*?)\\)\\s*;", FLAGS);
        Pattern alter = Pattern.compile("alter\\s+table\\s+" + t + "\\s+add\\s+column\\s+(\\w+)\\s+([\\w()]+)(.*?);", FLAGS);
        Pattern index = Pattern.compile("create\\s+(?:unique\\s+)?index\\s+(\\w+)\\s+on\\s+" + t + "\\b", Pattern.CASE_INSENSITIVE);
        Pattern column = Pattern.compile("\\s*(\\w+)\\s+(\\w+(?:\\(\\d+(?:,\\s*\\d+)?\\))?)(.*)", Pattern.DOTALL);
        List<Map<String, Object>> columns = new ArrayList<>();
        List<String> indexes = new ArrayList<>();
        SequencedSet<String> definedIn = new LinkedHashSet<>();     // migration order, not file-name order
        Path migrations = ROOT.resolve(MIGRATIONS_DIR);
        List<Path> sqls = List.of();
        if (Files.isDirectory(migrations)) {
            try (Stream<Path> files = Files.list(migrations)) {
                sqls = files.filter(p -> p.getFileName().toString().matches("V\\d+__.*\\.sql"))
                        .sorted(Comparator.comparingInt(p -> Integer.parseInt(p.getFileName().toString().replaceAll("^V(\\d+).*", "$1"))))
                        .toList();
            }
        }
        for (Path sql : sqls) {
            String text = Files.readString(sql);
            Matcher m = create.matcher(text);
            while (m.find()) {
                definedIn.add(sql.getFileName().toString());
                for (String col : m.group(1).split(",(?![^(]*\\))")) {
                    Matcher c = column.matcher(col);
                    if (c.matches() && !Set.of("primary", "constraint", "unique", "foreign").contains(c.group(1).toLowerCase(Locale.ROOT))) {
                        String rest = c.group(3).toLowerCase(Locale.ROOT);
                        columns.add(column(c.group(1), c.group(2), !rest.contains("not null") && !rest.contains("primary key")));
                    }
                }
            }
            Matcher a = alter.matcher(text);
            while (a.find()) {
                definedIn.add(sql.getFileName().toString());
                columns.add(column(a.group(1), a.group(2), !a.group(3).toLowerCase(Locale.ROOT).contains("not null")));
            }
            Matcher i = index.matcher(text);
            while (i.find()) {
                indexes.add(i.group(1));
            }
        }
        if (columns.isEmpty()) {
            throw new IllegalArgumentException("table '" + table + "' is not created by any migration in " + MIGRATIONS_DIR);
        }
        Map<String, Object> info = new LinkedHashMap<>();
        info.put("table", table);
        info.put("defined_in", List.copyOf(definedIn));
        info.put("columns", columns);
        info.put("indexes", indexes);
        return info;
    }

    static Map<String, Object> column(String name, String type, boolean nullable) {
        Map<String, Object> c = new LinkedHashMap<>();       // insertion order = the order Python's TypedDict emits
        c.put("name", name);
        c.put("type", type);
        c.put("nullable", nullable);
        return c;
    }

    static Map<String, Object> buildHealth(Map<String, Object> args) throws IOException {
        Pattern totals = Pattern.compile("Tests run: (\\d+), Failures: (\\d+), Errors: (\\d+)");
        int reports = 0, tests = 0, failures = 0, errors = 0;
        TreeSet<String> failing = new TreeSet<>();
        try (Stream<Path> files = Files.find(ROOT, 12, (p, attrs) -> attrs.isRegularFile() && p.toString().endsWith(".txt")
                && p.getParent().getFileName().toString().equals("surefire-reports")
                && p.getParent().getParent().getFileName().toString().equals("target"))) {
            for (Path report : files.toList()) {
                Matcher m = totals.matcher(Files.readString(report));
                if (m.find()) {
                    reports++;
                    int f = Integer.parseInt(m.group(2)), e = Integer.parseInt(m.group(3));
                    tests += Integer.parseInt(m.group(1));
                    failures += f;
                    errors += e;
                    if (f > 0 || e > 0) {
                        String name = report.getFileName().toString();
                        failing.add(name.substring(0, name.length() - 4));
                    }
                }
            }
        }
        Map<String, Object> health = new LinkedHashMap<>();
        health.put("reports", reports);
        health.put("tests", tests);
        health.put("failures", failures);
        health.put("errors", errors);
        health.put("failing_classes", List.copyOf(failing));
        return health;
    }

    static final String TOPIC_INPUT = """
            {"type":"object","properties":{"topic":{"type":"string","description":"persistence, messaging, testing, ..."}},
             "required":["topic"],"additionalProperties":false}""";
    static final String TABLE_INPUT = """
            {"type":"object","properties":{"table":{"type":"string","description":"table name, e.g. orders"}},
             "required":["table"],"additionalProperties":false}""";
    static final String TABLE_OUTPUT = """
            {"type":"object","required":["table","defined_in","columns","indexes"],"properties":{
              "table":{"type":"string"},"defined_in":{"type":"array","items":{"type":"string"}},
              "columns":{"type":"array","items":{"type":"object","required":["name","type","nullable"],"properties":{
                "name":{"type":"string"},"type":{"type":"string"},"nullable":{"type":"boolean"}}}},
              "indexes":{"type":"array","items":{"type":"string"}}}}""";
    static final String HEALTH_OUTPUT = """
            {"type":"object","required":["reports","tests","failures","errors","failing_classes"],"properties":{
              "reports":{"type":"integer"},"tests":{"type":"integer"},"failures":{"type":"integer"},"errors":{"type":"integer"},
              "failing_classes":{"type":"array","items":{"type":"string"}}}}""";

    public static void main(String[] args) {
        System.err.println("order-platform MCP server (Java SDK) for " + ROOT);    // stderr only
        Prompt review = Prompt.builder("review_migration").description("Review a Flyway migration against the persistence rules.")
                .arguments(List.of(PromptArgument.builder("file").description("migration file, e.g. V3__add_status.sql")
                        .required(true).build()))
                .build();
        McpSyncServer server = McpServer.sync(new StdioServerTransportProvider(JSON))
                .serverInfo("order-platform", "1.0.0")
                .instructions("Read-only project knowledge for order-platform: architecture rules, the schema as Flyway "
                        + "migrations define it, and the last build's test results. Use before designing or reviewing changes.")
                .capabilities(ServerCapabilities.builder().tools(false).prompts(false).build())
                .validateToolInputs(true)
                .tools(tool("architecture_rules", "Return the team's rules for a topic (e.g. persistence, messaging, testing) "
                                + "from .claude/rules/<topic>.md.", TOPIC_INPUT, null, OrderPlatformMcpServer::architectureRules),
                        tool("describe_table", "Describe a table as the applied Flyway migrations define it: columns, nullability, "
                                + "indexes, defining files.", TABLE_INPUT, TABLE_OUTPUT, OrderPlatformMcpServer::describeTable),
                        tool("build_health", "Summarise the last test run from target/surefire-reports (all modules): totals and "
                                + "failing test classes.", "{\"type\":\"object\",\"properties\":{}}", HEALTH_OUTPUT,
                                OrderPlatformMcpServer::buildHealth))
                .prompts(new SyncPromptSpecification(review, (exchange, request) -> GetPromptResult.builder(
                        List.of(new PromptMessage(Role.USER, TextContent.builder("Review " + request.arguments().get("file")
                                + " against architecture_rules('persistence'). Check: immutability of applied versions, an index "
                                + "for every foreign key, backward compatibility with the previous release, and lock duration "
                                + "on large tables.").build()))).description(review.description()).build()))
                .build();
        Runtime.getRuntime().addShutdownHook(new Thread(server::closeGracefully));
    }
}
```

### L3 · `OrderPlatformSpringMcp.java` (Spring Boot 4.1.2 + Spring AI 2.0.2)

**What it shows.**
- `@McpTool` / `@McpToolParam` methods on a `@Component`, found by the annotation scanner.
- Records with `@JsonProperty` for the snake_case output.
- `generateOutputSchema = true`.
- `@McpPrompt` returning a `GetPromptResult` with `Role.USER` (rule 6).
- The stdio-safe properties as `setDefaultProperties`, so command-line `--key=value` still overrides them; L4's negative control uses exactly that.

**What it does not show.** The WebMVC/WebFlux starters, Spring Security, or tests with `@SpringBootTest`.

Compile with `-parameters`.

```java
// OrderPlatformSpringMcp.java - the same order-platform server as a Spring Boot 4.1 app on Spring AI 2.0's MCP server starter
// (org.springframework.ai:spring-ai-starter-mcp-server, stdio). @McpTool methods are discovered by the annotation scanner;
// Spring AI generates the input schema from the parameters (compile with -parameters) and the output schema from the record.
// The stdio rules live in DEFAULTS (= src/main/resources/application.properties): no web server, no banner, no console log.
package com.acme.orderplatform.mcp;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.modelcontextprotocol.spec.McpSchema.GetPromptResult;
import io.modelcontextprotocol.spec.McpSchema.PromptMessage;
import io.modelcontextprotocol.spec.McpSchema.Role;
import io.modelcontextprotocol.spec.McpSchema.TextContent;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.springframework.ai.mcp.annotation.McpArg;
import org.springframework.ai.mcp.annotation.McpPrompt;
import org.springframework.ai.mcp.annotation.McpTool;
import org.springframework.ai.mcp.annotation.McpTool.McpAnnotations;
import org.springframework.ai.mcp.annotation.McpToolParam;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.stereotype.Component;

@SpringBootApplication
public class OrderPlatformSpringMcp {

    static final Map<String, Object> DEFAULTS = Map.of(
            "spring.main.web-application-type", "none",          // stdio server: no Tomcat, no port
            "spring.main.banner-mode", "off",                    // the banner goes to stdout = corrupts JSON-RPC
            "logging.pattern.console", "",                       // Boot's default console appender writes to stdout
            "logging.file.name", "${java.io.tmpdir}/order-platform-mcp.log",
            "spring.ai.mcp.server.stdio", "true",
            "spring.ai.mcp.server.name", "order-platform",
            "spring.ai.mcp.server.instructions", "Read-only project knowledge for order-platform: architecture rules, the "
                    + "schema as Flyway migrations define it, and the last build's test results. Use before designing or "
                    + "reviewing changes.");

    public static void main(String[] args) {
        SpringApplication app = new SpringApplication(OrderPlatformSpringMcp.class);
        app.setDefaultProperties(DEFAULTS);                      // command-line --key=value still overrides
        app.run(args);
    }

    public record Column(String name, String type, boolean nullable) {}

    public record TableInfo(String table, @JsonProperty("defined_in") List<String> definedIn, List<Column> columns,
                            List<String> indexes) {}

    public record BuildHealth(int reports, int tests, int failures, int errors,
                              @JsonProperty("failing_classes") List<String> failingClasses) {}

    @Component
    public static class OrderPlatformTools {
        static final Path ROOT = Path.of(System.getenv().getOrDefault("CLAUDE_PROJECT_DIR", ".")).toAbsolutePath().normalize();
        static final String MIGRATIONS_DIR = "src/main/resources/db/migration";
        static final int FLAGS = Pattern.CASE_INSENSITIVE | Pattern.DOTALL;

        @McpTool(name = "architecture_rules", description = "Return the team's rules for a topic (e.g. persistence, messaging, "
                + "testing) from .claude/rules/<topic>.md.", annotations = @McpAnnotations(readOnlyHint = true,
                destructiveHint = false, idempotentHint = true, openWorldHint = false))
        public String architectureRules(@McpToolParam(description = "persistence, messaging, testing, ...") String topic)
                throws IOException {
            Path rules = ROOT.resolve(".claude/rules");
            Path rule = rules.resolve(topic.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9-]", "") + ".md");
            if (!Files.exists(rule)) {
                TreeSet<String> available = new TreeSet<>();
                if (Files.isDirectory(rules)) {
                    try (Stream<Path> files = Files.list(rules)) {
                        files.map(p -> p.getFileName().toString()).filter(n -> n.endsWith(".md"))
                                .forEach(n -> available.add(n.substring(0, n.length() - 3)));
                    }
                }
                throw new IllegalArgumentException("no rules for '" + topic + "'; available: "
                        + (available.isEmpty() ? "none" : String.join(", ", available)));
            }
            return Files.readString(rule).replaceFirst("(?s)^---\n.*?\n---\n", "").strip();
        }

        @McpTool(name = "describe_table", description = "Describe a table as the applied Flyway migrations define it: columns, "
                + "nullability, indexes, defining files.", generateOutputSchema = true, annotations = @McpAnnotations(
                readOnlyHint = true, destructiveHint = false, idempotentHint = true, openWorldHint = false))
        public TableInfo describeTable(@McpToolParam(description = "table name, e.g. orders") String table) throws IOException {
            String t = Pattern.quote(table);
            Pattern create = Pattern.compile("create\\s+table\\s+" + t + "\\s*\\((.*?)\\)\\s*;", FLAGS);
            Pattern alter = Pattern.compile("alter\\s+table\\s+" + t + "\\s+add\\s+column\\s+(\\w+)\\s+([\\w()]+)(.*?);", FLAGS);
            Pattern index = Pattern.compile("create\\s+(?:unique\\s+)?index\\s+(\\w+)\\s+on\\s+" + t + "\\b", Pattern.CASE_INSENSITIVE);
            Pattern column = Pattern.compile("\\s*(\\w+)\\s+(\\w+(?:\\(\\d+(?:,\\s*\\d+)?\\))?)(.*)", Pattern.DOTALL);
            List<Column> columns = new ArrayList<>();
            List<String> indexes = new ArrayList<>();
            LinkedHashSet<String> definedIn = new LinkedHashSet<>();
            Path migrations = ROOT.resolve(MIGRATIONS_DIR);
            List<Path> sqls = List.of();
            if (Files.isDirectory(migrations)) {
                try (Stream<Path> files = Files.list(migrations)) {
                    sqls = files.filter(p -> p.getFileName().toString().matches("V\\d+__.*\\.sql"))
                            .sorted((a, b) -> Integer.compare(version(a), version(b))).toList();
                }
            }
            for (Path sql : sqls) {
                String text = Files.readString(sql);
                for (Matcher m = create.matcher(text); m.find(); ) {
                    definedIn.add(sql.getFileName().toString());
                    for (String col : m.group(1).split(",(?![^(]*\\))")) {
                        Matcher c = column.matcher(col);
                        if (c.matches() && !Set.of("primary", "constraint", "unique", "foreign").contains(c.group(1).toLowerCase(Locale.ROOT))) {
                            String rest = c.group(3).toLowerCase(Locale.ROOT);
                            columns.add(new Column(c.group(1), c.group(2), !rest.contains("not null") && !rest.contains("primary key")));
                        }
                    }
                }
                for (Matcher a = alter.matcher(text); a.find(); ) {
                    definedIn.add(sql.getFileName().toString());
                    columns.add(new Column(a.group(1), a.group(2), !a.group(3).toLowerCase(Locale.ROOT).contains("not null")));
                }
                for (Matcher i = index.matcher(text); i.find(); ) {
                    indexes.add(i.group(1));
                }
            }
            if (columns.isEmpty()) {
                throw new IllegalArgumentException("table '" + table + "' is not created by any migration in " + MIGRATIONS_DIR);
            }
            return new TableInfo(table, List.copyOf(definedIn), columns, indexes);
        }

        static int version(Path p) {
            return Integer.parseInt(p.getFileName().toString().replaceAll("^V(\\d+).*", "$1"));
        }

        @McpTool(name = "build_health", description = "Summarise the last test run from target/surefire-reports (all modules): "
                + "totals and failing test classes.", generateOutputSchema = true, annotations = @McpAnnotations(
                readOnlyHint = true, destructiveHint = false, idempotentHint = true, openWorldHint = false))
        public BuildHealth buildHealth() throws IOException {
            Pattern totals = Pattern.compile("Tests run: (\\d+), Failures: (\\d+), Errors: (\\d+)");
            int[] sum = new int[4];                              // reports, tests, failures, errors
            TreeSet<String> failing = new TreeSet<>();
            try (Stream<Path> files = Files.find(ROOT, 12, (p, attrs) -> attrs.isRegularFile() && p.toString().endsWith(".txt")
                    && p.getParent().getFileName().toString().equals("surefire-reports")
                    && p.getParent().getParent().getFileName().toString().equals("target"))) {
                files.forEach(report -> {
                    try {
                        Matcher m = totals.matcher(Files.readString(report));
                        if (m.find()) {
                            int f = Integer.parseInt(m.group(2)), e = Integer.parseInt(m.group(3));
                            sum[0]++;
                            sum[1] += Integer.parseInt(m.group(1));
                            sum[2] += f;
                            sum[3] += e;
                            if (f > 0 || e > 0) {
                                String name = report.getFileName().toString();
                                failing.add(name.substring(0, name.length() - 4));
                            }
                        }
                    } catch (IOException e) {
                        throw new UncheckedIOException(e);
                    }
                });
            }
            return new BuildHealth(sum[0], sum[1], sum[2], sum[3], List.copyOf(failing));
        }

        /** Returns an explicit USER message: a String return renders as an ASSISTANT message (measured, Spring AI 2.0.2). */
        @McpPrompt(name = "review_migration", description = "Review a Flyway migration against the persistence rules.")
        public GetPromptResult reviewMigration(@McpArg(name = "file", description = "migration file, e.g. V3__add_status.sql",
                required = true) String file) {
            String text = "Review " + file + " against architecture_rules('persistence'). Check: immutability of applied "
                    + "versions, an index for every foreign key, backward compatibility with the previous release, and lock "
                    + "duration on large tables.";
            return GetPromptResult.builder(List.of(new PromptMessage(Role.USER, TextContent.builder(text).build())))
                    .description("Review a Flyway migration against the persistence rules.").build();
        }
    }
}
```

### L4 · `mcp_stdio_conformance.py`

**What it shows.**
- A raw JSON-RPC client: newline framing, server→client request handling, and junk-line detection.
- Run against all three servers over one fixture project, with:
  - both Java listings compiled under `-Xlint:all -Werror` first;
  - a 2026-07-28 `server/discover` probe, the 2025-11-25 handshake, instruction length, tool-name validity and annotations;
  - each tool's success and error paths, unknown-tool and missing-argument behaviour, the prompt's role;
  - stdout purity, and exit time after stdin EOF.
- Two negative controls: the Spring server with Boot's defaults restored from the command line, and the Python server behind a `print()` banner.
- Finally, a cross-implementation comparison of the structured results.

**What it does not show.**
- Claude Code itself. This client models the documented behaviour; it is not Claude Code's client.
- HTTP transports, OAuth, or concurrency.

Run: `python mcp_stdio_conformance.py` (with `JAVA_HOME`, `MCP_JAVA_CP` and `SPRING_MCP_CP` set for the Java legs).

```python
"""mcp_stdio_conformance.py - a stdlib-only MCP stdio client (raw JSON-RPC, no SDK) that checks what Claude Code relies on:
handshake, stdout purity, tools/list hygiene, tool-call and error semantics, prompts, and exit on stdin EOF (on Windows
Claude Code closes stdin, then kills the process tree 300 ms later). Runs the Python, plain-Java and Spring AI order-platform
servers against one fixture project and checks they return identical structured results; two negative controls show what
stdout pollution looks like. Java needs JAVA_HOME plus MCP_JAVA_CP (MCP SDK) / SPRING_MCP_CP (Spring AI starter) classpaths.
"""
import json
import os
import pathlib
import queue
import re
import subprocess
import sys
import tempfile
import threading
import time

PROTOCOL = "2026-07-28"                # asked for in initialize; a server answers with the newest revision it speaks there
MODERN = {"io.modelcontextprotocol/protocolVersion": "2026-07-28", "io.modelcontextprotocol/clientCapabilities": {}}
HERE = pathlib.Path(__file__).resolve().parent
SURE = "-" * 79 + "\nTest set: {0}\n" + "-" * 79 + "\nTests run: {1}, Failures: {2}, Errors: 0, Skipped: 0, Time elapsed: 0.4 s -- in {0}\n"
FIXTURE = {
    ".claude/rules/persistence.md": "---\npaths:\n  - \"**/*.sql\"\n---\n# Persistence rules\n"
        "- Applied Flyway migrations are immutable; fix forward with a new V<n>.\n"
        "- Every foreign key gets an index in the same migration.\n- No `select *` in repository code.\n",
    ".claude/rules/messaging.md": "# Messaging rules\n- Publish through the transactional outbox, never from inside a @Transactional method.\n",
    "src/main/resources/db/migration/V1__create_orders.sql": "create table orders (\n  id bigint primary key,\n"
        "  customer_id bigint not null,\n  amount numeric(12, 2) not null,\n  note varchar(200)\n);\n",
    "src/main/resources/db/migration/V2__add_status.sql": "alter table orders add column status varchar(20) not null default 'NEW';\n"
        "create index idx_orders_customer on orders (customer_id);\n",
    "src/main/resources/db/migration/V10__add_shipped_at.sql": "alter table orders add column shipped_at timestamptz;\n",
    "order-service/target/surefire-reports/com.acme.order.OrderServiceTest.txt": SURE.format("com.acme.order.OrderServiceTest", 12, 0),
    "outbox-relay/target/surefire-reports/com.acme.outbox.OutboxRelayTest.txt": SURE.format("com.acme.outbox.OutboxRelayTest", 5, 1),
}


class StdioClient:
    """Newline-delimited JSON-RPC 2.0 over a child's stdin/stdout. Any stdout line that is not a JSON-RPC message is junk."""

    def __init__(self, cmd, env, cwd):
        self.p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, cwd=cwd)
        self.inbox, self.junk, self.next_id = queue.Queue(), [], 0
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(target=lambda: [None for _ in self.p.stderr], daemon=True).start()   # drain stderr: no pipe deadlock

    def _read(self):
        for raw in self.p.stdout:
            line = raw.decode("utf-8", "replace").strip()
            try:
                msg = json.loads(line)
                ok = isinstance(msg, dict) and msg.get("jsonrpc") == "2.0"
            except json.JSONDecodeError:
                ok = False
            if ok:
                self.inbox.put(msg)
            elif line:
                self.junk.append(line)
        self.inbox.put(None)

    def send(self, msg):
        self.p.stdin.write((json.dumps(msg) + "\n").encode("utf-8"))
        self.p.stdin.flush()

    def notify(self, method, params=None):
        self.send({"jsonrpc": "2.0", "method": method, **({"params": params} if params is not None else {})})

    def request(self, method, params=None, timeout=30.0):
        self.next_id += 1
        rid, deadline = self.next_id, time.monotonic() + timeout
        self.send({"jsonrpc": "2.0", "id": rid, "method": method, **({"params": params} if params is not None else {})})
        while True:
            msg = self.inbox.get(timeout=max(0.01, deadline - time.monotonic()))
            if msg is None:
                raise EOFError(f"server closed stdout during {method}")
            if msg.get("id") == rid and ("result" in msg or "error" in msg):
                return msg
            if "method" in msg and "id" in msg:                               # server->client request (ping, roots/list)
                self.send({"jsonrpc": "2.0", "id": msg["id"], "result": {"roots": []} if msg["method"] == "roots/list" else {}})

    def call(self, name, arguments):
        return self.request("tools/call", {"name": name, "arguments": arguments})

    def close(self):
        """Close stdin like Claude Code on Windows; report how long the server took to exit (killed after 3 s)."""
        start = time.monotonic()
        self.p.stdin.close()
        try:
            self.p.wait(timeout=3)
            return time.monotonic() - start
        except subprocess.TimeoutExpired:
            self.p.kill()
            self.p.wait()
            return None


def text_of(result):
    return "".join(c.get("text", "") for c in result.get("content", []) if c.get("type") == "text")


def check(label, server, project, quiet=False):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(project), PYTHONUNBUFFERED="1")
    rows, structured = [], {}

    def row(ok, what, detail):
        rows.append(f"  {'PASS' if ok is True else 'FAIL' if ok is False else 'INFO'} {what}: {detail}")

    probe = StdioClient(server, env, HERE)               # 2026-07-28 is stateless: server/discover + a _meta envelope
    d = probe.request("server/discover", {"_meta": MODERN})
    probe.close()
    row(None, "server/discover (2026-07-28)", f"supportedVersions {d['result']['supportedVersions']}" if "result" in d
        else f"JSON-RPC error {d['error']['code']} - initialize handshake only")
    c = StdioClient(server, env, HERE)

    init = c.request("initialize", {"protocolVersion": PROTOCOL, "capabilities": {"roots": {"listChanged": True}},
                                    "clientInfo": {"name": "conformance", "version": "1.0"}})["result"]
    c.notify("notifications/initialized")
    caps = sorted(k for k in init["capabilities"] if k in ("tools", "prompts", "resources", "logging"))
    row(bool(init.get("protocolVersion")), "handshake", f"protocolVersion {init['protocolVersion']}, "
        f"server {init['serverInfo']['name']}, capabilities {'+'.join(caps)}")
    instructions = init.get("instructions") or ""
    row(0 < len(instructions) <= 4096, "instructions", f"{len(instructions)} chars (Claude Code cuts at 4,096; tool search "
        "matches on them)")

    tools = c.request("tools/list")["result"]["tools"]
    names = [t["name"] for t in tools]
    bad = [n for n in names if not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", n)]
    ro = all((t.get("annotations") or {}).get("readOnlyHint") is True for t in tools)
    row(not bad and ro, "tools/list", f"{len(tools)} tools {sorted(names)}, names valid: {not bad}, all readOnlyHint: {ro}")
    with_out = sorted(t["name"] for t in tools if t.get("outputSchema"))
    row(None, "outputSchema declared by", ", ".join(with_out) or "none")
    size = len(json.dumps(tools, separators=(",", ":")))
    row(None, "tool definitions", f"{size:,} chars of JSON, roughly {size // 4:,} tokens if loaded upfront (chars/4 estimate)")

    r = c.call("architecture_rules", {"topic": "persistence"})["result"]
    t = text_of(r)
    row(not r.get("isError") and t.startswith("# Persistence rules") and "paths:" not in t,
        "architecture_rules(persistence)", f"{t.count(chr(10) + '- ')} rules, frontmatter stripped: {'paths:' not in t}")
    structured["rules"] = t
    r = c.call("architecture_rules", {"topic": "security"})["result"]
    row(r.get("isError") is True, "architecture_rules(security)", f"isError={r.get('isError')} -> {text_of(r)!r}")

    r = c.call("describe_table", {"table": "orders"})["result"]
    s = r.get("structuredContent") or {}
    cols = [col["name"] for col in s.get("columns", [])]
    row(not r.get("isError") and cols[-1:] == ["shipped_at"] and s.get("indexes") == ["idx_orders_customer"]
        and s.get("defined_in") == ["V1__create_orders.sql", "V2__add_status.sql", "V10__add_shipped_at.sql"],
        "describe_table(orders)", f"columns {cols}, from {s.get('defined_in')}, indexes {s.get('indexes')}")
    structured["orders"] = s
    r = c.call("describe_table", {"table": "payments"})["result"]
    row(r.get("isError") is True, "describe_table(payments)", f"isError={r.get('isError')} -> {text_of(r)!r}")

    r = c.call("build_health", {})["result"]
    s = r.get("structuredContent") or {}
    row(s.get("tests") == 17 and s.get("failures") == 1, "build_health",
        f"{s.get('reports')} reports, {s.get('tests')} tests, {s.get('failures')} failure, failing {s.get('failing_classes')}")
    structured["health"] = s

    for what, name, args in (("unknown tool", "drop_table", {"table": "orders"}),
                             ("missing required argument", "describe_table", {})):
        m = c.call(name, args)
        if "error" in m:
            row(None, what, f"JSON-RPC error {m['error']['code']}: {m['error']['message'][:70]!r}")
        else:
            row(None, what, f"tool result isError={m['result'].get('isError')}: {text_of(m['result'])[:70]!r}")

    prompts = c.request("prompts/list")["result"]["prompts"]
    got = c.request("prompts/get", {"name": "review_migration", "arguments": {"file": "V2__add_status.sql"}})["result"]
    msg = got["messages"][0]
    row(msg["role"] == "user" and "V2__add_status.sql" in msg["content"]["text"], "prompts",
        f"{[p['name'] for p in prompts]} (Claude Code: /mcp__order-platform__review_migration), renders a user message")

    row(not c.junk, "stdout purity", f"{len(c.junk)} non-protocol line(s)" + (f", first: {c.junk[0]!r}" if c.junk else ""))
    took = c.close()
    row(took is not None and took < 3, "exit on stdin EOF",
        "no (killed after 3 s)" if took is None else "within 300 ms" if took < 0.3 else "yes, but after more than 300 ms")
    print(f"== {label} ==")
    fails = [r for r in rows if r.startswith("  FAIL")]
    print("\n".join(fails if quiet else rows))
    if quiet:
        print(f"  ({len(rows) - len(fails)} other checks passed or informational)")
    return structured


def main():
    with tempfile.TemporaryDirectory() as tmp:
        project = pathlib.Path(tmp, "order-platform")
        for rel, body in FIXTURE.items():
            (project / rel).parent.mkdir(parents=True, exist_ok=True)
            (project / rel).write_text(body, encoding="utf-8", newline="\n")
        results = {"python": check("python: order_platform_mcp.py (mcp 2.x MCPServer)",
                                   [sys.executable, "order_platform_mcp.py"], project)}
        java_home = os.environ.get("JAVA_HOME")
        servers = (("java", "OrderPlatformMcpServer.java", "OrderPlatformMcpServer", "MCP_JAVA_CP", [],
                    "java: OrderPlatformMcpServer (MCP Java SDK, stdio)"),
                   ("spring", "OrderPlatformSpringMcp.java", "com.acme.orderplatform.mcp.OrderPlatformSpringMcp", "SPRING_MCP_CP",
                    ["-parameters"], "spring: OrderPlatformSpringMcp (Spring Boot 4.1 + Spring AI 2.0 starter, stdio)"))
        for key, source, main_class, cp_var, extra, label in servers:
            cp = os.environ.get(cp_var)
            if not (java_home and cp):
                print(f"== {key}: skipped (set JAVA_HOME and {cp_var}) ==")
                continue
            classes = pathlib.Path(tmp, f"classes-{key}")
            javac = subprocess.run([str(pathlib.Path(java_home, "bin", "javac")), "--release", "21", *extra, "-Xlint:all",
                                    "-Werror", "-cp", cp, "-d", str(classes), source], cwd=HERE, capture_output=True, text=True)
            print(f"== javac --release 21 {' '.join(extra)}{' ' if extra else ''}-Xlint:all -Werror {source}: "
                  f"rc={javac.returncode} ==")
            if javac.returncode == 0:
                java = [str(pathlib.Path(java_home, "bin", "java")), "-cp", f"{classes}{os.pathsep}{cp}", main_class]
                results[key] = check(label, java, project)
                if key == "spring":
                    check("negative control: the Spring server with Boot's defaults (banner + console logging)",
                          java + ["--spring.main.banner-mode=console", "--logging.pattern.console=%5p %m%n"], project, quiet=True)
        banner = [sys.executable, "-c", "print('Starting order-platform MCP server...'); import runpy, sys; "
                  "sys.argv = ['order_platform_mcp.py']; runpy.run_path('order_platform_mcp.py', run_name='__main__')"]
        check("negative control: the Python server behind a print() banner", banner, project, quiet=True)
        for other in [k for k in results if k != "python"]:
            same = [k for k in results["python"] if results["python"][k] == results[other][k]]
            print(f"== python vs {other}: {len(same)}/{len(results['python'])} results identical ({', '.join(same)}) ==")


if __name__ == "__main__":
    main()
```

**Output (verified):**

```text
== python: order_platform_mcp.py (mcp 2.x MCPServer) ==
  INFO server/discover (2026-07-28): supportedVersions ['2026-07-28']
  PASS handshake: protocolVersion 2025-11-25, server order-platform, capabilities prompts+resources+tools
  PASS instructions: 188 chars (Claude Code cuts at 4,096; tool search matches on them)
  PASS tools/list: 3 tools ['architecture_rules', 'build_health', 'describe_table'], names valid: True, all readOnlyHint: True
  INFO outputSchema declared by: architecture_rules, build_health, describe_table
  INFO tool definitions: 2,318 chars of JSON, roughly 579 tokens if loaded upfront (chars/4 estimate)
  PASS architecture_rules(persistence): 3 rules, frontmatter stripped: True
  PASS architecture_rules(security): isError=True -> "Error executing tool architecture_rules: no rules for 'security'; available: messaging, persistence"
  PASS describe_table(orders): columns ['id', 'customer_id', 'amount', 'note', 'status', 'shipped_at'], from ['V1__create_orders.sql', 'V2__add_status.sql', 'V10__add_shipped_at.sql'], indexes ['idx_orders_customer']
  PASS describe_table(payments): isError=True -> "Error executing tool describe_table: table 'payments' is not created by any migration in src/main/resources/db/migration"
  PASS build_health: 2 reports, 17 tests, 1 failure, failing ['com.acme.outbox.OutboxRelayTest']
  INFO unknown tool: tool result isError=True: 'Unknown tool: drop_table'
  INFO missing required argument: tool result isError=True: 'Error executing tool describe_table: 1 validation error for describe_t'
  PASS prompts: ['review_migration'] (Claude Code: /mcp__order-platform__review_migration), renders a user message
  PASS stdout purity: 0 non-protocol line(s)
  PASS exit on stdin EOF: within 300 ms
== javac --release 21 -Xlint:all -Werror OrderPlatformMcpServer.java: rc=0 ==
== java: OrderPlatformMcpServer (MCP Java SDK, stdio) ==
  INFO server/discover (2026-07-28): JSON-RPC error -32601 - initialize handshake only
  PASS handshake: protocolVersion 2025-11-25, server order-platform, capabilities logging+prompts+tools
  PASS instructions: 188 chars (Claude Code cuts at 4,096; tool search matches on them)
  PASS tools/list: 3 tools ['architecture_rules', 'build_health', 'describe_table'], names valid: True, all readOnlyHint: True
  INFO outputSchema declared by: build_health, describe_table
  INFO tool definitions: 1,862 chars of JSON, roughly 465 tokens if loaded upfront (chars/4 estimate)
  PASS architecture_rules(persistence): 3 rules, frontmatter stripped: True
  PASS architecture_rules(security): isError=True -> "no rules for 'security'; available: messaging, persistence"
  PASS describe_table(orders): columns ['id', 'customer_id', 'amount', 'note', 'status', 'shipped_at'], from ['V1__create_orders.sql', 'V2__add_status.sql', 'V10__add_shipped_at.sql'], indexes ['idx_orders_customer']
  PASS describe_table(payments): isError=True -> "table 'payments' is not created by any migration in src/main/resources/db/migration"
  PASS build_health: 2 reports, 17 tests, 1 failure, failing ['com.acme.outbox.OutboxRelayTest']
  INFO unknown tool: JSON-RPC error -32602: 'Unknown tool: invalid_tool_name'
  INFO missing required argument: tool result isError=True: 'Tool (describe_table) input validation failed: Validation failed: JSON'
  PASS prompts: ['review_migration'] (Claude Code: /mcp__order-platform__review_migration), renders a user message
  PASS stdout purity: 0 non-protocol line(s)
  PASS exit on stdin EOF: within 300 ms
== javac --release 21 -parameters -Xlint:all -Werror OrderPlatformSpringMcp.java: rc=0 ==
== spring: OrderPlatformSpringMcp (Spring Boot 4.1 + Spring AI 2.0 starter, stdio) ==
  INFO server/discover (2026-07-28): JSON-RPC error -32601 - initialize handshake only
  PASS handshake: protocolVersion 2025-11-25, server order-platform, capabilities logging+prompts+resources+tools
  PASS instructions: 188 chars (Claude Code cuts at 4,096; tool search matches on them)
  PASS tools/list: 3 tools ['architecture_rules', 'build_health', 'describe_table'], names valid: True, all readOnlyHint: True
  INFO outputSchema declared by: build_health, describe_table
  INFO tool definitions: 2,250 chars of JSON, roughly 562 tokens if loaded upfront (chars/4 estimate)
  PASS architecture_rules(persistence): 3 rules, frontmatter stripped: True
  PASS architecture_rules(security): isError=True -> "no rules for 'security'; available: messaging, persistence\r\nno rules for 'security'; available: messaging, persistence"
  PASS describe_table(orders): columns ['id', 'customer_id', 'amount', 'note', 'status', 'shipped_at'], from ['V1__create_orders.sql', 'V2__add_status.sql', 'V10__add_shipped_at.sql'], indexes ['idx_orders_customer']
  PASS describe_table(payments): isError=True -> "table 'payments' is not created by any migration in src/main/resources/db/migration\r\ntable 'payments' is not created by any migration in src/main/resources/db/migration"
  PASS build_health: 2 reports, 17 tests, 1 failure, failing ['com.acme.outbox.OutboxRelayTest']
  INFO unknown tool: JSON-RPC error -32602: 'Unknown tool: invalid_tool_name'
  INFO missing required argument: tool result isError=True: 'Tool (describe_table) input validation failed: Validation failed: JSON'
  PASS prompts: ['review_migration'] (Claude Code: /mcp__order-platform__review_migration), renders a user message
  PASS stdout purity: 0 non-protocol line(s)
  PASS exit on stdin EOF: within 300 ms
== negative control: the Spring server with Boot's defaults (banner + console logging) ==
  FAIL stdout purity: 23 non-protocol line(s), first: '.   ____          _            __ _ _'
  (15 other checks passed or informational)
== negative control: the Python server behind a print() banner ==
  FAIL stdout purity: 1 non-protocol line(s), first: 'Starting order-platform MCP server...'
  (15 other checks passed or informational)
== python vs java: 3/3 results identical (rules, orders, health) ==
== python vs spring: 3/3 results identical (rules, orders, health) ==
```

How to read it:
- **Every PASS row passed in all three implementations.** The INFO rows record where the SDKs legitimately differ (§1.3, §1.4, §1.5).
- **The negative controls are why the purity check exists.** Restoring two Boot defaults from the command line put 23 non-protocol lines on stdout, starting with the banner.
- **The handshake still succeeded in both negative controls,** because this client skips junk lines. Don't infer from that what a stricter client does with a corrupted stream: keep stdout clean.

---

## 4. Failure modes

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| F1 | Server "connects" then nothing works, or times out | Banner or console logs on stdout | Rule 1 properties; log to a file or stderr; L4 purity check |
| F2 | Model says "the tool failed" and can't say why | Python tool raised `ValueError`; the message was hidden | `ToolError` (rule 2) |
| F3 | Every Spring tool call fails validation on `arg0` | Compiled without `-parameters` | `<parameters>true</parameters>` (rule 5) |
| F4 | Slash-command prompt reads as if Claude said it | `String` return from `@McpPrompt`: assistant role | `GetPromptResult` with `Role.USER` (rule 6) |
| F5 | Build breaks on SDK upgrade | Deprecated constructors and builders, removed later | `-Xlint:all -Werror` now; migrate to the builders (rule 7) |
| F6 | `describe_table` lists V10 columns first | Lexical file ordering | Numeric version sort (L4 checks the order) |
| F7 | Python tool has no output schema | `-> dict` return type | Return a `TypedDict` |
| F8 | Server leaves orphan processes on Windows | Ignores stdin EOF; killed after 300 ms | Exit on EOF (rule 8); clean up in a shutdown hook |
| F9 | Paths resolve against the wrong directory | Used the working directory | `CLAUDE_PROJECT_DIR` (rule 9) |
| F10 | Spring server never answers | `spring.ai.mcp.server.stdio` left at its `false` default | Set it to `true` |

---

## 5. Staff-level drills

<details><summary><b>D1 · "Why not just give Claude a database MCP server instead of <code>describe_table</code>?"</b></summary>

**Staff answer.** They answer different questions.
- The database server says what a *dev database* contains now, with credentials, network access and file 02's whole threat model.
- `describe_table` says what the *migrations* define. That is what the code ships against, available offline, in CI, with no secret.

For "why is order 8812 stuck", use the read-only database. For "add a column and update the repository", use the migrations view. That view also catches a missed `NOT NULL` in a pending migration, which no running database has seen yet.
</details>

<details><summary><b>D2 · "Spring AI or the plain Java SDK for our team's server?"</b></summary>

**Staff answer.** It depends on where the knowledge lives.
- **Already in Spring beans** (a rules engine, a repository, a feature-flag client): Spring AI's `@McpTool` on those beans. Pay the ~3 s startup and the 52 jars, and pin the stdio properties.
- **Files and conventions**: the plain SDK (one JAR, fast start) or Python (fewest lines).

Either way, run L4 in CI. Two of the three implementations here shipped a contract bug on the first draft: Python's hidden error and Spring's assistant-role prompt. Neither was a compile error.
</details>

<details><summary><b>D3 · "How do we roll out a new tool without breaking everyone's sessions?"</b></summary>

**Staff answer.**
- Tool lists are read at connect. With tool search on, a new tool appears as a name on the next connect. Without it, a mid-session `tools/list_changed` busts the prompt cache (file 01 §1.4).
- Ship the tool in a new server version.
- Keep old tool names working for one release; rename by aliasing.
- Version the server through `serverInfo.version`.
- Gate it with L4 extended by the new tool's fixture.
- For structured outputs, treat `outputSchema` like an API contract: add fields, don't rename them.
</details>

<details><summary><b>D4 · "Should our server use the 2026-07-28 revision?"</b></summary>

**Staff answer.** Let the SDK decide.
- Python `mcp` 2.3.0 already serves both revisions. The Java SDK 2.1.0 and Spring AI 2.0.2 speak 2025-11-25 [measured].
- What matters is what your *client* negotiates. Observe it before depending on stateless discovery or caching hints.
- Design so nothing depends on it: no reliance on `roots` (deprecated in the new revision), no server-initiated `sampling`, idempotent read-only tools that are safe to cache.
</details>

---

## 6. Checklist

- [ ] Nothing writes to stdout except the SDK; Spring stdio properties set; L4 purity passes.
- [ ] Anticipated failures are `isError` results with actionable text (`ToolError` in Python).
- [ ] Data tools declare an output schema; `structuredContent` plus a text fallback.
- [ ] Java: `-Xlint:all -Werror`; Spring: `-parameters`; prompts return `Role.USER`.
- [ ] Root from `CLAUDE_PROJECT_DIR`; exit on stdin EOF within 300 ms.
- [ ] Server instructions: what and when, keywords first, under 4,096 chars; few tools with narrow outputs.
- [ ] L4 (extended with your fixtures) runs in CI on every server change.

---

## 7. References

- Claude Code MCP docs (stdio env, shutdown, limits, tool search for server authors, `anthropic/*` `_meta` keys): <https://code.claude.com/docs/en/mcp>
- MCP specification (lifecycle, tools, structured content, errors): <https://modelcontextprotocol.io/specification>
- MCP Python SDK: <https://github.com/modelcontextprotocol/python-sdk>
- MCP Java SDK: <https://github.com/modelcontextprotocol/java-sdk>
- Spring AI MCP server docs: <https://docs.spring.io/spring-ai/reference/api/mcp/mcp-server-boot-starter-docs.html>

Previous: [02 · Essential MCP servers](02-essential-mcp-servers-for-backend-engineers-postgres-github-docker-and-docs.md) · Next folder: [07 · Master prompt templates](../07-Master-Prompt-Templates-for-Java-Backend-Projects-From-Scratch/01-zero-to-production-java21-spring-boot-microservice-scaffolding-prompt.md) · [KB README](../README.md)

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

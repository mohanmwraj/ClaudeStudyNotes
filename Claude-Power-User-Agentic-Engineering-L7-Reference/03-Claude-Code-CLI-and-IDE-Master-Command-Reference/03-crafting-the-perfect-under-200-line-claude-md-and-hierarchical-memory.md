# Crafting the Perfect Under-200-Line CLAUDE.md, and Hierarchical Memory

> **Folder 03 · File 3 of 3** · verified 2026-10-30 against code.claude.com (memory, best-practices, context-window, sub-agents, settings-reference)
> **Listing:** `claude_md_lint.py` (lints CLAUDE.md against Claude Code's own guidance; its GOOD fixture is this file's Java 21 CLAUDE.md)

---

## 0. Orientation

CLAUDE.md is the most-loaded and least-engineered prompt in most repositories. Two facts from the docs determine how to write it:

1. **It is loaded into every session**, so "every line in it takes a little of Claude's attention on *every* task, whether it's relevant or not" [doc].
2. **It is context, not enforced configuration.** "To block an action regardless of what Claude decides, use a PreToolUse hook instead" [doc].

So a good CLAUDE.md is short, holds only what Claude can't see in the repo, and leaves anything that must always or never happen to hooks and deny rules. This file covers:

- the memory hierarchy: managed, user, project, local, subdirectory, `.claude/rules/`, imports and auto memory
- a 31-line CLAUDE.md for a Java 21 / Spring Boot monorepo that passes every lint rule
- path-scoped rules for persistence, messaging and tests
- a linter for CI

### 0.1 The twelve rules

1. **Stay under 200 lines (aim for well under).** "Longer files consume more context and reduce adherence." [doc]
2. **Put the commands that check work first.** "The single most useful line in your CLAUDE.md is the command that runs it." [doc]
3. **Write only what Claude can't see:** misleading code, decisions not in the repo, anything you've corrected twice. [doc]
4. **Don't describe architecture or file layout.** "Claude reads the repo itself." [doc]
5. **No IMPORTANT / ALL CAPS.** Current models follow plain wording, and "piling on emphasis mostly makes Claude over-apply the rule". [doc]
6. **Concrete and verifiable:** "Use 2-space indentation", not "Format code properly". [doc]
7. **A rule that can't bend is a hook or deny rule, not a line here.** [doc]
8. **Scope partial rules with `.claude/rules/*.md` and a `paths:` frontmatter**, so they load only when Claude touches matching files. [doc]
9. **Imports organise but don't save context:** imported files load with the file, up to 4 hops deep. [doc]
10. **Personal preferences go in `CLAUDE.local.md` (gitignored)**, or in `~/.claude/CLAUDE.md`. [doc]
11. **No task state and no secrets.** Task notes go in progress files; secrets are committed and loaded into every session. [inference + Folder 02]
12. **Lint it in CI and audit it with `/doctor prompt-audit`**, which finds stale, missing-file and contradictory instructions. [doc + measured: L1]

---

## 1. First principles

### 1.1 Why short wins: attention is the budget, again

Folder 01 file 01 §1.4 showed that every token competes for attention mass. CLAUDE.md sits at the start of every conversation, so each irrelevant line is a distractor on every task. The docs make the same point operationally: if Claude keeps missing a line, "either the file has grown long enough that the line gets lost, or the line is a rule that can't have exceptions, in which case it belongs in a hook" [doc].

Imports and `.claude/rules/` help you *organise*, but only path-scoped rules and subdirectory CLAUDE.md files *defer* loading.

### 1.2 The hierarchy: who loads what, and when [doc]

| Scope | Location | Loaded |
|---|---|---|
| Managed policy | Windows: `C:\Program Files\ClaudeCode\CLAUDE.md` · Linux/WSL: `/etc/claude-code/CLAUDE.md` · macOS: `/Library/Application Support/ClaudeCode/CLAUDE.md` | Every session, for everyone; can't be excluded |
| User | `~/.claude/CLAUDE.md`, plus `~/.claude/rules/` | Every session, every project |
| Project | `./CLAUDE.md` or `./.claude/CLAUDE.md`, plus `./.claude/rules/` | At launch, for the cwd **and every parent directory** |
| Local | `./CLAUDE.local.md` (add it to `.gitignore`) | With the project file |
| Subdirectory | `order-service/CLAUDE.md` | **On demand**, once Claude reads, writes or edits a file in that directory, or you `@`-mention one |
| Auto memory | `~/.claude/projects/<project>/memory/` (written by Claude) | Every session, first 200 lines or 25 KB |

Loading rules:
- **Files concatenate rather than override**, ordered from the filesystem root down to your working directory.
- In large monorepos, ancestor files that don't apply to you can be skipped with `claudeMdExcludes` (glob patterns). A managed CLAUDE.md can't be excluded.
- Claude Code also reads `AGENTS.md`, so a repository set up for other coding agents works without a duplicate file.
- **The built-in Explore and Plan subagents start without your CLAUDE.md files**, for speed. Other subagents load them unless `omitClaudeMd` is set [doc].

### 1.3 `.claude/rules/`: modular, path-scoped instructions [doc]

- **Discovery.** All `.md` files under `.claude/rules/` are discovered recursively, one topic per file.
- **Path scoping.** A rule with YAML frontmatter `paths: [...]` loads **only when Claude uses Read, Write or Edit on a matching file** (or views one with a Bash command that counts as a read). A rule without `paths` loads unconditionally.
- **Frontmatter.** `paths` is the *only* frontmatter field Claude Code reads. Others are ignored, and YAML that doesn't parse makes the rule load as if it had no `paths`. Check with `claude --debug`.
- **Sharing.** Symlinks are supported, so you can share rules across repos. A link that points outside the working directory needs a one-time approval, and links to network paths don't load.
- **Personal rules.** `~/.claude/rules/` holds rules that apply to every project.

For a Java monorepo this is the key tool. Persistence conventions load when Claude opens a repository class or a Flyway migration. Kafka conventions load when it touches a listener. Test conventions load under `src/test/`.

### 1.4 Imports [doc]

- `@path/to/file.md` imports a file. Relative paths resolve **from the importing file**, not the cwd.
- Imports can nest to a **maximum of four hops**.
- Code spans and fenced blocks aren't parsed, so wrap a path in backticks to mention it without importing.
- A path with spaces needs backslashes; a quoted path isn't imported at all.
- Imports that resolve outside the working directory need a one-time approval per project.

Imports don't reduce context: "imported files load together with the [file]" [doc]. L1 checks resolution and depth.

### 1.5 Auto memory: what Claude writes for itself [doc]

- **Content.** Claude saves four kinds of notes (`user`, `feedback`, `project`, `reference`). It skips anything derivable from the code, and anything CLAUDE.md already says.
- **Storage.** It lives under `~/.claude/projects/<project>/memory/`, shared across all worktrees of the same repo. Relocate it with `autoMemoryDirectory`.
- **Loading.** The first 200 lines or 25 KB load into every session.
- **Control.** `/memory` edits CLAUDE.md files, toggles auto memory and shows its entries.

Use auto memory for personal corrections that accumulate. Use CLAUDE.md for team decisions.

### 1.6 What belongs: the docs' four-question test [doc]

Keep a line only if it is one of these:
1. **How to confirm work**: the exact build, test and lint commands, and how to run one test.
2. **Where the code misleads**: an old pattern that's everywhere but mustn't be copied; a directory that looks dead but isn't.
3. **Decisions not in the repo**: which error helper, how deploys work, what needs a migration review.
4. **Anything you've had to correct twice.**

Everything else is noise, or belongs in a different mechanism:

| It's really… | Put it in |
|---|---|
| A rule that can't bend ("never edit `src/gen`", "always run the license script") | A deny rule or hook (Folder 03 file 02, Folder 05) |
| Instructions for part of the codebase | `.claude/rules/<topic>.md` with `paths:` |
| A team procedure (release, migration review) | A skill (Folder 04) |
| Personal preferences | `CLAUDE.local.md` or `~/.claude/CLAUDE.md` |
| Task state ("currently migrating payments") | `progress.md` / `SPEC.md` (Folder 02 file 03) |
| Architecture tour, file layout | Nowhere; Claude reads the repo |

### 1.7 After compaction

When `/compact` runs, the **root CLAUDE.md and auto memory are re-injected** and up to five recently edited files are re-read [doc: context-window]. That makes CLAUDE.md the safest home for the handful of invariants that must survive long sessions. Folder 02 file 03 measured state files keeping 97% of facts against 36% for summaries alone.

---

## 2. Practice

### 2.1 The CLAUDE.md for a Java 21 / Spring Boot monorepo (31 lines; lint-clean)

```markdown
# order-platform - Claude Code project memory

## Commands
- Build + unit tests: `./mvnw -q verify -DskipITs`
- One test class: `./mvnw -q test -Dtest=OrderServiceTest`
- Integration tests (Docker required): `./mvnw -q verify -Pit`
- Format: `./mvnw -q spotless:apply` (CI runs `spotless:check`)
- Architecture rules: `./mvnw -q test -Dtest=ArchitectureTest`
- Local stack: `docker compose up -d postgres kafka`

## Conventions (team decisions the code alone does not show)
- Java 21, Spring Boot 3.5; build only with the Maven wrapper.
- Constructor injection; no `@Autowired` fields.
- DTOs and events are `record`s; controllers never return entities.
- Errors are RFC 9457 `ProblemDetail` from `ApiErrors`; never expose exception messages.
- Schema changes are Flyway files in `src/main/resources/db/migration/`; applied migrations are immutable; `ddl-auto: validate`.
- No Kafka or HTTP call inside a transaction; publish through the outbox (`outbox` table, `OutboxRelay`).
- Transactional work called from the same class goes through `TransactionTemplate` (proxy self-invocation).
- Outbound HTTP uses the `RestClient` beans from `HttpClientsConfig`, which set timeouts.
- Entity ids use `SEQUENCE` with a pooled optimizer, not `IDENTITY`.
- Tests: JUnit 5 + Testcontainers (`AbstractIT` starts PostgreSQL 17 and Kafka); no H2.

## Gotchas
- `legacy-billing/` is live but frozen: do not copy its patterns (field injection, `RestTemplate`).
- The `generated/` package comes from `api/openapi.yaml`; change the YAML, then regenerate.
- `application-local.yml` is gitignored; copy `application-local.example.yml`.

## Where to look
- Feature specs: `docs/specs/` - implement against the spec's invariants and fill in its traceability table.
- Path-scoped rules: `.claude/rules/` (persistence, messaging, testing).
- Done means `./mvnw -q verify` passes.
```

Notice what it *doesn't* contain: no project tree, no "write clean code", no IMPORTANT, no "never edit `generated/`" as a bare rule. That one is a deny rule plus a hook; here it is only an explanation of *where to change instead*. It also has no task notes. The conventions are the brief's list (constructor injection, record DTOs, ProblemDetail, Flyway, Testcontainers), each phrased as a checkable decision.

### 2.2 Path-scoped rules (`.claude/rules/`)

`.claude/rules/persistence.md`:

```markdown
---
paths:
  - "**/src/main/java/**/repository/**"
  - "**/src/main/resources/db/migration/**"
---
# Persistence
- New migration = next V<n>__<snake_case>.sql; never edit or renumber an applied one.
- Every new foreign key gets an index in the same migration.
- Repositories return records or entities, never Optional<List<...>>; paginate with keyset (id > :after) for scans.
- Batch inserts: hibernate.jdbc.batch_size=50 with SEQUENCE ids; verify with the statistics log in OrderRepositoryIT.
```

`.claude/rules/messaging.md`:

```markdown
---
paths:
  - "**/src/main/java/**/messaging/**"
  - "**/src/main/java/**/*Listener.java"
---
# Kafka
- Producers: enable.idempotence=true, acks=all; key = aggregate id.
- Consumers are idempotent: dedupe on (topic, partition, offset) or event id in processed_event with a unique index.
- Never call KafkaTemplate.send in a transaction; write an outbox row (see OutboxRelay).
```

`.claude/rules/testing.md`:

```markdown
---
paths:
  - "**/src/test/**"
---
# Tests
- Integration tests extend AbstractIT (Testcontainers PostgreSQL 17 + Kafka); no H2, no embedded Kafka.
- Concurrency tests: CyclicBarrier with >= 50 threads; assert invariants, not timing.
- No Thread.sleep for synchronization; use Awaitility with a timeout.
```

### 2.3 Personal and user-level files

`CLAUDE.local.md` (gitignored):

```markdown
- My local Postgres listens on 5433 (application-local.yml points there).
- Prefer running single test classes; ask before running the full -Pit suite (it takes 9 minutes on my laptop).
```

`~/.claude/CLAUDE.md`:

```markdown
- When you finish, lead with the outcome in one sentence, then the evidence (command + output).
- I review diffs in IntelliJ; keep each commit to one logical change.
```

### 2.4 Monorepo layout

```text
repo/
├── CLAUDE.md                     # 31 lines: commands, conventions, gotchas, pointers
├── .claude/
│   ├── settings.json             # permissions + hooks (Folder 03 file 02, Folder 05)
│   └── rules/{persistence,messaging,testing}.md
├── order-service/CLAUDE.md       # loads only when Claude works in order-service/
├── payment-service/CLAUDE.md
└── docs/specs/*.md               # SPEC.md per feature (Folder 02 file 01)
```

In a huge monorepo where an ancestor CLAUDE.md belongs to another team, use the `claudeMdExcludes` setting with glob patterns, such as `"**/other-team/CLAUDE.md"` [doc].

### 2.5 Maintenance routine

1. Generate a draft with `/init`, then *delete*. "From there the work is mostly removing lines" [doc].
2. In a session, run `/context` to confirm what loaded.
3. Quarterly, or after a model upgrade: run `/doctor prompt-audit`, which flags instructions written for older models, pointing at missing files, or contradicting each other [doc].
4. In CI: run L1 on every change to CLAUDE.md and `.claude/rules/`.

---

## 3. Verified listing

### L1 · `claude_md_lint.py`: CLAUDE.md against Claude Code's guidance

**What it shows.** Ten rules (CM01–CM10):
- **CM01** size (200 docs target, 150 team target)
- **CM02** emphasis inflation
- **CM03** architecture tour
- **CM04** unverifiable instructions
- **CM05** missing build/test command
- **CM06** imports that don't resolve or exceed 4 hops
- **CM07** contradictions
- **CM08** secrets
- **CM09** task state
- **CM10** rules that should be hooks or deny rules

The 219-line BAD file trips all ten. The 31-line GOOD file (§2.1) is clean.

**What it does not show.** Whether a line is *true* about your repo. `/doctor prompt-audit` checks references against the files.

Run: `python claude_md_lint.py`.

```python
"""claude_md_lint.py - lint a CLAUDE.md against Claude Code's own guidance (code.claude.com memory and
best-practices pages, 2026-10-30): under 200 lines; concrete, verifiable instructions; the commands that
check work; no architecture tours Claude can read from the repo; no IMPORTANT/ALL-CAPS inflation; no
contradictions; no secrets; no task state; @imports that resolve within four hops; and rules that cannot
bend flagged for a hook or deny rule instead (CLAUDE.md is context, not enforced configuration).

Run: python claude_md_lint.py   (stdlib only; prints ALL ASSERTIONS PASSED)
"""
import pathlib
import re
import tempfile

MAX_LINES, TEAM_TARGET, MAX_IMPORT_HOPS = 200, 150, 4
VAGUE = re.compile(r"\b(clean code|best practices|properly|test your changes|be careful|good quality|as needed|"
                   r"keep (it|files) organi[sz]ed|write good)\b", re.I)
EMPHASIS = re.compile(r"\b(IMPORTANT|CRITICAL|ALWAYS|NEVER|MUST|YOU MUST)\b|!!+")
COMMAND = re.compile(r"`(\./mvnw|mvn|\./gradlew|gradle|npm|pnpm|yarn|make|docker compose|pytest|go test)[^`]*`")
ARCH_TOUR = re.compile(r"^\s*[│├└]──|project structure|directory layout|folder structure|the codebase is organi[sz]ed", re.I)
SECRET = re.compile(r"AKIA[0-9A-Z]{16}|sk-ant-[A-Za-z0-9_-]{10,}|(password|secret|token)\s*[:=]\s*\S{6,}", re.I)
TASK_STATE = re.compile(r"\b(20\d\d-\d\d-\d\d|currently (working|migrating)|this (week|sprint)|TODO|WIP|in progress)\b", re.I)
HARD_RULE = re.compile(r"\b(never (edit|modify|touch|commit|push|delete)|always run|before (every )?commit)\b", re.I)
IMPORT = re.compile(r"(?<![\w`])@([~\w./-]+\.md)\b")


def strip_code(text):
    text = re.sub(r"^```.*?^```", "", text, flags=re.M | re.S)
    return re.sub(r"`[^`\n]*`", "``", text)


def resolve_imports(path, depth=0, seen=None, out=None):
    """Follow @path imports from `path`; record missing files and chains deeper than four hops."""
    seen, out = seen if seen is not None else set(), out if out is not None else []
    for m in IMPORT.finditer(strip_code(path.read_text(encoding="utf-8"))):
        target = (path.parent / m.group(1)).resolve()
        if depth + 1 > MAX_IMPORT_HOPS:
            out.append(("CM06", f"import chain deeper than {MAX_IMPORT_HOPS} hops at {m.group(1)} - not loaded"))
        elif not target.exists():
            out.append(("CM06", f"import @{m.group(1)} does not resolve"))
        elif target not in seen:
            seen.add(target)
            resolve_imports(target, depth + 1, seen, out)
    return out


def lint(path):
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    prose = strip_code(text)
    f = []
    if len(lines) > MAX_LINES:
        f.append(("CM01", f"{len(lines)} lines > {MAX_LINES} (docs target); move partial-scope rules to .claude/rules/"))
    elif len(lines) > TEAM_TARGET:
        f.append(("CM01", f"{len(lines)} lines > team target {TEAM_TARGET}"))
    caps = EMPHASIS.findall(prose)
    if len(caps) > 3:
        f.append(("CM02", f"{len(caps)} emphasis markers (IMPORTANT/ALWAYS/NEVER/MUST/!!) - current models over-apply "
                          "emphasized rules; plain wording, or a hook if it cannot bend"))
    if ARCH_TOUR.search(text):
        f.append(("CM03", "architecture/file-layout tour - Claude reads the repo itself; keep only what it cannot see"))
    for n, line in enumerate(lines, 1):
        if VAGUE.search(strip_code(line)):
            f.append(("CM04", f"line {n}: not verifiable: \"{line.strip()[:60]}\""))
    if not COMMAND.search(text):
        f.append(("CM05", "no build/test command - the single most useful line is the command that checks work"))
    f.extend(resolve_imports(path))
    norm = [re.sub(r"[^a-z@ ]", "", l.lower()) for l in lines]
    reported = set()
    for a in norm:
        m = re.search(r"\b(?<!never )(?<!not )(always use|use)\s+(@?\w+)", a)
        subject = m.group(2) if m else None
        if subject and subject not in reported and any(
                re.search(rf"\b(never use|do not use|dont use|no)\s+{re.escape(subject)}\b", b) for b in norm):
            reported.add(subject)
            f.append(("CM07", f"contradiction around '{subject}' - Claude may pick one arbitrarily"))
    if SECRET.search(text):
        f.append(("CM08", "secret-like value in CLAUDE.md - it is loaded into every session and committed"))
    for n, line in enumerate(lines, 1):
        if TASK_STATE.search(strip_code(line)):
            f.append(("CM09", f"line {n}: task state belongs in progress files, not shared memory: \"{line.strip()[:50]}\""))
    for n, line in enumerate(lines, 1):
        if HARD_RULE.search(strip_code(line)):
            f.append(("CM10", f"line {n}: a rule that cannot bend - enforce with a hook or deny rule (CLAUDE.md is context)"))
    return f


GOOD = """\
# order-platform - Claude Code project memory

## Commands
- Build + unit tests: `./mvnw -q verify -DskipITs`
- One test class: `./mvnw -q test -Dtest=OrderServiceTest`
- Integration tests (Docker required): `./mvnw -q verify -Pit`
- Format: `./mvnw -q spotless:apply` (CI runs `spotless:check`)
- Architecture rules: `./mvnw -q test -Dtest=ArchitectureTest`
- Local stack: `docker compose up -d postgres kafka`

## Conventions (team decisions the code alone does not show)
- Java 21, Spring Boot 3.5; build only with the Maven wrapper.
- Constructor injection; no `@Autowired` fields.
- DTOs and events are `record`s; controllers never return entities.
- Errors are RFC 9457 `ProblemDetail` from `ApiErrors`; never expose exception messages.
- Schema changes are Flyway files in `src/main/resources/db/migration/`; applied migrations are immutable; `ddl-auto: validate`.
- No Kafka or HTTP call inside a transaction; publish through the outbox (`outbox` table, `OutboxRelay`).
- Transactional work called from the same class goes through `TransactionTemplate` (proxy self-invocation).
- Outbound HTTP uses the `RestClient` beans from `HttpClientsConfig`, which set timeouts.
- Entity ids use `SEQUENCE` with a pooled optimizer, not `IDENTITY`.
- Tests: JUnit 5 + Testcontainers (`AbstractIT` starts PostgreSQL 17 and Kafka); no H2.

## Gotchas
- `legacy-billing/` is live but frozen: do not copy its patterns (field injection, `RestTemplate`).
- The `generated/` package comes from `api/openapi.yaml`; change the YAML, then regenerate.
- `application-local.yml` is gitignored; copy `application-local.example.yml`.

## Where to look
- Feature specs: `docs/specs/` - implement against the spec's invariants and fill in its traceability table.
- Path-scoped rules: `.claude/rules/` (persistence, messaging, testing).
- Done means `./mvnw -q verify` passes.
"""

BAD = "\n".join([
    "# Project Guide", "",
    "IMPORTANT: ALWAYS follow these rules!! YOU MUST read everything. NEVER skip a rule. MUST MUST MUST.", "",
    "## Project structure", "src/main/java/com/acme", "├── order/      # order domain", "├── payment/    # payments",
    "└── shared/     # shared code", "",
    "## Rules", "- Write clean code and follow best practices.", "- Test your changes.",
    "- Always use Lombok for entities.", "- Never use Lombok.",
    "- Never edit files in src/main/java/com/acme/generated.",
    "- 2026-10-12: currently migrating payments to the outbox; TODO finish relay.",
    "- AWS key for local tests: AKIAABCDEFGHIJKLMNOP", "",
    "See @docs/missing.md and @docs/a.md for more.",
] + [f"- Note {i}: keep files organized." for i in range(1, 200)])

with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    (root / "docs").mkdir()
    chain = ["a", "b", "c", "d", "e"]                      # CLAUDE.md -> a -> b -> c -> d -> e (5 hops)
    for i, name in enumerate(chain):
        nxt = f"See @{chain[i + 1]}.md\n" if i + 1 < len(chain) else "end\n"
        (root / "docs" / f"{name}.md").write_text(nxt, encoding="utf-8")
    results = {}
    for label, body in [("BAD CLAUDE.md", BAD), ("GOOD CLAUDE.md (Java 21 / Spring Boot)", GOOD)]:
        p = root / "CLAUDE.md"
        p.write_text(body, encoding="utf-8")
        found = lint(p)
        results[label] = {c for c, _ in found}
        print(f"--- {label}: {len(body.splitlines())} lines, {len(found)} finding(s) {sorted(results[label])}")
        shown = {}
        for code, msg in found:                            # at most two lines per rule, then a count
            shown[code] = shown.get(code, 0) + 1
            if shown[code] <= 2:
                print(f"  {code} {msg}")
        for code, n in shown.items():
            if n > 2:
                print(f"  {code} ... and {n - 2} more")

assert results["BAD CLAUDE.md"] == {f"CM{i:02d}" for i in range(1, 11)}, results["BAD CLAUDE.md"]
assert results["GOOD CLAUDE.md (Java 21 / Spring Boot)"] == set(), results
print("ALL ASSERTIONS PASSED")
```

**Output (verified):**

```text
--- BAD CLAUDE.md: 219 lines, 211 finding(s) ['CM01', 'CM02', 'CM03', 'CM04', 'CM05', 'CM06', 'CM07', 'CM08', 'CM09', 'CM10']
  CM01 219 lines > 200 (docs target); move partial-scope rules to .claude/rules/
  CM02 8 emphasis markers (IMPORTANT/ALWAYS/NEVER/MUST/!!) - current models over-apply emphasized rules; plain wording, or a hook if it cannot bend
  CM03 architecture/file-layout tour - Claude reads the repo itself; keep only what it cannot see
  CM04 line 12: not verifiable: "- Write clean code and follow best practices."
  CM04 line 13: not verifiable: "- Test your changes."
  CM05 no build/test command - the single most useful line is the command that checks work
  CM06 import @docs/missing.md does not resolve
  CM06 import chain deeper than 4 hops at e.md - not loaded
  CM07 contradiction around 'lombok' - Claude may pick one arbitrarily
  CM08 secret-like value in CLAUDE.md - it is loaded into every session and committed
  CM09 line 17: task state belongs in progress files, not shared memory: "- 2026-10-12: currently migrating payments to the "
  CM10 line 16: a rule that cannot bend - enforce with a hook or deny rule (CLAUDE.md is context)
  CM04 ... and 199 more
--- GOOD CLAUDE.md (Java 21 / Spring Boot): 31 lines, 0 finding(s) []
ALL ASSERTIONS PASSED
```

---

## 4. Failure modes

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| F1 | Claude ignores a CLAUDE.md line | The file is too long, or the line is a must-hold rule | Shorten; move it to a hook or deny rule |
| F2 | Claude over-applies a rule everywhere | IMPORTANT/caps emphasis | Plain wording; scope it with `paths:` |
| F3 | Rules contradict between root and module files | Concatenation, not override | Audit (`/doctor prompt-audit`); one owner per topic |
| F4 | A persistence rule is missing when Claude edits migrations | It sits in root CLAUDE.md and got lost, or isn't scoped | `.claude/rules/persistence.md` with `paths:` |
| F5 | The Explore agent missed a convention | Explore and Plan start without CLAUDE.md | Put must-know facts where the main thread uses them; state the convention in the task prompt |
| F6 | Import silently missing | Bad relative path, a quoted path, > 4 hops, or awaiting external approval | L1 CM06; approve the dialog |
| F7 | Secrets exposed in transcripts | A key in CLAUDE.md | Remove and rotate; deny `Read(./.env*)` |
| F8 | Stale "currently working on" lines confuse new sessions | Task state in shared memory | Move to `progress.md` |
| F9 | Personal settings leak to the team | Personal lines in CLAUDE.md | `CLAUDE.local.md` / `~/.claude/CLAUDE.md` |

---

## 5. Staff-level drills

<details><summary><b>D1 · "Our CLAUDE.md is 600 lines of hard-won rules. Cut it how?"</b></summary>

**Staff answer.** Apply the four-question test (§1.6):
- Architecture and layout: delete.
- Must-hold rules: become deny rules or hooks.
- Partial-scope rules: move into `.claude/rules/*.md` with `paths:`.
- Procedures: become skills.
- Personal preferences: go to `CLAUDE.local.md`.
- Task notes: go to progress files.

What remains is usually under 60 lines: commands, misleading spots, unwritten decisions, repeat corrections. Then run `/doctor prompt-audit` and L1 in CI.
</details>

<details><summary><b>D2 · "Why not import our whole docs/ folder into CLAUDE.md?"</b></summary>

**Staff answer.** Imports load with the file, so you'd pay for all of it on every task and dilute the lines that matter. Link to specs by path ("implement against `docs/specs/`") and let Claude read the one it needs. Use path-scoped rules for conventions tied to file types.
</details>

<details><summary><b>D3 · "Explore subagent results ignore our conventions. Bug?"</b></summary>

**Staff answer.** It's by design. Explore and Plan start without CLAUDE.md "to keep research fast and inexpensive" [doc]. They gather facts; the main thread, which has CLAUDE.md, applies conventions when it writes the plan and the code. If research itself needs a convention ("ignore `legacy-billing/`"), state it in the request you make.
</details>

<details><summary><b>D4 · "What's the difference between CLAUDE.md and auto memory?"</b></summary>

**Staff answer.** You write CLAUDE.md, and it holds team instructions, versioned in git. Claude writes auto memory: per-repo learnings such as your preferences, your corrections, and project facts it can't derive. Auto memory is capped at 200 lines / 25 KB loaded, and shared across that repo's worktrees. Review it with `/memory`, and promote anything the whole team needs into CLAUDE.md.
</details>

---

## 6. Checklist

- [ ] Root CLAUDE.md is under 200 lines (target ≤ 60) and starts with commands.
- [ ] No architecture tour, no IMPORTANT/caps, no vague lines, no secrets, no task state.
- [ ] Must-hold rules are deny rules or hooks; partial-scope rules are path-scoped files.
- [ ] Personal preferences are in `CLAUDE.local.md` (gitignored) or `~/.claude/CLAUDE.md`.
- [ ] Imports resolve within 4 hops.
- [ ] L1 runs in CI; `/doctor prompt-audit` runs quarterly and after model upgrades.

---

## 7. References

- How Claude remembers your project (CLAUDE.md, rules, imports, auto memory, AGENTS.md): <https://code.claude.com/docs/en/memory>
- Best practices ("Keep CLAUDE.md short", "What you can stop doing"): <https://code.claude.com/docs/en/best-practices>
- Context window and compaction (what survives `/compact`): <https://code.claude.com/docs/en/context-window>
- Subagents (Explore and Plan start without CLAUDE.md): <https://code.claude.com/docs/en/sub-agents>
- Settings reference (`claudeMdExcludes`, `autoMemoryDirectory`): <https://code.claude.com/docs/en/settings-reference>
- Claude directory layout: <https://code.claude.com/docs/en/claude-directory>

Previous: [02 · Workflow and worktrees](02-the-explore-plan-execute-verify-workflow-and-git-worktree-parallel-agents.md) · [01 · Cheat sheet](01-complete-slash-commands-cli-flags-and-keyboard-shortcuts-cheat-sheet.md) · [KB README](../README.md)

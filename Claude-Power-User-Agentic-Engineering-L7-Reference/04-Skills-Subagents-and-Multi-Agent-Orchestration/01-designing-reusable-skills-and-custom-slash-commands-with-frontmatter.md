# Designing Reusable Skills and Custom Slash Commands with Frontmatter

> **Folder 04 · File 1 of 3** · verified 2026-10-30 against code.claude.com `skills.md` (frontmatter reference, substitutions, lifecycle, fork mode)
> **Listing:** `skill_lint.py` (lints SKILL.md against the documented frontmatter and behaviour; its GOOD fixture is the `/new-slice` skill)

---

## 0. Orientation

A **skill** is a folder with a `SKILL.md` (YAML frontmatter plus instructions) and optional supporting files, which Claude loads when it's relevant, or you start it with `/name`. It is the right home for team *procedures*: the scaffolding recipe, the release checklist, the migration playbook. Those would bloat CLAUDE.md if they lived there, and drift if they lived in people's heads.

Since 2026 skills and custom slash commands are the same mechanism. The older `.claude/commands/*.md` files still work, with the same frontmatter except `name` and `paths` [doc].

This file covers how skills load (and what that costs), the frontmatter that controls invocation and permissions, substitutions and dynamic context, fork mode, and a production `/new-slice` skill that generates Controller, Service, Repository, a Flyway migration and a Testcontainers IT in one command.

### 0.1 The twelve rules

1. **The description is the trigger.** Claude decides when to use a skill from `description` plus `when_to_use`, which are truncated at 1,536 characters in the listing. Put the use case first, and say *when*. [doc]
2. **Side effects → `disable-model-invocation: true`.** You don't want Claude deciding to deploy "because your code looks ready". [doc]
3. **Background knowledge → `user-invocable: false`.** Claude may load it, and nobody types it. [doc]
4. **Keep the body short.** A loaded skill "stays in context across turns, so every line is a recurring token cost". [doc]
5. **Push detail into supporting files**, referenced from SKILL.md so Claude loads them only when needed. Scripts are *executed*, not loaded. [doc]
6. **`allowed-tools` pre-approves tools for the invoking turn only.** The grant clears with your next message. Never grant bare `Bash`. [doc + measured: L1]
7. **Use `${CLAUDE_SKILL_DIR}` for bundled scripts**, in both the body and the `allowed-tools` rules, so the pre-approval matches the exact command. [doc]
8. **Arguments:** `$ARGUMENTS`, `$0`/`$1`, or named `arguments: [a, b]` → `$a`/`$b`. An undeclared `$name` stays literal. [doc + measured: L1]
9. **`` !`command` `` injects live context** (a diff, a status) before Claude sees the skill. [doc]
10. **`context: fork` runs the skill in a subagent that doesn't see your history.** It runs in the background by default, and its edits fall outside checkpoints. [doc]
11. **Scope reference skills with `paths:`**, so they activate only on matching files. [doc]
12. **Measure skills.** `/skill-doctor` shows each skill's context cost and usage; prune the ones nobody uses. [doc]

---

## 1. First principles

### 1.1 Progressive disclosure: what loads when [doc]

| Stage | What enters context | Cost |
|---|---|---|
| Session start | Each skill's name plus `description` (+ `when_to_use`), capped at 1,536 characters per skill | Every session, every skill. This is why descriptions must be tight and why unused skills should go. |
| Invocation (by you or Claude) | The rendered SKILL.md body, as one message | Stays in context for the rest of the session, and is re-attached after compaction within a token budget |
| On demand | Supporting files the body points at (`reference.md`, `examples.md`) | Only when Claude decides it needs them |
| Execution | `scripts/*.sh`, `*.py` run through Bash | Only their output enters context |

This is Folder 01's token economics applied to instructions. A 400-line skill invoked once costs 400 lines on every later turn of that session. A 40-line skill that points at a 400-line reference costs 40, plus the reference only when it's consulted.

### 1.2 Who can invoke a skill [doc]

| Frontmatter | You (`/name`) | Claude (automatically) | Typical use |
|---|---|---|---|
| (default) | yes | yes | Conventions, how-tos |
| `disable-model-invocation: true` | yes | **no**: if Claude tries, Claude Code blocks it and tells it not to reproduce the steps another way | `/deploy`, `/release`, `/send-slack-message`, `/new-slice` |
| `user-invocable: false` | **no** (hidden from the `/` menu) | yes | `legacy-billing-context`, domain glossaries |

Permission rules can also restrict skills, for example a `Skill(skill:<name>)` deny rule that matches every name the skill goes by [doc].

### 1.3 Where skills live, and precedence [doc]

| Location | Path | Loads in |
|---|---|---|
| Enterprise | `.claude/skills/<name>/SKILL.md` in the managed settings directory | Everyone on managed machines |
| Personal | `~/.claude/skills/<name>/SKILL.md` | All your projects on this machine |
| Project | `.claude/skills/<name>/SKILL.md` | This repository (commit it) |
| Nested | `<subdir>/.claude/skills/<name>/SKILL.md` | Sessions in or below `<subdir>`, or once Claude works on files there |
| Additional directory | `--add-dir` directories | That session |
| Plugin | `<plugin>/skills/<name>/SKILL.md` | As `/plugin-name:skill-name` where enabled |

Reserved names: `synced`, `anthropic-skills…`. A `:` is reserved for plugin namespaces. After editing skills mid-session, run `/reload-skills`.

### 1.4 The frontmatter that matters [doc]

| Field | Use it for |
|---|---|
| `name`, `description`, `when_to_use` | Command name (defaults to the folder name); the trigger text |
| `argument-hint`, `arguments` | Autocomplete hint; named positional arguments (`$aggregate`) |
| `disable-model-invocation`, `user-invocable` | Who may invoke it (§1.2) |
| `allowed-tools`, `disallowed-tools` | Pre-approve or remove tools *for the invoking turn* |
| `model`, `effort` | Override for the rest of the turn (e.g. `effort: high` for an audit skill) |
| `context: fork`, `agent`, `background` | Run in a subagent (`agent: Explore` for read-only research); wait for it with `background: false` |
| `paths` | Glob patterns that limit automatic activation |
| `hooks` | Hooks registered while the skill is active |
| `shell` | `bash` (default) or `powershell` for `!` injections |
| `metadata`, `license`, `compatibility` | Your own tooling; the Agent Skills spec |

### 1.5 Substitutions and dynamic context [doc]

- `$ARGUMENTS` is the full argument string. `$ARGUMENTS[N]` or `$N` (0-based) give single arguments, with shell-style quoting. `$name` comes from `arguments:`. An indexed placeholder without a value stays literal, and a missing named argument becomes empty.
- `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_SESSION_ID}` and `${CLAUDE_EFFORT}` are available. `${CLAUDE_SKILL_DIR}` and `${CLAUDE_PROJECT_DIR}` are substituted in the body **and** in `allowed-tools` Bash rules.
- `` !`git diff HEAD` `` runs before Claude reads the skill and inlines the output, so the instructions arrive with live data. Injected commands go through permission checks.
- Escape a literal `$1.00` as `\$1.00`.

### 1.6 Fork mode [doc]

`context: fork` starts a subagent of type `agent` and gives it the skill body as its prompt. That subagent **does not see your conversation**, so the skill must stand on its own.

- It runs in the background by default; set `background: false` to wait. In `-p` mode Claude Code always waits.
- Background forks get the narrower background tool set.
- Their edits are **not restored by `/rewind`**.

Use fork mode for research and audits that would flood your context, not for edits you want checkpointed.

### 1.7 Skill vs. CLAUDE.md vs. subagent vs. hook vs. MCP

| You have… | Use |
|---|---|
| A fact every task needs (the build command, a frozen directory) | CLAUDE.md |
| A procedure some tasks need (scaffold a slice, cut a release) | **Skill** |
| Work that should run in its own context, possibly with other tools or another model | Subagent (file 02), or a skill with `context: fork` |
| A rule that must always or never happen | Hook or deny rule (Folder 05) |
| Access to an external system (DB schema, tickets, docs) | MCP server (Folder 06) |

---

## 2. Practice

### 2.1 `/new-slice`: Controller + Service + Repository + Flyway + Testcontainers IT

```text
.claude/skills/new-slice/
├── SKILL.md              # 30 lines: procedure + done criterion
├── reference.md          # package layout, class shapes - loaded only when Claude needs it
└── scripts/
    └── next_migration.sh # prints the highest V<n> in a module - executed, never loaded
```

`SKILL.md` (verbatim from L1's GOOD fixture, which lints clean):

```markdown
---
name: new-slice
description: Scaffold one vertical slice - REST controller, service, repository, Flyway migration and a Testcontainers integration test - for a new aggregate in order-platform. Use when the user asks to add a new resource, entity or endpoint end to end.
argument-hint: "<Aggregate> <module>"
arguments: [aggregate, module]
disable-model-invocation: true
allowed-tools: Read Glob Grep Edit Write Bash(./mvnw -q *) Bash(${CLAUDE_SKILL_DIR}/scripts/next_migration.sh *)
---
# New vertical slice: $aggregate in $module

Read [reference.md](reference.md) first; it holds the package layout and the exact class shapes.

Create, in this order (each step must compile before the next):
1. Migration: run `${CLAUDE_SKILL_DIR}/scripts/next_migration.sh $module` for the next version, then write
   `V<n>__create_<table>.sql` with the table, a SEQUENCE, indexes for every foreign key, and NOT NULL defaults.
2. Entity + repository: SEQUENCE ids with a pooled optimizer; repository methods paginate with keyset.
3. Service: constructor injection; transactions via TransactionTemplate; no Kafka/HTTP inside a transaction;
   publish events through the outbox.
4. Controller: request/response records with Bean Validation; errors as ProblemDetail through ApiErrors.
5. Integration test `<Aggregate>ApiIT extends AbstractIT`: create, read, validation error (400 ProblemDetail),
   duplicate Idempotency-Key, and pagination.

Done when `./mvnw -q -pl $module verify -Pit` passes. Report the command and its summary lines, then list the
files you created.
```

Usage: `/new-slice Shipment order-service`.

Why each choice:
- `disable-model-invocation`: it creates many files, so you choose when it runs.
- Named arguments: readable.
- `allowed-tools`: approves exactly the two commands the body uses, for this turn only.
- Numbered steps: these are *actions in a required order*, which is correct even with thinking on (Folder 01 file 02 §1.2).
- A pass/fail done criterion, with evidence.

### 2.2 A reference skill scoped by path

```markdown
---
name: persistence-conventions
description: JPA, Flyway and query conventions for order-platform. Use when writing or reviewing repositories, entities or migrations.
user-invocable: false
paths: ["**/repository/**", "**/db/migration/**", "**/*Entity.java"]
---
- Ids: SEQUENCE with pooled optimizer (allocationSize 50); never IDENTITY on hot tables.
- Scans: keyset pagination (where id > :after order by id limit :n); never OFFSET on large tables.
- Every FK gets an index in the same migration; never edit an applied migration.
- Detail and examples: [reference.md](reference.md).
```

The same content can live in `.claude/rules/persistence.md` (Folder 03 file 03). Choose a **rule** when it is a short list Claude must always see on those files. Choose a **skill** when it has supporting files, examples or scripts.

### 2.3 A forked research skill (no edits, no context flood)

```markdown
---
name: blast-radius
description: Find every caller, consumer and test affected by changing a class or table. Use before refactoring shared code or schema.
context: fork
agent: Explore
argument-hint: "<class-or-table>"
---
Find everything that depends on $ARGUMENTS in this repository: direct callers, Spring injection points,
Kafka consumers of its events, SQL that reads or writes the table, and tests that exercise it.
Return a table: path | kind (caller/consumer/sql/test) | why it is affected. No proposals, no edits.
```

### 2.4 A side-effecting team procedure

```markdown
---
name: release-check
description: Pre-release checklist for a service - versions, migrations, changelog, dashboards. Use only when the user starts a release.
disable-model-invocation: true
argument-hint: "<service> <version>"
allowed-tools: Read Grep Bash(git log *) Bash(./mvnw -q *)
---
Changes since the last tag: !`git log --oneline $(git describe --tags --abbrev=0)..HEAD`

For $0 at version $1, verify and report pass/fail with evidence for each:
1. `./mvnw -q -pl $0 verify -Pit` passes.
2. New Flyway migrations are backward compatible with the previous release (no drops or renames).
3. CHANGELOG.md has an entry for $1 covering the commits above.
Do not tag, push or deploy; print the commands a human should run next.
```

---

## 3. Verified listing

### L1 · `skill_lint.py`

**What it shows.** Eleven checks (SK01–SK11) derived from the frontmatter reference and behaviour docs:
- unknown fields
- the 1,536-character description cap
- side effects without `disable-model-invocation`
- bare `Bash` in `allowed-tools`
- undeclared `$names`
- missing supporting files and scripts
- long bodies
- fork-only fields without `context: fork`
- reserved names
- descriptions with no *when*

The BAD skill trips nine; `/new-slice` (with its `reference.md` and `scripts/next_migration.sh`) is clean.

**What it does not show.** Whether Claude follows the skill well. Evaluate that by running it on real tasks; the skills docs describe evals with the skill-creator plugin.

Run: `pip install pyyaml && python skill_lint.py`.

```python
"""skill_lint.py - lint .claude/skills/<name>/SKILL.md against the frontmatter reference and behaviour in
Claude Code's skills docs (2026-10-30), then check the skill's supporting files exist.

  SK01 frontmatter missing or not YAML         SK07 $name placeholder not declared in `arguments`
  SK02 unknown frontmatter field               SK08 referenced supporting file / script missing
  SK03 no description, or description +        SK09 body long (skill content stays in context
       when_to_use over the 1,536-char cap           across turns: a recurring token cost)
  SK04 side-effecting task (deploy/push/release/ SK10 `agent` or `background` without
       migrate prod...) without                       `context: fork` (they only apply to forks)
       disable-model-invocation: true          SK11 reserved or invalid name (synced,
  SK05 bare `Bash` (or `*`) in allowed-tools          anthropic-skills*, ':' outside plugins)
  SK06 description says nothing about WHEN to use it

Run: python skill_lint.py   (needs pyyaml; prints ALL ASSERTIONS PASSED)
"""
import pathlib
import re
import tempfile

import yaml

FIELDS = {"name", "description", "when_to_use", "argument-hint", "arguments", "disable-model-invocation",
          "user-invocable", "allowed-tools", "disallowed-tools", "model", "effort", "context", "agent",
          "background", "hooks", "paths", "shell", "metadata", "license", "compatibility"}
SIDE_EFFECT = re.compile(r"\b(deploy|git push|publish|release|send (a )?(slack|email|message)|drop table|"
                         r"migrate (the )?prod|kubectl apply|terraform apply)\b", re.I)
WHEN = re.compile(r"\b(use (this )?when|use (it )?for|when the user|trigger|after|before)\b", re.I)
MAX_BODY_LINES = 120


def parse(text):
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not m:
        return None, text
    try:
        return yaml.safe_load(m.group(1)) or {}, m.group(2)
    except yaml.YAMLError:
        return None, text


def as_list(v):
    if v is None:
        return []
    if isinstance(v, list):
        return [str(x) for x in v]
    return [t for t in re.split(r"[,\s]+(?![^()]*\))", str(v)) if t]


def lint(skill_dir):
    skill_dir = pathlib.Path(skill_dir)
    fm, body = parse((skill_dir / "SKILL.md").read_text(encoding="utf-8"))
    if fm is None:
        return [("SK01", "frontmatter missing or not valid YAML")]
    f = []
    for k in sorted(set(fm) - FIELDS):
        f.append(("SK02", f"unknown field '{k}' (ignored)"))
    desc = str(fm.get("description") or "")
    if not desc:
        f.append(("SK03", "no description - Claude decides when to use a skill from it"))
    elif len(desc) + len(str(fm.get("when_to_use") or "")) > 1536:
        f.append(("SK03", "description + when_to_use exceed the 1,536-char listing cap (truncated)"))
    if desc and not WHEN.search(desc + " " + str(fm.get("when_to_use") or "")):
        f.append(("SK06", "description says what, not when - add 'Use when ...'"))
    if SIDE_EFFECT.search(body + " " + desc) and fm.get("disable-model-invocation") is not True:
        f.append(("SK04", "side-effecting workflow Claude may start on its own - set disable-model-invocation: true"))
    for t in as_list(fm.get("allowed-tools")):
        if t in ("Bash", "*", "Bash(*)"):
            f.append(("SK05", f"allowed-tools '{t}' pre-approves every shell command for the turn"))
    declared = set(as_list(fm.get("arguments")))
    builtin = {"ARGUMENTS", "CLAUDE_SESSION_ID", "CLAUDE_EFFORT", "CLAUDE_SKILL_DIR", "CLAUDE_PROJECT_DIR",
               "CLAUDE_PLUGIN_ROOT", "CLAUDE_PLUGIN_DATA"}
    for name in sorted(set(re.findall(r"(?<!\\)\$([A-Za-z_]\w*)", body)) - builtin - declared):
        f.append(("SK07", f"${name} is not declared in `arguments` - it stays literal"))
    refs = set(re.findall(r"\]\(([\w./-]+\.(?:md|sh|py|java|sql|txt))\)", body))
    refs |= {m for m in re.findall(r"\$\{CLAUDE_SKILL_DIR\}/([\w./-]+)", body + str(fm.get("allowed-tools", "")))}
    for r in sorted(refs):
        if not (skill_dir / r).exists():
            f.append(("SK08", f"references {r}, which is not in the skill directory"))
    if len(body.strip().splitlines()) > MAX_BODY_LINES:
        f.append(("SK09", f"body is {len(body.strip().splitlines())} lines - move detail into supporting files loaded on demand"))
    if fm.get("context") != "fork" and ("agent" in fm or "background" in fm):
        f.append(("SK10", "`agent`/`background` only apply with context: fork"))
    name = str(fm.get("name") or skill_dir.name)
    if name.lower() == "synced" or name.lower().startswith("anthropic-skills") or ":" in name:
        f.append(("SK11", f"name '{name}' is reserved or invalid outside a plugin"))
    return f


NEW_SLICE = """---
name: new-slice
description: Scaffold one vertical slice - REST controller, service, repository, Flyway migration and a Testcontainers integration test - for a new aggregate in order-platform. Use when the user asks to add a new resource, entity or endpoint end to end.
argument-hint: "<Aggregate> <module>"
arguments: [aggregate, module]
disable-model-invocation: true
allowed-tools: Read Glob Grep Edit Write Bash(./mvnw -q *) Bash(${CLAUDE_SKILL_DIR}/scripts/next_migration.sh *)
---
# New vertical slice: $aggregate in $module

Read [reference.md](reference.md) first; it holds the package layout and the exact class shapes.

Create, in this order (each step must compile before the next):
1. Migration: run `${CLAUDE_SKILL_DIR}/scripts/next_migration.sh $module` for the next version, then write
   `V<n>__create_<table>.sql` with the table, a SEQUENCE, indexes for every foreign key, and NOT NULL defaults.
2. Entity + repository: SEQUENCE ids with a pooled optimizer; repository methods paginate with keyset.
3. Service: constructor injection; transactions via TransactionTemplate; no Kafka/HTTP inside a transaction;
   publish events through the outbox.
4. Controller: request/response records with Bean Validation; errors as ProblemDetail through ApiErrors.
5. Integration test `<Aggregate>ApiIT extends AbstractIT`: create, read, validation error (400 ProblemDetail),
   duplicate Idempotency-Key, and pagination.

Done when `./mvnw -q -pl $module verify -Pit` passes. Report the command and its summary lines, then list the
files you created.
"""

REFERENCE = "# Slice reference\n- Package: com.acme.<module>.<aggregate>\n- Controller returns records, never entities.\n"
NEXT_MIGRATION = "#!/usr/bin/env bash\nls \"$1/src/main/resources/db/migration\" | sed -E 's/^V([0-9]+)__.*/\\1/' | sort -n | tail -1\n"

BAD = """---
name: synced
allowed-tools: Bash
agent: Explore
trigger: on-deploy
---
Deploy $env to production: run the tests, git push the release tag, then publish the image.
See [checklist.md](checklist.md).
""" + "\n".join(f"- step {i}: double-check everything carefully" for i in range(130))

with tempfile.TemporaryDirectory() as tmp:
    good = pathlib.Path(tmp, "new-slice")
    (good / "scripts").mkdir(parents=True)
    (good / "SKILL.md").write_text(NEW_SLICE, encoding="utf-8")
    (good / "reference.md").write_text(REFERENCE, encoding="utf-8")
    (good / "scripts" / "next_migration.sh").write_text(NEXT_MIGRATION, encoding="utf-8")
    bad = pathlib.Path(tmp, "release-prod")
    bad.mkdir()
    (bad / "SKILL.md").write_text(BAD, encoding="utf-8")
    for label, d, expected in [("BAD skill", bad, {f"SK{i:02d}" for i in range(2, 12) if i != 6}),
                               ("GOOD /new-slice skill", good, set())]:
        found = lint(d)
        codes = {c for c, _ in found}
        print(f"--- {label}: {sorted(codes) or 'clean'}")
        for c, m in found:
            print(f"  {c} {m}")
        assert codes == expected, (label, sorted(codes))
print("--- .claude/skills/new-slice/SKILL.md")
print(NEW_SLICE)
print("ALL ASSERTIONS PASSED")
```

**Output (verified):**

```text
--- BAD skill: ['SK02', 'SK03', 'SK04', 'SK05', 'SK07', 'SK08', 'SK09', 'SK10', 'SK11']
  SK02 unknown field 'trigger' (ignored)
  SK03 no description - Claude decides when to use a skill from it
  SK04 side-effecting workflow Claude may start on its own - set disable-model-invocation: true
  SK05 allowed-tools 'Bash' pre-approves every shell command for the turn
  SK07 $env is not declared in `arguments` - it stays literal
  SK08 references checklist.md, which is not in the skill directory
  SK09 body is 132 lines - move detail into supporting files loaded on demand
  SK10 `agent`/`background` only apply with context: fork
  SK11 name 'synced' is reserved or invalid outside a plugin
--- GOOD /new-slice skill: clean
--- .claude/skills/new-slice/SKILL.md
---
name: new-slice
description: Scaffold one vertical slice - REST controller, service, repository, Flyway migration and a Testcontainers integration test - for a new aggregate in order-platform. Use when the user asks to add a new resource, entity or endpoint end to end.
argument-hint: "<Aggregate> <module>"
arguments: [aggregate, module]
disable-model-invocation: true
allowed-tools: Read Glob Grep Edit Write Bash(./mvnw -q *) Bash(${CLAUDE_SKILL_DIR}/scripts/next_migration.sh *)
---
# New vertical slice: $aggregate in $module

Read [reference.md](reference.md) first; it holds the package layout and the exact class shapes.

Create, in this order (each step must compile before the next):
1. Migration: run `${CLAUDE_SKILL_DIR}/scripts/next_migration.sh $module` for the next version, then write
   `V<n>__create_<table>.sql` with the table, a SEQUENCE, indexes for every foreign key, and NOT NULL defaults.
2. Entity + repository: SEQUENCE ids with a pooled optimizer; repository methods paginate with keyset.
3. Service: constructor injection; transactions via TransactionTemplate; no Kafka/HTTP inside a transaction;
   publish events through the outbox.
4. Controller: request/response records with Bean Validation; errors as ProblemDetail through ApiErrors.
5. Integration test `<Aggregate>ApiIT extends AbstractIT`: create, read, validation error (400 ProblemDetail),
   duplicate Idempotency-Key, and pagination.

Done when `./mvnw -q -pl $module verify -Pit` passes. Report the command and its summary lines, then list the
files you created.

ALL ASSERTIONS PASSED
```

---

## 4. Failure modes

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| F1 | Claude never uses the skill | Description says *what*, not *when*; or it's truncated by the 1,536 cap | "Use when …" first; trim |
| F2 | Claude started a deploy on its own | Side-effecting skill without `disable-model-invocation` | Set it; also deny-rule the deploy command |
| F3 | Context bloat later in the session | A long skill body stays loaded | Move detail to supporting files |
| F4 | `$env` appears literally | Placeholder not declared in `arguments` | Declare it, or use `$0` |
| F5 | Script prompts for permission every time | `allowed-tools` rule doesn't match the exact command | Use `${CLAUDE_SKILL_DIR}` in both places |
| F6 | Forked audit's edits survived `/rewind` | Background fork edits are outside checkpoints | Fork only read-only work; use git |
| F7 | Skill edits not picked up | Cached listing | `/reload-skills` |
| F8 | Two skills with one name, the wrong one runs | Precedence across locations | Rename; check `/skills` |

---

## 5. Staff-level drills

<details><summary><b>D1 · "Skill or CLAUDE.md for our migration conventions?"</b></summary>

**Staff answer.** If every task needs it, use CLAUDE.md, but that is rarely true of migration rules. If it applies when touching migrations, use a path-scoped rule (short list) or a `user-invocable: false` skill with `paths:` (detail plus examples). If it's a *procedure* (create the next migration and verify it), use a task skill invoked as `/new-migration`. The cost model decides: CLAUDE.md costs on every task, and skills cost only when used.
</details>

<details><summary><b>D2 · "Why does our /deploy skill need <code>disable-model-invocation</code> if we have permission prompts?"</b></summary>

**Staff answer.** Auto mode reduces prompts, and a skill's `allowed-tools` pre-approves commands. Without the flag, Claude can decide to run the whole procedure when the conversation looks ready. With it, Claude Code blocks Claude's attempt and tells it not to reproduce the steps another way. Belt and braces: also put the production deploy command in `ask` or `deny`.
</details>

<details><summary><b>D3 · "Our skill is 500 lines and works great. Problem?"</b></summary>

**Staff answer.** It works, but after one invocation those 500 lines ride along on every later turn of the session. Keep SKILL.md to the procedure and the done criterion, and link `reference.md` and `examples.md` for detail. Run `/skill-doctor` to see the measured context cost and usage.
</details>

<details><summary><b>D4 · "When should a skill fork?"</b></summary>

**Staff answer.** When the work is self-contained and noisy, such as research, audits or blast-radius analysis, and you only want the summary back. Don't fork when the skill must see the conversation (a forked skill doesn't), or when its edits should be checkpointed (background forks aren't). For "continue this exact discussion elsewhere", use `/fork` or `/subtask`, which copy the conversation.
</details>

---

## 6. Checklist

- [ ] Every skill's description starts with the use case and says when to use it; it stays under 1,536 characters with `when_to_use`.
- [ ] Side-effecting skills set `disable-model-invocation: true`.
- [ ] `allowed-tools` grants exact commands, never bare `Bash`.
- [ ] Bodies are short; detail lives in supporting files; scripts sit under `scripts/` and are referenced via `${CLAUDE_SKILL_DIR}`.
- [ ] L1 lints `.claude/skills/**` in CI; `/skill-doctor` is reviewed quarterly.

---

## 7. References

- Extend Claude with skills (locations, frontmatter, substitutions, lifecycle, fork, restricting access): <https://code.claude.com/docs/en/skills>
- Commands (bundled skills such as `/batch`, `/loop`, `/code-review`): <https://code.claude.com/docs/en/commands>
- Agent Skills specification: <https://agentskills.io>
- Plugins (distributing skills): <https://code.claude.com/docs/en/plugins/overview>

Next: [02 · Isolated subagents](02-building-isolated-subagents-architect-security-auditor-and-test-runner.md) · [03 · Batch, background and headless CI](03-batch-migrations-background-agents-and-headless-ci-cd-automation.md) · [KB README](../README.md)

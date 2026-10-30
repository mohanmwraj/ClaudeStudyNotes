# The Complete Production `.claude/` Folder Blueprint for Java Monorepos

> **Folder 08 · File 1 of 2** · verified 2026-10-30. The blueprint ships as real files in [`blueprint/`](blueprint/), next to this page: 35 files.
> **Listing:** `blueprint_check.py`, which installs the blueprint into a scratch repository and validates it.
> - It uses every linter in this KB, extracted from the published Markdown.
> - It runs 13 cross-reference checks.
> - It plants four kinds of drift to show those checks catch them.

---

## 0. Orientation

Folders 03–07 each built and tested one piece of a team setup: CLAUDE.md, settings, subagents, skills, hooks, MCP, prompt templates. This file assembles them into **one tree you can copy into a Java monorepo**. It also proves they work *together*: the hooks the settings wire exist, every MCP server is enabled and permissioned, the copies match their tested originals.

Nothing in the tree is retyped from memory. A build step pulls each artifact from the listing that tested it:

| Path in your repo | Shipped as | From | Verified by |
|---|---|---|---|
| `CLAUDE.md` (33 lines) | `CLAUDE.template.md` | Folder 03's clean example, updated for Boot 4.1 | `claude_md_lint` (Folder 03) |
| `.claude/settings.json` | `dot-claude/settings.json` | Folder 03 permissions + Folder 05 hook wiring + Folder 06 MCP rules | `settings_validator` + schemastore schema (Folder 03) |
| `.claude/rules/*.md` (4) | `dot-claude/rules/` | this folder | CR06 (`paths:` frontmatter) |
| `.claude/agents/*.md` (4) | `dot-claude/agents/` | Folder 04 | `agent_lint` (Folder 04) |
| `.claude/skills/new-slice/` | `dot-claude/skills/new-slice/` | Folder 04 | `skill_lint` (Folder 04), CR10 |
| `.claude/hooks/*.py` (10) | `dot-claude/hooks/` | Folder 05, 40-case harness | CR00 (byte-identical), CR01–CR02, CR11 |
| `.claude/allowed-deps.txt` | `dot-claude/allowed-deps.txt` | this folder (Boot BOM families) | CR12 (the dependency guard's input exists) |
| `.claude/prompts/t1…t7.xml` | `dot-claude/prompts/` | Folder 07 | `prompt_template_check` (Folder 07), CR00 |
| `.mcp.json` | `dot-mcp.json` | Folder 06 | `mcp_config_lint` (Folder 06), CR03–CR04, CR09 |
| `tools/mcp/order_platform_mcp.py` | `tools/mcp/` | Folder 06, three-SDK conformance | CR00, CR09, CR11 |
| `.github/workflows/claude.yml` | `dot-github/workflows/` | Folder 04 | `ci_workflow_check` (Folder 04) |
| `.gitignore` lines | `gitignore-snippet` | this folder | CR07 |

**Why the odd names.** This KB lives inside a repository you also open in Claude Code. A real `.claude/`, `CLAUDE.md` or `.mcp.json` in a subfolder would load into *your* sessions: subdirectory CLAUDE.md files load on demand [doc]. `dot-claude/`, `dot-mcp.json`, `dot-github/` and `CLAUDE.template.md` stay inert until you install them.

### 0.1 The twelve rules

1. **CLAUDE.md holds only what applies to every task and that the code can't show.** That means commands, team decisions and gotchas. Ours is 33 lines; the brief's bar is under 150, the docs' under 200. [doc + Folder 03]
2. **Path-specific guidance goes in `.claude/rules/*.md` with `paths:` frontmatter.** It loads only when Claude works on matching files, so persistence rules don't cost tokens in a controller change. [doc]
3. **Commit `.claude/settings.json`; never commit `.claude/settings.local.json` or `CLAUDE.local.md`.** Precedence, highest first: managed, command line, project local, shared project, user. [doc]
4. **Permissions are evaluated deny → ask → allow.**
   - **Deny:** secrets and destructive git.
   - **Ask:** pushes and SQL execution.
   - **Allow:** the build and read-only git.

   [doc + Folder 03]
5. **Hooks enforce what CLAUDE.md can only request.** Exec form, `onFailure: block` on guards (v2.1.295+), short timeouts. Ten scripts, nine wired in settings, one in an agent's frontmatter. [doc + Folder 05]
6. **Reviewers are read-only subagents.** No `Edit`/`Write`, plus a frontmatter hook (`readonly_git.py`) that blocks mutating git. [Folder 04]
7. **Scaffolding skills set `disable-model-invocation: true`.** You invoke `/new-slice` deliberately; it never fires on its own. [doc + Folder 04]
8. **Team MCP servers live in `.mcp.json` with `${VAR}` secrets.** `enabledMcpjsonServers` names the same set, and `mcp__<server>__…` rules permission them. All three must agree (CR03–CR04). [doc + Folder 06]
9. **Prompt templates are versioned files** in `.claude/prompts/`, linted in CI, never pasted from a wiki. [Folder 07]
10. **CI runs Claude through `anthropics/claude-code-action@v1`** with turn caps, explicit permissions and an `if:` guard. [doc + Folder 04]
11. **Validate the tree as a whole.** Linters check files; only cross-references catch:
    - a deleted hook that settings still call;
    - a server added but never enabled;
    - a permission rule with a typo'd server name;
    - a hand-edited template.

    [measured: L1]
12. **Treat `.claude/` like build code.** CODEOWNERS on `.claude/**`, `.mcp.json` and `CLAUDE.md`; `blueprint_check.py` in CI; changes reviewed by the team that owns the guardrails.

---

## 1. First principles

### 1.1 The tree, installed

```text
your-monorepo/
├── CLAUDE.md                         # 33 lines: commands, decisions, gotchas, where to look
├── .mcp.json                         # order-platform (stdio), github (read-only), db (mcp_ro), docs, docker gateway
├── .gitignore                        # + settings.local.json, CLAUDE.local.md, .claude/worktrees/, .claude/audit/
├── .github/workflows/claude.yml      # @claude on PRs and issues, guarded and capped
├── tools/mcp/order_platform_mcp.py   # the team's read-only MCP server (Folder 06)
└── .claude/
    ├── settings.json                 # permissions + 9 wired hooks + MCP enablement + env + effort
    ├── allowed-deps.txt              # dependency_guard.py allowlist (coordinate globs)
    ├── rules/                        # persistence, messaging, testing, security (paths: frontmatter)
    ├── agents/                       # architect, code-reviewer, security-auditor, test-runner
    ├── skills/new-slice/             # SKILL.md, reference.md, scripts/next_migration.sh
    ├── hooks/                        # 10 Python hooks (guards, formatter, build gate, context, audit)
    └── prompts/                      # T1-T7 XML templates
```

### 1.2 What runs when [doc + Folder 05]

| Moment | What fires | Effect |
|---|---|---|
| Session start, resume, `/clear`, compaction | `session_context.py` | Branch, uncommitted changes, recent commits and the last surefire failures injected as context |
| Before any Bash call | `guard_bash.py`, `block_secret_reads.py` | Destructive git, unsafe `rm -rf`, Flyway clean, `curl \| sh` and credential reads blocked; compound commands split first |
| Before Read/Grep | `block_secret_reads.py` | `.env`, keys and `secrets/` unreadable, on top of the deny rules |
| Before Edit/Write/NotebookEdit | `protect_paths.py`, `secret_scan.py`, `dependency_guard.py` | Committed migrations, generated code, build output and `.git/` protected; secrets refused; new coordinates outside `allowed-deps.txt` get `ask`, dynamic versions are denied |
| After Edit/Write of Java | `format_java.py` | Spotless on the edited file; a failure is shown to Claude (exit 2) |
| After every tool call | `audit_log.py` | One redacted JSON line per call in `.claude/audit/` |
| Stop | `verify_build.py` | If Java/SQL/XML/Gradle files changed, the fast build must pass before Claude may finish |
| Inside the reviewer subagents | `readonly_git.py` (agent frontmatter) | No commits or pushes from a reviewer |

### 1.3 Permissions as layers [doc + Folders 03, 06]

| Layer | Rules | Why there |
|---|---|---|
| deny | `Read(./.env)`, `Read(./.env.*)`, `Read(./secrets/**)`, `Bash(git push --force *)`, `Bash(git reset --hard *)`, `Bash(rm -rf *)`, `mcp__github__merge_pull_request`, `mcp__github__delete_*` | Never, in any mode |
| ask | `Bash(git push *)`, `Bash(docker compose down *)`, `mcp__db__execute_sql` | A human in the loop |
| allow | `Bash(./mvnw *)`, read-only git, `docker compose ps`, `mcp__order-platform__*`, `mcp__docs__*`, `mcp__github__get_*` / `list_*` / `search_*` | Daily flow without prompts |

The deny rules and the hooks overlap on purpose. Rules match the command as written; hooks parse it (Folder 05). Each catches what the other misses.

### 1.4 What to change when you adopt it

1. **CLAUDE.md:** module names, commands, the three gotchas that are *yours*. Then run `claude_md_lint.py` (Folder 03).
2. **`.claude/rules/`:** your package globs in `paths:`.
3. **`.mcp.json`:** drop servers you don't use. Rename `order-platform`, then update `enabledMcpjsonServers` and the `mcp__…` rules (CR03–CR04 tell you if you missed one).
4. **Hooks:** `verify_build.py` runs `./mvnw`. Gradle teams change one command line (Folder 05 file 02).
5. **Prompts:** change each template's `<platform>` line to your BOM's versions.
6. **CI:** set `ANTHROPIC_API_KEY` as a repository secret; keep the turn cap.

---

## 2. Practice

### 2.1 Install (from this folder)

```bash
# bash / Git Bash / WSL: run from the root of the target repository
BP=/path/to/08-Power-User-Dotfiles-and-Daily-Workflow-Blueprint/blueprint
cp -r "$BP/dot-claude" .claude && cp "$BP/CLAUDE.template.md" CLAUDE.md && cp "$BP/dot-mcp.json" .mcp.json
mkdir -p .github tools && cp -r "$BP/dot-github/workflows" .github/ && cp -r "$BP/tools/mcp" tools/
cat "$BP/gitignore-snippet" >> .gitignore
```

```powershell
# PowerShell
$BP = "C:\path\to\08-Power-User-Dotfiles-and-Daily-Workflow-Blueprint\blueprint"
Copy-Item -Recurse "$BP\dot-claude" .claude; Copy-Item "$BP\CLAUDE.template.md" CLAUDE.md; Copy-Item "$BP\dot-mcp.json" .mcp.json
New-Item -ItemType Directory -Force .github, tools | Out-Null
Copy-Item -Recurse "$BP\dot-github\workflows" .github\; Copy-Item -Recurse "$BP\tools\mcp" tools\
Get-Content "$BP\gitignore-snippet" | Add-Content .gitignore
```

Then start `claude` in the repo:
1. Accept workspace trust, so project hooks and the `.mcp.json` approvals apply.
2. Approve the MCP servers.
3. Run `/mcp`; every row should show a checkmark.
4. Run `/context`.

### 2.2 `CLAUDE.md` (shipped as `CLAUDE.template.md`)

@@src:blueprint/CLAUDE.template.md@@

### 2.3 `.claude/settings.json`

@@src:blueprint/dot-claude/settings.json@@

`onFailure` is newer than the schemastore schema, so `settings_validator` checks a copy with it removed (L1 says so in its output). Claude Code v2.1.295+ honours it.

### 2.4 A path-scoped rule: `.claude/rules/persistence.md`

@@src:blueprint/dot-claude/rules/persistence.md@@

### 2.5 The reviewer: `.claude/agents/code-reviewer.md`

@@src:blueprint/dot-claude/agents/code-reviewer.md@@

### 2.6 `.mcp.json` (shipped as `dot-mcp.json`)

@@src:blueprint/dot-mcp.json@@

The hooks, the skill, the templates, the MCP server and the workflow are in [`blueprint/`](blueprint/). Their explanations live with their tests:
- hooks: [Folder 05](../05-Deterministic-Hooks-Guardrails-and-Auto-Verification/02-10-production-hook-scripts-for-java-maven-gradle-git-safety-and-secret-blocking.md);
- skill and agents: [Folder 04](../04-Skills-Subagents-and-Multi-Agent-Orchestration/01-designing-reusable-skills-and-custom-slash-commands-with-frontmatter.md);
- MCP server: [Folder 06](../06-MCP-Model-Context-Protocol-Setup-and-Custom-Servers/03-building-a-custom-mcp-server-in-java-spring-ai-and-python-fastmcp.md);
- templates: [Folder 07](../07-Master-Prompt-Templates-for-Java-Backend-Projects-From-Scratch/01-zero-to-production-java21-spring-boot-microservice-scaffolding-prompt.md).

---

## 3. Verified listing

### L1 · `blueprint_check.py`

**What it shows.**
- **Install:** the blueprint is copied into a scratch repository under its real names.
- **Linters:** extracted from this KB's own Markdown (Folders 03, 04, 06, 07), so the check uses exactly the published code. 16 artifacts pass with 0 findings:
  - `claude_md_lint` on CLAUDE.md;
  - `settings_validator` with the schemastore schema;
  - `skill_lint`;
  - `agent_lint` on four agents;
  - `ci_workflow_check` with the GitHub workflow schema;
  - `mcp_config_lint`;
  - `prompt_template_check` on seven templates.
- **Cross-references:** CR00–CR12 all pass:
  - the 18 copied scripts and templates are byte-identical to the published, tested listings;
  - hook wiring matches the scripts;
  - `.mcp.json`, `enabledMcpjsonServers` and the `mcp__` rules agree;
  - CLAUDE.md is under 150 lines and names only directories that exist;
  - every rule has `paths:` frontmatter;
  - `.gitignore`, the secret-denial layers and the MCP server path are in place;
  - skill scripts exist, and every Python file compiles;
  - the files the hooks read exist (the dependency allowlist).
- **Planted drift:** a hand-edited template, a deleted hook, an unenabled server and a typo'd permission rule. Each fails its cross-reference.

**What it does not show.** Live Claude Code behaviour: the trust dialog, approvals, actual hook execution in a session. Folder 05's 40-case harness covers the hooks. Your first session with `/mcp` and `/context` covers the rest.

Run: `python blueprint_check.py [path/to/blueprint]`. Requires PyYAML and jsonschema, plus `CLAUDE_SETTINGS_SCHEMA` and `GITHUB_WORKFLOW_SCHEMA` pointing at the downloaded schemas, as in Folders 03–04.

```python
"""blueprint_check.py - install the Folder 08 blueprint into a scratch repository under its real names (.claude/, CLAUDE.md,
.mcp.json, .github/, .gitignore) and validate the installed tree with every linter this KB built - extracted from the
KB's own markdown (Folders 03-07), so the check uses exactly the published code - plus cross-reference checks no single
linter can make: hook wiring vs scripts, .mcp.json vs enabledMcpjsonServers vs mcp__ rules, rule frontmatter, sizes,
.gitignore. Then it plants three kinds of drift and shows the cross-references catch them.
Usage: python blueprint_check.py [blueprint_dir]   (default: ./blueprint, else $KB/08-.../blueprint)
Needs PyYAML, jsonschema, CLAUDE_SETTINGS_SCHEMA and GITHUB_WORKFLOW_SCHEMA, as Folders 03-04 do.
"""
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import py_compile
import re
import shutil
import sys
import tempfile

NEEDED = ["claude_md_lint", "settings_validator", "skill_lint", "agent_lint", "ci_workflow_check", "mcp_config_lint",
          "prompt_template_check"]
INSTALL = {"dot-claude": ".claude", "dot-mcp.json": ".mcp.json", "dot-github": ".github", "CLAUDE.template.md": "CLAUDE.md",
           "tools": "tools"}


def locate(arg):
    if arg:
        return pathlib.Path(arg).resolve()
    here = pathlib.Path(__file__).resolve().parent / "blueprint"
    if here.is_dir():
        return here
    return pathlib.Path(os.environ["KB"]) / "08-Power-User-Dotfiles-and-Daily-Workflow-Blueprint" / "blueprint"


def load_validators(kb_root, into):
    """Extract each linter from the KB markdown (the published copy) and import it quietly."""
    modules = {}
    for md in sorted(kb_root.glob("0[3-7]-*/*.md")):
        for m in re.finditer(r'^```python\n("""(\w+)\.py - .*?)^```$', md.read_text(encoding="utf-8"), re.M | re.S):
            if m.group(2) in NEEDED and m.group(2) not in modules:
                path = into / f"{m.group(2)}.py"
                path.write_text(m.group(1), encoding="utf-8")
                spec = importlib.util.spec_from_file_location(m.group(2), path)
                module = importlib.util.module_from_spec(spec)
                with contextlib.redirect_stdout(io.StringIO()):
                    spec.loader.exec_module(module)
                modules[m.group(2)] = (module, md.parent.name[:2])
    missing = [n for n in NEEDED if n not in modules]
    if missing:
        sys.exit(f"validators not found in the KB markdown: {missing}")
    return modules


def published(kb_root):
    """Every listing the KB publishes (Python and XML headers), by file name: the tested originals."""
    found = {}
    for md in sorted(kb_root.glob("0[1-7]-*/*.md")):
        for m in re.finditer(r'^```\w*\n((?:"""(\w+\.py) - |<!-- (\w+\.xml) - ).*?)^```$', md.read_text(encoding="utf-8"),
                             re.M | re.S):
            found.setdefault(m.group(2) or m.group(3), m.group(1))
    return found


def install(blueprint, repo):
    for src, dst in INSTALL.items():
        s = blueprint / src
        (shutil.copytree if s.is_dir() else shutil.copy)(s, repo / dst)
    (repo / ".gitignore").write_text("target/\n" + (blueprint / "gitignore-snippet").read_text(encoding="utf-8"),
                                     encoding="utf-8")


def hook_scripts(settings):
    refs = set()
    for groups in settings.get("hooks", {}).values():
        for group in groups:
            for h in group.get("hooks", []):
                text = " ".join([h.get("command", "")] + h.get("args", []))
                refs |= set(re.findall(r"\.claude/hooks/(\w+\.py)", text))
    return refs


def strip_on_failure(settings):
    s, n = json.loads(json.dumps(settings)), 0
    for groups in s.get("hooks", {}).values():
        for group in groups:
            for h in group.get("hooks", []):
                n += h.pop("onFailure", None) is not None
    return s, n


def cross_references(repo, originals):
    """Checks that span files. Returns [(id, ok, detail)]."""
    out = []
    copies = sorted((repo / ".claude/hooks").glob("*.py")) + sorted((repo / ".claude/prompts").glob("*.xml")) \
        + [repo / "tools/mcp/order_platform_mcp.py"]
    drifted = [p.name for p in copies if originals.get(p.name) != p.read_text(encoding="utf-8")]
    out.append(("CR00", not drifted, f"{len(copies)} copied scripts/templates byte-identical to the tested listings "
                f"published in Folders 05-07; drifted: {drifted or 'none'}"))
    settings = json.loads((repo / ".claude/settings.json").read_text(encoding="utf-8"))
    mcp = json.loads((repo / ".mcp.json").read_text(encoding="utf-8"))["mcpServers"]
    agents = {p.name: p.read_text(encoding="utf-8") for p in (repo / ".claude/agents").glob("*.md")}
    wired = hook_scripts(settings)
    from_agents = {s for t in agents.values() for s in re.findall(r"\.claude/hooks/(\w+\.py)", t)}
    present = {p.name for p in (repo / ".claude/hooks").glob("*.py")}
    out.append(("CR01", not (wired | from_agents) - present, f"{len(wired)} scripts wired in settings.json, "
                f"{len(from_agents)} in agent frontmatter; missing: {sorted((wired | from_agents) - present) or 'none'}"))
    out.append(("CR02", not present - wired - from_agents, f"{len(present)} hook scripts present; unwired: "
                f"{sorted(present - wired - from_agents) or 'none'}"))
    enabled = set(settings.get("enabledMcpjsonServers", []))
    out.append(("CR03", enabled == set(mcp), f".mcp.json servers {sorted(mcp)}; enabledMcpjsonServers "
                f"differs by: {sorted(enabled ^ set(mcp)) or 'nothing'}"))
    rules = [r for k in ("allow", "ask", "deny") for r in settings["permissions"].get(k, [])]
    unknown = sorted({m for r in rules for m in re.findall(r"^mcp__([\w-]+)__", r)} - set(mcp))
    out.append(("CR04", not unknown, f"{sum(r.startswith('mcp__') for r in rules)} mcp__ permission rules; naming an "
                f"unconfigured server: {unknown or 'none'}"))
    claude_md = (repo / "CLAUDE.md").read_text(encoding="utf-8")
    refs = re.findall(r"`(\.claude/[\w/-]+/)`", claude_md)
    out.append(("CR05", len(claude_md.splitlines()) < 150 and all((repo / r).is_dir() for r in refs),
                f"CLAUDE.md {len(claude_md.splitlines())} lines (< 150); directories it names exist: {refs}"))
    no_paths = [p.name for p in (repo / ".claude/rules").glob("*.md")
                if not re.match(r"---\npaths:\n(  - .+\n)+---\n", p.read_text(encoding="utf-8"))]
    out.append(("CR06", not no_paths, f"{len(list((repo / '.claude/rules').glob('*.md')))} rules with paths: "
                f"frontmatter; without: {no_paths or 'none'}"))
    ignore = (repo / ".gitignore").read_text(encoding="utf-8").splitlines()
    need = [".claude/settings.local.json", "CLAUDE.local.md", ".claude/worktrees/", ".claude/audit/"]
    out.append(("CR07", all(n in ignore for n in need), f".gitignore covers {[n for n in need if n in ignore]}"))
    deny = settings["permissions"]["deny"]
    secret_hook = any("block_secret_reads.py" in json.dumps(g) for g in settings["hooks"].get("PreToolUse", []))
    out.append(("CR08", "Read(./.env)" in deny and any("secrets" in d for d in deny) and secret_hook,
                "secrets denied by rule (Read(./.env), ./secrets/**) and by the block_secret_reads hook"))
    stdio = [(n, a) for n, e in mcp.items() if e.get("type") == "stdio" for a in e.get("args", [])
             if a.endswith(".py")]
    exists = [(n, (repo / a.replace("${CLAUDE_PROJECT_DIR:-.}/", "")).is_file()) for n, a in stdio]
    out.append(("CR09", all(ok for _, ok in exists), f"stdio MCP server scripts present: {exists}"))
    skill = (repo / ".claude/skills/new-slice/SKILL.md").read_text(encoding="utf-8")
    scripts = re.findall(r"\$\{CLAUDE_SKILL_DIR\}/([\w/.-]+\.sh)", skill)
    out.append(("CR10", all((repo / ".claude/skills/new-slice" / s).is_file() for s in scripts),
                f"skill scripts referenced by SKILL.md exist: {sorted(set(scripts))}"))
    compiled = []
    for p in sorted((repo / ".claude/hooks").glob("*.py")) + [repo / "tools/mcp/order_platform_mcp.py"]:
        try:
            py_compile.compile(str(p), doraise=True, cfile=str(repo / "pyc.tmp"))
        except py_compile.PyCompileError:
            compiled.append(p.name)
    out.append(("CR11", not compiled, f"Python files that fail to compile: {compiled or 'none'}"))
    inputs = {"dependency_guard.py": ".claude/allowed-deps.txt"}                # files a hook reads at run time
    lacking = [f"{h} needs {f}" for h, f in inputs.items() if (repo / ".claude/hooks" / h).exists() and not (repo / f).exists()]
    out.append(("CR12", not lacking, f"files the hooks read exist: {lacking or sorted(inputs.values())}"))
    return out


def main():
    blueprint = locate(sys.argv[1] if len(sys.argv) > 1 else None)
    kb_root = next((r for r in (blueprint.parent.parent, pathlib.Path(os.environ.get("KB", "."))) if any(r.glob("0[3-7]-*"))),
                   blueprint.parent.parent)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        (tmp / "validators").mkdir()
        v = load_validators(kb_root, tmp / "validators")
        originals = published(kb_root)
        repo = tmp / "repo"
        repo.mkdir()
        install(blueprint, repo)
        files = sorted(p.relative_to(repo).as_posix() for p in repo.rglob("*") if p.is_file())
        print(f"installed {len(files)} files into a scratch repo; validators from Folders "
              f"{', '.join(sorted({f for _, f in v.values()}))} of the KB")
        total = 0

        def report(name, artifact, findings, note=""):
            nonlocal total
            total += len(findings)
            print(f"  {'PASS' if not findings else 'FAIL'} {name:<22} {artifact}: {len(findings)} finding(s){note}")
            for f in findings:
                print(f"       {f}")

        report("claude_md_lint", "CLAUDE.md", v["claude_md_lint"][0].lint(repo / "CLAUDE.md"))
        settings = json.loads((repo / ".claude/settings.json").read_text(encoding="utf-8"))
        stripped, n = strip_on_failure(settings)
        report("settings_validator", ".claude/settings.json", v["settings_validator"][0].validate(stripped),
               f" (after removing {n} onFailure fields the schemastore schema predates)")
        report("skill_lint", ".claude/skills/new-slice", v["skill_lint"][0].lint(repo / ".claude/skills/new-slice"))
        for agent in sorted((repo / ".claude/agents").glob("*.md")):
            report("agent_lint", f".claude/agents/{agent.name}", v["agent_lint"][0].lint(agent.read_text(encoding="utf-8")))
        report("ci_workflow_check", ".github/workflows/claude.yml",
               v["ci_workflow_check"][0].check((repo / ".github/workflows/claude.yml").read_text(encoding="utf-8")))
        mcp_mod = v["mcp_config_lint"][0]
        report("mcp_config_lint", ".mcp.json", mcp_mod.lint({"project": json.loads((repo / ".mcp.json").read_text(
            encoding="utf-8"))}, mcp_mod.ENV), " (with the team's variables set)")
        for t in sorted((repo / ".claude/prompts").glob("t*.xml")):
            report("prompt_template_check", f".claude/prompts/{t.name}",
                   v["prompt_template_check"][0].check(t.name, t.read_text(encoding="utf-8"))[0])
        print("cross-references:")
        crs = cross_references(repo, originals)
        for cid, ok, detail in crs:
            print(f"  {'PASS' if ok else 'FAIL'} {cid} {detail}")
        print(f"result: {total} linter finding(s), {sum(not ok for _, ok, _ in crs)} cross-reference failure(s)")

        print("\nplanted drift (what review misses and the cross-references catch):")
        (repo / ".claude/hooks/format_java.py").unlink()                       # script deleted, wiring left behind
        mcp = json.loads((repo / ".mcp.json").read_text(encoding="utf-8"))
        mcp["mcpServers"]["sentry"] = {"type": "http", "url": "https://mcp.sentry.dev/mcp"}   # added, never enabled
        (repo / ".mcp.json").write_text(json.dumps(mcp), encoding="utf-8")
        settings["permissions"]["allow"].append("mcp__gihtub__get_*")         # typo: matches no server
        (repo / ".claude/settings.json").write_text(json.dumps(settings), encoding="utf-8")
        t2 = repo / ".claude/prompts/t2_vertical_slice_scaffolder.xml"                 # hand-edited copy, never re-tested
        t2.write_text(t2.read_text(encoding="utf-8").replace("Hikari maximum pool size is set explicitly",
                                                             "Hikari pool size is left at its default"), encoding="utf-8")
        for cid, ok, detail in cross_references(repo, originals):
            if not ok:
                print(f"  FAIL {cid} {detail}")


if __name__ == "__main__":
    main()
```

**Output (verified):**

```text
installed 35 files into a scratch repo; validators from Folders 03, 04, 06, 07 of the KB
  PASS claude_md_lint         CLAUDE.md: 0 finding(s)
  PASS settings_validator     .claude/settings.json: 0 finding(s) (after removing 5 onFailure fields the schemastore schema predates)
  PASS skill_lint             .claude/skills/new-slice: 0 finding(s)
  PASS agent_lint             .claude/agents/architect.md: 0 finding(s)
  PASS agent_lint             .claude/agents/code-reviewer.md: 0 finding(s)
  PASS agent_lint             .claude/agents/security-auditor.md: 0 finding(s)
  PASS agent_lint             .claude/agents/test-runner.md: 0 finding(s)
  PASS ci_workflow_check      .github/workflows/claude.yml: 0 finding(s)
  PASS mcp_config_lint        .mcp.json: 0 finding(s) (with the team's variables set)
  PASS prompt_template_check  .claude/prompts/t1_phase0_rfc_spec.xml: 0 finding(s)
  PASS prompt_template_check  .claude/prompts/t2_vertical_slice_scaffolder.xml: 0 finding(s)
  PASS prompt_template_check  .claude/prompts/t3_kafka_outbox_idempotent.xml: 0 finding(s)
  PASS prompt_template_check  .claude/prompts/t4_beam_pipeline_auditor.xml: 0 finding(s)
  PASS prompt_template_check  .claude/prompts/t5_adversarial_concurrency.xml: 0 finding(s)
  PASS prompt_template_check  .claude/prompts/t6_testcontainers_archunit_legacy.xml: 0 finding(s)
  PASS prompt_template_check  .claude/prompts/t7_sql_explain_tuning.xml: 0 finding(s)
cross-references:
  PASS CR00 18 copied scripts/templates byte-identical to the tested listings published in Folders 05-07; drifted: none
  PASS CR01 9 scripts wired in settings.json, 1 in agent frontmatter; missing: none
  PASS CR02 10 hook scripts present; unwired: none
  PASS CR03 .mcp.json servers ['db', 'docker', 'docs', 'github', 'order-platform']; enabledMcpjsonServers differs by: nothing
  PASS CR04 8 mcp__ permission rules; naming an unconfigured server: none
  PASS CR05 CLAUDE.md 33 lines (< 150); directories it names exist: ['.claude/rules/', '.claude/prompts/']
  PASS CR06 4 rules with paths: frontmatter; without: none
  PASS CR07 .gitignore covers ['.claude/settings.local.json', 'CLAUDE.local.md', '.claude/worktrees/', '.claude/audit/']
  PASS CR08 secrets denied by rule (Read(./.env), ./secrets/**) and by the block_secret_reads hook
  PASS CR09 stdio MCP server scripts present: [('order-platform', True)]
  PASS CR10 skill scripts referenced by SKILL.md exist: ['scripts/next_migration.sh']
  PASS CR11 Python files that fail to compile: none
  PASS CR12 files the hooks read exist: ['.claude/allowed-deps.txt']
result: 0 linter finding(s), 0 cross-reference failure(s)

planted drift (what review misses and the cross-references catch):
  FAIL CR00 17 copied scripts/templates byte-identical to the tested listings published in Folders 05-07; drifted: ['t2_vertical_slice_scaffolder.xml']
  FAIL CR01 9 scripts wired in settings.json, 1 in agent frontmatter; missing: ['format_java.py']
  FAIL CR03 .mcp.json servers ['db', 'docker', 'docs', 'github', 'order-platform', 'sentry']; enabledMcpjsonServers differs by: ['sentry']
  FAIL CR04 9 mcp__ permission rules; naming an unconfigured server: ['gihtub']
```

---

## 4. Failure modes

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| F1 | Every Java edit errors "can't open file …format_java.py" | Hook deleted, wiring left in settings | CR01; remove both or neither |
| F2 | A teammate's server never loads | In `.mcp.json` but not `enabledMcpjsonServers`; or never approved | CR03; `/mcp` |
| F3 | Allowed tool still prompts | Permission rule names a server that doesn't exist (typo) | CR04 |
| F4 | Template output regressed after a "small tweak" | Hand-edited copy, never re-linted | CR00 + `prompt_template_check.py` in CI |
| F5 | Persistence rules ignored | Rule file without `paths:` frontmatter, or globs that don't match | CR06; check the globs against `git ls-files` |
| F6 | Personal settings leaked into the repo | `settings.local.json` / `CLAUDE.local.md` not ignored | CR07 |
| F7 | Hooks didn't run on a fresh clone | Workspace trust not accepted | Accept trust; `claude -p` runs them without asking (review first) |
| F8 | Claude reads `.env` via a script | Deny rules match tool calls, not what a script opens | `block_secret_reads.py` + secrets outside the repo (CR08) |
| F9 | Every dependency edit asks for approval | `allowed-deps.txt` missing, so the guard knows no families | CR12; ship the allowlist and keep it reviewed |

---

## 5. Staff-level drills

<details><summary><b>D1 · "Why ship the blueprint as files instead of a page of snippets?"</b></summary>

**Staff answer.** Snippets drift: copied from five places, edited in three, tested in none. Files built from the tested listings, with a check that installs them and validates the whole tree, give you a known-good starting state.

CR00 makes "known good" mechanical: a copy that differs from its tested original fails. Fork the folder, change what §1.4 lists, and keep L1 in CI.
</details>

<details><summary><b>D2 · "Our monorepo has 40 modules. One CLAUDE.md?"</b></summary>

**Staff answer.**
- **One root CLAUDE.md** for what applies everywhere (33 lines here).
- **`.claude/rules/` with `paths:`** for concerns that cut across modules: persistence, messaging, security.
- **Per-module CLAUDE.md files** only where a module truly differs, for example the frozen `legacy-billing/`. They load on demand when Claude works there [doc].

Resist a 400-line root file: it costs every request and dilutes every rule (Folder 01).
</details>

<details><summary><b>D3 · "Who owns <code>.claude/</code>?"</b></summary>

**Staff answer.** The same people who own the CI pipeline. It *is* CI for the agent: its guards, gates and supply chain (`.mcp.json` runs code on every laptop).
- CODEOWNERS on `.claude/**`, `.mcp.json` and `CLAUDE.md`.
- L1 plus the per-artifact linters as a required check.
- A quarterly review of hook logs (`audit_log.py`) for what was blocked and why.
</details>

---

## 6. Checklist

- [ ] Installed with the real names; `.gitignore` lines added; workspace trust accepted; `/mcp` all green.
- [ ] CLAUDE.md, rules, `.mcp.json` names, hook commands and template platform lines customised (§1.4).
- [ ] `blueprint_check.py` (or the individual linters) runs in CI on every change to `.claude/**`, `.mcp.json`, `CLAUDE.md`.
- [ ] CODEOWNERS on the same paths.

---

## 7. References

- Explore the `.claude` directory: <https://code.claude.com/docs/en/claude-directory>
- Settings (files, precedence): <https://code.claude.com/docs/en/settings>
- Memory (CLAUDE.md, CLAUDE.local.md, rules): <https://code.claude.com/docs/en/memory>
- Hooks: <https://code.claude.com/docs/en/hooks> · Subagents: <https://code.claude.com/docs/en/sub-agents> · Skills: <https://code.claude.com/docs/en/skills>
- MCP: <https://code.claude.com/docs/en/mcp> · GitHub Actions: <https://code.claude.com/docs/en/github-actions>

Next: [02 · 25 pro tips and troubleshooting degradation](02-25-pro-tips-hidden-shortcuts-and-troubleshooting-claude-degradation.md) · [KB README](../README.md)

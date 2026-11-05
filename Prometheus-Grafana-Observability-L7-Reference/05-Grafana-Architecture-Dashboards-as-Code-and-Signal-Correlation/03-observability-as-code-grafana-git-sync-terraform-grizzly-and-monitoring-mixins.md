# 03 · Observability as Code: Grafana Git Sync, Terraform, Grizzly/grafanactl and Monitoring Mixins

> **Folder 05 — Grafana Architecture, Dashboards as Code and Signal Correlation · File 3 of 3.**
> Pinned to **Grafana v13.3.0** (Git Sync GA since 13.0), **terraform-provider-grafana v4.53.0** (2026-10-28), **grafanactl v0.1.10**, grafonnet and the Grafana Foundation SDK (active repositories, November 2026). Grizzly's README states it "has been marked for deprecation and will be superseded by grafanactl".
> Labels: **[D]** documented · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L3 `mixin_lab.py` | One service spec generates 8 recording rules, a multi-window burn-rate alert and a RED dashboard (a mixin's shape); every artefact is validated by earlier linters (naming lint from Folder 04, PromQL parser from Folder 02, dashboard lint from File 1); the result is laid out as a Git Sync repository tree (with `_folder.json`), a Terraform-style plan (`grafana_folder` + `grafana_dashboard.config_json`), and a drift report that catches a UI edit introducing a hard-coded window and a 5 s refresh | <1 s |

**Verification.** All generated rules pass the Folder 04 naming lint and parse with `promql_mini.py`; the dashboard passes File 1's lint; drift detection is asserted. Tool and feature status comes from the tools' repositories and Grafana's "What's new in v13.0"; API group/version names that changed during 12.x–13.x are marked ⚠. No Grafana instance or Terraform run was executed.

---

## 0. Orientation

**What this file answers.** How to manage dashboards, alert rules, data sources and folders as reviewed, versioned code at the scale of hundreds of teams — which tool for which job in late 2026, and how to stop the UI and the repository from drifting apart.

**The 2026 landscape [D].**

| Tool | What it manages | Model | Status (Nov 2026) |
|---|---|---|---|
| **Git Sync** (built into Grafana) | dashboards and folders | bidirectional: UI saves become commits/PRs in GitHub, GitLab, Bitbucket or any git repository | **GA since Grafana 13.0** |
| **Provisioning files** | dashboards, data sources, alerting resources | read from disk at start/interval; `allowUiUpdates: false` for read-only | stable |
| **Terraform provider** (`grafana/grafana`) | almost everything: folders, dashboards, data sources, alert rules, contact points, policies, teams, RBAC, Cloud stacks, SLOs | declarative state, plan/apply | v4.53.0 |
| **grafanactl** | Grafana resources via the App Platform APIs (`/apis`) | pull/push/serve resources as files | v0.1.x, active |
| **Grizzly** | dashboards, folders, rules via Jsonnet/YAML | — | **deprecated → grafanactl** |
| **Grafana Foundation SDK** | typed builders for dashboards/panels/queries in Go, TypeScript, Python, Java, PHP | code generates JSON | active |
| **grafonnet + monitoring mixins** | Jsonnet libraries; mixins bundle dashboards + rules + alerts per system | code generates JSON/YAML | active (kubernetes-mixin, node-mixin…) |

---

## 1. First principles: what "as code" must guarantee

### 1.1 Four properties

1. **Single source of truth** — the repository (or Terraform state) decides; the UI either writes back to it (Git Sync) or is read-only (provisioning) or is overwritten (Terraform).
2. **Review and test before production** — linters for PromQL, naming and dashboard rules (L3 runs three), `promtool test rules`, rendering previews.
3. **Generated, not hand-written, where repetitive** — a service spec → rules + alerts + dashboards keeps 500 services consistent (L3).
4. **Drift is detected** — UI edits, API scripts and incident-time hotfixes are surfaced, not silently kept or lost (L3 §4).

```text
 service spec (YAML, owned by the team)
      │  generator (mixin / Foundation SDK / own code, pinned version)
      ▼
 rules.yaml   alerts.yaml   dashboards/*.json   ── committed to Git (CI fails if stale)
      │  CI: PromQL parse · naming lint · dashboard lint · promtool test rules · cost budget
      ▼
 merge ──► Prometheus/Mimir ruler (rules)     Grafana via Git Sync (dashboards/folders)
                                              Terraform (data sources, folders, RBAC, contact points)
      ▲                                                     │
      └──── drift report: export live (grafanactl/API) ─────┘  diff + lint → ticket or PR
```

### 1.2 Git Sync (Grafana 13) [D]

```text
 Grafana instance ◄──── sync (poll/webhook) ──── git repository  (GitHub / GitLab / Bitbucket / any git)
   folder "payments"  ◄──────────────────────────  grafana/payments/_folder.json
   dashboard "checkout / RED" ◄───────────────────  grafana/payments/checkout-red.json
   UI "Save" ──► commit on a branch ──► pull request (lint + review) ──► merge ──► synced back
```

- Folders and dashboards are files; folder metadata lives in `_folder.json`; changes made in the UI become commits or pull requests "without leaving the UI".
- Provisioned folders are protected from direct edits; branch previews show a dashboard from an unmerged branch.
- **Upgrade caution**: a migration bug in 13.0.0 could lose or revert Git-Synced dashboards when upgrading from 12.x; restore from backup and use ≥ 13.0.1.
- Git Sync covers dashboards and folders; alert rules, contact points and data sources are still managed by provisioning, Terraform or the App Platform APIs (13.3 promoted `AlertRule`/`RecordingRule` to `v1beta1` there ⚠).

### 1.3 Terraform vs Git Sync vs generators

| Need | Best fit | Why |
|---|---|---|
| Platform-owned resources (data sources, folders, RBAC, contact points, notification policies) | Terraform | plan/apply, secrets from vaults, dependency graph, multi-stack |
| Team dashboards that people iterate on in the UI | Git Sync | edits flow back as PRs; no "import JSON into Terraform" loop |
| Consistent per-service rules + dashboards | generators (mixins, Foundation SDK, own specs) | one spec, hundreds of outputs (L3) |
| Bulk migration, backups, multi-instance copy | grafanactl | file-based pull/push over the `/apis` resource APIs |

Anti-pattern: Terraform managing team dashboards that people also edit in the UI — every apply reverts their work, so they stop using either.

### 1.4 Monitoring mixins

A mixin (from the `monitoring-mixins` convention) is a Jsonnet package exporting `prometheusRules`, `prometheusAlerts` and `grafanaDashboards`, parameterised by `_config` (selectors, thresholds, label names). Examples: `kubernetes-mixin` (the source of kube-prometheus's rules), `node-mixin`, the Prometheus and Alertmanager mixins. L3 builds the same shape in Python from a service spec; the important properties are the same: one config object, deterministic output, linted artefacts, versioned releases.

<!-- listing:mixin_lab.py -->
```python
"""mixin_lab.py - observability as code in one pipeline: a service spec generates recording rules,
multi-window burn-rate alerts and a RED dashboard (the shape of a monitoring mixin), every artefact is
validated by the earlier listings' linters, and the result is laid out three ways: a Git Sync
repository tree, a Terraform-style JSON plan, and a drift report against a "live" copy that someone
edited by hand in the UI.

Reuses: promql_mini.Parser (Folder 02), rules_lab.lint (Folder 04), dashboard_lab.red_dashboard and
lint_expr (this folder). Deterministic, stdlib only.

Usage: python mixin_lab.py [target.md]
"""
import hashlib
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from dashboard_lab import lint_expr, red_dashboard  # noqa: E402
from promql_mini import Parser  # noqa: E402
from rules_lab import lint  # noqa: E402

SPEC = {"service": "checkout", "team": "payments", "slo": 0.999,
        "requests": "http_server_requests_seconds_count", "error_matcher": 'outcome="SERVER_ERROR"'}


def build(spec):
    svc, m = spec["service"], spec["requests"]
    sel = f'job="{svc}"'
    rules = [{"record": f"job:{m.replace('_count', '')}:rate{w}",
              "expr": f'sum by (job) (rate({m}{{{sel}}}[{w}]))'} for w in ("5m", "30m", "1h", "6h")]
    rules += [{"record": f"job:{m.replace('_count', '')}_errors:rate{w}",
               "expr": f'sum by (job) (rate({m}{{{sel}, {spec["error_matcher"]}}}[{w}]))'} for w in ("5m", "30m", "1h", "6h")]
    budget = 1 - spec["slo"]
    base = m.replace("_count", "")

    def ratio(w):
        return f"(job:{base}_errors:rate{w} / job:{base}:rate{w})"
    alerts = [{"alert": f"{svc.title()}ErrorBudgetBurn",
               "expr": f"({ratio('1h')} > {14.4 * budget:.4f} and {ratio('5m')} > {14.4 * budget:.4f}) or "
                       f"({ratio('6h')} > {6 * budget:.4f} and {ratio('30m')} > {6 * budget:.4f})",
               "for": "2m", "labels": {"severity": "page", "team": spec["team"]}}]
    dash = red_dashboard(svc)
    return rules, alerts, dash


def main():
    checks = []
    rules, alerts, dash = build(SPEC)
    print(f"== 1. Generated from a {len(json.dumps(SPEC))}-byte spec: {len(rules)} recording rules, {len(alerts)} alert, "
          f"1 dashboard ==")
    problems = 0
    for r in rules:
        iss = lint(r)
        Parser(r["expr"]).parse()
        problems += len(iss)
        print(f"  rule  {r['record']:<62} {'ok' if not iss else iss}")
    for a in alerts:
        Parser(a["expr"]).parse()
        print(f"  alert {a['alert']:<62} parses; page tiers 14.4x(1h,5m) / 6x(6h,30m)")
    dash_issues = [i for p in dash["panels"] if p["type"] != "row" for t in p["targets"] for i in lint_expr(t["expr"])]
    print(f"  dashboard '{dash['title']}': {sum(1 for p in dash['panels'] if p['type'] != 'row')} panels, lint issues {len(dash_issues)}")
    checks.append(("all artefacts valid", problems == 0 and not dash_issues))
    print()

    print("== 2. Git Sync repository layout (Grafana 13: folders and dashboards as files, PR-based changes) ==")
    tree = {
        f"grafana/{SPEC['team']}/_folder.json": {"title": SPEC["team"].title()},
        f"grafana/{SPEC['team']}/{SPEC['service']}-red.json": dash,
        f"prometheus/rules/{SPEC['service']}.rules.yaml": {"groups": [{"name": f"{SPEC['service']}.rules", "rules": rules + alerts}]},
    }
    for path, obj in tree.items():
        blob = json.dumps(obj, sort_keys=True).encode()
        print(f"  {path:<44} {len(blob):>6} B  sha256 {hashlib.sha256(blob).hexdigest()[:12]}")
    print()

    print("== 3. Terraform-style plan (grafana_folder + grafana_dashboard with config_json) ==")
    plan = {"resource": {
        "grafana_folder": {SPEC["team"]: {"title": SPEC["team"].title(), "uid": f"{SPEC['team']}-folder"}},
        "grafana_dashboard": {f"{SPEC['service']}_red": {"folder": f"${{grafana_folder.{SPEC['team']}.uid}}",
                                                         "config_json": json.dumps(dash, sort_keys=True), "overwrite": True}}}}
    print(f"  {len(json.dumps(plan)):,} bytes of plan JSON; resources: "
          f"{[f'{k}.{n}' for k, v in plan['resource'].items() for n in v]}")
    print()

    print("== 4. Drift: someone edits the live dashboard in the UI ==")
    live = json.loads(json.dumps(dash))
    live["panels"][2]["targets"][0]["expr"] = live["panels"][2]["targets"][0]["expr"].replace("$__rate_interval", "1m")
    live["refresh"] = "5s"

    def diff(a, b, path=""):
        out = []
        if isinstance(a, dict) and isinstance(b, dict):
            for k in sorted(set(a) | set(b)):
                out += diff(a.get(k), b.get(k), f"{path}.{k}")
        elif isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
            for i, (x, y) in enumerate(zip(a, b)):
                out += diff(x, y, f"{path}[{i}]")
        elif a != b:
            out.append(path)
        return out
    drift = diff(dash, live)
    for d in drift:
        print(f"  drift at {d}")
    new_issues = [i for p in live["panels"] if p["type"] != "row" for t in p["targets"] for i in lint_expr(t["expr"])]
    print(f"  lint on the live copy: {new_issues}")
    checks.append(("drift detected", len(drift) == 2 and new_issues))
    print("-> with Git Sync the UI edit becomes a pull request that this lint runs on; with Terraform the next")
    print("   apply reverts it; with neither, the 5 s refresh and hard-coded window ship silently.")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:mixin_lab.py -->
```text
== 1. Generated from a 152-byte spec: 8 recording rules, 1 alert, 1 dashboard ==
  rule  job:http_server_requests_seconds:rate5m                        ok
  rule  job:http_server_requests_seconds:rate30m                       ok
  rule  job:http_server_requests_seconds:rate1h                        ok
  rule  job:http_server_requests_seconds:rate6h                        ok
  rule  job:http_server_requests_seconds_errors:rate5m                 ok
  rule  job:http_server_requests_seconds_errors:rate30m                ok
  rule  job:http_server_requests_seconds_errors:rate1h                 ok
  rule  job:http_server_requests_seconds_errors:rate6h                 ok
  alert CheckoutErrorBudgetBurn                                        parses; page tiers 14.4x(1h,5m) / 6x(6h,30m)
  dashboard 'checkout / RED': 8 panels, lint issues 0

== 2. Git Sync repository layout (Grafana 13: folders and dashboards as files, PR-based changes) ==
  grafana/payments/_folder.json                    21 B  sha256 3729f8fe9863
  grafana/payments/checkout-red.json             4549 B  sha256 84ca52176357
  prometheus/rules/checkout.rules.yaml           1870 B  sha256 6bd670698172

== 3. Terraform-style plan (grafana_folder + grafana_dashboard with config_json) ==
  5,441 bytes of plan JSON; resources: ['grafana_folder.payments', 'grafana_dashboard.checkout_red']

== 4. Drift: someone edits the live dashboard in the UI ==
  drift at .panels[2].targets[0].expr
  drift at .refresh
  lint on the live copy: ['hard-coded range window; use $__rate_interval']
-> with Git Sync the UI edit becomes a pull request that this lint runs on; with Terraform the next
   apply reverts it; with neither, the 5 s refresh and hard-coded window ship silently.

checks: 2/2 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Terraform: platform resources (provider v4.x)

```hcl
terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.53"
    }
  }
}

provider "grafana" {
  url  = "https://grafana.example.internal"
  auth = var.grafana_service_account_token
}

resource "grafana_folder" "payments" {
  title = "Payments"
  uid   = "payments"
}

resource "grafana_data_source" "mimir" {
  type = "prometheus"
  name = "Mimir"
  uid  = "mimir"
  url  = "http://mimir-query-frontend.observability:8080/prometheus"
  json_data_encoded = jsonencode({
    timeInterval                = "30s"
    httpMethod                  = "POST"
    prometheusType              = "Mimir"
    exemplarTraceIdDestinations = [{ name = "trace_id", datasourceUid = "tempo" }]
  })
}

resource "grafana_dashboard" "checkout_red" {
  folder      = grafana_folder.payments.uid
  config_json = file("${path.module}/generated/checkout-red.json")   # produced by the generator in CI
  overwrite   = true
}

resource "grafana_contact_point" "payments_pager" {
  name = "payments-pager"
  pagerduty {
    integration_key = var.pd_payments_key
  }
}
```

### 2.2 CI pipeline for observability code

```yaml
# .github/workflows/observability.yaml (excerpt)
name: observability-as-code
on:
  pull_request:
    paths: ["observability/**"]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Generate rules and dashboards from service specs
        run: python observability/generate.py --specs observability/services --out observability/generated
      - name: PromQL and naming lint
        run: python observability/lint.py observability/generated
      - name: promtool checks
        run: |
          promtool check rules observability/generated/rules/*.yaml
          promtool test rules observability/tests/*.yaml
      - name: Fail if generated files are stale
        run: git diff --exit-code observability/generated
      - name: Terraform plan (platform resources)
        run: terraform -chdir=observability/terraform init -input=false && terraform -chdir=observability/terraform plan -input=false
```

### 2.3 A Foundation SDK dashboard (Python builder, shape)

```python
# Grafana Foundation SDK (Python) - typed builders emit dashboard JSON (API shape ⚠: pin the SDK version)
from grafana_foundation_sdk.builders import dashboard, prometheus, timeseries
from grafana_foundation_sdk.cog.encoder import JSONEncoder

board = (
    dashboard.Dashboard("checkout / RED")
    .uid("checkout-red")
    .refresh("1m")
    .with_panel(
        timeseries.Panel()
        .title("Requests / s")
        .unit("reqps")
        .with_target(
            prometheus.Dataquery().expr(
                'sum(rate(http_server_requests_seconds_count{job="$job"}[$__rate_interval]))'
            )
        )
    )
)
print(JSONEncoder(sort_keys=True, indent=2).encode(board.build()))
```

### 2.4 grafanactl workflow (file-based resource sync)

```bash
# configure a context once (server URL + token), then pull/push resources as files  (⚠ CLI is v0.x)
grafanactl config set contexts.prod.grafana.server https://grafana.example.internal
grafanactl config use-context prod
grafanactl resources pull dashboards -p ./resources           # export for backup/migration
grafanactl resources push -p ./resources --dry-run            # what would change
grafanactl resources push -p ./resources
```

---

## 3. Failure modes and FinOps debugging

### F1. Terraform fights the UI

**Symptom.** Dashboards edited in the UI revert every night; teams stop improving them.

**Signature.** Team dashboards managed by Terraform with `overwrite = true`; scheduled applies.

**Root cause.** Two sources of truth.

**Fix.** Move team dashboards to Git Sync (UI → PR) or make them read-only and generated; keep Terraform for platform resources.

**Prevention.** Ownership matrix: which tool owns which resource type.

### F2. Silent drift from incident hotfixes

**Symptom.** After an incident, a "temporary" panel and a changed alert threshold remain for months; nobody knows why.

**Signature.** Live dashboards differ from Git; no PR exists for the change (L3 §4 detects exactly this).

**Root cause.** Editable production resources without write-back.

**Fix.** Git Sync PRs for UI edits, or a nightly drift report (export via grafanactl/API, diff against Git) that opens tickets.

**Prevention.** Read-only provisioned folders for critical dashboards.

### F3. 500 hand-copied dashboards, 500 variations

**Symptom.** Every team's RED dashboard differs subtly (wrong windows, missing `le`, different units); fixes must be applied 500 times.

**Signature.** Dashboards created by "save as" from an old template; no generator.

**Root cause.** Copy-paste instead of generation.

**Fix.** A spec-driven generator (L3, mixins, Foundation SDK) and a migration that replaces copies with generated dashboards.

**Prevention.** New services onboard by adding a spec file, not a dashboard.

### F4. Secrets in dashboards-as-code repositories

**Symptom.** Data source passwords and contact-point keys appear in Git history.

**Signature.** Provisioning files with inline `secureJsonData`; Terraform variables committed.

**Root cause.** Secrets treated as config.

**Fix.** Rotate; use environment-variable interpolation or a secrets manager (Terraform data sources from Vault/cloud secret stores).

**Prevention.** Secret scanning in CI; provisioning templates with `$__env{}`/file references.

### F5. Generator upgrades that rewrite every dashboard

**Symptom.** A library bump changes 2,000 dashboards' JSON in one PR; reviewers approve blindly; a panel type change breaks dashboards.

**Signature.** Unpinned grafonnet/Foundation SDK versions; schema migration in Grafana 13 changing serialised fields.

**Root cause.** Generated artefacts are code whose compiler changed.

**Fix.** Pin generator versions; upgrade in a dedicated PR with rendered-diff previews for a sample of dashboards.

**Prevention.** Snapshot tests of generated JSON for representative specs.

### F6. Deprecated tooling on the critical path

**Symptom.** A pipeline built on Grizzly fails after a Grafana upgrade; no fixes are coming.

**Signature.** Grizzly marked for deprecation in favour of grafanactl; App Platform APIs (`/apis`) replacing `/api`.

**Root cause.** Tooling lifecycle not tracked.

**Fix.** Migrate to grafanactl / Terraform / Git Sync according to the ownership matrix.

**Prevention.** Quarterly review of observability tooling status as part of platform hygiene.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Design dashboards-as-code for 300 teams."</b></summary>

**Initial Prompt.** Pick tools and workflows.

**L5 Textbook Answer.** Put all dashboards in Terraform.

**Why L5 Fails at 3 AM or on the Bill.** Terraform state for thousands of UI-iterated dashboards becomes a fight between applies and edits, with huge plans nobody reviews.

**L7 Principal Defense.** Ownership matrix: Terraform for platform resources (data sources, folders, RBAC, contact points, policies); generators for standard per-service dashboards and rules from specs (L3), output committed and synced; Git Sync for team-owned dashboards so UI edits become PRs; read-only provisioning for critical shared dashboards; CI with PromQL, naming and dashboard lints plus promtool tests; drift reports for everything else.
</details>

<details><summary><b>Q2 · "Git Sync or Terraform for dashboards?"</b></summary>

**Initial Prompt.** Choose one.

**L5 Textbook Answer.** Terraform, it's the standard IaC tool.

**Why L5 Fails at 3 AM or on the Bill.** Dashboards are iterated visually; forcing JSON edits through Terraform kills iteration.

**L7 Principal Defense.** Git Sync for dashboards humans iterate on (UI → PR, review, merge), Terraform for resources with dependencies and secrets. Both keep Git as the source of truth; they differ in who writes the change. Generated dashboards can use either; the important part is not having two owners for one resource.
</details>

<details><summary><b>Q3 · "What is a monitoring mixin and why use one?"</b></summary>

**Initial Prompt.** Explain mixins.

**L5 Textbook Answer.** Jsonnet packages of dashboards and alerts for common software.

**Why L5 Fails at 3 AM or on the Bill.** Misses the contract: a `_config` object makes them portable across label schemes; without understanding it, teams fork and diverge.

**L7 Principal Defense.** A mixin exports rules, alerts and dashboards as functions of a config (selectors, label names, thresholds), versioned with the software it monitors (kubernetes-mixin, node-mixin). We vendor them, override `_config` for our label conventions, render in CI, lint, test, and ship — upgrades become version bumps, not re-authoring.
</details>

<details><summary><b>Q4 · "How do you detect drift?"</b></summary>

**Initial Prompt.** Prove production matches Git.

**L5 Textbook Answer.** Re-apply Terraform regularly.

**Why L5 Fails at 3 AM or on the Bill.** Re-applying hides drift (and destroys hotfixes) rather than surfacing it.

**L7 Principal Defense.** Export live resources (grafanactl or API), normalise (strip ids/versions), diff against Git (L3 §4 does this at JSON-path granularity), lint the live copy, and open tickets or PRs. With Git Sync, drift becomes impossible for synced folders because UI saves are commits.
</details>

<details><summary><b>Q5 · "Should SLO rules be hand-written?"</b></summary>

**Initial Prompt.** Teams write their own SLO alerts.

**L5 Textbook Answer.** Yes, teams know their services best.

**Why L5 Fails at 3 AM or on the Bill.** Burn-rate rules are formulaic and easy to get wrong (single windows, missing absent handling); 300 hand-written copies diverge.

**L7 Principal Defense.** Teams write specs (objective, SLI queries, owner); a generator (Sloth, Pyrra, or ours as in L3) produces the recording rules, burn-rate alerts and dashboards; CI validates them. Teams own the *what*, the platform owns the *how*.
</details>

<details><summary><b>Q6 · "What changed in Grafana's API surface and why does it matter for automation?"</b></summary>

**Initial Prompt.** Our scripts call `/api/dashboards/db`. Any risk?

**L5 Textbook Answer.** No, the API is stable.

**Why L5 Fails at 3 AM or on the Bill.** Grafana 13 deprecates `/api` in favour of `/apis` (App Platform), removes numeric-ID data source APIs by default, and changes RBAC defaults; scripts break on upgrades.

**L7 Principal Defense.** Move automation to supported clients (Terraform provider, grafanactl, Git Sync) that track API changes; pin and test them against each Grafana minor; read the upgrade guide's breaking changes (numeric IDs, `/api` deprecation, RBAC tightening) before upgrades.
</details>

<details><summary><b>Q7 · "How do you test a dashboard?"</b></summary>

**Initial Prompt.** What does a dashboard test look like?

**L5 Textbook Answer.** Open it and look.

**Why L5 Fails at 3 AM or on the Bill.** Visual checks miss broken queries until an incident.

**L7 Principal Defense.** Static: JSON schema validity, PromQL parse, lint rules (L1/L3). Semantic: run every panel query against staging and assert non-empty results with expected labels. Snapshot: generated JSON compared to approved snapshots. Cost: query-cost estimate under a budget (File 1 L1 model).
</details>

<details><summary><b>Q8 · "What's the migration path off Grizzly?"</b></summary>

**Initial Prompt.** We use Grizzly for everything.

**L5 Textbook Answer.** Keep using it until it breaks.

**Why L5 Fails at 3 AM or on the Bill.** It's marked for deprecation; it will break on an API change at a bad time.

**L7 Principal Defense.** Inventory resources by type; dashboards and folders → Git Sync (or generated + synced); alerting and platform resources → Terraform; bulk ops → grafanactl. Migrate per folder, verify with drift reports, delete the Grizzly pipeline when parity is proven.
</details>

---

## 5. Invariants checklist

- [ ] An ownership matrix assigns each resource type to exactly one tool (Git Sync, Terraform, generator + sync, provisioning).
- [ ] Standard dashboards and SLO rules are generated from specs; generated output is committed and CI fails on staleness.
- [ ] CI runs PromQL/naming/dashboard lints, `promtool check/test rules`, and Terraform plan.
- [ ] Generator and provider versions are pinned; upgrades get dedicated PRs with rendered previews.
- [ ] Drift between live resources and Git is reported automatically.
- [ ] No secrets in repositories; provisioning references environment or files.
- [ ] Deprecated tooling (Grizzly, `/api` scripts) has a migration plan.

---

## 6. References

- What's new in Grafana v13.0 (Git Sync GA): <https://grafana.com/docs/grafana/latest/whatsnew/whats-new-in-v13-0/>
- Git Sync documentation: <https://grafana.com/docs/grafana/latest/observability-as-code/provision-resources/intro-git-sync/>
- Terraform provider for Grafana: <https://registry.terraform.io/providers/grafana/grafana/latest/docs>
- grafanactl: <https://github.com/grafana/grafanactl>
- Grafana Foundation SDK: <https://github.com/grafana/grafana-foundation-sdk>
- grafonnet: <https://github.com/grafana/grafonnet>
- Monitoring mixins: <https://monitoring.mixins.dev/>
- Grizzly (deprecated): <https://github.com/grafana/grizzly>

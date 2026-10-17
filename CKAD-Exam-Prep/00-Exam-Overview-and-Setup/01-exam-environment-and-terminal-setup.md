# Exam Environment and Terminal Setup

How the CKAD exam desktop works (per the LF "Important Instructions: CKA and CKAD" and ExamUI pages, checked 17 Oct 2026), and the few seconds of setup that pay off on every task.

---

## 1. What you will see

```text
┌──────────────────────── PSI Secure Browser (Bridge) ─────────────────────────┐
│ Content Panel (left)           │ Remote Linux desktop (right)                 │
│  - task text + weight          │  - Terminal Emulator  (starts on host "base")│
│  - infobox: ssh <host>         │  - Firefox  (allowed docs only)              │
│  - Quick Reference doc links   │  - VSCodium (extensions disabled)            │
│  - flag / navigate tasks       │  - virtual keyboard, settings icons          │
└────────────────────────────────┴──────────────────────────────────────────────┘
Timer alerts at 30, 15 and 5 minutes remaining. Drag the border to resize the panel; +/- on the toolbar changes the font size.
```

## 2. One host per task

```text
base  (no kubectl, no tools)
  │   ssh <host-from-task-infobox>        <- every task names its designated host
  ▼
task host: kubectl + k alias + bash completion, yq, curl, wget, man
  │   ...solve and verify...
  │   exit                                 <- back to base; nested ssh is NOT supported
  ▼
base  -> next task
```

- **Always run the infobox `ssh` command first.** The cluster you need is reachable from that host.
- No password is needed for the ssh hop.
- `sudo -i` gives root on any host (or prefix single commands with `sudo`).
- **Do not reboot base.** Rebooting it does not restart your exam environment.
- Look at the prompt before typing `exit`. Candidates report that an extra `exit` on base closes the terminal session. If that happens, open a new Terminal Emulator from the desktop.
- Files you create live on **that** host. If a task says "save to /opt/course/3/out.txt", make sure you're on the task's host when you write it.

## 3. First seconds on each host (keep it tiny)

The `k` alias and completion are already configured. Variables and `~/.vimrc` are per host, so set only what you will actually use:

```bash
export do="--dry-run=client -o yaml"; export now="--force --grace-period=0"
echo 'set expandtab tabstop=2 shiftwidth=2 autoindent' >> ~/.vimrc     # once per host, only if you will edit YAML in vim
```

Check whether optional tools exist before you plan around them:

```bash
which helm podman docker kustomize jq tmux 2>/dev/null; helm version 2>/dev/null | head -1
```

Guaranteed on SSH hosts: `kubectl` (+`k`, completion), `yq`, `curl`, `wget`, `man`. **Don't count on jq.** The jsonpath equivalent always works:

```bash
k get pod web -o jsonpath='{.status.podIP}{"\n"}'          # instead of: -o json | jq -r .status.podIP
k get deploy web -o yaml | yq '.spec.template.spec.containers[0].image'
```

## 4. Keyboard and clipboard rules

| Action | Keys |
|---|---|
| Copy / paste **in the terminal** | **Ctrl+Shift+C / Ctrl+Shift+V** (or right-click menu) |
| Copy / paste in Firefox, VSCodium and other apps | Ctrl+C / Ctrl+V |
| Delete a word in bash (instead of Ctrl+W, which closes the browser tab) | **Ctrl+Alt+W** |
| Find on a docs page | Ctrl+F (resize Firefox so its whole window is visible first) |
| Locate the mouse cursor | Ctrl+Alt+K |
| INSERT key | **Prohibited**. In vim use `i`/`a`/`o` to enter insert mode, `Esc` to leave it. |
| Special characters (non-US keyboards) | Virtual Keyboard icon on the desktop |

## 5. Editing YAML

- **vim on the task host** is the reliable path: the file is created where kubectl runs.
- Paste docs YAML with `:set paste` → `i` → Ctrl+Shift+V → `Esc` → `:set nopaste`, so indentation survives.
- Indent a block: `V` (select lines) then `>` or `<`. Undo: `u`. Save and quit: `:wq`. Quit without saving: `:q!`.
- **VSCodium runs on the remote desktop itself, not on the task host.** Files you save in it aren't on the SSH host. Use it as a scratchpad, or copy from it into vim on the host.
- Validate before applying: `k apply --dry-run=server -f qN.yaml` catches schema errors without changing anything.

More vim/bash/tmux skills: [../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md).

## 6. Documentation in Firefox

- Allowed: kubernetes.io/docs, kubernetes.io/blog, helm.sh/docs, and the Quick Reference links in each task. The kubernetes.io search box is fine, but **do not open external search results**.
- Most-used pages are listed in [08-docs-navigation-map.md](08-docs-navigation-map.md). Practise finding them this weekend.
- Outside the browser, `man <cmd>`, `kubectl explain` and `<cmd> --help` are always available. Docs under `/usr/share` are allowed.

## 7. Habits that save minutes

| Habit | Why |
|---|---|
| `k explain deploy.spec.strategy.rollingUpdate` | Field names and types without leaving the terminal |
| Keep each task's manifest as `~/qN.yaml` on its host | Re-apply after a mistake in seconds |
| `k get <kind> -n <ns>` before creating | Reveals pre-existing objects the task expects you to modify |
| `k config set-context --current --namespace=<ns>` right after ssh | Removes the #1 point-loser: wrong namespace |
| Verify with one command, then `exit` | Bank the points, avoid nested-ssh trouble |

## 8. Make your practice lab feel the same

Your lab ([02-local-practice-lab-setup.md](02-local-practice-lab-setup.md)) has one cluster, so you won't ssh between hosts there. To build the habit anyway:
- Start each practice question by writing down its namespace and running `k config set-context --current --namespace=<ns>`.
- Practise with **only** the allowed docs open.
- Use killer.sh, which reproduces the remote-desktop and multi-host workflow, at least once before the exam.

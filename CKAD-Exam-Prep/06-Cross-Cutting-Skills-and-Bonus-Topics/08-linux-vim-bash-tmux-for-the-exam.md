# Linux, vim, bash and tmux for the Exam

**Why it matters / what the exam expects:** the exam runs in a remote Linux desktop with terminal windows (environment details: [00-Exam-Overview-and-Setup](../00-Exam-Overview-and-Setup/README.md)). You edit YAML in vim (or nano), test apps with `wget`/`curl`/`nslookup` from temporary pods, and juggle output with `grep`/`awk`/`base64`. Ten seconds saved per edit adds up to whole tasks over two hours. This page is the survival kit; practise it until it is muscle memory.

---

## Core concepts

### What the exam hosts give you

Per the current Linux Foundation exam documentation (authoritative summary and links: [00-Exam-Overview-and-Setup](../00-Exam-Overview-and-Setup/README.md)):

| Topic | Situation |
|---|---|
| Preconfigured | `kubectl` with the `k` alias and bash completion |
| Available tools | `yq`, `curl`, `wget`, `man` pages (plus the usual coreutils: grep, awk, sed, sort, base64, ...) |
| **May not be available** | `jq` and `tmux` (listed until 2024, no longer listed) - know the JSONPath / `yq` alternative and use a second terminal window instead of tmux |
| Where you work | each task runs on a designated host reached with `ssh <host>`; `exit` returns you to the base machine; nested ssh (ssh from one task host to another) is not supported |
| Consequence | exports and `~/.vimrc` tweaks may have to be re-applied on every new task host - keep them short |

### Per-host setup (three lines, ~15 seconds)

```bash
export do="--dry-run=client -o yaml"             # k run web --image=nginx:1.27 $do > web.yaml
export now="--force --grace-period=0"            # k delete pod web $now
echo 'set expandtab tabstop=2 shiftwidth=2 softtabstop=2 autoindent number' >> ~/.vimrc
```

Only if `type k` says the alias is missing on a host:

```bash
alias k=kubectl; source <(kubectl completion bash); complete -o default -F __start_kubectl k
```

The same as a reusable installer for your practice machine: [yaml/bashrc-exam-snippet.sh](yaml/bashrc-exam-snippet.sh) (`bash yaml/bashrc-exam-snippet.sh && source ~/.bashrc`) and [yaml/vimrc.txt](yaml/vimrc.txt).

> **Exam tip:** aliases exist only in your interactive shell. Inside `xargs`, `watch`, scripts (`bash file.sh`) and `vim :!` commands, write `kubectl`, not `k`. Exported variables such as `$do` do work there.

---

## Key fields / syntax

### vim survival kit

| Mode | Enter with | Leave with |
|---|---|---|
| Normal (move, delete, copy) | `Esc` | - |
| Insert | `i` (before cursor), `a` (after), `A` (end of line), `o` / `O` (new line below / above) | `Esc` |
| Visual (characters) | `v` | `Esc` |
| Visual-line | `V` | `Esc` |
| Visual-block (columns) | `Ctrl-v` | `Esc` |
| Command-line | `:` | `Enter` / `Esc` |

| Task | Keys (Normal mode) |
|---|---|
| Move by word / line start / line end | `w` `b` · `0` `^` · `$` |
| File start / end / line 42 | `gg` · `G` · `42G` or `:42` |
| Page down / up | `Ctrl-d` · `Ctrl-u` |
| Delete line / 3 lines / to end of line | `dd` · `3dd` · `D` |
| Copy (yank) line / 5 lines | `yy` · `5yy` |
| Paste below / above | `p` · `P` |
| Undo / redo / repeat last change | `u` · `Ctrl-r` · `.` |
| Delete char / replace char / join lines | `x` · `r<c>` · `J` |
| Change word / to end of line | `cw` · `C` |
| Indent / outdent current line | `>>` · `<<` (one `shiftwidth`, i.e. 2 spaces) |
| Indent a block | `V`, move with `j`/`k` (or `5j`), then `>` (or `3>` for three levels); `.` repeats |
| Search forward / next / previous | `/pattern` `Enter` · `n` · `N` (`*` = word under cursor) |
| Replace everywhere / with confirmation | `:%s/old/new/g` · `:%s/old/new/gc` |
| Indent lines 10-20 by 2 spaces | `:10,20s/^/  /` |
| Save / save+quit / quit without saving | `:w` · `:wq` (or `:x`, `ZZ`) · `:q!` |
| Reload the file, discarding changes | `:e!` |
| Insert a command's output into the file | `:r !kubectl create deploy web --image=nginx:1.27 $do` |

**Visual-block (`Ctrl-v`) recipes:**

```text
Add 2 spaces in front of lines 5-12 :  go to line 5, Ctrl-v, 7j, I, type two spaces, Esc   (applies to every line)
Comment out lines                   :  Ctrl-v, select lines, I, type "# ", Esc
Delete a column of characters       :  Ctrl-v, select the block, x (or d)
```

**Settings worth knowing:**

| Command | Effect |
|---|---|
| `:set number` / `:set nonumber` | line numbers (kubectl errors quote line numbers) |
| `:set paste` / `:set nopaste` | stop auto-indent from "staircasing" pasted YAML - turn on before pasting, off afterwards |
| `:set expandtab shiftwidth=2 tabstop=2` | spaces instead of tabs, 2-space indent |
| `:set list` / `:set nolist` | show tabs (`^I`) and line ends (`$`) |
| `:retab` | convert existing tabs to spaces (with `expandtab` set) |
| `:syntax on` · `:noh` | colours · clear search highlighting |

Recommended `~/.vimrc` (full annotated version: [yaml/vimrc.txt](yaml/vimrc.txt)):

```vim
set expandtab tabstop=2 shiftwidth=2 softtabstop=2 autoindent number
```

Creating `~/.vimrc` stops Vim from loading its `defaults.vim`, so add `syntax on` if you miss colours.

**nano fallback** (`export KUBE_EDITOR=nano` for `kubectl edit`): `Ctrl-O` save · `Ctrl-X` exit · `Ctrl-K` cut line · `Ctrl-U` paste · `Ctrl-W` search · `Alt-U` undo. In `~/.nanorc`: `set tabsize 2` and `set tabstospaces`.

### bash essentials

| Need | How |
|---|---|
| Search history | `Ctrl-r` then type (repeat `Ctrl-r` for older matches, `Ctrl-g` to abort) · `history \| grep autoscale` · `!123` |
| Repeat / reuse | `!!` last command · `!$` or `Alt-.` last argument · `sudo !!` |
| Line editing | `Ctrl-a` / `Ctrl-e` start / end · `Ctrl-w` delete word · `Ctrl-u` delete to start · `Ctrl-l` clear screen · `Ctrl-c` abort |
| Variables | `export NS=team-a` then `k -n $NS get pods`; plain `NS=x` is not passed to child processes |
| Exit status / chaining | `echo $?` · `cmd1 && cmd2` (only on success) · `cmd1 \|\| cmd2` (only on failure) · `;` (always) |
| Redirection | `>` overwrite · `>>` append · `2>&1` stderr too · `&> file` both · `> /dev/null` discard · `\| tee file` show and save |
| Backups | `cp web.yaml{,.bak}` (= `cp web.yaml web.yaml.bak`) |

**Heredocs** - create files or apply YAML without opening an editor:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: tmp-nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.27
EOF

cat > /tmp/web-svc.yaml <<'EOF'      # 'EOF' quoted: $VARS and $(cmds) are NOT expanded
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: web
  ports:
  - port: 80
EOF

POD=web; cat <<EOF                   # unquoted EOF: $POD IS expanded
pod is $POD
EOF
```

**Loops:**

```bash
for i in 1 2 3; do k run nginx-$i --image=nginx:1.27 --labels=batch=loop; done
for p in $(k get pods -l app=web -o name); do k exec "$p" -- nginx -v; done
for ns in dev qa prod; do echo "== $ns"; k get pods -n "$ns" --no-headers | wc -l; done
while true; do k get pods -l app=web --no-headers; sleep 2; done      # poor man's watch (Ctrl-c)
watch -n 2 kubectl get pods                                            # watch needs kubectl, not k
```

**Text tools:**

```bash
k get pods -A | grep -i -E 'error|crash'            # -i ignore case, -E extended regex
k get pods --no-headers | grep -v Running            # -v invert
k describe pod web | grep -n -A5 -i events           # -n line numbers, -A/-B/-C context
k get pods -A --no-headers | awk '{print $1"/"$2}'   # columns ($1 = first)
awk -F: '{print $1}' /etc/passwd | head -3           # -F field separator
k get pods -A --no-headers | sort -k5 -n -r | head -5   # sort by column 5 (RESTARTS with -A), numeric, reverse
k get pods -A --no-headers | awk '{print $1}' | sort | uniq -c | sort -rn   # count per namespace
k logs web --tail=50 ; k logs web -f                 # last 50 lines / follow
k get pods -o name | cut -d/ -f2                     # strip the "pod/" prefix
sed -i 's/nginx:1.27/nginx:1.27-alpine/' web.yaml    # in-place replace
k get pods -A -o wide | column -t                    # align columns
diff -u web.yaml web-live.yaml                       # compare two manifests
```

**base64:**

```bash
echo -n 'S3cr3t!' | base64                  # -n matters: without it the newline is encoded too
echo 'UzNjcjN0IQ==' | base64 -d             # decode
base64 -w0 tls.crt                          # no line wrapping (long values on one line)
k get secret db -o jsonpath='{.data.password}' | base64 -d; echo
```

### Network tools for testing applications

`curl` and `wget` are available on the exam hosts themselves; inside pods it depends on the image - hence the throw-away test pods below.

| Tool | Example | Available in |
|---|---|---|
| `wget` | `wget -qO- --timeout=2 http://web-svc.team-a` · `wget -S --spider http://web-svc` (headers only) | `busybox:1.36` |
| `curl` | `curl -s -m 3 http://web-svc.team-a/` · `-I` headers · `-v` verbose · `-k` ignore TLS · `-H 'Host: web.example.com'` | `curlimages/curl:8.10.1` |
| `nc` (netcat) | `nc -zv -w 2 db-svc 5432` (TCP port open?) - flags differ between netcat builds, check `nc --help` | busybox and many images |
| `nslookup` | `nslookup web-svc.team-a.svc.cluster.local` - use the FQDN with busybox; short names can fail with some busybox builds | `busybox:1.36` |
| `dig` | `dig +short web-svc.team-a.svc.cluster.local` | dnsutils images, not busybox |
| DNS config | `cat /etc/resolv.conf` (search domains, nameserver = cluster DNS) | every image with a shell |
| Service env vars | `env \| grep -i _SERVICE_` | every pod created after the Service |

```bash
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=2 http://web-svc.team-a:80
k run tmp --rm -it --image=curlimages/curl:8.10.1 --restart=Never -- curl -s -m 3 http://web-svc.team-a
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup web-svc.team-a.svc.cluster.local
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh      # interactive shell, exit to delete
k exec -it web -c app -- sh                                         # from inside an existing pod
curl -s http://<node-ip>:30080                                      # NodePort from the terminal host (if reachable)
```

### tmux basics (may not be available in the exam)

tmux is no longer listed among the exam tools. Without it: open a second terminal window for `k get pods -w`, or use `watch kubectl get pods`, or `k get pods -w &` and `fg` / `Ctrl-c` when done. Learn tmux for daily work and for practice labs. Prefix = `Ctrl-b`, then the key.

| Keys | Action |
|---|---|
| `tmux` / `tmux new -s exam` / `tmux attach` | start / named session / re-attach |
| `Ctrl-b %` · `Ctrl-b "` | split left/right · split top/bottom |
| `Ctrl-b` + arrow key · `Ctrl-b o` | move to the pane in that direction · next pane |
| `Ctrl-b z` | zoom the current pane (toggle) |
| `Ctrl-b x` | close the current pane |
| `Ctrl-b c` · `Ctrl-b n` / `p` · `Ctrl-b 0..9` | new window · next / previous window · window by number |
| `Ctrl-b [` | copy/scroll mode: arrows/PgUp/PgDn, `q` to leave |
| Copy in copy mode | default keys: `Ctrl-Space` start selection, `Alt-w` copy; vi keys (`set -g mode-keys vi`): `Space` start, `Enter` copy · `Ctrl-b ]` paste |
| `Ctrl-b d` | detach (session keeps running) |

Useful `~/.tmux.conf` lines: `set -g mouse on` (scroll and select with the mouse) and `set -g mode-keys vi`. Typical layout: `k get pods -w` in one pane, work in the other.

### yq (available on exam hosts) and jq (may not be)

Two different tools are called `yq`: mikefarah's Go `yq` v4 (syntax below - the common one) and kislyuk's Python wrapper, which uses jq syntax. Run `yq --version` once to see which one you have. Feed `yq` with `-o yaml`; feed `jq` with `-o json`. JSONPath (see [02](02-output-formatting-jsonpath-and-custom-columns.md)) always works without extra tools.

```bash
# Pod names
k get pods -o yaml | yq '.items[].metadata.name'
k get pods -o json | jq -r '.items[].metadata.name'                                         # jq variant

# Running pods only
k get pods -o yaml | yq '.items[] | select(.status.phase == "Running") | .metadata.name'
k get pods -o json | jq -r '.items[] | select(.status.phase=="Running") | .metadata.name'   # jq variant

# Name and node per pod
k get pods -o yaml | yq '.items[] | .metadata.name + " " + .spec.nodeName'
k get pods -o json | jq -r '.items[] | "\(.metadata.name) \(.spec.nodeName)"'               # jq variant

# Regex match on names (JSONPath cannot do this)
k get pods -o yaml | yq '.items[] | select(.metadata.name | test("^web-")) | .metadata.name'
k get pods -o json | jq -r '.items[] | select(.metadata.name | test("^web-")) | .metadata.name'   # jq variant

# Decode one Secret key / every key
k get secret db -o yaml | yq '.data.password | @base64d'
k get secret db -o yaml | yq '.data | map_values(@base64d)'
k get secret db -o json | jq -r '.data | map_values(@base64d)'                              # jq variant (jq 1.6+)

# Unique images in the cluster
k get pods -A -o yaml | yq '[.items[].spec.containers[].image] | unique | .[]'
k get pods -A -o json | jq -r '[.items[].spec.containers[].image] | unique[]'               # jq variant
```

Editing manifests with yq:

```bash
yq '.spec.template.spec.containers[0].image' deploy.yaml           # read one field from a manifest
yq -i '.spec.replicas = 3' deploy.yaml                              # edit a manifest in place
yq -i '.metadata.labels.tier = "frontend"' deploy.yaml              # add/change a label
yq -i '.spec.template.spec.containers[0].image = "nginx:1.27-alpine"' deploy.yaml   # change the image
yq 'select(.kind == "Service")' all.yaml                            # pick documents of a multi-doc file by kind
k get deploy web -o yaml | yq '.spec.template.spec.containers[].name'   # container names of a live object
```

### Copy and paste in a remote desktop

| Where | Copy | Paste |
|---|---|---|
| Terminal window | `Ctrl+Shift+C` | `Ctrl+Shift+V` |
| Browser (docs) and other GUI apps | `Ctrl+C` | `Ctrl+V` |
| Linux selection buffer | select with the mouse | middle-click (if the desktop supports it) |

`Ctrl+C` inside a terminal **interrupts** the running command - it does not copy. Confirm the exact shortcuts for the current exam desktop in the official candidate documentation (linked from [00](../00-Exam-Overview-and-Setup/README.md)).

---

## Imperative commands

The commands for this topic are the shell commands above; the kubectl-side helpers are collected in [commands.md](commands.md). Practise this sequence until it takes under a minute:

```bash
k create deploy web --image=nginx:1.27 --replicas=2 $do > web.yaml   # generate
vim web.yaml                                                          # add e.g. resources; :wq
k apply -f web.yaml && k rollout status deploy/web                    # apply and wait
k expose deploy web --port=80                                         # service
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=2 http://web   # test
k delete deploy web; k delete svc web                                 # clean up
```

---

## Exam traps & tips

> **Exam tip:** before typing, check the prompt - which host am I on? Each task names its host: `ssh <host>` first, and `exit` back to the base machine when the task is done; nested ssh from one task host to the next is not supported. On a new host, re-run the three per-host setup lines if `echo "$do"` prints nothing.

> **Exam tip:** `echo 'secret' | base64` encodes a trailing newline; Secrets created that way contain `secret\n`. Use `echo -n` or `kubectl create secret generic --from-literal`.

> **Exam tip:** with busybox use `wget -qO- --timeout=2 ...`; without a timeout a blocked connection (NetworkPolicy tests) hangs until you press `Ctrl-c`.

- `watch k get pods` fails (alias); use `watch kubectl get pods` (or `alias watch='watch '`).
- Quote heredoc delimiters (`<<'EOF'`) when the content contains `$` (jsonpath, shell variables in scripts).
- `Ctrl-s` in some terminals freezes output - `Ctrl-q` unfreezes it.
- vim: if keys behave strangely you are probably still in insert or visual mode - press `Esc` twice.
- Keep a scratch file (e.g. `~/notes.txt`) for task numbers you skipped and come back later.

---

## Architect notes

- Shell fluency remains a core SRE skill for incident response, but production changes should come from reviewed, idempotent automation (GitOps, CI), not from interactive sessions.
- Do not ship `curl`/`nslookup` in production images just for debugging; use ephemeral debug containers (`kubectl debug`) and keep images minimal or distroless.
- On bastion hosts use tmux/screen for long-running operations and session recording for auditability.
- jq/yq belong in pipelines and scripts; standardise on one `yq` implementation in your tooling images.
- kubectl plugins via krew (`ctx`, `ns`, `neat`, `tree`, `who-can`) speed up daily work - they are not available in the exam, so train with plain kubectl too.
- Distribute a team shell profile (aliases, completion, prompt showing context and namespace) so everybody sees which cluster they are about to change.

---

## Docs to bookmark

- kubectl Quick Reference (autocomplete, aliases): https://kubernetes.io/docs/reference/kubectl/quick-reference/
- Install and Set Up kubectl on Linux (bash completion): https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- Get a Shell to a Running Container: https://kubernetes.io/docs/tasks/debug/debug-application/get-shell-running-container/
- Debug Services (wget/nslookup from a test pod): https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/
- Debugging DNS Resolution: https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/

---

## Quick self-check

1. Indent lines 8-15 of a YAML file by two spaces in vim - give two different ways.
2. Pasted YAML in vim is shifted further right with every line. What happened and what is the fix?
3. Why does `watch k get pods` fail?
4. Decode the base64 string `aGVsbG8=` and explain why `echo hello | base64` gives a different string than `echo -n hello | base64`.
5. Test DNS for Service `api` in namespace `shop` from a throw-away pod.

<details><summary>Answers</summary>

1. `:8,15s/^/  /` - or go to line 8, `V`, `7j`, `>` (with `shiftwidth=2`) - or `Ctrl-v` on line 8, `7j`, `I`, two spaces, `Esc`.
2. Auto-indent re-indented each pasted line. Undo (`u`), `:set paste`, `i`, paste again, `Esc`, `:set nopaste`.
3. `watch` runs the command through `sh -c`, where the interactive alias `k` does not exist. Use `watch kubectl get pods`.
4. `echo aGVsbG8= | base64 -d` → `hello`. Without `-n`, echo appends a newline, which is encoded as well (`aGVsbG8K`).
5. `k run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup api.shop.svc.cluster.local`

</details>

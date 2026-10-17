#!/usr/bin/env bash
# Appends CKAD exam shell helpers to ~/.bashrc (idempotent - safe to run twice).
# Usage:   bash bashrc-exam-snippet.sh            # or: bash bashrc-exam-snippet.sh /path/to/other/rc-file
#          source ~/.bashrc
# This installer is for your PRACTICE machine. In the exam, `k` and bash completion are preconfigured and
# each task runs on its own ssh host: there you only type the two export lines (and the one-line ~/.vimrc),
# again on every new host (check with: echo "$do"). See ../08-linux-vim-bash-tmux-for-the-exam.md.
set -euo pipefail

MARKER="# >>> ckad exam helpers >>>"
TARGET="${1:-$HOME/.bashrc}"

if grep -qF "$MARKER" "$TARGET" 2>/dev/null; then
  echo "CKAD helpers already present in $TARGET - nothing to do."
  exit 0
fi

cat >> "$TARGET" <<'EOF'
# >>> ckad exam helpers >>>
alias k=kubectl
source <(kubectl completion bash) 2>/dev/null || true   # tab completion for kubectl
complete -o default -F __start_kubectl k 2>/dev/null || true   # ... and for the alias k
export do="--dry-run=client -o yaml"      # k create deploy web --image=nginx:1.27 $do > web.yaml
export now="--force --grace-period=0"     # k delete pod web $now

# Optional extras (only if you will really use them):
alias kn='kubectl config set-context --current --namespace'   # kn dev   -> default namespace "dev"
alias kgp='kubectl get pods -o wide'
export KUBE_EDITOR=vim                    # editor used by kubectl edit
# <<< ckad exam helpers <<<
EOF

echo "Appended CKAD helpers to $TARGET - now run: source $TARGET"

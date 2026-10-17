#!/usr/bin/env bash
# =============================================================================
# CKAD Mock Exam 05 — cleanup
#   bash cleanup.sh
# Removes only what this exam (setup.sh + the reference solutions) created:
#   - Helm release "web" (m05-helm) and the Helm repo entry "m05-podinfo"
#   - cluster-scoped objects: CRD maintenancewindows.ops.m05.ckad.io,
#     PriorityClass m05-batch-critical, anything else labelled ckad-mock=exam-05
#   - every namespace labelled ckad-mock=exam-05 (m05-*)
#   - the local container + image of Q19 (m05-greeter, localhost/m05-greeter:1.1)
#   - ~/ckad-mocks/exam-05
# =============================================================================
set -euo pipefail

EXAM="exam-05"
LABEL="ckad-mock=${EXAM}"
BASE="${HOME}/ckad-mocks/${EXAM}"

info() { printf '==> %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

have kubectl || { echo "ERROR: kubectl not found in PATH." >&2; exit 1; }
kubectl get namespace default >/dev/null 2>&1 || { echo "ERROR: cannot reach the cluster." >&2; exit 1; }

# 1. Helm (installed by the solutions)
if have helm; then
  if helm status web -n m05-helm >/dev/null 2>&1; then
    info "Uninstalling Helm release web (m05-helm)"
    helm uninstall web -n m05-helm >/dev/null || true
  fi
  repos="$(helm repo list 2>/dev/null || true)"
  if grep -q '^m05-podinfo[[:space:]]' <<<"${repos}"; then
    info "Removing Helm repo m05-podinfo"
    helm repo remove m05-podinfo >/dev/null || true
  fi
fi

# 2. Cluster-scoped objects (created by the solutions)
info "Deleting cluster-scoped objects"
kubectl delete crd maintenancewindows.ops.m05.ckad.io --ignore-not-found
kubectl delete priorityclass m05-batch-critical --ignore-not-found
kubectl delete crd,priorityclass,clusterrole,clusterrolebinding -l "${LABEL}" --ignore-not-found

# 3. Namespaces (everything namespaced lives in m05-*)
info "Deleting namespaces labelled ${LABEL} (this can take a minute)"
kubectl delete namespace -l "${LABEL}" --ignore-not-found --timeout=300s \
  || echo "WARNING: some namespaces are still terminating; check with: kubectl get ns -l ${LABEL}" >&2
leftover="$(kubectl get namespace -o name 2>/dev/null | grep '^namespace/m05-' || true)"
if [[ -n "${leftover}" ]]; then
  echo "NOTE: these m05-* namespaces remain (not labelled ${LABEL}, so not deleted):" >&2
  echo "${leftover}" >&2
fi

# 4. Local container artefacts from Q19
for tool in podman docker; do
  if have "${tool}"; then
    "${tool}" rm -f m05-greeter >/dev/null 2>&1 || true
    "${tool}" rmi -f localhost/m05-greeter:1.1 >/dev/null 2>&1 || true
  fi
done

# 5. Local files
if [[ -d "${BASE}" ]]; then
  info "Removing ${BASE}"
  rm -rf "${BASE}"
fi
rmdir "${HOME}/ckad-mocks" 2>/dev/null || true   # only if now empty

echo "Mock exam 05 cleaned up. (Stop any 'kubectl port-forward' you left running.)"

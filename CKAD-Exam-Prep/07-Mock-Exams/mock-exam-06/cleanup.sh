#!/usr/bin/env bash
# =============================================================================
# CKAD Mock Exam 06 — cleanup
#   bash cleanup.sh
# Removes only what this exam (setup.sh + the reference solutions) created:
#   - Helm releases portal (m06-helm) and portal-old (m06-legacy)
#   - CRDs featureflags.flags.m06.ckad.io / flagsets.flags.m06.ckad.io,
#     ClusterRoles + ClusterRoleBindings m06-flag-operator / m06-flag-viewer,
#     anything else cluster-scoped labelled ckad-mock=exam-06
#   - every namespace labelled ckad-mock=exam-06 (m06-*)
#   - the local images of Q17 (tally:2.1.0, registry.m06.local:5000/tally:2.1.0)
#   - ~/ckad-mocks/exam-06
# =============================================================================
set -euo pipefail

EXAM="exam-06"
LABEL="ckad-mock=${EXAM}"
BASE="${HOME}/ckad-mocks/${EXAM}"

info() { printf '==> %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

have kubectl || { echo "ERROR: kubectl not found in PATH." >&2; exit 1; }
kubectl get namespace default >/dev/null 2>&1 || { echo "ERROR: cannot reach the cluster." >&2; exit 1; }

# 1. Helm releases (setup.sh installed them; the solutions upgrade/roll back/uninstall them)
if have helm; then
  for rel in portal:m06-helm portal-old:m06-legacy; do
    name="${rel%%:*}"; ns="${rel##*:}"
    if helm status "${name}" -n "${ns}" >/dev/null 2>&1; then
      info "Uninstalling Helm release ${name} (${ns})"
      helm uninstall "${name}" -n "${ns}" >/dev/null || true
    fi
  done
fi

# 2. Cluster-scoped objects
info "Deleting cluster-scoped objects"
kubectl delete crd featureflags.flags.m06.ckad.io flagsets.flags.m06.ckad.io --ignore-not-found
kubectl delete clusterrolebinding m06-flag-operator m06-flag-viewer --ignore-not-found
kubectl delete clusterrole m06-flag-operator m06-flag-viewer --ignore-not-found
kubectl delete crd,clusterrole,clusterrolebinding,priorityclass -l "${LABEL}" --ignore-not-found

# 3. Namespaces (everything namespaced lives in m06-*)
info "Deleting namespaces labelled ${LABEL} (StatefulSet PVCs can take a minute)"
kubectl delete namespace -l "${LABEL}" --ignore-not-found --timeout=300s \
  || echo "WARNING: some namespaces are still terminating; check with: kubectl get ns -l ${LABEL}" >&2
leftover="$(kubectl get namespace -o name 2>/dev/null | grep '^namespace/m06-' || true)"
if [[ -n "${leftover}" ]]; then
  echo "NOTE: these m06-* namespaces remain (not labelled ${LABEL}, so not deleted):" >&2
  echo "${leftover}" >&2
fi

# 4. Local images from Q17
for tool in podman docker; do
  if have "${tool}"; then
    "${tool}" rmi -f registry.m06.local:5000/tally:2.1.0 tally:2.1.0 localhost/tally:2.1.0 >/dev/null 2>&1 || true
  fi
done

# 5. Local files
if [[ -d "${BASE}" ]]; then
  info "Removing ${BASE}"
  rm -rf "${BASE}"
fi
rmdir "${HOME}/ckad-mocks" 2>/dev/null || true   # only if now empty

echo "Mock exam 06 cleaned up. (Images you loaded into kind nodes with 'kind load' stay cached there.)"

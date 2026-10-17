#!/usr/bin/env bash
# CKAD Mock Exam 04 (Intermediate+) - cleanup
#
#   bash cleanup.sh
#
# Removes everything setup.sh and the reference solutions created:
#   - Helm releases billing (m04-helm-a), audit and reports (m04-helm-b)
#   - all namespaces labelled ckad-mock=exam-04 (m04-*) and everything inside them
#   - cluster-scoped objects: PersistentVolume m04-reports-pv, ClusterRoleBinding
#     m04-auditor-everywhere, ClusterRole m04-deploy-viewer, CRD featureflags.flags.m04.example.com
#   - the local images m04-api:2.4.1 and m04-api:stable (podman and/or docker)
#   - the work directory ~/ckad-mocks/exam-04
set -euo pipefail

EXAM="exam-04"
D="${HOME}/ckad-mocks/${EXAM}"

info() { printf '>> %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

if have kubectl && kubectl get nodes --request-timeout=15s >/dev/null 2>&1; then
  if have helm; then
    for rel in m04-helm-a/billing m04-helm-b/audit m04-helm-b/reports; do
      ns="${rel%%/*}"
      name="${rel##*/}"
      if helm status "$name" -n "$ns" >/dev/null 2>&1; then
        helm uninstall "$name" -n "$ns" >/dev/null && info "helm release ${rel} uninstalled" || true
      fi
    done
  fi

  info "deleting namespaces labelled ckad-mock=${EXAM} (this can take a minute)"
  kubectl delete namespace -l "ckad-mock=${EXAM}" --ignore-not-found --wait=true --timeout=300s \
    || echo "WARNING: namespace deletion is still in progress - check with: kubectl get ns -l ckad-mock=${EXAM}" >&2

  info "deleting cluster-scoped objects"
  kubectl delete persistentvolume -l "ckad-mock=${EXAM}" --ignore-not-found >/dev/null
  kubectl delete persistentvolume m04-reports-pv --ignore-not-found >/dev/null
  kubectl delete clusterrolebinding -l "ckad-mock=${EXAM}" --ignore-not-found >/dev/null
  kubectl delete clusterrolebinding m04-auditor-everywhere --ignore-not-found >/dev/null
  kubectl delete clusterrole m04-deploy-viewer --ignore-not-found >/dev/null
  kubectl delete customresourcedefinition featureflags.flags.m04.example.com --ignore-not-found >/dev/null
else
  echo "WARNING: no reachable cluster - skipping Kubernetes cleanup" >&2
fi

for rt in podman docker; do
  if have "$rt"; then
    for img in m04-api:2.4.1 m04-api:stable; do
      "$rt" rmi -f "$img" >/dev/null 2>&1 && info "removed image ${img} (${rt})" || true
    done
  fi
done

rm -rf "$D"
rmdir "${HOME}/ckad-mocks" 2>/dev/null || true
info "removed ${D}"
echo "Note: the hostPath directory /tmp/m04-reports stays on the node that ran Pod 'reports'"
echo "      (remove it with 'minikube ssh' or 'docker exec <kind-node> rm -rf /tmp/m04-reports' if you like)."
echo "Mock Exam 04 cleanup finished."

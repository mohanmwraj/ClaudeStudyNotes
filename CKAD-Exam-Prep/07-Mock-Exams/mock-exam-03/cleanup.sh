#!/usr/bin/env bash
# CKAD Mock Exam 03 (Intermediate) - cleanup
#
#   bash cleanup.sh
#
# Removes everything setup.sh and the reference solutions created:
#   - Helm release storefront (namespace m03-helm)
#   - all namespaces labelled ckad-mock=exam-03 (m03-*) and everything inside them
#   - the cluster-scoped CRD databasebackups.ops.m03.example.com
#   - the local image m03-motd:1.1 (podman and/or docker)
#   - the work directory ~/ckad-mocks/exam-03
set -euo pipefail

EXAM="exam-03"
D="${HOME}/ckad-mocks/${EXAM}"

info() { printf '>> %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

if have kubectl && kubectl get nodes --request-timeout=15s >/dev/null 2>&1; then
  if have helm && helm status storefront -n m03-helm >/dev/null 2>&1; then
    helm uninstall storefront -n m03-helm >/dev/null && info "helm release m03-helm/storefront uninstalled"
  fi

  info "deleting namespaces labelled ckad-mock=${EXAM} (this can take a minute)"
  kubectl delete namespace -l "ckad-mock=${EXAM}" --ignore-not-found --wait=true --timeout=300s \
    || echo "WARNING: namespace deletion is still in progress - check with: kubectl get ns -l ckad-mock=${EXAM}" >&2

  info "deleting cluster-scoped objects"
  kubectl delete customresourcedefinition -l "ckad-mock=${EXAM}" --ignore-not-found >/dev/null
  kubectl delete customresourcedefinition databasebackups.ops.m03.example.com --ignore-not-found >/dev/null
else
  echo "WARNING: no reachable cluster - skipping Kubernetes cleanup" >&2
fi

for rt in podman docker; do
  if have "$rt"; then
    "$rt" rmi -f m03-motd:1.1 >/dev/null 2>&1 && info "removed image m03-motd:1.1 (${rt})" || true
  fi
done

rm -rf "$D"
rmdir "${HOME}/ckad-mocks" 2>/dev/null || true
info "removed ${D}"
echo "Mock Exam 03 cleanup finished."

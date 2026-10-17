#!/usr/bin/env bash
# =============================================================================
# CKAD Mock Exam 01 — cleanup
#   bash cleanup.sh
# Removes what setup.sh and the reference solutions created:
#   Helm release m01-shop, namespaces labelled ckad-mock=exam-01, namespace m01-helm,
#   PV m01-pv-data, CRD backups.m01.example.com, the local image m01-webapp:1.0
#   and ~/ckad-mocks/exam-01. Nothing else is touched.
# =============================================================================
set -euo pipefail

EXAM="exam-01"
LABEL="ckad-mock=${EXAM}"
BASE="${HOME}/ckad-mocks/${EXAM}"

have() { command -v "$1" >/dev/null 2>&1; }
have kubectl || { echo "ERROR: kubectl not found in PATH." >&2; exit 1; }

echo "==> Helm releases installed by the solutions"
if have helm; then
  if helm status m01-shop -n m01-helm >/dev/null 2>&1; then
    if helm uninstall m01-shop -n m01-helm >/dev/null; then
      echo "    uninstalled m01-shop (m01-helm)"
    else
      echo "WARNING: could not uninstall m01-shop - the namespace deletion below removes its objects anyway"
    fi
  fi
else
  echo "    helm not found - skipped"
fi

echo "==> Namespaces labelled ${LABEL} (this can take a minute)"
kubectl delete namespace -l "${LABEL}" --wait=true --timeout=300s \
  || echo "WARNING: some namespaces are still terminating - re-run cleanup.sh later"

echo "==> Namespace created by the Helm install (Q7)"
kubectl delete namespace m01-helm --ignore-not-found --wait=true --timeout=300s \
  || echo "WARNING: namespace m01-helm is still terminating"

echo "==> Cluster-scoped objects"
kubectl delete persistentvolume m01-pv-data --ignore-not-found --timeout=120s \
  || echo "WARNING: PV m01-pv-data not deleted yet"
kubectl delete customresourcedefinition -l "${LABEL}" --ignore-not-found

echo "==> Local image from Q1 (if present)"
for tool in podman docker; do
  if have "${tool}"; then
    "${tool}" rmi m01-webapp:1.0 >/dev/null 2>&1 && echo "    removed m01-webapp:1.0 (${tool})" || true
  fi
done

echo "==> Files under ${BASE}"
rm -rf "${BASE}"
rmdir "${HOME}/ckad-mocks" 2>/dev/null || true   # only removed when empty

echo "Done. (The hostPath directory /tmp/m01-data inside the node is left; it is harmless.)"

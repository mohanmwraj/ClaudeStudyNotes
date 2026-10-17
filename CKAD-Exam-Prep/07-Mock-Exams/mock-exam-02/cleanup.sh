#!/usr/bin/env bash
# =============================================================================
# CKAD Mock Exam 02 — cleanup
#   bash cleanup.sh
# Removes what setup.sh and the reference solutions created:
#   Helm releases m02-web (m02-helm) and m02-legacy (m02-tools), namespaces labelled
#   ckad-mock=exam-02, CRDs labelled ckad-mock=exam-02, the local image m02-report:2.0
#   and ~/ckad-mocks/exam-02. Nothing else is touched.
# =============================================================================
set -euo pipefail

EXAM="exam-02"
LABEL="ckad-mock=${EXAM}"
BASE="${HOME}/ckad-mocks/${EXAM}"

have() { command -v "$1" >/dev/null 2>&1; }
have kubectl || { echo "ERROR: kubectl not found in PATH." >&2; exit 1; }

echo "==> Helm releases"
if have helm; then
  for rel in m02-web:m02-helm m02-legacy:m02-tools; do
    name="${rel%%:*}"
    ns="${rel##*:}"
    if helm status "${name}" -n "${ns}" >/dev/null 2>&1; then
      if helm uninstall "${name}" -n "${ns}" >/dev/null; then
        echo "    uninstalled ${name} (${ns})"
      else
        echo "WARNING: could not uninstall ${name} - the namespace deletion below removes its objects anyway"
      fi
    fi
  done
else
  echo "    helm not found - skipped"
fi

echo "==> Namespaces labelled ${LABEL} (this can take a minute)"
kubectl delete namespace -l "${LABEL}" --wait=true --timeout=300s \
  || echo "WARNING: some namespaces are still terminating - re-run cleanup.sh later"

echo "==> Cluster-scoped objects"
kubectl delete customresourcedefinition -l "${LABEL}" --ignore-not-found

echo "==> Local image from Q1 (if present)"
for tool in podman docker; do
  if have "${tool}"; then
    "${tool}" rmi m02-report:2.0 >/dev/null 2>&1 && echo "    removed m02-report:2.0 (${tool})" || true
  fi
done

echo "==> Files under ${BASE}"
rm -rf "${BASE}"
rmdir "${HOME}/ckad-mocks" 2>/dev/null || true   # only removed when empty

echo "Done."

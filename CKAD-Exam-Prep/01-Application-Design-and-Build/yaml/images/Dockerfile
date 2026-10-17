# Demonstrates every common Dockerfile instruction on a tiny, NON-ROOT static web server (busybox httpd).
#
# Build:  podman build --format docker -t ckad-web:v1 .      (or: docker build -t ckad-web:v1 .)
#         --format docker keeps HEALTHCHECK; podman/buildah default to the OCI format, which drops it.
# Build with another version:  podman build --build-arg APP_VERSION=2.0 -t ckad-web:v2 .
# Run:    podman run -d --name ckad-web -p 8080:8080 ckad-web:v1 && curl -s localhost:8080
# Logs:   podman logs ckad-web     (httpd -v logs requests to stderr)

# ARG before the first FROM: only usable inside FROM lines
ARG BASE_TAG=1.36
FROM busybox:${BASE_TAG}

# Build-time variable with a default (override with --build-arg). Visible in "podman history" -> never a secret.
ARG APP_VERSION=1.0

# Metadata (inspect: podman image inspect --format '{{json .Labels}}' ckad-web:v1)
LABEL org.opencontainers.image.title="ckad-web" \
      org.opencontainers.image.version="${APP_VERSION}" \
      maintainer="ckad-student"

# Runtime environment: persisted in the image config; a Pod's env overrides it. Never put secrets here.
ENV APP_VERSION=${APP_VERSION} \
    PORT=8080 \
    DOC_ROOT=/www

# Creates the directory if needed and sets the working directory for the following instructions
WORKDIR /www

# Copy from the build context (prefer COPY; ADD additionally fetches URLs and auto-extracts local tar archives)
COPY --chown=10001:10001 index.html ./index.html

# Build-time command = new layer. Chain commands in ONE RUN to keep layers few and clean up in the same step.
RUN echo "version ${APP_VERSION}" > /www/version.txt \
 && mkdir -p /www/uploads \
 && chown -R 10001:10001 /www

# Declares a mount point. Changes to /www/uploads in later build steps are discarded.
# Kubernetes does NOT create volumes from this - mount a Kubernetes volume at that path instead.
VOLUME ["/www/uploads"]

# Numeric UID:GID so Kubernetes "runAsNonRoot: true" can verify the user (a user NAME cannot be verified)
USER 10001:10001

# Documentation only - publishes nothing (podman/docker need -p; Kubernetes needs a Service)
EXPOSE 8080

# Used by podman/docker only. Kubernetes ignores HEALTHCHECK - configure liveness/readiness probes instead.
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -q -O /dev/null "http://127.0.0.1:${PORT}/" || exit 1

# Signal sent on "podman stop" and by containerd/CRI-O when Kubernetes stops the container (default SIGTERM)
STOPSIGNAL SIGTERM

# ENTRYPOINT (exec form) = the executable; CMD = default arguments, replaced by "podman run IMAGE <args>".
# Kubernetes: container.command replaces ENTRYPOINT, container.args replaces CMD.
# Exec form does no variable expansion, so the port is written literally here.
ENTRYPOINT ["httpd", "-f", "-v"]
CMD ["-p", "8080", "-h", "/www"]

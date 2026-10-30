---
paths:
  - "**/adapter/in/web/**"
  - "**/src/main/resources/application*.yml"
---
# Security rules
- Credentials come from the environment or the secret manager; none in code, YAML or tests.
- Every request DTO is validated with Bean Validation; error bodies are ProblemDetail without internals.
- New dependencies need a reason in the PR description and a pinned version from the Boot BOM where it manages one.
- Log identifiers, not personal data; no request bodies at INFO.

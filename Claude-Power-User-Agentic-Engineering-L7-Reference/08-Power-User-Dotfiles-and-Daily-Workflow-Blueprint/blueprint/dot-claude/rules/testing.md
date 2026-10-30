---
paths:
  - "**/src/test/**"
---
# Testing rules
- Integration tests extend `AbstractIT` (Testcontainers PostgreSQL 17 and Kafka via @ServiceConnection); no H2, no mocked DataSource.
- Container images use pinned tags.
- Race tests release threads with a CyclicBarrier, run at least 200 rounds, assert the domain invariant each round, and are shown failing before the fix.
- ArchUnit rules over legacy code are frozen; the `archunit_store/` diff may only remove lines.

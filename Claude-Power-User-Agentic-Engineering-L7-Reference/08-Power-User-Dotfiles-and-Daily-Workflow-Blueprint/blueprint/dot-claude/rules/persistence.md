---
paths:
  - "**/src/main/resources/db/migration/**"
  - "**/adapter/out/persistence/**"
---
# Persistence rules
- Applied Flyway migrations are immutable; fix forward with a new V<n>.
- Every foreign key gets an index in the same migration.
- Indexes on live tables are built CONCURRENTLY in a migration that runs outside a transaction.
- Repositories implement `application` ports; list queries paginate by keyset; no `select *`.
- Money is `numeric` plus a currency column; timestamps are `timestamptz`.

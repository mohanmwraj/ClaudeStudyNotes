---
name: new-slice
description: Scaffold one vertical slice - REST controller, service, repository, Flyway migration and a Testcontainers integration test - for a new aggregate in order-platform. Use when the user asks to add a new resource, entity or endpoint end to end.
argument-hint: "<Aggregate> <module>"
arguments: [aggregate, module]
disable-model-invocation: true
allowed-tools: Read Glob Grep Edit Write Bash(./mvnw -q *) Bash(${CLAUDE_SKILL_DIR}/scripts/next_migration.sh *)
---
# New vertical slice: $aggregate in $module

Read [reference.md](reference.md) first; it holds the package layout and the exact class shapes.

Create, in this order (each step must compile before the next):
1. Migration: run `${CLAUDE_SKILL_DIR}/scripts/next_migration.sh $module` for the next version, then write
   `V<n>__create_<table>.sql` with the table, a SEQUENCE, indexes for every foreign key, and NOT NULL defaults.
2. Entity + repository: SEQUENCE ids with a pooled optimizer; repository methods paginate with keyset.
3. Service: constructor injection; transactions via TransactionTemplate; no Kafka/HTTP inside a transaction;
   publish events through the outbox.
4. Controller: request/response records with Bean Validation; errors as ProblemDetail through ApiErrors.
5. Integration test `<Aggregate>ApiIT extends AbstractIT`: create, read, validation error (400 ProblemDetail),
   duplicate Idempotency-Key, and pagination.

Done when `./mvnw -q -pl $module verify -Pit` passes. Report the command and its summary lines, then list the
files you created.

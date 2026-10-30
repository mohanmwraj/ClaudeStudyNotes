# order-platform - Claude Code project memory

## Commands
- Build + unit tests: `./mvnw -q verify -DskipITs`
- One test class: `./mvnw -q test -Dtest=OrderServiceTest`
- Integration tests (Docker required): `./mvnw -q verify -Pit`
- Format: `./mvnw -q spotless:apply` (the PostToolUse hook runs it after edits; CI runs `spotless:check`)
- Architecture rules: `./mvnw -q test -Dtest=ArchitectureTest`
- Local stack: `docker compose up -d postgres kafka`

## Conventions (team decisions the code alone does not show)
- Java 21 source level on a JDK 25 runtime; Spring Boot 4.1 with its managed versions; Maven wrapper only.
- Packages: `domain` (no framework imports), `application` (use cases, ports, transactions), `adapter` (web, persistence, messaging).
- Constructor injection; no `@Autowired` fields. DTOs and events are `record`s; controllers never return entities.
- Errors are RFC 9457 `ProblemDetail` from `ApiErrors`; responses carry no exception messages or stack traces.
- Schema changes are new Flyway files in `src/main/resources/db/migration/`; applied migrations are immutable.
- No Kafka or HTTP call inside a transaction; events go through the outbox (`OutboxWriter`, `OutboxRelay`).
- Transactional work called from the same class goes through `TransactionTemplate` (proxy self-invocation).
- Virtual threads are on, so the Hikari pool size is the database concurrency limit; change it only with the sizing arithmetic.
- Outbound HTTP uses the `RestClient` beans from `HttpClientsConfig` (timeouts and Resilience4j already applied).
- Tests: JUnit 6 + Testcontainers (`AbstractIT` starts PostgreSQL 17 and Kafka); no H2.

## Gotchas
- `legacy-billing/` is live but frozen by ArchUnit (`archunit_store/`); do not copy its patterns.
- The `generated/` package comes from `api/openapi.yaml`; change the YAML, then regenerate.
- `application-local.yml` is gitignored; copy `application-local.example.yml`.

## Where to look
- Specs: `docs/specs/`; implement against the spec's invariants and fill in its traceability table.
- Path-scoped rules: `.claude/rules/` (persistence, messaging, testing, security).
- Prompt templates T1-T7: `.claude/prompts/`; `/new-slice` wraps T2.
- Project knowledge over MCP: the `order-platform` server (`architecture_rules`, `describe_table`, `build_health`).
- Done means `./mvnw -q verify` passes.

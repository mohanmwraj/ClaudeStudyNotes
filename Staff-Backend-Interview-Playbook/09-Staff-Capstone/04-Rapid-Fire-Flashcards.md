# 9.4 Rapid-Fire Flashcards

> **330 cards.** Pillars 1–8 and 10 are collected verbatim from each pillar's bar-raiser file (so they stay in sync with the evidence), followed by 20 capstone cards. Click a question to reveal the answer.
>
> **How to use:** a Leitner box. Five boxes; every card starts in box 1. Review box 1 daily, box 2 every 2 days, box 3 every 4, box 4 weekly, box 5 before the interview. A correct answer moves a card up one box; a miss sends it back to box 1. Say answers **out loud** in one or two sentences, then follow the source link for any card you hesitate on.

**Jump to:** [1. Build systems](#1-build-systems) · [2. SQL and RDBMS internals](#2-sql-and-rdbms-internals) · [3. JPA, Hibernate, Spring Data](#3-jpa-hibernate-spring-data) · [4. Spring and Spring Boot internals](#4-spring-and-spring-boot-internals) · [5. Microservices patterns](#5-microservices-patterns) · [6. Resilience and caching](#6-resilience-and-caching) · [7. Docker, JVM, Kubernetes](#7-docker-jvm-kubernetes) · [8. Reading real codebases](#8-reading-real-codebases) · [10. Kafka in production](#10-kafka-in-production) · [Capstone](#capstone)

---

## 1. Build systems

Source and context: [01-Build-Systems bar-raiser file](../01-Build-Systems/05-Bar-Raiser-Drill-Downs.md)

<details><summary>1. Name the 3 Maven lifecycles and the phase that runs integration tests' cleanup.</summary>`clean`, `default`, `site`. `post-integration-test` (Failsafe's `verify` goal runs after it, so containers are stopped even when tests fail).</details>

<details><summary>2. What's the execution id of a goal run from the command line?</summary>`default-cli`.</details>

<details><summary>3. How do you disable an inherited plugin execution?</summary>Redeclare the execution with the same `<id>` and `<phase>none</phase>`.</details>

<details><summary>4. Inheritance vs aggregation in one sentence each.</summary>Inheritance (`<parent>`) merges configuration from parent to child. Aggregation (`<modules>`/`<subprojects>`) only says which projects build together in the reactor.</details>

<details><summary>5. Which wins: a `dependencyManagement` entry or nearest-wins?</summary>`dependencyManagement`. It rewrites transitive versions before conflict resolution (`version managed from 1.0`).</details>

<details><summary>6. Maven tie-break at equal depth?</summary>First declaration in POM order.</details>

<details><summary>7. Which BOM wins when two imports manage the same GA?</summary>The first import declared.</details>

<details><summary>8. `requireUpperBoundDeps` vs `dependencyConvergence`?</summary>Upper-bound fails only on downgrades. Convergence fails on any disagreement.</details>

<details><summary>9. What can `banDuplicateClasses` find that the dependency tree can't?</summary>The same FQCN in two *different* artifacts (relocated or uber jars), where correctness depends on classpath order.</details>

<details><summary>10. Gradle's three phases?</summary>Initialization (settings, included builds, project objects), configuration (scripts, task registration, task graph), execution.</details>

<details><summary>11. `tasks.register` vs `tasks.create`?</summary>`register` is lazy (configured only if the task is in the graph). `create` configures eagerly on every build.</details>

<details><summary>12. UP-TO-DATE vs FROM-CACHE?</summary>UP-TO-DATE: inputs and outputs unchanged since the last run in this workspace. FROM-CACHE: outputs restored from the local or remote build cache using the cache key.</details>

<details><summary>13. Why is `Jar` not cacheable in Gradle?</summary>Re-zipping is about as cheap as downloading the zip from the cache.</details>

<details><summary>14. What does the configuration cache skip?</summary>Initialization and configuration (scripts, plugins, task-graph calculation) when the inputs to configuration are unchanged.</details>

<details><summary>15. Why is `Task.project` forbidden at execution time with the configuration cache?</summary>Execution runs from a serialized task graph with no `Project` model.</details>

<details><summary>16. `platform()` vs `enforcedPlatform()`?</summary>Constraints that join conflict resolution vs forced versions (downgrades included).</details>

<details><summary>17. Version catalog vs platform?</summary>Aliases for writing coordinates vs resolution constraints that affect transitive dependencies.</details>

<details><summary>18. `api` vs `implementation` in `java-library`?</summary>`api` dependencies leak to consumers' compile classpath (use them for types in your public signatures). `implementation` dependencies don't, which enables compile avoidance.</details>

<details><summary>19. What did JDK 23 change for annotation processors?</summary>No implicit discovery from the classpath. Processors must be requested explicitly.</details>

<details><summary>20. Boot 4.1.2's default Buildpacks builder?</summary>`paketobuildpacks/builder-noble-java-tiny` (Ubuntu 24.04, tiny run image).</details>

<details><summary>21. Which layer does a sibling reactor module go to in Boot's `layers.idx`?</summary>`application`.</details>

<details><summary>22. Why does the AOT cache need `extract` rather than the fat jar?</summary>It needs a plain classpath of jars (same jars, same order) at training and production time. Nested jars inside a Boot fat jar aren't supported.</details>

<details><summary>23. Two Maven 3.10 changes that can break an upgrade?</summary>Stricter POM validation (duplicates now fail) and no super-POM plugin versions (unpinned plugins change).</details>

<details><summary>24. Maven 4's build POM vs consumer POM?</summary>Model 4.1.0 build POM for building. A model 4.0.0 consumer POM is deployed for consumers (optionally flattened).</details>

<details><summary>25. Spring Framework 7 and `commons-logging`?</summary>Spring 7 dropped `spring-jcl` and depends on Apache Commons Logging 1.3.x. Ban only versions below 1.3.</details>

<details><summary>26. What does a Gradle `java-platform` publish?</summary>A POM whose `<dependencyManagement>` holds the constraints (imported BOMs become `<scope>import</scope>`), plus Gradle Module Metadata.</details>

<details><summary>27. `api` and `implementation` in the published POM?</summary>`compile` and `runtime` scope.</details>

<details><summary>28. Can Maven read a Gradle version catalog?</summary>No. Publish a BOM next to the catalog for Maven consumers.</details>

<details><summary>29. Why can "used undeclared" be dangerous if the code compiles?</summary>The version comes from someone else's dependency (slf4j 2.0.17 via HikariCP in our run) and changes when they change.</details>

<details><summary>30. Classic `dependency:analyze` false positive?</summary>Aggregator artifacts (`junit-jupiter`, Boot starters): "unused declared" while their parts are "used undeclared".</details>

<details><summary>31. How do surefire and failsafe both feed JaCoCo?</summary>`jacoco:prepare-agent` sets `argLine`, used by both; keep `@{argLine}` if you customize it.</details>

<details><summary>32. What does "configuration cache cannot be reused because environment variable X has changed" mean?</summary>X was read at configuration time (eagerly); read it through `providers.environmentVariable` inside the task.</details>

<details><summary>33. What does "Loaded 24231 auto-discovered prefixes for remote repository central" mean?</summary>Maven Resolver 2's prefix filter: the repository is only asked for paths it serves.</details>

<details><summary>34. Gradle's dependency-confusion control?</summary>`dependencyResolutionManagement` with `FAIL_ON_PROJECT_REPOS` and per-repository `content { includeGroup / excludeGroup }`.</details>

---

## 2. SQL and RDBMS internals

Source and context: [02-SQL-RDBMS-Internals bar-raiser file](../02-SQL-RDBMS-Internals/08-Bar-Raiser-Drill-Downs.md)

<details><summary>1. How big is a PostgreSQL page and an InnoDB page?</summary>8 KB and 16 KB.</details>

<details><summary>2. What's a `ctid`?</summary>(block number, line pointer) — the physical address an index stores.</details>

<details><summary>3. Tuple header size?</summary>23 bytes, padded to 24, plus a 4-byte line pointer.</details>

<details><summary>4. Two conditions for a HOT update?</summary>No indexed (or INCLUDE'd) column changes, and the new version fits on the same page.</details>

<details><summary>5. What's a full-page image and when is it written?</summary>A copy of the whole page in WAL on the first modification after a checkpoint, to survive torn writes.</details>

<details><summary>6. When does TOAST kick in?</summary>When a row exceeds about 2 KB: compress first, then move values out of line in ~2 KB chunks.</details>

<details><summary>7. E-S-R?</summary>Composite index column order: Equality, then Sort, then Range.</details>

<details><summary>8. What does `Index Searches: 5` mean in PG 18?</summary>Five index descents (e.g. a skip scan over 4 leading values + 1).</details>

<details><summary>9. Why can an index-only scan read the heap?</summary>Pages not marked all-visible in the visibility map need a visibility check (`Heap Fetches`).</details>

<details><summary>10. `jsonb_ops` vs `jsonb_path_ops`?</summary>`jsonb_path_ops` is smaller (40% in our test) but supports only `@>`.</details>

<details><summary>11. What's BRIN good for?</summary>Huge, physically ordered (append-only) tables queried by range: 24 kB vs 21 MB for the B-tree.</details>

<details><summary>12. What problem does `CREATE STATISTICS` solve?</summary>Misestimates from correlated columns (independence assumption): rows=1 → 142, actual 143.</details>

<details><summary>13. Three join algorithms and when each wins?</summary>Nested loop (small outer, indexed inner), hash (large unsorted equi-joins), merge (both sides sorted).</details>

<details><summary>14. What does `Batches: 16` on a Hash node mean?</summary>The hash table didn't fit in `work_mem × hash_mem_multiplier` and spilled to disk in 16 batches.</details>

<details><summary>15. After how many executions can a prepared statement go generic?</summary>After 5 custom plans (and pgjdbc server-prepares after 5 executions).</details>

<details><summary>16. Are CTEs optimization fences in PostgreSQL 12+?</summary>No, single-reference side-effect-free CTEs are inlined unless `MATERIALIZED`.</details>

<details><summary>17. What's the default window frame with ORDER BY?</summary>`RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` — ties are peers.</details>

<details><summary>18. Why does keyset need a tiebreaker?</summary>The sort key must be unique or rows at page boundaries are skipped or duplicated.</details>

<details><summary>19. How do you tell insert from update in `ON CONFLICT … RETURNING`?</summary>`(xmax = 0)` trick, or use `MERGE … RETURNING merge_action()` (PG 17+).</details>

<details><summary>20. What's the xmin horizon?</summary>The oldest snapshot anyone (sessions, slots, standbys) might still need; VACUUM can't remove versions newer than it.</details>

<details><summary>21. Why must tuples be frozen?</summary>32-bit XIDs wrap around; frozen tuples are "older than everything" forever.</details>

<details><summary>22. InnoDB equivalent of "dead but not yet removable"?</summary>A growing history list length (undo not purged).</details>

<details><summary>23. Which anomaly does SERIALIZABLE prevent that REPEATABLE READ doesn't (PostgreSQL)?</summary>Write skew.</details>

<details><summary>24. SQLStates to retry?</summary>40001 (serialization failure) and 40P01 (deadlock).</details>

<details><summary>25. Which row lock does an FK check take?</summary>`FOR KEY SHARE` on the referenced row — blocked by `FOR UPDATE`, not by `FOR NO KEY UPDATE`.</details>

<details><summary>26. What does `SKIP LOCKED` give up?</summary>Strict FIFO across workers.</details>

<details><summary>27. How does a 50 ms ALTER cause an outage?</summary>It waits for ACCESS EXCLUSIVE and every later query queues behind it.</details>

<details><summary>28. InnoDB next-key lock?</summary>A record lock plus the gap before it.</details>

<details><summary>29. LSN fencing in one line?</summary>Read a replica only when `pg_last_wal_replay_lsn() >= commit_lsn`.</details>

<details><summary>30. Why `LazyConnectionDataSourceProxy` with routing?</summary>So the routing decision happens after the read-only flag is set.</details>

<details><summary>31. Why can't you `DETACH PARTITION … CONCURRENTLY` sometimes?</summary>A default partition exists.</details>

<details><summary>32. Little's law?</summary>L = λW: busy connections = TPS × transaction time.</details>

<details><summary>33. Seq scan cost formula?</summary>`relpages × seq_page_cost + reltuples × (cpu_tuple_cost + cpu_operator_cost × quals)`: 21,912 for the atlas `orders` scan.</details>

<details><summary>34. Parallel divisor for 2 workers?</summary>2.4 (each worker 1, leader 1 − 0.3 × 2); CPU cost is divided, I/O isn't.</details>

<details><summary>35. Why can `Heap Fetches` stay high right after VACUUM?</summary>Index cleanup was bypassed (< ~2 % of pages with dead items); pages with `LP_DEAD` stubs can't be all-visible. `VACUUM (INDEX_CLEANUP ON)`.</details>

<details><summary>36. `Heap Blocks: lossy`?</summary>The bitmap didn't fit in `work_mem`; whole pages are rechecked (`Rows Removed by Index Recheck`).</details>

<details><summary>37. Signature of a row-goal trap?</summary>`Limit` → ordered `Index Scan` with a `Filter` and a huge `Rows Removed by Filter`.</details>

<details><summary>38. What does `(customer_id)::numeric = …` in a Filter tell you?</summary>The parameter was sent as numeric; the column is cast and its index can't be used (JDBC `BigDecimal` for a `bigint`).</details>

<details><summary>39. `Trigger for constraint … time=4184`?</summary>FK enforcement per row; the referencing column has no index.</details>

<details><summary>40. Does PostgreSQL derive range predicates across a join?</summary>No, only equalities (equivalence classes). Add the redundant predicate on the big side.</details>

<details><summary>41. `SubPlan` vs `hashed SubPlan` vs `InitPlan`?</summary>Per outer row / once into a hash table / once before the parent.</details>

<details><summary>42. Default selectivities when there are no statistics?</summary>1/3 for inequalities, 0.5 % for equalities.</details>

<details><summary>43. What does a logical replication slot hold back?</summary>`catalog_xmin` (catalog bloat) and WAL; not data-table vacuum.</details>

<details><summary>44. When are SSI page locks promoted?</summary>Beyond `max_pred_locks_per_relation` (default −2 → 64/2 = 32 pages) per relation.</details>

<details><summary>45. Why doesn't a big report seq scan wipe `shared_buffers`?</summary>Tables larger than ¼ of `shared_buffers` are scanned through a small ring buffer (`BAS_BULKREAD`).</details>

<details><summary>46. Four WAL records per non-HOT update with two indexes?</summary>`Heap/LOCK`, `Heap/UPDATE`, and one `Btree/INSERT_LEAF` per index; a HOT update is one `Heap/HOT_UPDATE`.</details>

---

## 3. JPA, Hibernate, Spring Data

Source and context: [03-JPA-Hibernate-Spring-Data bar-raiser file](../03-JPA-Hibernate-Spring-Data/06-Bar-Raiser-Drill-Downs.md)

<details><summary>1. Four entity states?</summary>Transient, managed, detached, removed.</details>

<details><summary>2. What does `merge()` return?</summary>A managed copy; the argument stays detached (and it SELECTs first).</details>

<details><summary>3. When does the INSERT happen after `persist()` with a SEQUENCE id?</summary>At flush; the id is fetched at persist.</details>

<details><summary>4. Default UPDATE shape?</summary>All columns; `@DynamicUpdate` for changed columns only.</details>

<details><summary>5. Why can field access on an association return null?</summary>It's a proxy; only methods are intercepted.</details>

<details><summary>6. ActionQueue order (simplified)?</summary>Orphan actions, inserts, updates, collection actions, deletes last.</details>

<details><summary>7. Does a native query trigger auto-flush in Hibernate 7?</summary>Yes (verified: pending insert flushed before native count).</details>

<details><summary>8. Does a JdbcTemplate query trigger Hibernate auto-flush?</summary>No (verified: 0 rows until `em.flush()`).</details>

<details><summary>9. SQL shape of batch fetching on PostgreSQL?</summary>`where id = any (?)` with one array parameter.</details>

<details><summary>10. Why MultipleBagFetchException?</summary>Two unordered `List` (bag) collections can't be de-duplicated from a Cartesian product.</details>

<details><summary>11. What did Hibernate 7.4 change about JOIN FETCH + limit?</summary>Paginates parent rows in a derived table in SQL; falls back to memory for shapes like ordering by a collection column.</details>

<details><summary>12. The safety flag?</summary>`hibernate.query.fail_on_pagination_over_collection_fetch=true`.</details>

<details><summary>13. Why does IDENTITY break batching?</summary>The id is known only after the INSERT, so Hibernate inserts at persist time.</details>

<details><summary>14. `allocationSize` rule?</summary>Must equal the sequence's INCREMENT BY.</details>

<details><summary>15. Hibernate 7 pooled-lo setting?</summary>`hibernate.id.optimizer.pooled.preferred=pooled-lo`.</details>

<details><summary>16. Fastest bulk load in PostgreSQL from Java?</summary>COPY via pgjdbc CopyManager (~75× IDENTITY inserts here).</details>

<details><summary>17. pgjdbc option that rewrites batches?</summary>`reWriteBatchedInserts=true`.</details>

<details><summary>18. What does a bulk JPQL update skip?</summary>The persistence context, @Version increments, listeners, cascades.</details>

<details><summary>19. Spring Data `save()` with an assigned id?</summary>Calls `merge()` → SELECT + INSERT; implement `Persistable`.</details>

<details><summary>20. Default rollback rule?</summary>RuntimeException and Error roll back; checked exceptions commit.</details>

<details><summary>21. Cause of UnexpectedRollbackException?</summary>A joined (REQUIRED) inner failure marked the transaction rollback-only and the outer tried to commit.</details>

<details><summary>22. REQUIRES_NEW cost?</summary>A second connection per request; pool deadlock risk.</details>

<details><summary>23. What does `readOnly = true` do with Hibernate?</summary>FlushMode MANUAL, read-only entities (no snapshots), `Connection.setReadOnly`, enables replica routing.</details>

<details><summary>24. What does `@Transactional(timeout = 1)` do?</summary>Sets JDBC query timeouts; the driver cancels long SQL statements.</details>

<details><summary>25. Spring 7 core retry annotation and enabler?</summary>`@Retryable` with `@EnableResilientMethods` (also `@ConcurrencyLimit`).</details>

<details><summary>26. Where must retries live?</summary>Outside the transactional proxy; each attempt is a new transaction.</details>

<details><summary>27. Three conditions for streaming rows from PostgreSQL through Hibernate?</summary>A fetch size, a transaction (pgjdbc ignores fetch size with autocommit on), and no retention (`clear()`, StatelessSession or projections).</details>

<details><summary>28. What does a query cache entry contain?</summary>The ids of the result; entities come from the entity cache.</details>

<details><summary>29. What does a JPQL bulk update do to the L2 cache?</summary>Evicts the whole region of the updated entity and invalidates cached queries over it.</details>

<details><summary>30. And a native update without `addSynchronizedEntityClass`?</summary>Evicts every region of the second-level cache.</details>

<details><summary>31. Caffeine JCache's default size bound?</summary>None: `maximum.size = null`, expiry `eternal`.</details>

<details><summary>32. SQL shape of Hibernate 7 batch fetching on PostgreSQL?</summary>`where id = any (?)` with one array parameter.</details>

<details><summary>33. What does `in_clause_parameter_padding` do?</summary>Rounds IN-list placeholders up to a power of two (3 → 4, 5 → 8, 9 → 16).</details>

<details><summary>34. How does PostgreSQL 18's `pg_stat_statements` record IN lists of different lengths?</summary>As one entry: `in ($1 /*, ... */)`, for both parameters and literals.</details>

<details><summary>35. What's wrong with `@Fetch(SUBSELECT)` on a paginated query?</summary>The subselect re-runs the parent `WHERE` without the limit: children of every matching parent are loaded.</details>

<details><summary>36. Which queries trigger an AUTO flush?</summary>JPQL whose query spaces overlap pending changes, and every native query (unless synchronized spaces are declared).</details>

<details><summary>37. What does `@TenantId` not filter?</summary>Native SQL (and anything outside Hibernate).</details>

<details><summary>38. SQLSTATE for a write in a read-only transaction?</summary>25006 (enforced by pgjdbc only inside transactions with the default `readOnlyMode=transaction`).</details>

<details><summary>39. What does `StatelessSession.upsert()` generate on PostgreSQL?</summary>`INSERT … ON CONFLICT (id) DO UPDATE SET …`.</details>

---

## 4. Spring and Spring Boot internals

Source and context: [04-Spring-Boot-Internals bar-raiser file](../04-Spring-Boot-Internals/06-Bar-Raiser-Drill-Downs.md)

<details><summary>1. BDRPP vs BFPP vs BPP?</summary>Add definitions / edit definitions / wrap or modify instances.</details>

<details><summary>2. Order of init callbacks?</summary>`@PostConstruct` → `afterPropertiesSet` → `initMethod`.</details>

<details><summary>3. When are AOP proxies created?</summary>`postProcessAfterInitialization` (after init callbacks).</details>

<details><summary>4. Safe point to use other beans at startup?</summary>`SmartInitializingSingleton` or `ApplicationReadyEvent`.</details>

<details><summary>5. Why must post-processor `@Bean` methods be static?</summary>So the configuration class isn't instantiated early (missing processing).</details>

<details><summary>6. `proxyBeanMethods = false` consequence?</summary>Calling another `@Bean` method creates a new, unmanaged instance.</details>

<details><summary>7. Prototype in singleton?</summary>Created once; use `ObjectProvider`, `@Lookup` or a scoped proxy.</details>

<details><summary>8. How does auto-configuration back off?</summary>`@ConditionalOnMissingBean` (+ deferred import after user config).</details>

<details><summary>9. Where are auto-config candidates listed?</summary>`META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`.</details>

<details><summary>10. Three singleton caches?</summary>`singletonObjects`, `earlySingletonObjects`, `singletonFactories`.</details>

<details><summary>11. Can constructor cycles be resolved?</summary>No.</details>

<details><summary>12. Spring AOT vs JDK AOT cache?</summary>Build-time bean-definition code vs pre-loaded/linked classes from a training run (they compose).</details>

<details><summary>13. JDK vs CGLIB proxy?</summary>Implements interfaces vs subclasses the class.</details>

<details><summary>14. Which `@Order` value is outermost?</summary>The lowest.</details>

<details><summary>15. Default order of the transaction advisor?</summary>Lowest precedence (innermost).</details>

<details><summary>16. Spring 7 `@Retryable` vs `@Transactional` on one method?</summary>Retry outermost (verified): each attempt is a new transaction.</details>

<details><summary>17. What happens to a final method on a CGLIB proxy?</summary>Not intercepted; Spring logs a WARN; runs on the proxy instance.</details>

<details><summary>18. Default Tomcat max threads?</summary>200.</details>

<details><summary>19. Property to enable virtual threads in Boot?</summary>`spring.threads.virtual.enabled=true`.</details>

<details><summary>20. Which JDK removed `synchronized` pinning?</summary>JDK 24 (JEP 491).</details>

<details><summary>21. Never do this in WebFlux?</summary>Block an event-loop thread.</details>

<details><summary>22. The servlet-to-Spring bridge filter?</summary>`DelegatingFilterProxy` → `FilterChainProxy`.</details>

<details><summary>23. Which filter authenticates bearer tokens?</summary>`BearerTokenAuthenticationFilter`.</details>

<details><summary>24. New filter in Spring Security 7's resource server chain?</summary>`OAuth2ProtectedResourceMetadataFilter` (RFC 9728).</details>

<details><summary>25. 401 vs 403 for JWTs?</summary>401 missing/invalid token; 403 valid token without the required scope (`insufficient_scope`).</details>

<details><summary>26. Why place a rate-limit filter after bearer authentication?</summary>To key on the user instead of the IP.</details>

<details><summary>27. Why does `@ConditionalOnBean` fail in an application `@Configuration`?</summary>User configuration is registered before the deferred auto-configurations, so auto-configured beans don't exist yet.</details>

<details><summary>28. How are auto-configurations ordered?</summary>Alphabetically by name, then `@AutoConfigureOrder`, then `before`/`after` constraints.</details>

<details><summary>29. Why `afterName` strings instead of `after` classes?</summary>No compile dependency on the module that contains them (Boot 4's per-technology modules).</details>

<details><summary>30. What does `spring-autoconfigure-metadata.properties` enable?</summary>Filtering auto-configuration candidates (e.g. `ConditionalOnClass`) without loading their classes.</details>

<details><summary>31. Since JDK 23, when do annotation processors on the class path run?</summary>Only with `-proc:full` or an explicit processor path; otherwise silently not at all.</details>

<details><summary>32. What does Spring AOT do to `@Profile` and `@ConditionalOnProperty`?</summary>Evaluates them at build time; the runtime environment can't change the bean graph.</details>

<details><summary>33. For `@ResponseBody`, when does `postHandle` run?</summary>After the body is written: headers set there are ignored.</details>

<details><summary>34. What `ex` does `afterCompletion` get when an `@ExceptionHandler` resolved the exception?</summary>`null`.</details>

<details><summary>35. Why can a servlet filter record 200 for a request that returned 500?</summary>The unhandled exception leaves the chain before Tomcat's ERROR dispatch to `/error` writes the 500.</details>

<details><summary>36. What happens to a `@TransactionalEventListener` when there's no transaction?</summary>It is skipped silently unless `fallbackExecution = true`.</details>

<details><summary>37. Which `@Transactional` propagation is allowed on a `@TransactionalEventListener` (Spring 6.1+)?</summary>`REQUIRES_NEW` or `NOT_SUPPORTED`.</details>

<details><summary>38. What happens to Boot's `applicationTaskExecutor` when you define an `Executor` bean?</summary>It backs off (mode `auto`); `spring.task.execution.mode=force` keeps it.</details>

<details><summary>39. Phase of `webServerGracefulShutdown` and its per-phase timeout?</summary>`Integer.MAX_VALUE - 1024`; `spring.lifecycle.timeout-per-shutdown-phase` (30 s).</details>

<details><summary>40. Lifecycle stop order?</summary>Highest phase first; `@PreDestroy`/destroy callbacks after all lifecycles stopped.</details>

<details><summary>41. Do security filter-chain denials reach `@ControllerAdvice`?</summary>No: entry points and access-denied handlers write them; only method-security denials (inside the dispatcher) do.</details>

<details><summary>42. Lowest-precedence property source?</summary>Default properties (`SpringApplicationBuilder.properties`, `setDefaultProperties`).</details>

---

## 5. Microservices patterns

Source and context: [05-Microservices-Patterns bar-raiser file](../05-Microservices-Patterns/08-Bar-Raiser-Drill-Downs.md)

<details><summary>1. What does a service boundary also define?</summary>A consistency (transaction) boundary.</details>

<details><summary>2. Spring Modulith module = ?</summary>A direct sub-package of the application's main package; its top-level package is its API.</details>

<details><summary>3. What does `@ApplicationModuleListener` combine?</summary>`@Async` + `@TransactionalEventListener` (after commit) + `@Transactional(REQUIRES_NEW)`.</details>

<details><summary>4. Strangler fig steps?</summary>Facade, pick a seam, build new, sync data, shift traffic gradually, delete old.</details>

<details><summary>5. Why avoid 2PC across services?</summary>Locks across the network, in-doubt transactions, availability = product of participants, many systems don't support XA.</details>

<details><summary>6. Saga step types?</summary>Compensatable, pivot, retriable.</details>

<details><summary>7. Compensation order?</summary>Reverse order of completed steps.</details>

<details><summary>8. Semantic lock?</summary>An application-level "in progress" state (e.g. `PENDING`) visible to other transactions.</details>

<details><summary>9. Outbox delivery guarantee?</summary>At-least-once; exactly-once effects need idempotent consumers.</details>

<details><summary>10. Relay order of operations?</summary>Send, wait for the ack, then mark published.</details>

<details><summary>11. How do multiple relays avoid double sends?</summary>`FOR UPDATE SKIP LOCKED`.</details>

<details><summary>12. What doesn't `SKIP LOCKED` preserve?</summary>Per-aggregate ordering across relays.</details>

<details><summary>13. CDC operational risk?</summary>Replication slots retain WAL (and hold back catalog_xmin) while the consumer is down.</details>

<details><summary>14. Insert-then-delete outbox trick?</summary>CDC still sees the INSERT in the WAL; the table stays empty.</details>

<details><summary>15. Event store optimistic lock?</summary>Unique `(stream_id, version)`.</details>

<details><summary>16. Why can sequence-based projectors miss events?</summary>Positions are assigned at insert, visible at commit; out-of-order commits get skipped.</details>

<details><summary>17. Read models are…?</summary>Disposable: rebuild by replay.</details>

<details><summary>18. Aggregator rules?</summary>Parallel calls, per-call timeouts within a deadline, fallbacks for optional data.</details>

<details><summary>19. BFF owner?</summary>The team owning that client experience.</details>

<details><summary>20. Sidecar vs ambient?</summary>Proxy per pod vs per-node L4 agent + optional L7 waypoints.</details>

<details><summary>21. W3C traceparent fields?</summary>version-traceid-parentid-flags.</details>

<details><summary>22. Head vs tail sampling?</summary>Decision at trace start vs after completion (keeps errors/slow traces).</details>

<details><summary>23. What does a consumer-driven contract capture?</summary>Only what the consumer uses, with matchers.</details>

<details><summary>24. Pact gate before deploy?</summary>`can-i-deploy` against the Pact Broker.</details>

<details><summary>25. What is a late pivot reply, and the only correct response?</summary>A success for the irreversible step after the saga gave up on it; a forward action (refund).</details>

<details><summary>26. Why must an orchestrator's state machine be total?</summary>Duplicates and late replies are guaranteed; unhandled pairs become poison messages.</details>

<details><summary>27. What does a tombstone in a compensation protect against?</summary>A release that runs before its reservation being undone by the late reservation.</details>

<details><summary>28. Reply handler vs timeout sweeper: how do they avoid double transitions?</summary>The handler takes `FOR UPDATE`, the sweeper `FOR UPDATE SKIP LOCKED`; the first to lock wins.</details>

<details><summary>29. Why must the inbox row share the effect's transaction?</summary>A crash otherwise records "seen" without the effect (lost forever) or vice versa.</details>

<details><summary>30. How do you prevent overselling without distributed locks?</summary>An atomic conditional update (`where available >= qty`) plus a check constraint.</details>

<details><summary>31. Which exceptions should skip retries and go to the DLT?</summary>Non-transient ones (unknown saga, malformed message); classify them explicitly.</details>

<details><summary>32. Why avoid non-blocking retry topics for saga replies?</summary>They break per-key ordering.</details>

<details><summary>33. What makes a Kafka-fed projection idempotent and order-safe?</summary>A per-aggregate version and `where v.version < excluded.version`.</details>

<details><summary>34. How does a client read its own write from a CQRS view?</summary>The command returns the version; the client waits for it (or reads the write model briefly).</details>

<details><summary>35. What header did Modulith's Kafka externalization add, and why does it matter?</summary>`__TypeId__` with the producer's class name; other codebases can't load it.</details>

<details><summary>36. What does `republish-outstanding-events-on-restart` risk in a cluster?</summary>Every starting instance re-drives the same publications concurrently.</details>

<details><summary>37. Idempotency key arbitration?</summary>`insert … on conflict do nothing` in the effect's transaction; concurrent twins block, then replay the stored response.</details>

<details><summary>38. Jackson trap for money in JSON?</summary>Decimals parse as `double` (`25.00` → `25.0`) without `USE_BIG_DECIMAL_FOR_FLOATS`.</details>

---

## 6. Resilience and caching

Source and context: [06-Resilience-Caching bar-raiser file](../06-Resilience-Caching/05-Bar-Raiser-Drill-Downs.md)

<details><summary>1. What replaced `RingBitBuffer` in Resilience4j?</summary>The `Metrics` sliding windows in `resilience4j-core` (count- and time-based), since 1.0.</details>

<details><summary>2. Default sliding-window lock strategy in 2.4.0?</summary>`SYNCHRONIZED` (ReentrantLock). `LOCK_FREE` is opt-in.</details>

<details><summary>3. Default `minimumNumberOfCalls` and `slowCallDurationThreshold`?</summary>100 calls and 60 s.</details>

<details><summary>4. Why did OPEN→HALF_OPEN happen at 617 ms with a 500 ms wait?</summary>The transition is lazy: it happens on the first call after the wait, unless automatic transition is enabled.</details>

<details><summary>5. `maxWaitDurationInHalfOpenState` default?</summary>0, which means wait indefinitely.</details>

<details><summary>6. Resilience4j Spring aspect order, outer to inner?</summary>Retry → CircuitBreaker → RateLimiter → TimeLimiter → Bulkhead.</details>

<details><summary>7. `AtomicRateLimiter` algorithm?</summary>Fixed cycles with permit reservation; can admit 2× the limit across a boundary.</details>

<details><summary>8. Spring 7 `@Retryable` defaults?</summary>`maxRetries` 3, `delay` 1000 ms, `multiplier` 1.0, `jitter` 0.</details>

<details><summary>9. Bulkhead for virtual threads?</summary>A semaphore (`SemaphoreBulkhead`, `@ConcurrencyLimit`), sized by Little's law and ≤ the connection pool.</details>

<details><summary>10. W-TinyLFU admission rule in Caffeine 3.3.1?</summary>Admit if freq(candidate) > freq(victim); if freq(candidate) ≥ 6, admit with probability 1/128; else reject.</details>

<details><summary>11. Caffeine window and protected share?</summary>Window ~1 % (`PERCENT_MAIN = 0.99`), protected 80 % of main.</details>

<details><summary>12. `refreshAfterWrite` vs `expireAfterWrite`?</summary>Refresh serves stale and reloads asynchronously; expire blocks the reader on reload.</details>

<details><summary>13. Stampede defenses?</summary>Coalescing, distributed lease, stale-while-revalidate, XFetch.</details>

<details><summary>14. Bloom filter size for 1M items at 1 %?</summary>≈9.59M bits (1.1 MB), 7 hashes.</details>

<details><summary>15. Avalanche defenses?</summary>TTL jitter, L1 shield, fast-failing Redis client, miss bulkhead, HA/persistence, staggered rollouts.</details>

<details><summary>16. Fix for the cache-aside stale-fill race?</summary>Leases (delete revokes the lease), versioned fills, or CDC invalidation.</details>

<details><summary>17. Pub/Sub delivery guarantee?</summary>At-most-once; keep L1 TTLs short.</details>

<details><summary>18. Lease lock vs correctness?</summary>A lease prevents duplicate work, not concurrent writes; correctness needs fencing tokens or DB constraints.</details>

<details><summary>19. Retries ×3 with backoff + jitter on an overloaded dependency: measured load?</summary>2.72×, queue 284 → 1,024, and fewer successes than without retries (167 vs 184).</details>

<details><summary>20. What made retries safe in the chaos lab?</summary>A 10 % retry budget that never retries breaker or bulkhead rejections: load stayed at 0.07×–0.09×.</details>

<details><summary>21. What does a circuit breaker mainly protect?</summary>The dependency: load fell to 0.13× / 0.09× and its queue to 22 (vs 284). Latency was already bounded by the timeout.</details>

<details><summary>22. Where should `slowCallDurationThreshold` sit?</summary>Below the client timeout (250 ms vs 300 ms), so slowness counts before calls time out. The default is 60 s.</details>

<details><summary>23. What did breaker recovery cost in the lab?</summary>57 of 400 recovery-phase requests failed during OPEN (1 s) → HALF_OPEN (5 trial calls) → CLOSED.</details>

<details><summary>24. Per-pod bulkhead of 10, HPA max 40, dependency of 20 workers?</summary>400 concurrent calls: per-pod limits multiply with replicas. Size from max replicas or use adaptive limits.</details>

<details><summary>25. What did a Sentinel failover lose?</summary>38 acknowledged writes (asynchronous replication); `WAIT` lost 0 of the writes it confirmed.</details>

<details><summary>26. How long did Sentinel failover take?</summary>1.75 s in one run, 17.5 s in another (a retried failover plus client back-off).</details>

<details><summary>27. Lettuce's default command timeout?</summary>60 s. Set ~200 ms for a cache.</details>

<details><summary>28. `@Cacheable` on Redis, Redis stalls, no `CacheErrorHandler`?</summary>The request fails (`QueryTimeoutException`). With a handler it degrades to a miss.</details>

<details><summary>29. Spring Data Redis 4 cache writes are…?</summary>Asynchronous by default: 21–59 of 200 immediate re-reads missed. Use immediate writes for read-your-writes.</details>

<details><summary>30. `volatile-lru` with keys that have no TTL?</summary>Behaves like `noeviction`: 14,760 failed `SET`s in the lab.</details>

<details><summary>31. Best eviction policy on a Zipf workload?</summary>`allkeys-lfu` 83.1 % vs `allkeys-lru` 81.3 % vs `allkeys-random` 78.2 %.</details>

<details><summary>32. Memory for a 40-byte value?</summary>110 bytes as its own key, 44 bytes inside a listpack hash.</details>

---

## 7. Docker, JVM, Kubernetes

Source and context: [07-Docker-JVM-Kubernetes bar-raiser file](../07-Docker-JVM-Kubernetes/06-Bar-Raiser-Drill-Downs.md)

<details><summary>1. Exit code 137 with OOMKilled means?</summary>The kernel's cgroup OOM killer sent SIGKILL: total process memory exceeded `memory.max`.</details>

<details><summary>2. Default MaxRAMPercentage?</summary>25 %.</details>

<details><summary>3. Default GC with 1 CPU?</summary>SerialGC.</details>

<details><summary>4. Does the JVM use CPU requests for availableProcessors?</summary>Not since JDK 19; only the limit (quota) and cpuset.</details>

<details><summary>5. ParallelGCThreads formula above 8 CPUs?</summary>8 + (n − 8) × 5/8.</details>

<details><summary>6. Biggest non-heap items in a small Boot app?</summary>GC structures, Metaspace, code cache, CDS archive.</details>

<details><summary>7. MaxDirectMemorySize default?</summary>The max heap size.</details>

<details><summary>8. What does `ExitOnOutOfMemoryError` give you?</summary>The JVM exits (code 3) on OOME instead of limping on, so Kubernetes restarts it.</details>

<details><summary>9. CFS period and what a limit of 2 means?</summary>100 ms; 200 ms of CPU time per period across all threads.</details>

<details><summary>10. Throttling metric?</summary>`container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total` (or `nr_throttled` in cpu.stat).</details>

<details><summary>11. Why shell-form ENTRYPOINT breaks shutdown?</summary>`sh` is PID 1 and doesn't forward SIGTERM to Java.</details>

<details><summary>12. Distroless Java 25 user and entrypoint?</summary>uid 65532; `/usr/bin/java -jar`.</details>

<details><summary>13. Where to train the AOT cache?</summary>In the runtime image, with production GC flags.</details>

<details><summary>14. What happens if the AOT cache doesn't match?</summary>Default: a warning and the app runs without it. `-XX:AOTMode=on`: the JVM fails to start.</details>

<details><summary>15. Boot 4.1.2 shutdown defaults?</summary>`server.shutdown=GRACEFUL`, 30 s per shutdown phase.</details>

<details><summary>16. When does Boot set readiness to ACCEPTING_TRAFFIC?</summary>After `ApplicationRunner`s/`CommandLineRunner`s complete.</details>

<details><summary>17. `/livez` and `/readyz` on the main port?</summary>`management.endpoint.health.probes.add-additional-paths=true`.</details>

<details><summary>18. Why preStop sleep?</summary>Endpoint removal and SIGTERM happen in parallel; the sleep covers LB propagation.</details>

<details><summary>19. Grace period counts from?</summary>Pod deletion, including preStop time.</details>

<details><summary>20. HPA defaults: tolerance, downscale window, CPU init period?</summary>0.1, 5 min, 5 min.</details>

<details><summary>21. HPA CPU utilization is relative to?</summary>Requests.</details>

<details><summary>22. KEDA Kafka `lagThreshold` default and `allowIdleConsumers` default?</summary>10 and false.</details>

<details><summary>23. Boot 4 AOP starter and web starter names?</summary>`spring-boot-starter-aspectj`; `spring-boot-starter-webmvc` (`-web` is deprecated).</details>

<details><summary>24. Removed Redis property in Boot 4.1?</summary>`spring.data.redis.lettuce.cluster.refresh.adaptive`: adaptive triggers are always on.</details>

<details><summary>25. What does jdeps miss?</summary>Service providers: `jdk.localedata` (de/ja dates printed in English) and `jdk.charsets` (IBM037), silently.</details>

<details><summary>26. Why keep `java.desktop` in a server runtime?</summary>Spring uses `java.beans`; without it: `NoClassDefFoundError: java/beans/PropertyEditorSupport`.</details>

<details><summary>27. Paketo's default jlink?</summary>`java.*` only: CPU metrics 404, `-XX:StartFlightRecording` fails at boot. Pass `--add-modules`.</details>

<details><summary>28. Does `InitialRAMPercentage` keep the heap committed?</summary>No: G1 uncommitted 674 MB at the first Remark, 0.85 s into startup.</details>

<details><summary>29. What makes a pinned heap resident?</summary>`-XX:+AlwaysPreTouch`: working set 874 MB vs 267 MB without it.</details>

<details><summary>30. Idle non-heap of the order-service (NMT)?</summary>159 MB: GC 51, Metaspace 33, compiler 24, code cache 17, CDS/AOT 14, symbols 8, class space 6, NMT 3, threads 2.</details>

<details><summary>31. `JAVA_TOOL_OPTIONS` vs `JDK_JAVA_OPTIONS`?</summary>The first reaches every JVM, `jcmd` included (`-Xmx1m` killed it); the second only the `java` launcher.</details>

<details><summary>32. `minAvailable: 75%` at 2 replicas allows how many evictions?</summary>0: percentages round up. `maxUnavailable: 25%` allows 1.</details>

<details><summary>33. Does quota count terminating pods?</summary>Yes, until they reach a terminal phase. The Deployment controller doesn't wait for them: budget one extra wave.</details>

<details><summary>34. Exit code of plain Spring Boot when Flyway fails at startup?</summary>1, for every cause. Exit-code mappers aren't consulted when the context never became active.</details>

<details><summary>35. `podFailurePolicy` for a migration Job?</summary>`FailJob` on the permanent exit code, `Ignore` on `DisruptionTarget`, count the rest; requires `restartPolicy: Never`.</details>

<details><summary>36. Two Flyway runs at once on PostgreSQL?</summary>Safe: the second waited ~5 s for the lock, then found the schema up to date.</details>

<details><summary>37. Why did a canary alert lose its `job` label?</summary>`a > on (namespace) b` keeps only the `on` labels; `group_left` keeps the left side's.</details>

<details><summary>38. What only the API server catches?</summary>Cross-field rules, e.g. `podFailurePolicy` with `restartPolicy: OnFailure`, an invalid CronJob `timeZone`: run `--dry-run=server`.</details>

---

## 8. Reading real codebases

Source and context: [08-GitHub-Codebases-Study-Guide bar-raiser file](../08-GitHub-Codebases-Study-Guide/05-Code-Reading-Plan-and-Bar-Raiser-Drill-Downs.md)

<details><summary>1. Does `jbubernik/modular-monolith-with-ddd` exist?</summary>No (GitHub API 404). The reference is `kgrzybek/modular-monolith-with-ddd`, in C#.</details>

<details><summary>2. Spring Modulith's outbox mechanism?</summary>The event publication registry (`PersistentApplicationEventMulticaster` + `EventPublicationRegistry`), written in the publisher's transaction.</details>

<details><summary>3. `@ApplicationModuleListener` is?</summary>`@Async` + `@TransactionalEventListener` + `@Transactional(REQUIRES_NEW)`.</details>

<details><summary>4. ddd-by-examples `placeOnHold` returns?</summary>`Either<BookHoldFailed, BookPlacedOnHoldEvents>`.</details>

<details><summary>5. Petclinic microservices versions?</summary>Boot 4.0.1, Spring Cloud 2025.1.0, Java 17.</details>

<details><summary>6. Larsson Fourth Edition Spring Boot version?</summary>3.5.x (README: upgraded from 3.5.0 to 3.5.16).</details>

<details><summary>7. FTGO CreateOrderSaga pivot?</summary>Authorizing the card (`accountingService.authorize`).</details>

<details><summary>8. Eventuate semantic-lock tables?</summary>`saga_lock_table` and `saga_stash_table`.</details>

<details><summary>9. Eventuate dedup table?</summary>`received_messages` (`consumer_id`, `message_id`).</details>

<details><summary>10. Debezium's outbox router now lives in?</summary>The `debezium-connect-plugins` module (`io.debezium.transforms.outbox.EventRouter`).</details>

<details><summary>11. HikariCP borrow tiers?</summary>Thread-local list → shared CAS scan → fair hand-off queue.</details>

<details><summary>12. HikariCP entry states?</summary>NOT_IN_USE 0, IN_USE 1, REMOVED −1, RESERVED −2.</details>

<details><summary>13. HikariCP validation bypass window?</summary>500 ms (`com.zaxxer.hikari.aliveBypassWindowMs`).</details>

<details><summary>14. HikariCP maxLifetime jitter?</summary>Up to 25 % subtracted (keepalive up to 20 %).</details>

<details><summary>15. Why FastList scans from the end?</summary>Statements are usually closed in reverse order of creation.</details>

<details><summary>16. Resilience4j breaker state storage?</summary>An `AtomicReference<CircuitBreakerState>` swapped with `getAndUpdate`.</details>

<details><summary>17. Caffeine sketch memory?</summary>One `long` (16 × 4-bit counters) per entry, rounded up to a power of two.</details>

<details><summary>18. Caffeine sketch aging?</summary>Every 10 × max-size samples, halve all counters (shift + mask).</details>

<details><summary>19. Caffeine counters per key and locality?</summary>Depth 4, all within one 64-byte block.</details>

<details><summary>20. Where does Kafka keep per-producer sequence state on the broker?</summary>`ProducerStateManager` (storage module).</details>

---

## 10. Kafka in production

Source and context: [10-Kafka-Production bar-raiser file](../10-Kafka-Production/05-Bar-Raiser-Drill-Downs.md)

<details><summary>1. Kafka 4.x producer defaults for acks, idempotence, linger?</summary>`all`, `true`, 5 ms.</details>

<details><summary>2. Why `max.in.flight ≤ 5` with idempotence?</summary>The broker tracks the last 5 batch sequences per producer and partition.</details>

<details><summary>3. What does `read_committed` stop at?</summary>The last stable offset (start of the oldest open transaction).</details>

<details><summary>4. Consumer default `auto.offset.reset`?</summary>`latest`: new groups skip existing data.</details>

<details><summary>5. Eager vs cooperative vs KIP-848?</summary>Eager revokes all; cooperative revokes only moving partitions (two rounds); KIP-848 is broker-side, incremental, with no group barrier.</details>

<details><summary>6. `DefaultErrorHandler` default?</summary>`FixedBackOff(0, 9)`: 10 attempts, no delay, then log and skip.</details>

<details><summary>7. Spring Kafka 4 DLT suffix?</summary>`-dlt` (older versions used `.DLT`).</details>

<details><summary>8. Blocking vs non-blocking retries?</summary>Blocking keeps order but stalls the partition; non-blocking keeps throughput but breaks per-key order.</details>

<details><summary>9. Max useful consumers in a group?</summary>The partition count.</details>

<details><summary>10. Static member, plain `close()`: how long until its partitions move?</summary>The session timeout: 45.1 s classic, 45.3 s KIP-848, 48 s cooperative. No LeaveGroup is sent.</details>

<details><summary>11. Static id = Deployment pod name, eager assignor, one pod replaced?</summary>45 s to recover, and the survivor owned nothing for 41.4 s: the whole group stopped.</details>

<details><summary>12. KIP-848 dynamic member leaves: handoff?</summary>0.5 s (classic: ~3 s, one heartbeat).</details>

<details><summary>13. How does spring-kafka 4.1.2 close consumers and name static members?</summary>Plain `close()`; `group.instance.id` + `-0…-N` per concurrent consumer.</details>

<details><summary>14. Which client settings does KIP-848 reject?</summary>`session.timeout.ms`, `heartbeat.interval.ms`, `partition.assignment.strategy` ("cannot be set when group.protocol=CONSUMER").</details>

<details><summary>15. KIP-848 session timeout default and minimum?</summary>Broker-side `group.consumer.session.timeout.ms`: 45 s default, 45 s minimum; heartbeat 5 s.</details>

<details><summary>16. KEDA's partition cap counts…?</summary>Pods, not consumers: concurrency 3 × 12 replicas = 36 consumers for 12 partitions.</details>

<details><summary>17. `ensureEvenDistributionOfPartitions` on 12 partitions?</summary>Replicas step through factors: 1, 2, 3, 4, 6, 12. Can't be combined with `limitToPartitionsWithLag`.</details>

<details><summary>18. KEDA `cooldownPeriod` applies to…?</summary>Scaling to zero only; 1 ↔ N is the HPA `behavior`.</details>

<details><summary>19. RF 3, min ISR 2, two brokers down?</summary>`acks=all` refused (`NotEnoughReplicas`, retriable → `TimeoutException` after 120 s); `acks=1` accepted with one copy.</details>

<details><summary>20. `KafkaAdmin` partition increase, config change, partition decrease?</summary>Applied asynchronously; ignored unless `setModifyTopicConfigs(true)`; silently ignored.</details>

<details><summary>21. Does a Kafka consumer pod need a preStop sleep?</summary>No: no Service traffic. Grace = in-flight work + 10 s container stop + leave + margin.</details>

---

## Capstone

Source and context: [9.1](01-Reference-Architecture-End-to-End-Order-Platform.md), [9.2](02-Comparison-Matrices-Master-Sheet.md), [9.3](03-Mock-Interview-Loops-L5-vs-L6.md)

<details><summary>1. What four correctness properties anchor the order-platform design?</summary>No lost orders, no double charge, no oversell (or a bounded, explicit amount), and a freshness budget per data type.</details>

<details><summary>2. What does `202 Accepted` + order id buy in checkout?</summary>The submission depends on one database only; inventory and payment outages don't fail it.</details>

<details><summary>3. Where does the idempotency key live?</summary>In the same transaction as the order (and the outbox row), so a retried request returns the stored response.</details>

<details><summary>4. What's the pivot step in an order saga?</summary>Payment authorization: after it succeeds, the saga only moves forward (retriable steps).</details>

<details><summary>5. A payment call timed out. Retry?</summary>Not blindly: query the PSP by idempotency key first; retry only with the same key; reconcile nightly.</details>

<details><summary>6. One-statement inventory reservation?</summary>`UPDATE stock SET reserved = reserved + :q WHERE … AND on_hand - reserved >= :q` (0 rows = insufficient).</details>

<details><summary>7. Three ways to relieve a flash-sale hot row?</summary>Bucketed stock rows, token pre-allocation claimed with `SKIP LOCKED`, a single-writer partition.</details>

<details><summary>8. Why fix partition counts up front?</summary>Adding partitions remaps keys and breaks per-key ordering.</details>

<details><summary>9. Where is the real scale in a retail order platform?</summary>Catalog reads (cache hit rate is capacity) and hot-SKU contention, not order writes.</details>

<details><summary>10. Checkout price source?</summary>The pricing source of truth, versioned on the order, never a cache.</details>

<details><summary>11. 99.95 % monthly availability is how much downtime?</summary>About 22 minutes per 30 days.</details>

<details><summary>12. Standard burn-rate alert pair?</summary>Fast: 2 % of the budget in 1 h. Slow: 5 % in 6 h.</details>

<details><summary>13. B+Tree vs LSM in one line each?</summary>B+Tree: update in place, cheap predictable reads. LSM: append + compact, cheap writes, more read/space work.</details>

<details><summary>14. What's the RUM conjecture?</summary>You can optimize two of read, update and memory overhead, not all three.</details>

<details><summary>15. Optimistic vs pessimistic: decide by?</summary>Conflict likelihood and whether the lock must span user think time; prefer a single atomic update when possible.</details>

<details><summary>16. G1 vs ZGC in a 2-CPU pod: the trap?</summary>ZGC's pauses are tiny but concurrent work needs CPU and heap headroom; measured stalls can still be tens of ms.</details>

<details><summary>17. Choreography vs orchestration: the deciding question?</summary>Where the control flow lives and who can answer "where is order 42?".</details>

<details><summary>18. Maven vs Gradle: the deciding question?</summary>A fixed lifecycle for uniformity vs a programmable task graph for fine-grained incrementality.</details>

<details><summary>19. Name five things samples usually leave out.</summary>Outbox, idempotent consumers, contract tests, shutdown behavior, container sizing.</details>

<details><summary>20. Staff-level answer shape?</summary>What I'd build first, what I'd defer, what would change my mind, and how we'd know we were wrong.</details>


**Next:** [9.5 Production-readiness checklists →](05-Production-Readiness-Checklists.md)

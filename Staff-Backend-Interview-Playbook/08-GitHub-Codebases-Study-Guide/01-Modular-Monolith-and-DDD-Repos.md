# 8.1 Codebases to Study: Modular Monolith and DDD

> **Verified 2026-10-25** through the GitHub API (existence, language, default branch, last push) and the repositories' file trees. Every path below was checked to exist. Code excerpts are quoted from the default branch on that date.
>
> **Pairs with:** [5.1 decomposition and modular monoliths](../05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md), [5.5 CQRS/ES](../05-Microservices-Patterns/05-CQRS-and-Event-Sourcing.md).

---

## 0. Why read real codebases at all 🔥

Interviewers at L5/L6 don't ask "what is an aggregate?" They ask "**where did you see it done well, and what would you change?**" Reading a codebase gives you three things a blog post can't:

1. **Concrete vocabulary**: "Spring Modulith's `ApplicationModules.verify()`", "the library repo's `PlacingOnHoldPolicy`", "kgrzybek's `CheckRule`" are specific and checkable. That's the evidence a bar-raiser looks for.
2. **The unglamorous parts**: outbox processors, inbox deduplication, architecture tests, module wiring. That's where real systems spend most of their code.
3. **Something to critique.** Every sample makes trade-offs. Saying what you'd do differently in production is the L6 signal.

---

## 1. Correcting the brief: there is no `jbubernik/modular-monolith-with-ddd` ⚠️

`https://api.github.com/repos/jbubernik/modular-monolith-with-ddd` returns **404**. The well-known repository is **[kgrzybek/modular-monolith-with-ddd](https://github.com/kgrzybek/modular-monolith-with-ddd)** (≈14k stars), and it's written in **C# / .NET**, not Java. It's still one of the best modular-monolith references in any language. Read it for the design, then use **Spring Modulith** and **ddd-by-examples/library** for the Java/Spring idioms.

| Repository | Language | Default branch | Stars | Last push | What it's best for |
|---|---|---|---|---|---|
| [spring-projects/spring-modulith](https://github.com/spring-projects/spring-modulith) | Java | `main` | 1,202 | 2026-10-23 | Enforced module boundaries, an event publication registry (outbox in a monolith), module tests, documentation |
| [kgrzybek/modular-monolith-with-ddd](https://github.com/kgrzybek/modular-monolith-with-ddd) | C# | `master` | 14,092 | 2024-06-04 | A full system: 5 modules, outbox/inbox, internal commands, business rules, architecture tests, one event-sourced module |
| [ddd-by-examples/library](https://github.com/ddd-by-examples/library) | Java | `master` | 5,883 | 2026-09-17 | Tactical DDD in Java: aggregates as policies + events, functional error handling, ArchUnit boundaries, event storming docs |

---

## 2. spring-projects/spring-modulith ⚡

### 2.1 What it is

A library that turns *packages* into *verifiable modules*: each top-level package under the application package is a module; only its root package (and explicitly `@NamedInterface`-annotated packages) is public; cycles and access to `internal` packages fail a test. Modules talk through Spring application events, which can be **persisted** (the event publication registry) and **externalized** to Kafka/AMQP.

### 2.2 Files to read, in order

| Path | What to look for |
|---|---|
| `spring-modulith-core/src/main/java/org/springframework/modulith/core/ApplicationModules.java` | How modules are detected from packages (ArchUnit underneath), `verify()` and the cycle/encapsulation checks |
| `spring-modulith-core/src/main/java/org/springframework/modulith/core/ApplicationModule.java` | A module's base package, named interfaces, dependencies on other modules |
| `spring-modulith-api/src/main/java/org/springframework/modulith/NamedInterface.java` | Exposing a sub-package as public API |
| `spring-modulith-events/spring-modulith-events-core/src/main/java/org/springframework/modulith/events/support/PersistentApplicationEventMulticaster.java` | **The outbox inside the monolith**: events for transactional listeners are stored in the same transaction, then delivered |
| `spring-modulith-events/spring-modulith-events-core/src/main/java/org/springframework/modulith/events/core/DefaultEventPublicationRegistry.java` | Marking publications complete, resubmitting incomplete ones |
| `spring-modulith-events/spring-modulith-events-core/src/main/java/org/springframework/modulith/events/support/CompletionMode.java` | What "completed" means (update a column, delete the row, archive) |
| `spring-modulith-events/spring-modulith-events-jdbc/src/main/java/org/springframework/modulith/events/jdbc/JdbcEventPublicationRepository.java` | The SQL behind the registry |
| `spring-modulith-events/spring-modulith-events-api/src/main/java/org/springframework/modulith/events/ApplicationModuleListener.java` | Why it's `@Async` + `@TransactionalEventListener` + `REQUIRES_NEW` in one annotation |
| `spring-modulith-events/spring-modulith-events-api/src/main/java/org/springframework/modulith/events/Externalized.java` | Routing an event to a broker topic |
| `spring-modulith-docs/src/main/java/org/springframework/modulith/docs/Documenter.java` | Generating C4/PlantUML and module canvases from the code |
| `spring-modulith-examples/spring-modulith-example-full/` and `spring-modulith-examples/spring-modulith-example-outbox/` | Complete runnable examples |

### 2.3 Reading questions

1. `@ApplicationModuleListener` runs **after commit, asynchronously, in a new transaction**. What happens to the event if the JVM dies between the commit and the listener finishing? (Answer in the registry code: the publication stays incomplete and can be resubmitted. That's at-least-once, so the listener must be idempotent.)
2. Where does the registry write happen relative to the publisher's transaction, and why must it be the *same* transaction?
3. How does `verify()` decide that `inventory.internal` is off-limits to `order`?

This kit ran all three: a shortcut into `inventory.internal` produced two violations, and a failing listener left its publication incomplete until resubmission ([5.1](../05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md)).

### 2.4 What to critique 🧊

* Module boundaries are **compile-time packages + tests**, not runtime isolation: one module can still exhaust the shared connection pool or heap. Bulkheads still matter ([6.2](../06-Resilience-Caching/02-Bulkheads-Rate-Limiters-Retries-Jitter-Decorator-Order.md)).
* All modules share one database by default. Encapsulation of *tables* is a convention unless you add schemas and grants ([5.2](../05-Microservices-Patterns/02-Data-Ownership-Database-per-Service.md)).
* The registry table grows with every event. Choose a `CompletionMode` and a cleanup policy.

---

## 3. kgrzybek/modular-monolith-with-ddd (C#) 🧊

### 3.1 Structure

Five modules under `src/Modules/`: **Administration, Meetings, Payments, Registrations, UserAccess**, each split into Domain / Application / Infrastructure with its own tests, plus shared `src/BuildingBlocks/`. C4 diagrams live in `docs/C4/`.

### 3.2 Files to read

| Path | What to look for |
|---|---|
| `src/BuildingBlocks/Domain/Entity.cs` | `CheckRule(IBusinessRule rule)`: domain invariants as objects |
| `src/BuildingBlocks/Domain/IBusinessRule.cs`, `src/BuildingBlocks/Domain/BusinessRuleValidationException.cs` | The rule contract |
| `src/Modules/Meetings/Domain/Meetings/Meeting.cs` | A rich aggregate that enforces its rules |
| `src/Modules/Meetings/Domain/Meetings/Rules/MeetingAttendeeMustBeAMemberOfGroupRule.cs` | One rule = one class, named in ubiquitous language |
| `src/BuildingBlocks/Application/Outbox/OutboxMessage.cs` | The outbox record |
| `src/Modules/Meetings/Infrastructure/Configuration/Processing/Outbox/ProcessOutboxCommandHandler.cs` | The relay that publishes outbox messages |
| `src/BuildingBlocks/Infrastructure/Inbox/InboxMessage.cs` and `src/Modules/Meetings/Infrastructure/Configuration/Processing/Inbox/ProcessInboxCommandHandler.cs` | The **inbox**: incoming integration events stored first, processed later (dedup + retry) |
| `src/BuildingBlocks/Infrastructure/InternalCommands/InternalCommand.cs` | Internal commands: deferred, persisted work inside a module |
| `src/Modules/Payments/Infrastructure/AggregateStore/SqlStreamAggregateStore.cs` | The **event-sourced** module (SQL Stream Store) |
| `src/Modules/Payments/Infrastructure/AggregateStore/SubscriptionsManager.cs` and `SqlServerCheckpointStore.cs` | Projections with checkpoints |
| `src/Modules/Meetings/Tests/ArchTests/Domain/DomainTests.cs` | Architecture tests enforcing layering and domain purity |

The rule check, quoted from `Entity.cs`:

```csharp
protected void CheckRule(IBusinessRule rule)
{
    if (rule.IsBroken())
    {
        throw new BusinessRuleValidationException(rule);
    }
}
```

### 3.3 The Java translation

| kgrzybek (C#) | Java / Spring equivalent |
|---|---|
| Module = assembly set + architecture tests | Spring Modulith module + `ApplicationModules.verify()`, or ArchUnit |
| Outbox per module + processing job | Modulith event publication registry, or the [5.4](../05-Microservices-Patterns/04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md) outbox |
| Inbox per module | `processed_message` dedup table + listener, or Eventuate's `received_messages` ([8.3](03-Saga-Outbox-Event-Driven-Repos.md)) |
| Internal commands | A persisted job table, Spring Modulith's incomplete-publication resubmission, or a scheduler with `SKIP LOCKED` ([2.6](../02-SQL-RDBMS-Internals/06-Isolation-Anomalies-Row-Locks-SKIP-LOCKED-Gap-Locks-Deadlocks.md)) |
| `IBusinessRule` + `CheckRule` | A small `BusinessRule` interface, or the policy functions of the library repo (§4) |
| SQL Stream Store aggregate store | An events table with unique `(stream_id, version)` ([5.5](../05-Microservices-Patterns/05-CQRS-and-Event-Sourcing.md)), or EventStoreDB / Axon |

### 3.4 What to critique

* Last push June 2024: read it for **design**, not for current .NET API usage.
* Outbox + inbox + internal commands in every module is a lot of machinery. For many teams, a single outbox table and a dedup table per consumer are enough. Ask what each piece buys before copying it.

---

## 4. ddd-by-examples/library ⚡

### 4.1 Why it stands out

It models a public library (patrons place books on hold, check them out, holds expire) after an **event storming** session documented in `docs/` (`docs/big-picture.md`, `docs/design-level.md`, `docs/example-mapping.md`). The code makes design choices visible:

* **Aggregates return events or failures, they don't mutate and throw.** From `src/main/java/io/pillopl/library/lending/patron/model/Patron.java`:

  ```java
  public Either<BookHoldFailed, BookPlacedOnHoldEvents> placeOnHold(AvailableBook aBook, HoldDuration duration) {
      Option<Rejection> rejection = patronCanHold(aBook, duration);
      if (rejection.isEmpty()) {
          BookPlacedOnHold bookPlacedOnHold = bookPlacedOnHoldNow(aBook.getBookId(), aBook.type(), aBook.getLibraryBranch(), patron.getPatronId(), duration);
          if (patronHolds.maximumHoldsAfterHolding(aBook)) {
              return announceSuccess(events(bookPlacedOnHold, MaximumNumberOhHoldsReached.now(patron, MAX_NUMBER_OF_HOLDS)));
          }
          return announceSuccess(events(bookPlacedOnHold));
      }
      return announceFailure(bookHoldFailedNow(rejection.get(), aBook.getBookId(), aBook.getLibraryBranch(), patron));
  }
  ```

* **Business rules are first-class functions.** `PlacingOnHoldPolicy.java` defines `onlyResearcherPatronsCanHoldRestrictedBooksPolicy`, `overdueCheckoutsRejectionPolicy`, `regularPatronMaximumNumberOfHoldsPolicy`, `onlyResearcherPatronsCanPlaceOpenEndedHolds`, combined by `allCurrentPolicies()`.
* **States as types**: `AvailableBook`, `BookOnHold`, `CheckedOutBook` instead of a `status` field, so illegal transitions don't compile.
* **Boundaries are tested** with ArchUnit, e.g. `src/test/groovy/io/pillopl/library/ModularArchitectureTest.java`:

  ```java
  @ArchTest
  public static final ArchRule catalogue_should_not_depend_on_lending =
          noClasses()
                  .resideInAPackage("..catalogue..")
                  .should()
                  .resideInAPackage("..lending..");
  ```

  and `src/test/groovy/io/pillopl/library/lending/architecture/LendingHexagonalArchitectureTest.java` for ports and adapters.

### 4.2 Files to read

| Path | What to look for |
|---|---|
| `src/main/java/io/pillopl/library/lending/patron/model/Patron.java` | Aggregate as decision function: `Either<Failure, Events>` |
| `src/main/java/io/pillopl/library/lending/patron/model/PlacingOnHoldPolicy.java` | Policies as composable lambdas |
| `src/main/java/io/pillopl/library/lending/patron/model/PatronEvent.java` | The event vocabulary from the event storming |
| `src/main/java/io/pillopl/library/lending/book/model/BookDuplicateHoldFound.java` | Handling a race between two aggregates with an event, not a distributed lock |
| `src/main/java/io/pillopl/library/lending/book/application/PatronEventsHandler.java` | Eventual consistency between the Patron and Book aggregates |
| `src/main/java/io/pillopl/library/lending/patron/infrastructure/PatronsDatabaseRepository.java` | Persisting an aggregate that isn't a JPA entity |
| `src/main/java/io/pillopl/library/lending/dailysheet/model/HoldsToExpireSheet.java` | A read model built for one job (CQRS-lite) |
| `src/main/java/io/pillopl/library/commons/events/DomainEvents.java` | Event publishing abstraction |

### 4.3 Reading questions

1. Two patrons place a hold on the same book at the same instant. The Patron aggregate can't see other patrons. Where is the conflict detected, and what does `BookDuplicateHoldFound` do about it? What does that cost in consistency?
2. Why does `placeOnHold` return events instead of mutating state and saving? What does that make easy to test?
3. Which consistency boundary would you choose if the business said "a book must never be on hold for two patrons, not even for a second"? (Then the book, not the patron, must own the decision, or the database must enforce it.)

---

## 5. A two-week study exercise

| Day | Task |
|---|---|
| 1–2 | Read the library's `docs/` and the Patron model; draw the aggregates and events yourself before reading `PatronEvent.java` |
| 3–4 | Run `spring-modulith-example-full`; break a boundary on purpose and read the `verify()` failure |
| 5 | Port one library policy to a Spring Modulith module (`lending`), with an `@ApplicationModuleListener` reacting in a `catalogue` module |
| 6–7 | Read kgrzybek's outbox/inbox/internal-commands flow end to end; write down which of the three you'd keep |
| 8–9 | Add an ArchUnit/Modulith test that fails when a module reads another module's table through a repository |
| 10 | Write a one-page ADR: "modular monolith now, extraction criteria later" ([5.1](../05-Microservices-Patterns/01-Decomposition-Modular-Monolith-Strangler-Branch-by-Abstraction.md)) |

---

## 6. Interview soundbites

* "The `jbubernik` repo doesn't exist; the reference people mean is kgrzybek's, and it's C#. I read it for design: business rules as objects, per-module outbox and inbox, an event-sourced payments module."
* "In Java, Spring Modulith makes the same boundaries testable, and its event publication registry is an outbox inside the monolith: at-least-once, so listeners are idempotent."
* "The library repo models aggregates as decision functions that return `Either<Failure, Events>`, with policies as composable lambdas and states as types. Duplicate holds across aggregates are resolved by an event, which is a deliberate consistency trade-off."

**Next:** [8.2 Microservices and cloud-native repositories →](02-Microservices-and-Cloud-Native-Repos.md)

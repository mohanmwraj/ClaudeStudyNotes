# 5.1 Decomposition: Modular Monolith (Spring Modulith) vs Microservices, Strangler Fig, Branch by Abstraction

> **Verified stack:** Spring Boot **4.1.2**, Spring Modulith **2.1.2** (`spring-modulith-starter-core`, `-starter-jdbc`, `-starter-test`, `-docs`), PostgreSQL **18.6**. Module verification, the violation report, the generated C4 diagrams and the event publication registry rows below are real output.

---

## 0. First principles: you're drawing consistency and change boundaries 🔥

Decomposition answers two questions:

1. **What must change together?** Code that changes together should be deployed together. If two "services" always ship in lockstep, they're one service with a network call in the middle.
2. **What must be consistent together?** Data that must satisfy an invariant atomically ("never oversell stock") belongs inside **one transaction boundary**, which means one database and usually one service. Splitting it means replacing a transaction with a saga ([5.3](03-Sagas-Choreography-vs-Orchestration-Compensation-Semantic-Locks.md)), which is much more expensive.

A network boundary is the most expensive boundary you can draw: latency, partial failure, versioned contracts, distributed debugging, eventual consistency. Draw it where you **gain** something: independent deployment by independent teams, independent scaling, fault isolation, or different technology needs.

---

## 1. Monolith → modular monolith → microservices ⚡

| | Monolith ("big ball of mud") | **Modular monolith** | Microservices |
|---|---|---|---|
| Deployment unit | 1 | 1 | N |
| Module boundaries | None enforced | **Enforced** (build/test-time checks) | Enforced by the network |
| Cross-module calls | Anything calls anything | Public API types + events only | HTTP/gRPC/messaging |
| Transactions | Local, everywhere | Local inside a module; events between modules | Local per service; sagas between |
| Operational cost | Low | Low | High (per-service CI/CD, observability, on-call) |
| Team scaling | Poor beyond ~2 teams | Good to ~5–10 teams | Good for many independent teams |
| Refactoring a boundary | Easy, but nothing prevents decay | Easy (move packages) | **Hard** (data migration, contracts) |

The staff-level default: **start as a modular monolith with boundaries you verify**, and extract a module into a service when you have a concrete reason (a team that needs independent releases, a scaling or isolation hot spot). Well-kept module boundaries make that extraction mostly mechanical.

---

## 2. Spring Modulith: verified boundaries 🔥

### 2.1 The convention

Each **direct sub-package of the application's main package** is a module. Its top-level package is its **public API**; sub-packages (`internal`, `domain`…) are **private** to the module.

```text
com.acme.shop
├── ShopApplication.java
├── order/                         ← module "order"
│   ├── OrderPlaced.java           (public event)
│   └── OrderService.java          (public API)
├── inventory/                     ← module "inventory"
│   ├── InventoryService.java      (public, listens to OrderPlaced)
│   └── internal/StockRepository.java   (PRIVATE to inventory)
└── notification/                  ← module "notification"
    └── NotificationService.java
```

### 2.2 Verification as a test (verified)

```java
class ModularityTests {
    ApplicationModules modules = ApplicationModules.of(ShopApplication.class);

    @Test
    void printModules() {
        modules.forEach(m -> System.out.println("MODULE " + m.getIdentifier() + " -> base package " + m.getBasePackage().getName()));
    }

    @Test
    void verifiesModularStructure() {
        modules.verify();          // fails on cycles and on access to non-exposed (internal) types
        System.out.println("VERIFY OK");
    }

    @Test
    void writesDocumentation() {
        new Documenter(modules).writeModulesAsPlantUml().writeIndividualModulesAsPlantUml();
    }
}
```

**Output (verified):**

```text
VERIFY OK
MODULE order -> base package com.acme.shop.order
MODULE inventory -> base package com.acme.shop.inventory
MODULE notification -> base package com.acme.shop.notification
```

…and `target/spring-modulith-docs/` contains `components.puml`, `module-order.puml`, `module-inventory.puml`, `module-notification.puml` (C4 component diagrams generated from the **code**, so they can't go stale):

```text
Component(ShopApplication.ShopApplication.Order, "Order", $techn="Module", ...)
Component(ShopApplication.ShopApplication.Inventory, "Inventory", $techn="Module", ...)
Component(ShopApplication.ShopApplication.Notification, "Notification", $techn="Module", ...)
Rel(ShopApplication.ShopApplication.Inventory, ShopApplication.ShopApplication.Order, "listens to", ...)
Rel(ShopApplication.ShopApplication.Notification, ShopApplication.ShopApplication.Order, "listens to", ...)
```

### 2.3 Breaking a boundary (verified)

A developer takes a "shortcut" from `order` into inventory's internals:

```java
package com.acme.shop.order;

import com.acme.shop.inventory.internal.StockRepository;
import org.springframework.stereotype.Component;

/** ❌ The order module reaching into another module's internals. */
@Component
class OrderShortcut {
    private final StockRepository stock;
    OrderShortcut(StockRepository stock) { this.stock = stock; }
}
```

**Output (verified, `ModularityTests.verifiesModularStructure` fails the build):**

```text
org.springframework.modulith.core.Violations:
- Cycle detected: Slice inventory ->
                Slice order ->
                Slice inventory
  1. Dependencies of Slice inventory
    - Method <com.acme.shop.inventory.InventoryService.on(com.acme.shop.order.OrderPlaced)> has parameter of type <com.acme.shop.order.OrderPlaced> in (InventoryService.java:0)
    ...
  2. Dependencies of Slice order
    - Constructor <com.acme.shop.order.OrderShortcut.<init>(com.acme.shop.inventory.internal.StockRepository)> has parameter of type <com.acme.shop.inventory.internal.StockRepository> in (OrderShortcut.java:0)
    - Field <com.acme.shop.order.OrderShortcut.stock> has type <com.acme.shop.inventory.internal.StockRepository> in (OrderShortcut.java:0)
- Module 'order' depends on non-exposed type com.acme.shop.inventory.internal.StockRepository within module 'inventory'!
```

Two violations from one shortcut: an **encapsulation** breach (an internal type) and a **cycle** (`inventory` already depends on `order` by listening to `OrderPlaced`, so `order → inventory` closes the loop). This is the same structural check that makes a later extraction into a service possible: a module with no cycles and no internal leakage can be moved behind a network boundary.

### 2.4 Events between modules, with a durable registry (verified)

Modules communicate through **events**, so the publisher doesn't know its listeners:

```java
@Service
public class OrderService {
    @Transactional
    public long place(String sku, int quantity) {
        long id = jdbc.sql("insert into shop_order (sku, quantity) values (?, ?) returning id").params(sku, quantity).query(Long.class).single();
        events.publishEvent(new OrderPlaced(id, sku, quantity));   // recorded in the event publication registry, same transaction
        return id;
    }
}

@Service
public class InventoryService {
    @ApplicationModuleListener                // async + after commit + its own transaction
    void on(OrderPlaced event) { stock.reserve(event.sku(), event.quantity()); ... }
}

@Service
public class NotificationService {
    public static final AtomicBoolean emailServerDown = new AtomicBoolean(true);
    @ApplicationModuleListener
    void on(OrderPlaced event) {
        if (emailServerDown.get()) throw new IllegalStateException("SMTP unavailable");
        System.out.println("  [notification] email sent for order " + event.orderId());
    }
}
```

`@ApplicationModuleListener` = `@Async` + `@TransactionalEventListener` (after commit) + `@Transactional(propagation = REQUIRES_NEW)`. With `spring-modulith-starter-jdbc`, every publication to every listener is written to the **event publication registry** table *in the publisher's transaction*: an outbox inside your monolith.

**Output (verified):**

```text
  order 1 committed
  [inventory] reserved 2 x book for order 1 on task-1
  -- after commit (SMTP down)
  InventoryService       completed=true
  NotificationService    completed=false
  stock reserved = 2
  [notification] email sent for order 1
  -- after resubmitIncompletePublications (SMTP back)
  InventoryService       completed=true
  NotificationService    completed=true
```

The registry table (created by Modulith 2.1.2):

```text
         Column         |           Type           | Nullable
------------------------+--------------------------+----------
 id                     | uuid                     | not null
 listener_id            | text                     | not null
 event_type             | text                     | not null
 serialized_event       | text                     | not null
 publication_date       | timestamp with time zone | not null
 completion_date        | timestamp with time zone |
 status                 | text                     |
 completion_attempts    | integer                  |
 last_resubmission_date | timestamp with time zone |
```

```text
                         listener_id                          |           event_type            |  status   | completion_attempts | done
 com.acme.shop.inventory.InventoryService.on(com.acme.shop.or | com.acme.shop.order.OrderPlaced | COMPLETED |                   1 | t
 com.acme.shop.notification.NotificationService.on(com.acme.s | com.acme.shop.order.OrderPlaced | COMPLETED |                   2 | t
```

A failing listener doesn't lose the event. It stays incomplete until resubmitted (`IncompleteEventPublications.resubmitIncompletePublications(...)`, or `spring.modulith.events.republish-outstanding-events-on-restart=true`), and the registry records attempts. Operationally, keep the table small with `spring.modulith.events.completion-mode` (`UPDATE` by default; `DELETE` or `ARCHIVE` completed publications) and use the `spring.modulith.events.staleness.*` settings (present in 2.1.2's configuration metadata) to detect publications stuck in progress. Externalizing events to Kafka/AMQP (`@Externalized`) builds on the same registry, which makes it the natural bridge when a module later becomes a service.

---

## 3. Strangler Fig: migrating a legacy system incrementally 🔥

```mermaid
flowchart LR
    C[Clients] --> F["Facade / API gateway<br/>(routing by path, header, tenant, %)"]
    F -->|/orders/** (new)| N[New order service]
    F -->|everything else| L[Legacy monolith]
    N <-->|"sync data during migration<br/>(CDC from legacy DB, or events)"| L
```

The steps:

1. **Put a facade in front** (API gateway, reverse proxy, or the monolith's own controller layer) that can route per endpoint.
2. **Pick a seam**: a capability with clear inputs and outputs and low coupling. Not the core everything depends on.
3. **Build the new implementation**, keep the data in sync during migration (CDC from the legacy database with Debezium, [5.4 §6](04-Transactional-Outbox-and-Idempotent-Consumer-Complete-Implementation.md); or dual writes through events, never ad hoc dual writes in application code).
4. **Shift traffic gradually** (by tenant, percentage or header), compare results (shadow traffic / "dark launching"), keep a rollback route.
5. **Delete the legacy code path.** A strangler that never removes the old system is just two systems.

An illustrative route configuration (Spring Cloud Gateway style; not run in this lab, since the gateway is a separate service):

```yaml
spring:
  cloud:
    gateway:
      server:
        webflux:
          routes:
            - id: orders-new
              uri: http://order-service
              predicates:
                - Path=/api/orders/**
                - Weight=orders, 20          # 20% of /api/orders traffic to the new service
            - id: orders-legacy
              uri: http://legacy-monolith
              predicates:
                - Path=/api/orders/**
                - Weight=orders, 80
            - id: legacy-everything-else
              uri: http://legacy-monolith
              predicates:
                - Path=/**
```

---

## 4. Branch by Abstraction: replacing a component *inside* a codebase ⚡

When the thing to replace is a library or internal component (a payment SDK, a persistence layer, a pricing engine) rather than an endpoint, put an **abstraction** in front of it, migrate callers to the abstraction, switch implementations behind a flag, then delete the old one, all on trunk with no long-lived branch.

```java
public interface PriceCalculator {                       // 1. the abstraction
    Money price(Cart cart);
}

class LegacyPriceCalculator implements PriceCalculator { ... }   // 2. wraps the old code
class RulesEnginePriceCalculator implements PriceCalculator { ... } // 3. the new implementation

@Configuration
class PricingConfig {
    @Bean PriceCalculator priceCalculator(FeatureFlags flags, LegacyPriceCalculator legacy, RulesEnginePriceCalculator next) {
        return cart -> flags.isEnabled("pricing.rules-engine", cart.tenantId())   // 4. switch per tenant at runtime
                ? next.price(cart)
                : legacy.price(cart);
    }
}
```

*(Illustrative.)* A useful extra step is a **verifying** implementation that calls both, returns the legacy result and logs mismatches: the in-process equivalent of shadow traffic.

---

## 5. ❌ Naïve vs ✅ production-hardened decomposition

| ❌ Naïve | ✅ Hardened |
|---|---|
| Split into services by technical layer (UI service, logic service, DB service) | Split by business capability / bounded context |
| Microservices on day one for a 6-person team | Modular monolith with verified boundaries; extract with a reason |
| "Modules" by convention only | `ApplicationModules.verify()` in CI (verified: a shortcut produced 2 violations) |
| Cross-module calls into internals | Public API types and events only |
| In-process events lost when a listener fails | Event publication registry (verified: incomplete → resubmitted → completed) |
| Big-bang rewrite | Strangler fig with a facade, gradual traffic shift, and deletion of the old path |
| Long-lived "rewrite" branch | Branch by abstraction + feature flags on trunk |

---

## 6. Source to read

| Repo | Path | What to look for |
|---|---|---|
| [spring-projects/spring-modulith](https://github.com/spring-projects/spring-modulith) | `spring-modulith-core/src/main/java/org/springframework/modulith/core/ApplicationModules.java` | Module detection, `verify()`, `detectViolations` |
| spring-projects/spring-modulith | `spring-modulith-events/spring-modulith-events-core/src/main/java/org/springframework/modulith/events/support/PersistentApplicationEventMulticaster.java` | How publications are stored in the publisher's transaction |
| spring-projects/spring-modulith | `spring-modulith-events/spring-modulith-events-jdbc/` | The JDBC registry schema per database |
| spring-projects/spring-modulith | `spring-modulith-docs/src/main/java/org/springframework/modulith/docs/Documenter.java` | Diagram generation |
| [ddd-by-examples/library](https://github.com/ddd-by-examples/library) | the whole repo | A DDD modular monolith in Java (see [8.1](../08-GitHub-Codebases-Study-Guide/01-Modular-Monolith-and-DDD-Repos.md)) |

---

## 7. Interview soundbites

* "A service boundary is a consistency boundary. Splitting an invariant across services turns a transaction into a saga, so I start with a modular monolith and extract with a reason."
* "Spring Modulith makes module boundaries a test. One shortcut into another module's internals produced an encapsulation violation and a cycle."
* "Module events go through a durable publication registry; a failed listener stayed incomplete and completed after resubmission. It's an outbox inside the monolith."
* "Strangler fig needs a facade, gradual traffic shifting, data sync via CDC or events, and deleting the old path. Branch by abstraction does the same inside a codebase."

---

## 8. Deep dive: from verified boundaries to a verified extraction path 🔥

§2 proved that Spring Modulith turns module boundaries into a failing test, and that its event registry survives a failed listener. [5.11](11-Modular-Monolith-Blueprint-Spring-Modulith-Externalized-Events-Extraction.md) takes the same approach to the end of the road: a module that is *ready to become a service*. What it added, all verified:

| Question | Answer from 5.11 | Evidence |
|---|---|---|
| Can a module expose *part* of itself? | `@NamedInterface("api")` + `allowedDependencies = "catalog :: api"` | One `new PriceTable()` across the line = **3 violations** (field, constructor, method), each with a line number |
| Is a module testable alone? | `@ApplicationModuleTest`: STANDALONE booted inventory with **0** beans from other modules; order needed `DIRECT_DEPENDENCIES` (STANDALONE failed: no `CatalogApi`) | The bootstrap mode is a dependency audit |
| Does an event survive a broker outage? | `@Externalized` publishes through the same registry: `place()` returned in 14 ms with Kafka down; the publication went `FAILED`, then `COMPLETED (attempts=2)` after a restart | §4 outage drill |
| Does one failing listener hurt others? | No: the inventory listener `FAILED` while the Kafka externalizer for the same event `COMPLETED`, and the order committed | §4, order 2 |
| What's the first extraction bug? | Every Kafka record carried `__TypeId__=com.acme.shop.order.OrderPlaced`, the monolith's class name, which a separate codebase can't load | §8: ignore type headers or map logical type ids |

The extraction path (§8 of 5.11) mirrors this file's strangler fig at module scale:

1. Prove isolation with `verify()` and a STANDALONE module test.
2. Externalize the module's input events, which makes the topic the contract.
3. Run the new service in **shadow** mode against the topic.
4. Cut over behind a flag, with an **inbox** in the new service.
5. Move the module's tables, then delete the module.

Steps 2–4 are branch by abstraction (§4) with a topic as the abstraction.

---

## Summary

| Topic | Key point | Evidence |
|---|---|---|
| Boundaries | A service boundary is a consistency boundary; start modular, extract with a reason | §0, §1 |
| Spring Modulith | Module = direct sub-package; `verify()` fails on internals access and cycles | §2.2–2.3 |
| Module events | Durable publication registry; failed listeners stay incomplete until resubmitted | §2.4 |
| Named interfaces | Expose part of a module; one illegal use = 3 violations with lines | §8 (5.11 §2) |
| Externalization | Registry-backed Kafka publishing; the commit doesn't wait for Kafka | §8 (5.11 §4) |
| Strangler fig | Facade, gradual shift, data sync, delete the old path | §3 |
| Branch by abstraction | The same inside one codebase, behind an interface and a flag | §4 |
| Extraction | Contract (topic) → shadow → cut over with inbox → move data → delete | §8 |

**Next:** [5.2 Data ownership: database per service →](02-Data-Ownership-Database-per-Service.md)

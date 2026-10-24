# 5.3 · Query Performance — N+1, Fetch Strategies, Cartesian Products, Pagination, Projections

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** Hibernate ORM 7.4 *What's New* ("Limits and Fetch Joins") and User Guide (fetching, batch and subselect fetching); Spring Data JPA reference (Projections, Scrolling); PostgreSQL 18 docs (indexes, `LIMIT`/`OFFSET`); Vlad Mihalcea, *High-Performance Java Persistence*; Markus Winand, *Use The Index, Luke* (keyset pagination).
> **Verified stack:** Hibernate ORM **7.4.13.Final**, Spring Data JPA **4.1.2**, Spring Framework 7.0.10, PostgreSQL 18.6 (embedded), statements captured with `datasource-proxy` 1.11.1. Timings come from a laptop with the database on loopback, so **production round trips cost more than shown here**.

---

## 1. Where the time goes in an ORM read 🔥

| Cost | Driven by | Typical symptom | Main lever |
|---|---|---|---|
| **Round trips** | Number of SQL statements × network RTT (+ pool checkout) | Hundreds of identical `SELECT … WHERE x_id = ?` per request | Fetch joins, entity graphs, batch/subselect fetching |
| **Rows transferred** | Joins multiply rows (Cartesian products) | One query, but 100k+ rows for 500 parents | One collection per query; batch fetching |
| **Columns transferred** | `SELECT *`-style entity loads with wide columns | High network/heap use for list screens | Projections (closed interface / DTO) |
| **Hydration + bookkeeping** | Managed entities: `EntityEntry`, snapshots, identity map | High allocation and GC on read paths | DTO projections, read-only sessions ([5.2 §2](02-JPA-Hibernate-Persistence-Context-Internals.md#2-dirty-checking-cost-and-alternatives-)) |
| **Database work** | Missing indexes, deep `OFFSET`, bad plans | Single query slow even alone | Indexes on FK columns, keyset pagination, `EXPLAIN (ANALYZE, BUFFERS)` |

Rule of thumb: **decide the fetch plan per use case at the query, not in the mapping.** Map every association `LAZY`, then fetch exactly what each screen or endpoint needs with a join fetch, an entity graph or a projection.

---

## 2. The N+1 select problem 🔥

You load N parents with 1 query, then touching a lazy association on each parent fires one more query per parent: **1 + N statements**. It comes in three flavours:

1. **Lazy to-many in a loop**: `for (Author a : authors) a.getBooks().size()`. This is the classic one.
2. **Lazy to-one in a loop**: `book.getAuthor().getName()` initializes one proxy per distinct author.
3. **EAGER to-one with JPQL** (the JPA default for `@ManyToOne`/`@OneToOne`). JPQL ignores the mapping's fetch type when it builds SQL, so Hibernate loads the EAGER association **afterwards with one SELECT per distinct target**, even if your code never touches it.

| Fix | How | Statements for 200 authors | Trade-off |
|---|---|---|---|
| `JOIN FETCH` | `select a from Author a left join fetch a.books` | 1 | Parent columns are repeated per child row; one collection per query (see §3) |
| Entity graph | `@EntityGraph(attributePaths = "books")` or `GraphSemantic.FETCH`/`LOAD` | 1 | Same SQL as a join fetch, declared outside the query |
| Batch fetching | `@BatchSize(size = 50)`, `hibernate.default_batch_fetch_size`, `Session.setFetchBatchSize(50)` | 1 + ⌈N / 50⌉ | Works for lazy loads triggered anywhere; no row multiplication |
| Subselect fetching | `@Fetch(FetchMode.SUBSELECT)`, `hibernate.use_subselect_fetch`, `Session.setSubselectFetchingEnabled(true)` | 2 | Re-runs the original query as a subquery, so it repeats an expensive root query |
| DTO projection | `select new …(a.name, count(b))` / record | 1 | No entities; ideal for read-only screens |

### 2.1 Runnable: five ways to load 200 authors with their 2,000 books, counted at the JDBC layer

<!-- run: javac cp=@p5 timeout=300 -->
```java
package demo.perf;

import ch.qos.logback.classic.Level;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import jakarta.persistence.*;
import java.util.*;
import java.util.function.Consumer;
import net.ttddyy.dsproxy.ExecutionInfo;
import net.ttddyy.dsproxy.QueryInfo;
import net.ttddyy.dsproxy.listener.QueryExecutionListener;
import net.ttddyy.dsproxy.support.ProxyDataSourceBuilder;
import org.hibernate.Session;
import org.hibernate.SessionFactory;
import org.hibernate.jpa.HibernatePersistenceConfiguration;
import org.hibernate.tool.schema.Action;
import org.slf4j.LoggerFactory;

public class NPlusOne {
    @Entity(name = "Author") @Table(name = "author")
    public static class Author {
        @Id Long id; String name;
        @OneToMany(mappedBy = "author") List<Book> books = new ArrayList<>();
    }
    @Entity(name = "Book") @Table(name = "book")
    public static class Book {
        @Id Long id; String title;
        @ManyToOne(fetch = FetchType.LAZY) Author author;
    }
    @Entity(name = "Review") @Table(name = "review")
    public static class Review {
        @Id Long id; int stars;
        @ManyToOne Author author;                                       // JPA default for to-one: EAGER
    }

    static final List<String> sql = Collections.synchronizedList(new ArrayList<>());

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.ERROR);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            HikariConfig hc = new HikariConfig();
            hc.setJdbcUrl(pg.getJdbcUrl("postgres", "postgres"));
            var counting = ProxyDataSourceBuilder.create(new HikariDataSource(hc)).listener(new QueryExecutionListener() {
                public void beforeQuery(ExecutionInfo e, List<QueryInfo> q) { }
                public void afterQuery(ExecutionInfo e, List<QueryInfo> q) { sql.add(q.get(0).getQuery()); }
            }).build();
            try (EntityManagerFactory emf = new HibernatePersistenceConfiguration("demo")
                    .managedClasses(Author.class, Book.class, Review.class)
                    .property("hibernate.connection.datasource", counting)
                    .schemaToolingAction(Action.CREATE_DROP).createEntityManagerFactory()) {
                SessionFactory sf = emf.unwrap(SessionFactory.class);
                sf.inTransaction(s -> {
                    s.createNativeMutationQuery("insert into author(id, name) select g, 'author-' || g from generate_series(1, 200) g").executeUpdate();
                    s.createNativeMutationQuery("insert into book(id, title, author_id) select g, 'book-' || g, 1 + (g % 200) from generate_series(1, 2000) g").executeUpdate();
                    s.createNativeMutationQuery("insert into review(id, stars, author_id) select g, 1 + g % 5, 1 + (g % 200) from generate_series(1, 2000) g").executeUpdate();
                });
                for (int round = 0; round < 2; round++) {                      // round 0 = warm-up
                    boolean print = round == 1;
                    run(sf, print, "lazy collection in a loop (N+1)", s -> {}, "from Author");
                    run(sf, print, "join fetch", s -> {}, "from Author a left join fetch a.books");
                    run(sf, print, "entity graph (fetchgraph hint)", s -> {}, "GRAPH");
                    run(sf, print, "session.setFetchBatchSize(50)", s -> s.setFetchBatchSize(50), "from Author");
                    run(sf, print, "session.setSubselectFetchingEnabled", s -> s.setSubselectFetchingEnabled(true), "from Author");
                }
                sf.inTransaction(s -> {                                         // never touches review.author, still N+1
                    sql.clear();
                    List<Review> reviews = s.createSelectionQuery("from Review where stars = 5", Review.class).getResultList();
                    System.out.printf("%-38s reviews=%d statements=%3d%n", "EAGER @ManyToOne, JPQL 'from Review'", reviews.size(), sql.size());
                    System.out.println("    2nd: " + shorten(sql.get(1)));
                });
            }
        }
    }

    static void run(SessionFactory sf, boolean print, String label, Consumer<Session> setup, String hql) {
        sf.inTransaction(s -> {
            setup.accept(s);
            sql.clear();
            long t0 = System.nanoTime();
            List<Author> authors;
            if (hql.equals("GRAPH")) {
                EntityGraph<Author> g = s.createEntityGraph(Author.class);
                g.addAttributeNodes("books");
                authors = s.createSelectionQuery("from Author", Author.class).setEntityGraph(g, org.hibernate.graph.GraphSemantic.FETCH).getResultList();
            } else {
                authors = s.createSelectionQuery(hql, Author.class).getResultList();
            }
            int books = 0;
            for (Author a : authors) books += a.books.size();          // touches every lazy collection
            long us = (System.nanoTime() - t0) / 1_000;
            if (print) {
                System.out.printf("%-38s authors=%d books=%d statements=%3d %,7d µs%n", label, authors.size(), books, sql.size(), us);
                System.out.println("    1st: " + shorten(sql.get(0)));
                if (sql.size() > 1) System.out.println("    2nd: " + shorten(sql.get(1)));
            }
        });
    }

    static String shorten(String s) { s = s.replaceAll("\\s+", " "); return s.length() > 150 ? s.substring(0, 150) + "…" : s; }
}
```

One measured run:

```
lazy collection in a loop (N+1)        authors=200 books=2000 statements=201 159,004 µs
    1st: select a1_0.id,a1_0.name from author a1_0
    2nd: select b1_0.author_id,b1_0.id,b1_0.title from book b1_0 where b1_0.author_id=?
join fetch                             authors=200 books=2000 statements=  1   7,068 µs
    1st: select a1_0.id,b1_0.author_id,b1_0.id,b1_0.title,a1_0.name from author a1_0 left join book b1_0 on a1_0.id=b1_0.author_id
entity graph (fetchgraph hint)         authors=200 books=2000 statements=  1   9,936 µs
    1st: select a1_0.id,b1_0.author_id,b1_0.id,b1_0.title,a1_0.name from author a1_0 left join book b1_0 on a1_0.id=b1_0.author_id
session.setFetchBatchSize(50)          authors=200 books=2000 statements=  5  19,548 µs
    1st: select a1_0.id,a1_0.name from author a1_0
    2nd: select b1_0.author_id,b1_0.id,b1_0.title from book b1_0 where b1_0.author_id = any (?)
session.setSubselectFetchingEnabled    authors=200 books=2000 statements=  2   8,976 µs
    1st: select a1_0.id,a1_0.name from author a1_0
    2nd: select b1_0.author_id,b1_0.id,b1_0.title from book b1_0 where b1_0.author_id in (select a1_0.id from author a1_0)
EAGER @ManyToOne, JPQL 'from Review'   reviews=400 statements= 41
    2nd: select a1_0.id,a1_0.name from author a1_0 where a1_0.id=?
```

What the numbers show:

* **N+1 really is 1 + N.** It took 201 statements, with every lazy collection initialized by its own `where author_id=?` query.
* **The join fetch returned 200 authors, not 2,000.** Since Hibernate 6, root entities from a fetch join are **deduplicated automatically**, so you no longer need `select distinct` (which in Hibernate 5 also sent a pointless `DISTINCT` to the database).
* **The entity graph produced exactly the same SQL** as the hand-written join fetch.
* **Batch fetching on PostgreSQL uses a single array parameter** (`author_id = any (?)`), so every batch has the same SQL text and reuses the same prepared statement and plan. 200 lazy collections with batch size 50 means 1 + 4 = 5 statements.
* **Subselect fetching** loads *all* the collections with one extra query that embeds the original root query.
* **EAGER `@ManyToOne` caused N+1 without the code touching the association.** 400 reviews pointed to 40 distinct authors, so the query took 1 + 40 statements. This is why every to-one should be explicitly `LAZY`.
* The local timings understate the damage: 201 statements cost ~160 ms over loopback. Over a real network add your RTT per statement, plus pool contention, because the connection is held for the whole loop.

### 2.2 The same fixes in Spring Data JPA

```java
public interface AuthorRepository extends JpaRepository<Author, Long> {

    @EntityGraph(attributePaths = "books")                   // LEFT JOIN FETCH books, same SQL as above
    List<Author> findByNameStartingWith(String prefix);

    @Query("select a from Author a left join fetch a.books where a.id in :ids")
    List<Author> findWithBooks(Collection<Long> ids);

    @Query("select new com.example.AuthorSummary(a.name, count(b)) from Author a left join a.books b group by a.name")
    List<AuthorSummary> summaries();                          // read-only screen: no entities at all
}
```

```yaml
spring:
  jpa:
    open-in-view: false                       # don't let N+1 hide in serializers (5.4 §6)
    properties:
      hibernate.default_batch_fetch_size: 50  # safety net for any lazy load you didn't plan for
```

### 2.3 Detecting N+1 before production

* **Assert statement counts in tests.** This is the only reliable guard. With datasource-proxy, wrap the `DataSource` via `ProxyDataSourceBuilder.create(ds).countQuery().build()`, call `QueryCountHolder.clear()`, run the use case, then assert `QueryCountHolder.getGrandTotal().getSelect() == 1`. Hibernate's `Statistics.getPrepareStatementCount()` (with `hibernate.generate_statistics=true`) works too.
* **Dev logging:** `logging.level.org.hibernate.SQL=debug`. N+1 is visible as a wall of identical SELECTs.
* **Production:** traces whose span count per request runs into the hundreds (OpenTelemetry JDBC instrumentation, [8.2](../08-Observability-Security-Testing/02-Observability-OpenTelemetry-Micrometer-Logging.md)); `pg_stat_statements` showing one tiny query with a huge `calls` count; Hibernate statistics exported as Micrometer `hibernate.*` meters (Spring Boot auto-configures this when `org.hibernate.orm:hibernate-micrometer` is on the classpath; counts stay at zero unless `hibernate.generate_statistics=true`).

---

## 3. Cartesian products & multiple bag fetch 🔥

A **bag** is a `List` (or `Collection`) association without `@OrderColumn`: unordered and duplicates allowed. With join fetches the SQL result is the product of every fetched collection: an author with 20 books and 20 talks yields 20 × 20 = 400 rows.

* **Two bags in one fetch:** Hibernate refuses with `MultipleBagFetchException`, because it cannot tell real duplicates from join duplicates in a bag.
* **One bag + one set:** allowed, and **silently wrong**: the bag receives a duplicate element for every row of the product (measured below: 400 "books" instead of 20).
* **Two sets:** correct results, but the row count still explodes (parents × children₁ × children₂).

### 3.1 Runnable: the Cartesian product, measured, and the two-query fix

<!-- run: javac cp=@p5 timeout=300 -->
```java
package demo.perf;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import jakarta.persistence.*;
import java.util.*;
import net.ttddyy.dsproxy.ExecutionInfo;
import net.ttddyy.dsproxy.QueryInfo;
import net.ttddyy.dsproxy.listener.QueryExecutionListener;
import net.ttddyy.dsproxy.support.ProxyDataSourceBuilder;
import org.hibernate.SessionFactory;
import org.hibernate.jpa.HibernatePersistenceConfiguration;
import org.hibernate.tool.schema.Action;
import org.slf4j.LoggerFactory;

public class CartesianProducts {
    @Entity(name = "Author") @Table(name = "author")
    public static class Author {
        @Id Long id; String name;
        @OneToMany(mappedBy = "author") List<Book> books = new ArrayList<>();     // a "bag": unordered, duplicates allowed
        @OneToMany(mappedBy = "author") List<Award> awards = new ArrayList<>();   // another bag
        @OneToMany(mappedBy = "author") Set<Talk> talks = new HashSet<>();        // a set
    }
    @Entity(name = "Book") @Table(name = "book")   public static class Book  { @Id Long id; String title; @ManyToOne(fetch = FetchType.LAZY) Author author; }
    @Entity(name = "Award") @Table(name = "award") public static class Award { @Id Long id; String title; @ManyToOne(fetch = FetchType.LAZY) Author author; }
    @Entity(name = "Talk") @Table(name = "talk")   public static class Talk  { @Id Long id; String title; @ManyToOne(fetch = FetchType.LAZY) Author author; }

    static final List<String> sql = Collections.synchronizedList(new ArrayList<>());

    public static void main(String[] args) throws Exception {
        Logger root = (Logger) LoggerFactory.getLogger("ROOT");
        root.setLevel(Level.WARN);
        root.detachAndStopAllAppenders();
        ListAppender<ILoggingEvent> warnings = new ListAppender<>();
        warnings.start();
        root.addAppender(warnings);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            HikariConfig hc = new HikariConfig();
            hc.setJdbcUrl(pg.getJdbcUrl("postgres", "postgres"));
            var counting = ProxyDataSourceBuilder.create(new HikariDataSource(hc)).listener(new QueryExecutionListener() {
                public void beforeQuery(ExecutionInfo e, List<QueryInfo> q) { }
                public void afterQuery(ExecutionInfo e, List<QueryInfo> q) { sql.add(q.get(0).getQuery()); }
            }).build();
            try (EntityManagerFactory emf = new HibernatePersistenceConfiguration("demo")
                    .managedClasses(Author.class, Book.class, Award.class, Talk.class)
                    .property("hibernate.connection.datasource", counting)
                    .schemaToolingAction(Action.CREATE_DROP).createEntityManagerFactory()) {
                SessionFactory sf = emf.unwrap(SessionFactory.class);
                sf.inTransaction(s -> {
                    s.createNativeMutationQuery("insert into author(id, name) select g, 'author-' || g from generate_series(1, 500) g").executeUpdate();
                    for (String t : List.of("book", "award", "talk"))
                        s.createNativeMutationQuery("insert into " + t + "(id, title, author_id) select g, '" + t + "-' || g, 1 + (g % 500) from generate_series(1, 10000) g").executeUpdate();
                });

                // 1. two bags in one fetch join
                try {
                    sf.inTransaction(s -> s.createSelectionQuery("from Author a left join fetch a.books left join fetch a.awards", Author.class).getResultList());
                } catch (Exception e) {
                    System.out.println("1. two bags: " + e.getClass().getName() + ": " + e.getMessage());
                }

                for (int round = 0; round < 2; round++) {
                    boolean print = round == 1;
                    // 2. bag + set: allowed, but every author row × books × talks
                    sf.inTransaction(s -> {
                        long rows = (Long) s.createNativeQuery("select count(*) from author a left join book b on b.author_id = a.id left join talk t on t.author_id = a.id", Long.class).getSingleResult();
                        sql.clear();
                        long t0 = System.nanoTime();
                        List<Author> list = s.createSelectionQuery("from Author a left join fetch a.books left join fetch a.talks", Author.class).getResultList();
                        long ms = (System.nanoTime() - t0) / 1_000_000;
                        Author first = list.get(0);
                        if (print) System.out.printf("2. bag + set, one query:   statements=%d  JDBC rows=%,7d  %4d ms  author %d: books=%d talks=%d%n",
                            sql.size(), rows, ms, first.id, first.books.size(), first.talks.size());
                    });
                    // 3. one collection per query; the persistence context stitches them onto the same Author instances
                    sf.inTransaction(s -> {
                        sql.clear();
                        long t0 = System.nanoTime();
                        List<Author> list = s.createSelectionQuery("from Author a left join fetch a.books", Author.class).getResultList();
                        s.createSelectionQuery("from Author a left join fetch a.talks where a in :authors", Author.class).setParameter("authors", list).getResultList();
                        long ms = (System.nanoTime() - t0) / 1_000_000;
                        Author first = list.get(0);
                        if (print) System.out.printf("3. one query per collection: statements=%d  JDBC rows=%,7d  %4d ms  author %d: books=%d talks=%d%n",
                            sql.size(), 10_000 + 10_000, ms, first.id, first.books.size(), first.talks.size());
                    });
                }

                // 4. pagination + collection fetch join
                warnings.list.clear();
                sf.inTransaction(s -> {
                    sql.clear();
                    List<Author> page = s.createSelectionQuery("from Author a left join fetch a.books order by a.id", Author.class)
                        .setFirstResult(0).setMaxResults(10).getResultList();
                    System.out.println("4. page size=" + page.size() + ", SQL: " + sql.get(0).replaceAll("\\s+", " "));
                    warnings.list.stream().map(ILoggingEvent::getFormattedMessage).filter(m -> m.startsWith("HHH")).forEach(m -> System.out.println("   WARN " + m));
                });
                // 5. the fix: page the root ids first, then fetch the collection for just those ids
                sf.inTransaction(s -> {
                    sql.clear();
                    List<Long> ids = s.createSelectionQuery("select a.id from Author a order by a.id", Long.class).setMaxResults(10).getResultList();
                    List<Author> page = s.createSelectionQuery("from Author a left join fetch a.books where a.id in :ids order by a.id", Author.class)
                        .setParameter("ids", ids).getResultList();
                    System.out.println("5. two-step page size=" + page.size() + ", statements=" + sql.size());
                    sql.forEach(q -> System.out.println("   " + q.replaceAll("\\s+", " ")));
                });
            }
        }
    }
}
```

One measured run:

```
1. two bags: java.lang.IllegalArgumentException: org.hibernate.loader.MultipleBagFetchException: cannot simultaneously fetch multiple bags: [demo.perf.CartesianProducts$Author.awards, demo.perf.CartesianProducts$Author.books]
2. bag + set, one query:   statements=1  JDBC rows=200,000   504 ms  author 2: books=400 talks=20
3. one query per collection: statements=2  JDBC rows= 20,000    87 ms  author 2: books=20 talks=20
4. page size=10, SQL: select a1_0.id,b1_0.author_id,b1_0.id,b1_0.title,a1_0.name from (select a1_0.id,a1_0.name from author a1_0 order by a1_0.id offset ? rows fetch first ? rows only) a1_0(id,name) left join book b1_0 on a1_0.id=b1_0.author_id order by a1_0.id
5. two-step page size=10, statements=2
   select a1_0.id from author a1_0 order by a1_0.id fetch first ? rows only
   select a1_0.id,b1_0.author_id,b1_0.id,b1_0.title,a1_0.name from author a1_0 left join book b1_0 on a1_0.id=b1_0.author_id where a1_0.id in (?,?,?,?,?,?,?,?,?,?) order by a1_0.id
```

* **Line 1:** two bags fail fast with `MultipleBagFetchException`, wrapped in `IllegalArgumentException` by the JPA `createQuery` contract.
* **Line 2:** bag + set ran, but transferred **200,000 rows** for 500 authors and **corrupted the bag**: author 2 has 20 books in the database and **400** in memory. A JSON endpoint would serialize 400 books.
* **Line 3:** fetching one collection per query transferred 20,000 rows and was ~6× faster. The second query attaches talks to the **same `Author` instances**, because the persistence context is an identity map ([5.2 §1](02-JPA-Hibernate-Persistence-Context-Internals.md#1-the-mental-model-)).
* Changing `List` to `Set` "fixes" the exception and corruption, but **not** the row explosion. Prefer one collection per query, or batch fetching, for multiple collections.

### 3.2 Pagination with a collection fetch join 🎓

Limiting a joined result set in SQL would cut a parent's collection in half, so for years Hibernate refused to paginate in SQL. Before **7.4** it logged `HHH90003004: firstResult/maxResults specified with collection fetch; applying in memory` (`HHH000104` in Hibernate 5). It then **loaded every matching row and paginated in the JVM**: a page of 10 could read the whole table. You could make it throw instead with `hibernate.query.fail_on_pagination_over_collection_fetch=true`.

**Hibernate 7.4 changed this** ("Limits and Fetch Joins" in its What's New): on databases that support limits in subqueries, it pages the **root rows in a derived table** and joins the collection to that page. Lines 4–5 of the run above show it on PostgreSQL:

```
select … from (select a1_0.id,a1_0.name from author a1_0 order by a1_0.id offset ? rows fetch first ? rows only) a1_0(id,name)
         left join book b1_0 on a1_0.id=b1_0.author_id order by a1_0.id
```

**The two-step pattern** (page the IDs, then fetch by `id in :ids`, line 5) is still the portable answer:

* for Hibernate < 7.4 (Spring Boot 3.x, Boot 4.0);
* for databases without limits in subqueries;
* when the page query needs filters or sorts you don't want joined to children;
* when a Spring Data `Page<T>` needs a separate count query anyway.

If you page a `@Query` with a fetch join in Spring Data, give it an explicit `countQuery` without the fetch.

---

## 4. Projections: interface vs DTO vs tuple ⚡

| Kind | Declared as | Columns selected (measured) | Row object | Managed / dirty-checked? |
|---|---|---|---|---|
| Entity | `List<Customer>` | **all** mapped columns, including wide ones | Entity | Yes |
| **Closed interface** projection | `interface NameOnly { String getFirstName(); … }` | Only the getters' columns | **JDK proxy** over a JPA `Tuple` | No |
| **Open interface** projection | `@Value("#{target.firstName + ' ' + target.lastName}")` | **All** columns (the entity is loaded as the SpEL target) | JDK proxy over the **entity** | The entity is |
| **DTO record/class** (derived query) | `List<ContactDto>` | Constructor parameters only | Your record | No |
| DTO from `@Query` JPQL | `select c.firstName, c.email from Customer c` → `List<ContactDto>` | Selected columns; Spring Data **rewrites the query to `select new …`** | Your record | No |
| Dynamic projection | `<T> List<T> findBy…(…, Class<T> type)` | Depends on the class passed | Proxy or record | Depends |
| `Tuple` / `Object[]` | `createQuery(…, Tuple.class)` | As written | Tuple | No |

### 4.1 Runnable: the SQL each projection generates, and what 50,000 rows cost

<!-- run: javac cp=@p5 jvm="-Xmx1g" timeout=300 -->
```java
package demo.proj;

import ch.qos.logback.classic.Level;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import jakarta.persistence.*;
import java.util.*;
import java.util.function.Supplier;
import javax.sql.DataSource;
import net.ttddyy.dsproxy.ExecutionInfo;
import net.ttddyy.dsproxy.QueryInfo;
import net.ttddyy.dsproxy.listener.QueryExecutionListener;
import net.ttddyy.dsproxy.support.ProxyDataSourceBuilder;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.orm.jpa.JpaTransactionManager;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;
import org.springframework.transaction.annotation.EnableTransactionManagement;
import org.springframework.transaction.support.TransactionTemplate;

public class Projections {
    @Entity(name = "Customer") @Table(name = "customer")
    public static class Customer {
        @Id Long id; String firstName; String lastName; String email;
        @Column(length = 4000) String notes;                                // a wide column that projections can skip
        protected Customer() {}
        public String getFirstName() { return firstName; }                  // SpEL in open projections reads getters
        public String getLastName() { return lastName; }
    }

    public interface NameOnly { String getFirstName(); String getLastName(); }                                   // closed projection
    public interface FullName { @Value("#{target.firstName + ' ' + target.lastName}") String getFullName(); }   // open projection (SpEL)
    public record ContactDto(String firstName, String email) {}                                                 // DTO projection

    public interface CustomerRepository extends JpaRepository<Customer, Long> {
        List<Customer> findByLastName(String lastName);
        List<NameOnly> findNamesByLastName(String lastName);
        List<FullName> findFullNamesByLastName(String lastName);
        List<ContactDto> findContactsByLastName(String lastName);
        <T> List<T> findByLastNameOrderById(String lastName, Class<T> type);                                   // dynamic projection
        @Query("select c.firstName, c.email from Customer c where c.lastName = :lastName")
        List<ContactDto> jpqlContacts(String lastName);
        @Query("select c from Customer c")
        List<Customer> allEntities();
        @Query("select c.firstName as firstName, c.lastName as lastName from Customer c")
        List<NameOnly> allNames();
        @Query("select c.firstName, c.email from Customer c")
        List<ContactDto> allContacts();
    }

    static final List<String> sql = Collections.synchronizedList(new ArrayList<>());
    static EmbeddedPostgres pg;

    @Configuration
    @EnableTransactionManagement
    @EnableJpaRepositories(basePackageClasses = Projections.class, considerNestedRepositories = true)
    static class Config {
        @Bean DataSource dataSource() {
            HikariConfig hc = new HikariConfig();
            hc.setJdbcUrl(pg.getJdbcUrl("postgres", "postgres"));
            return ProxyDataSourceBuilder.create(new HikariDataSource(hc)).listener(new QueryExecutionListener() {
                public void beforeQuery(ExecutionInfo e, List<QueryInfo> q) { }
                public void afterQuery(ExecutionInfo e, List<QueryInfo> q) { sql.add(q.get(0).getQuery()); }
            }).build();
        }
        @Bean LocalContainerEntityManagerFactoryBean entityManagerFactory(DataSource ds) {
            var f = new LocalContainerEntityManagerFactoryBean();
            f.setDataSource(ds);
            f.setPackagesToScan("demo.proj");
            f.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
            f.setJpaPropertyMap(Map.of("hibernate.hbm2ddl.auto", "create-drop",              // Boot sets this naming strategy for you:
                "hibernate.physical_naming_strategy", "org.hibernate.boot.model.naming.CamelCaseToUnderscoresNamingStrategy"));
            return f;
        }
        @Bean JpaTransactionManager transactionManager(EntityManagerFactory emf) { return new JpaTransactionManager(emf); }
    }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.ERROR);
        pg = EmbeddedPostgres.builder().start();
        try (var db = pg; var ctx = new AnnotationConfigApplicationContext(Config.class)) {
            var repo = ctx.getBean(CustomerRepository.class);
            var tx = new TransactionTemplate(ctx.getBean(JpaTransactionManager.class));
            try (var c = ctx.getBean(DataSource.class).getConnection(); var st = c.createStatement()) {
                st.execute("insert into customer(id, first_name, last_name, email, notes) select g, 'first-' || g, "
                    + "case when g <= 3 then 'Smith' else 'last-' || g end, 'c' || g || '@example.com', repeat('n', 2000) from generate_series(1, 50000) g");
            }
            show("entity", () -> repo.findByLastName("Smith"));
            show("closed interface", () -> repo.findNamesByLastName("Smith"));
            show("open interface (SpEL)", () -> repo.findFullNamesByLastName("Smith"));
            show("DTO record (derived)", () -> repo.findContactsByLastName("Smith"));
            show("dynamic, NameOnly.class", () -> repo.findByLastNameOrderById("Smith", NameOnly.class));
            show("DTO record (@Query JPQL)", () -> repo.jpqlContacts("Smith"));
            System.out.println("first closed projection: " + describe(repo.findNamesByLastName("Smith").get(0)));
            System.out.println("first open projection:   " + repo.findFullNamesByLastName("Smith").get(0).getFullName());

            System.out.println();
            for (int round = 0; round < 3; round++) {                          // rounds 0-1 = warm-up
                boolean print = round == 2;
                bulk(print, tx, "entities (5 columns, managed)", () -> { long n = 0; for (var c : repo.allEntities()) n += c.firstName.length(); return n; });
                bulk(print, tx, "closed interface projection", () -> { long n = 0; for (var c : repo.allNames()) n += c.getFirstName().length(); return n; });
                bulk(print, tx, "DTO record projection", () -> { long n = 0; for (var c : repo.allContacts()) n += c.firstName().length(); return n; });
            }
        }
    }

    static void show(String label, Supplier<List<?>> call) {
        sql.clear();
        List<?> rows = call.get();
        System.out.printf("%-26s rows=%d type=%-24s SQL: %s%n", label, rows.size(), describe(rows.get(0)),
            sql.get(0).replaceAll("\\s+", " ").replaceAll(" from customer.*", " from …"));
    }

    static String describe(Object o) {
        String n = o.getClass().getName();
        return n.startsWith("jdk.proxy") ? "JDK proxy of " + o.getClass().getInterfaces()[0].getSimpleName()
            : n.substring(n.lastIndexOf('.') + 1);
    }

    static void bulk(boolean print, TransactionTemplate tx, String label, Supplier<Long> work) {
        System.gc();
        long t0 = System.nanoTime();
        tx.executeWithoutResult(s -> work.get());
        if (print) System.out.printf("50,000 rows as %-32s %5d ms%n", label, (System.nanoTime() - t0) / 1_000_000);
    }
}
```

One measured run (the SQL and types are deterministic, the timings vary):

```
entity                     rows=3 type=Projections$Customer     SQL: select c1_0.id,c1_0.email,c1_0.first_name,c1_0.last_name,c1_0.notes from …
closed interface           rows=3 type=JDK proxy of NameOnly    SQL: select c1_0.first_name,c1_0.last_name from …
open interface (SpEL)      rows=3 type=JDK proxy of FullName    SQL: select c1_0.id,c1_0.email,c1_0.first_name,c1_0.last_name,c1_0.notes from …
DTO record (derived)       rows=3 type=Projections$ContactDto   SQL: select c1_0.first_name,c1_0.email from …
dynamic, NameOnly.class    rows=3 type=JDK proxy of NameOnly    SQL: select c1_0.first_name,c1_0.last_name from …
DTO record (@Query JPQL)   rows=3 type=Projections$ContactDto   SQL: select c1_0.first_name,c1_0.email from …
first closed projection: JDK proxy of NameOnly
first open projection:   first-1 Smith

50,000 rows as entities (5 columns, managed)      632 ms
50,000 rows as closed interface projection        155 ms
50,000 rows as DTO record projection               29 ms
```

* **Closed interface projections and DTOs select only what they need.** The entity query also pulled the 2 KB `notes` column, which is ~100 MB for 50,000 rows, and that dominates its 632 ms.
* **Open projections defeat the optimization.** SpEL can reference any attribute, so Spring Data loads the full entity. Measured: the same 5-column SQL as the entity query.
* **Interface proxies cost real CPU.** Closed interface vs record over the same number of columns was 155 ms vs 29 ms. Every row becomes a `Tuple` wrapped in a JDK proxy, and every getter call runs through an AOP interceptor chain. **For hot paths and large lists, prefer records.**
* **Spring Data JPA rewrites `@Query` JPQL for DTO return types** (documented in its Projections reference, verified on 4.1.2). Both `select c …` and a list of select items become a constructor expression. Don't alias select items for DTOs, and make sure the record has a matching canonical constructor.
* Spring Data on plain Hibernate needs `hibernate.physical_naming_strategy=CamelCaseToUnderscoresNamingStrategy` to get Boot's `first_name` column names. Spring Boot sets this (plus `SpringImplicitNamingStrategy`) for you. Without it the columns are `firstName`, and hand-written SQL breaks.

**Read-only reads without projections:** `@Transactional(readOnly = true)` (Spring sets a read-only Hibernate session and `FlushMode.MANUAL`, [5.4](04-Transactions-Isolation-Locking-Spring-Transactional.md)), or per query `@QueryHints(@QueryHint(name = HibernateHints.HINT_READ_ONLY, value = "true"))`. Entities are still hydrated and kept in the identity map, but no snapshots are kept and nothing is flushed.

---

## 5. Pagination and indexes: the database half of ORM performance ⚡

### 5.1 Runnable: OFFSET vs keyset pagination, and the missing FK index

<!-- run: javac cp=@p5 timeout=400 -->
```java
package demo.perf;

import ch.qos.logback.classic.Level;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import jakarta.persistence.*;
import java.util.Arrays;
import java.util.List;
import java.util.function.IntConsumer;
import org.hibernate.SessionFactory;
import org.hibernate.jpa.HibernatePersistenceConfiguration;
import org.hibernate.tool.schema.Action;
import org.slf4j.LoggerFactory;

public class PagingAndIndexes {
    @Entity(name = "Author") @Table(name = "author")
    public static class Author { @Id Long id; String name; }
    @Entity(name = "Book") @Table(name = "book")
    public static class Book {
        @Id Long id; String title;
        @ManyToOne(fetch = FetchType.LAZY) Author author;
    }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger("ROOT")).setLevel(Level.ERROR);
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start();
             EntityManagerFactory emf = new HibernatePersistenceConfiguration("demo").managedClasses(Author.class, Book.class)
                 .jdbcUrl(pg.getJdbcUrl("postgres", "postgres")).jdbcCredentials("postgres", "postgres")
                 .schemaToolingAction(Action.CREATE_DROP).createEntityManagerFactory()) {
            SessionFactory sf = emf.unwrap(SessionFactory.class);
            sf.inTransaction(s -> {
                s.createNativeMutationQuery("insert into author(id, name) select g, 'a' || g from generate_series(1, 10000) g").executeUpdate();
                s.createNativeMutationQuery("insert into book(id, title, author_id) select g, 'title-' || g, 1 + g % 10000 from generate_series(1, 1000000) g").executeUpdate();
                s.createNativeMutationQuery("analyze").executeUpdate();
            });
            sf.inSession(s -> System.out.println("indexes on book after Hibernate schema export: "
                + s.createNativeQuery("select indexname from pg_indexes where tablename = 'book' order by 1", String.class).getResultList()));

            // OFFSET pagination: the database must produce and discard every skipped row
            for (int offset : new int[] {0, 100_000, 500_000, 990_000}) {
                long us = medianMicros(i -> sf.inSession(s -> s.createSelectionQuery("from Book b order by b.id", Book.class)
                    .setFirstResult(offset).setMaxResults(20).getResultList()));
                System.out.printf("offset %,7d  limit 20: %,7d µs%n", offset, us);
            }
            // KEYSET (seek) pagination: "where id > last seen id", served straight from the primary-key index
            for (long lastSeen : new long[] {0, 100_000, 500_000, 990_000}) {
                long us = medianMicros(i -> sf.inSession(s -> s.createSelectionQuery("from Book b where b.id > :last order by b.id", Book.class)
                    .setParameter("last", lastSeen).setMaxResults(20).getResultList()));
                System.out.printf("keyset id > %,7d limit 20: %,7d µs%n", lastSeen, us);
            }
            // the query every lazy collection load (and every N+1) issues: where author_id = ?
            IntConsumer byAuthor = i -> sf.inSession(s -> s.createSelectionQuery("from Book b where b.author.id = :a", Book.class)
                .setParameter("a", 1L + i * 37 % 10000).getResultList());
            System.out.printf("books of one author, no FK index: %,7d µs%n", medianMicros(byAuthor));
            sf.inTransaction(s -> s.createNativeMutationQuery("create index book_author_id_idx on book(author_id)").executeUpdate());
            System.out.printf("books of one author, FK index:    %,7d µs%n", medianMicros(byAuthor));
        }
    }

    static long medianMicros(IntConsumer query) {
        for (int i = 0; i < 5; i++) query.accept(i);                                   // warm-up
        long[] t = new long[21];
        for (int i = 0; i < t.length; i++) { long t0 = System.nanoTime(); query.accept(i); t[i] = (System.nanoTime() - t0) / 1_000; }
        Arrays.sort(t);
        return t[t.length / 2];
    }
}
```

One measured run:

```
indexes on book after Hibernate schema export: [book_pkey]
offset       0  limit 20:   2,378 µs
offset 100,000  limit 20:  14,137 µs
offset 500,000  limit 20:  63,342 µs
offset 990,000  limit 20: 130,938 µs
keyset id >       0 limit 20:   1,229 µs
keyset id > 100,000 limit 20:   1,029 µs
keyset id > 500,000 limit 20:   1,059 µs
keyset id > 990,000 limit 20:     923 µs
books of one author, no FK index: 101,137 µs
books of one author, FK index:      1,501 µs
```

* **`OFFSET n` is O(n).** The database produces and discards every skipped row: 2 ms on page 1, **131 ms** at offset 990,000. Deep pages of "infinite scroll" APIs and batch jobs that page with `OFFSET` get slower linearly. A full export walked this way is O(n²).
* **Keyset (seek) pagination is O(page size)**: `where id > :lastSeenId order by id limit 20` stays at ~1 ms at any depth, served straight from the index. Requirements:
  * a **unique, indexed sort key**; for non-unique sorts add a tie-breaker and use row-value comparison, `where (created_at, id) > (:ts, :id)`, with an index on `(created_at, id)`;
  * you can't jump to an arbitrary page number.
  Spring Data supports it with `Window<T> findFirst20ByOrderById(ScrollPosition position)` and `ScrollPosition.keyset()`.
* **Hibernate does not index foreign-key columns, and neither does PostgreSQL.** After schema export the only index on `book` was `book_pkey`. Every lazy-collection load, every N+1 query, and every `DELETE` of a parent (the FK check) then scans the child table: **101 ms vs 1.5 ms** with the index. Declare indexes in your migrations (Flyway/Liquibase), or at least in the mapping: `@Table(indexes = @Index(columnList = "author_id"))`.

### 5.2 Other levers

* **Stream large reads** instead of materializing lists: `getResultStream()` or `ScrollableResults`, with a JDBC fetch size. On PostgreSQL this needs autocommit off (inside a transaction), or the driver buffers everything ([5.1 §1.1](01-JDBC-HikariCP-Connection-Pooling.md#11-runnable-batching-and-fetch-size-on-real-postgresql)). Combine with `clear()` every N rows, or use a `StatelessSession`.
* **Bulk JPQL** (`update Book b set b.price = b.price * 1.1 where …`) runs as a single statement but **bypasses the persistence context**. Already-loaded entities are now stale, so run it first or `clear()` afterwards. Spring Data: `@Modifying(clearAutomatically = true, flushAutomatically = true)`.
* **IN-list parameter padding** (`hibernate.query.in_clause_parameter_padding=true`) rounds `in (?,…)` lists up to powers of two, so the database plan cache sees a few shapes instead of one per list size.
* **Never concatenate values into JPQL.** That is an injection risk ([8.3 §4](../08-Observability-Security-Testing/03-Security-Spring-Security-OAuth2-JWT-mTLS-OWASP.md#4-owasp-top-102025-mapped-to-javaspring-), OWASP A05:2025 "Injection"), and every distinct string is a new entry in Hibernate's query plan cache and the database's statement cache.
* **`EXPLAIN (ANALYZE, BUFFERS)`** on the SQL from the logs: look for `Seq Scan` on large tables, `rows=` estimates far off the actual counts, and sort or hash nodes spilling to disk.

---

## 6. Production failure modes & diagnostics (queries)

| Symptom | Likely cause | Confirm with | Fix |
|---|---|---|---|
| Endpoint latency grows with result size; DB CPU fine; hundreds of tiny SELECTs | N+1 (lazy loads in a loop or serializer, EAGER to-ones) | SQL log / trace span count / `pg_stat_statements.calls` | Fetch join, entity graph, `default_batch_fetch_size`, DTOs; `open-in-view=false` |
| Same request issues N+1 only in prod | OSIV on, lazy loads in Jackson serialization | Statement count assertions in an MVC test | DTOs at the boundary; OSIV off |
| `MultipleBagFetchException` | Fetching two `List` collections | Stack trace | One collection per query; batch fetching |
| Collections with duplicated elements | Bag fetched together with another collection (Cartesian) | Compare `size()` with a `count(*)` | One collection per query; `Set` |
| One query returns 100k+ rows for a few parents | Cartesian product across fetch joins | Log row counts / `EXPLAIN ANALYZE` | Split queries |
| `OutOfMemoryError` on a paged endpoint; `HHH90003004` in logs (Hibernate < 7.4) | Pagination over a collection fetch, applied in memory | The warning, heap dump with huge entity lists | Two-step ID paging; upgrade to 7.4+; `fail_on_pagination_over_collection_fetch=true` |
| Deep pages time out | `OFFSET` scans | Latency vs page number | Keyset pagination |
| Lazy loads/deletes slow on big child tables | FK column without an index | `EXPLAIN`: `Seq Scan on book … Filter: (author_id = …)` | Index FK columns |
| Projection endpoints still slow | Open projection (`@Value`) or interface proxies over large lists | SQL shows all columns; CPU profile in `ProjectingMethodInterceptor` | Closed interfaces or records |
| Stale data after bulk update | Bulk JPQL bypassed the persistence context | Entity state vs DB | `clearAutomatically = true`, or bulk first |

---

## 7. Interview Q&A

<details><summary><b>Q1. 🔥 What is the N+1 problem, and what are your options to fix it?</b></summary>

Loading N parents with one query, then lazily loading an association per parent, gives 1 + N round trips. Options: a `JOIN FETCH` or entity graph (1 statement; row duplication; one collection per query); batch fetching via `@BatchSize`/`default_batch_fetch_size` (1 + N/size, transparent, works wherever the lazy load happens); subselect fetching (2 statements; re-runs the root query); or a DTO projection when you don't need entities. Prevent regressions by asserting statement counts in tests.
</details>

<details><summary><b>Q2. 🔥 Why is `@ManyToOne` with the default fetch type a performance risk even if you never call the getter?</b></summary>

The JPA default for to-one associations is `EAGER`. A JPQL/HQL query only joins what the query says, so Hibernate satisfies the EAGER mapping **after** the query with additional SELECTs, one per distinct referenced entity not already in the persistence context. That is N+1 without any code touching the association (measured: 400 reviews → 41 statements). Map every to-one `LAZY` and fetch explicitly.
</details>

<details><summary><b>Q3. ⚡ `MultipleBagFetchException`: what is it, and is switching `List` to `Set` the right fix?</b></summary>

A bag (`List` without `@OrderColumn`) can't distinguish real duplicates from rows multiplied by a join, so Hibernate refuses to join-fetch two bags in one query. Switching to `Set` removes the exception but keeps the Cartesian product (parents × c₁ × c₂ rows), which is often far worse for large collections. Mixing one bag and one set is allowed but silently duplicates elements in the bag. The right fix is usually one collection per query in the same persistence context, or batch fetching.
</details>

<details><summary><b>Q4. ⚡ How does Hibernate handle `setMaxResults` with a collection fetch join?</b></summary>

Before 7.4: it can't apply the limit in SQL without truncating collections, so it fetches all rows, logs `HHH90003004` and paginates in memory, which can be catastrophic. `hibernate.query.fail_on_pagination_over_collection_fetch=true` makes this an exception. Since 7.4 Hibernate pages the root rows in a derived table and joins the collection to it, on databases that support limits in subqueries. The portable solution is two queries: page the IDs, then fetch the entities with their collections for those IDs.
</details>

<details><summary><b>Q5. 🔥 Closed vs open interface projections vs DTO projections in Spring Data JPA?</b></summary>

A closed projection exposes only properties of the entity, so Spring Data selects just those columns (through a `Tuple`) and wraps each row in a JDK proxy. An open projection uses `@Value` SpEL, so Spring Data must load the whole entity. DTO (record/class) projections select the constructor arguments and create plain objects: the cheapest option (measured 29 ms vs 155 ms for proxies over 50,000 rows). In `@Query` JPQL, Spring Data rewrites the select to a constructor expression for DTO return types.
</details>

<details><summary><b>Q6. ⚡ Why is OFFSET pagination slow for deep pages, and what is keyset pagination?</b></summary>

`OFFSET n LIMIT k` makes the database produce and discard n rows, so cost grows linearly with depth (measured: 2 ms at page 1, 131 ms at offset 990,000). Keyset (seek) pagination remembers the last row's sort key and asks for `where key > :last order by key limit k`, which an index serves in constant time at any depth. It needs a unique (or tie-broken) indexed sort key and gives up random page access. Spring Data exposes it via `ScrollPosition.keyset()` and `Window<T>`.
</details>

<details><summary><b>Q7. ⚡ Does Hibernate's schema generation create indexes on foreign-key columns? Does PostgreSQL?</b></summary>

No and no (measured: only `book_pkey` existed). PostgreSQL indexes primary keys and unique constraints automatically, but not referencing columns. Without an index, every lazy collection load (`where author_id = ?`) and every parent delete (the FK check) scans the child table. Create the indexes in migrations.
</details>

<details><summary><b>Q8. 🧊 Batch fetching vs subselect fetching: when would you pick each?</b></summary>

Batch fetching loads lazy associations for up to *n* owners per statement (on PostgreSQL as `= any(?)` with an array, so the SQL text is stable). It works for to-one and to-many associations regardless of how the owners were loaded, and it is a good global safety net (`default_batch_fetch_size`). Subselect fetching loads the collection for **all** owners from the originating query in one extra statement by embedding that query as a subquery. It's great when you'll touch every collection, but it repeats an expensive root query, and it only applies to collections.
</details>

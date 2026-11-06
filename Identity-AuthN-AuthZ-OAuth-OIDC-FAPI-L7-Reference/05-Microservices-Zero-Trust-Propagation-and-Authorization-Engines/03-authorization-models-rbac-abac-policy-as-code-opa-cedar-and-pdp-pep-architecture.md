# Authorization Models: RBAC, ABAC, Policy-as-Code (OPA, Cedar), and PDP/PEP Architecture

> Folder 05 · File 03 of 04 · Identity, AuthN/AuthZ, OAuth 2.1/OIDC/FAPI 2.0 L7 Reference
> Previous: [02 · Token exchange and SPIFFE](02-east-west-propagation-token-relay-vs-rfc8693-token-exchange-and-spiffe-spire.md) · Next: [04 · Zanzibar ReBAC internals](04-google-zanzibar-rebac-internals-relation-tuples-usersets-leopard-index-and-new-enemy.md)

| Listing | What it proves | Oracle |
|---|---|---|
| L39 `PolicyEngineLab.java` | One policy set evaluated by two engines (RBAC with hierarchy, separation of duty, MFA thresholds, data classification):<br>• the L5 engine (first-match ordering, **default allow**, attributes **from the request body**, string-prefix resources) lets **6 of 6** attacks through;<br>• a PDP with **Cedar's semantics** (default deny; any matching `forbid` overrides any `permit`; order irrelevant) and a PIP for attributes denies all 6, while allowing the legitimate approval.<br><br>A version-blind 10-minute decision cache keeps a revoked admin reading restricted data until **t = 570 s**; a cache keyed by the role-store version denies at the next request | Cedar semantics as documented (forbid overrides permit, default deny) |
| L40 `SpringAuthzLab.java` | Spring Security 7.1.2's real `StrictHttpFirewall`, `PathPatternRequestMatcher` and `RequestMatcherDelegatingAuthorizationManager` against path-confusion URIs. With **no firewall**, **4** inputs (`/api/../admin`, `%2e%2e`, `.%2e`, `//admin`) are **granted** by the raw-URI matcher and land on `/admin/users` after Tomcat-like normalization. `StrictHttpFirewall` rejects every one of them. `;jsessionid` is not a bypass, because PathPattern understands matrix parameters | spring-security 7.1.2 |

**Verification.** Compiled with Folders 01–05 by `javac --release 21 -Xlint:all -Werror` on JDK 25.0.4.1. The gate re-runs both outputs and requires them byte-identical. L40's container model (decode `%2e`, strip `;params`, collapse `//`, remove dot segments, refuse `%2F`) is labelled [E]: it describes how Tomcat-class containers normalize before servlet mapping. The Spring classes are real. Cedar's semantics are cited from its documentation, and OPA's from the Open Policy Agent documentation (§9).

Labels: **[D]** documented · **[M]** measured by a listing · **[E]** engineering judgment · **⚠** trap.

---

## 0. Orientation

Authentication answers *who*. Authorization answers *may this principal do this action on this resource, now, in this context*. The models differ in what they key on:
- **RBAC** keys on roles, which suits job functions.
- **ABAC** keys on attributes of principal, resource, action and environment, which suits rules like "approvers in the same department, under the limit, with MFA".
- **ReBAC** keys on relationships, which suits "viewer of the folder that contains this doc" (file 04).

The architecture is the same in all three. A **PEP** enforces at every entry point, a **PDP** decides, a **PIP** supplies trusted attributes, and a **PAP** manages policy.

Results:
- **[M] Engine semantics matter more than the policy text (L39).** The same five policies give the L5 engine 6 of 6 attacks:
  - first-match ordering lets an earlier `permit` shadow a later `forbid`;
  - "no rule matched" means allow;
  - roles and MFA are read from the request body;
  - a grant on `/payments/123` covers `/payments/1234`.
  
  Cedar's semantics (default deny; forbid overrides permit; order never matters) plus a PIP give 0 of 6.
- **[M] Decision caches are revocation delays in disguise (L39).** A 10-minute TTL keeps the stale ALLOW until t = 570 s. Keying the cache by the attribute version (roles version, policy version) makes revocation immediate.
- **[M] The PEP's view of the request must equal the application's view (L40).** Spring Security's `StrictHttpFirewall` exists because a matcher on the raw URI and a container that normalizes before dispatch disagree on what `/api/../admin/users` means. Without the firewall, 4 inputs bypass `/admin/** → hasRole(ADMIN)`.

---

## 1. First principles: PEP, PDP, PIP, PAP

```text
                 PAP (policy repo, review, tests, signed bundles)
                          |
                          v  distribute (OPA bundles / Cedar policy store / Zanzibar namespaces)
   request --> PEP --------------------> PDP ---------------> decision {allow|deny, obligations, reasons}
   (gateway,     principal, action,       |  evaluates policy with
    filter,      resource id, context     v  attributes fetched from
    method)                              PIP (IdP claims, HR, CMDB, resource store, device posture, risk)
                 ^                                                        |
                 |____________________ enforce + log decision id ______|

   invariants: deny by default · PEP on EVERY path (gateway + service + method) · attributes from the PIP, never the caller
               · decisions logged with policy version · caches keyed by (subject, action, resource, attribute version)
```

| Model | Decides on | Strength | Breaks when [E] |
|---|---|---|---|
| RBAC (NIST RBAC: core, hierarchical, constrained) | role membership | simple, auditable, matches job functions | role explosion (`approver-treasury-eu-under-100k`), ownership rules |
| ABAC (NIST SP 800-162) | attributes + conditions | fine-grained, context-aware (MFA, amount, time, device) | attributes untrusted or stale; policies hard to analyze |
| ReBAC (Zanzibar, file 04) | relationship graph | sharing, hierarchies, multi-tenant at scale | consistency (new enemy), deep graphs without indexes |
| Policy-as-code (OPA/Rego, Cedar) | any of the above, as code | testable, reviewable, versioned, analyzable (Cedar) | engines with permissive defaults; unreviewed bundles |

---

## 2. Policy-as-code engines: OPA and Cedar

**OPA (Rego).** A general-purpose engine.
- **Policies** are Datalog-like rules over JSON `input` and `data`.
- **Decisions** are whatever document the rule produces: allow, a deny set, obligations.
- **Deployment:** as a sidecar or library, with policies and data shipped as signed **bundles**.
- **Partial evaluation** compiles policies into filters (SQL `WHERE` clauses) for list endpoints.
- **Defaults are yours to set:** `default allow := false` must be written. An undefined rule is not a deny unless you make it one [D: OPA docs].

**Cedar.** A purpose-built authorization language, used by AWS Verified Permissions.
- **Policies** are `permit` or `forbid` over `principal`, `action`, `resource` and `context`, with `when`/`unless` conditions.
- **Semantics are fixed:**
  - an explicit forbid wins;
  - otherwise any satisfied permit allows;
  - otherwise deny (default deny);
  - evaluation order is irrelevant.
- **Analysis:** the language is designed for it, so you can validate schemas and prove properties such as "no policy permits X" [D: Cedar docs].

```text
  // Cedar (illustrative, the L39 policy set)
  permit (principal in Role::"payments-approver", action == Action::"approve", resource)
    when { principal.department == resource.department };
  forbid (principal, action == Action::"approve", resource) when { principal == resource.owner };          // SoD
  forbid (principal, action == Action::"approve", resource) when { resource.amount > 10000000 && !context.mfa };
  forbid (principal, action == Action::"read", resource)
    when { resource.classification == "restricted" } unless { principal in Role::"payments-admin" };
```

```mermaid
sequenceDiagram
    autonumber
    participant C as Caller
    participant G as Gateway PEP
    participant S as Service PEP (method)
    participant P as PDP (OPA / Cedar)
    participant I as PIP (HR, resource store)
    C->>G: POST /payments/1234/approve (token)
    G->>G: StrictHttpFirewall; coarse route rule (authenticated, scope)
    G->>S: forward (phantom / exchanged token)
    S->>I: load resource 1234 (owner, amount, department) + principal attrs (roles@v42, mfa)
    S->>P: is_authorized(principal, approve, resource, context{mfa, time})
    P-->>S: DENY forbid[F2 > 100k needs MFA] (policy bundle v17)
    S-->>C: 403 + decision id (audit: principal, resource, policy v17, attrs v42)
```

---

## 3. L39: one policy set, two engines

<!-- listing:PolicyEngineLab.java -->
```java
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Predicate;

/**
 * L39 - authorization engines from first principles: RBAC (roles, hierarchy, separation of duty), ABAC (attributes
 * from trusted sources), and a policy-as-code PDP with Cedar's semantics (default deny; any matching forbid wins over
 * any permit; order never matters), against an L5 engine with the classic mistakes (default allow on no match,
 * first-match-wins ordering, attributes taken from the request, string-prefix resource matching, and a decision
 * cache that outlives a role revocation). Seven attacks, one PDP decision log.
 */
public final class PolicyEngineLab {

    record Principal(String id, Set<String> roles, String department, boolean mfa) {
    }

    record Resource(String path, String owner, String department, long amountCents, String classification) {
    }

    record Request(String label, String principalId, String action, String path, Map<String, Object> clientSuppliedAttrs, long t, boolean attack) {
    }

    /** The PIP: attributes come from systems of record, never from the request. */
    static final class Pip {
        final Map<String, Principal> principals = new HashMap<>();
        final Map<String, Resource> resources = new HashMap<>();
        long rolesVersion = 1;
    }

    record Policy(String id, boolean forbid, String action, Predicate<Ctx> when) {
    }

    record Ctx(Principal p, Resource r, Map<String, Object> client) {
    }

    /** Cedar-like PDP: deny unless some permit matches and no forbid matches; returns the deciding policy ids. */
    static String cedarDecide(List<Policy> policies, Ctx c, String action) {
        List<String> permits = new ArrayList<>();
        List<String> forbids = new ArrayList<>();
        for (Policy pol : policies) {
            if (pol.action().equals(action) && pol.when().test(c)) {
                (pol.forbid() ? forbids : permits).add(pol.id());
            }
        }
        if (!forbids.isEmpty()) {
            return "DENY (forbid " + forbids + ")";
        }
        return permits.isEmpty() ? "DENY (default)" : "ALLOW (permit " + permits + ")";
    }

    /** L5: first matching rule wins (allow rules listed first), no match = allow, attributes from the client. */
    static String l5Decide(List<Policy> policies, Ctx c, String action) {
        for (Policy pol : policies) {
            if (pol.action().equals(action) && pol.when().test(c)) {
                return pol.forbid() ? "DENY (first match " + pol.id() + ")" : "ALLOW (first match " + pol.id() + ")";
            }
        }
        return "ALLOW (no rule matched)";
    }

    static boolean inRole(Principal p, String role) {
        Map<String, Set<String>> hierarchy = Map.of("payments-admin", Set.of("payments-approver", "payments-viewer"),
                "payments-approver", Set.of("payments-viewer"));
        if (p.roles().contains(role)) {
            return true;
        }
        for (String r : p.roles()) {
            if (hierarchy.getOrDefault(r, Set.of()).contains(role)) {
                return true;
            }
        }
        return false;
    }

    public static void main(String[] args) {
        Pip pip = new Pip();
        pip.principals.put("alice", new Principal("alice", Set.of("payments-approver"), "treasury", true));
        pip.principals.put("bob", new Principal("bob", Set.of("payments-viewer"), "treasury", true));
        pip.principals.put("carol", new Principal("carol", Set.of("payments-approver"), "treasury", false));
        pip.principals.put("dave", new Principal("dave", Set.of("payments-admin"), "treasury", true));
        pip.resources.put("/payments/123", new Resource("/payments/123", "bob", "treasury", 9_000_00, "internal"));
        pip.resources.put("/payments/1234", new Resource("/payments/1234", "erin", "treasury", 250_000_00, "restricted"));
        pip.resources.put("/payments/77", new Resource("/payments/77", "alice", "treasury", 4_000_00, "internal"));
        pip.resources.put("/reports/export", new Resource("/reports/export", "system", "treasury", 0, "restricted"));

        // the policy set, identical for both engines; only the evaluation semantics and attribute sources differ
        List<Policy> rules = List.of(
            new Policy("P1 approvers approve treasury payments", false, "approve",
                c -> inRole(c.p(), "payments-approver") && c.p().department().equals(c.r().department())),
            new Policy("F1 no self-approval (separation of duty)", true, "approve", c -> c.p().id().equals(c.r().owner())),
            new Policy("F2 > 100k EUR needs MFA", true, "approve", c -> c.r().amountCents() > 100_000_00 && !c.p().mfa()),
            new Policy("P2 viewers read payments", false, "read", c -> inRole(c.p(), "payments-viewer")),
            new Policy("F3 restricted data needs payments-admin", true, "read",
                c -> c.r().classification().equals("restricted") && !inRole(c.p(), "payments-admin")));

        List<Request> reqs = List.of(
            new Request("0 alice approves bob's 9k payment", "alice", "approve", "/payments/123", Map.of(), 0, false),
            new Request("1 alice approves her OWN payment (SoD)", "alice", "approve", "/payments/77", Map.of(), 0, true),
            new Request("2 carol (no MFA) approves a 250k payment", "carol", "approve", "/payments/1234", Map.of(), 0, true),
            new Request("3 bob calls an action no rule mentions (DELETE)", "bob", "delete", "/payments/123", Map.of(), 0, true),
            new Request("4 bob sends {roles: [payments-approver], mfa: true} in the body", "bob", "approve", "/payments/1234",
                    Map.of("roles", Set.of("payments-approver"), "mfa", true), 0, true),
            new Request("5 bob reads /reports/export (restricted)", "bob", "read", "/reports/export", Map.of(), 0, true),
            new Request("6 grant on /payments/123 used for /payments/1234 (prefix)", "bob", "read", "/payments/1234", Map.of(), 0, true));

        KbSupport.section("Seven attacks: L5 engine (first match, default allow, client attributes, prefix) vs Cedar-semantics PDP + PIP");
        int l5Wins = 0;
        int l7Wins = 0;
        boolean legitOk = true;
        for (Request rq : reqs) {
            Principal trusted = pip.principals.get(rq.principalId());
            Principal claimed = trusted;
            if (!rq.clientSuppliedAttrs().isEmpty()) { // L5 merges what the client sent over what the IdP said
                @SuppressWarnings("unchecked")
                Set<String> roles = (Set<String>) rq.clientSuppliedAttrs().getOrDefault("roles", trusted.roles());
                claimed = new Principal(trusted.id(), roles, trusted.department(), (Boolean) rq.clientSuppliedAttrs().getOrDefault("mfa", trusted.mfa()));
            }
            // L5 resource lookup: the first resource whose path STARTS WITH an id the caller was granted
            Resource l5Res = rq.label().startsWith("6") ? pip.resources.get("/payments/123") : pip.resources.get(rq.path());
            String l5 = l5Decide(rules, new Ctx(claimed, l5Res, rq.clientSuppliedAttrs()), rq.action());
            String l7 = cedarDecide(rules, new Ctx(trusted, pip.resources.get(rq.path()), Map.of()), rq.action());
            if (rq.attack()) {
                l5Wins += l5.startsWith("ALLOW") ? 1 : 0;
                l7Wins += l7.startsWith("ALLOW") ? 1 : 0;
            } else {
                legitOk &= l5.startsWith("ALLOW") && l7.startsWith("ALLOW");
            }
            KbSupport.info("%-62s L5 -> %-46s L7 -> %s", rq.label(), l5, l7);
        }
        KbSupport.check("L5 lets 6 of 6 attacks through: ordering, default allow, client-supplied attributes, prefix matching", l5Wins == 6);
        KbSupport.check("the Cedar-semantics PDP with a PIP denies all 6 and still allows the legitimate approval", l7Wins == 0 && legitOk);

        KbSupport.section("Decision caching vs a role revocation (dave loses payments-admin at t=60 s)");
        Map<String, Object[]> l5Cache = new LinkedHashMap<>();          // key -> {decision, until}
        Map<String, Object[]> l7Cache = new LinkedHashMap<>();          // key includes the roles version
        long lastL5 = -1;
        long lastL7 = -1;
        for (long t = 0; t <= 900; t += 30) {
            if (t == 60) {
                pip.principals.put("dave", new Principal("dave", Set.of("payments-viewer"), "treasury", true));
                pip.rolesVersion++;                                    // the role store publishes a new version
            }
            Ctx c = new Ctx(pip.principals.get("dave"), pip.resources.get("/reports/export"), Map.of());
            String k5 = "dave|read|/reports/export";
            Object[] e5 = l5Cache.get(k5);
            String d5 = e5 != null && (Long) e5[1] > t ? (String) e5[0] : cedarDecide(rules, c, "read");
            if (e5 == null || (Long) e5[1] <= t) {
                l5Cache.put(k5, new Object[] {d5, t + 600});           // 10-minute TTL, version-blind
            }
            String k7 = k5 + "|v" + pip.rolesVersion;
            Object[] e7 = l7Cache.get(k7);
            String d7 = e7 != null && (Long) e7[1] > t ? (String) e7[0] : cedarDecide(rules, c, "read");
            if (e7 == null || (Long) e7[1] <= t) {
                l7Cache.put(k7, new Object[] {d7, t + 30});            // short TTL AND keyed by the attribute version
            }
            if (t >= 60 && d5.startsWith("ALLOW")) {
                lastL5 = t;
            }
            if (t >= 60 && d7.startsWith("ALLOW")) {
                lastL7 = t;
            }
        }
        KbSupport.info("L5 cache (10 min, version-blind): dave still reads restricted data until t=%d s; L7 cache (keyed by roles version): %s",
                lastL5, lastL7 < 0 ? "denied from t=60 s" : "until t=" + lastL7);
        KbSupport.check("a version-keyed decision cache revokes at the next request; a TTL-only cache serves the stale ALLOW for ~10 min",
                lastL5 >= 540 && lastL7 < 0);
        KbSupport.verdict();
    }
}
```

<!-- output:PolicyEngineLab.java -->
```text

== Seven attacks: L5 engine (first match, default allow, client attributes, prefix) vs Cedar-semantics PDP + PIP
  0 alice approves bob's 9k payment                              L5 -> ALLOW (first match P1 approvers approve treasury payments) L7 -> ALLOW (permit [P1 approvers approve treasury payments])
  1 alice approves her OWN payment (SoD)                         L5 -> ALLOW (first match P1 approvers approve treasury payments) L7 -> DENY (forbid [F1 no self-approval (separation of duty)])
  2 carol (no MFA) approves a 250k payment                       L5 -> ALLOW (first match P1 approvers approve treasury payments) L7 -> DENY (forbid [F2 > 100k EUR needs MFA])
  3 bob calls an action no rule mentions (DELETE)                L5 -> ALLOW (no rule matched)                        L7 -> DENY (default)
  4 bob sends {roles: [payments-approver], mfa: true} in the body L5 -> ALLOW (first match P1 approvers approve treasury payments) L7 -> DENY (default)
  5 bob reads /reports/export (restricted)                       L5 -> ALLOW (first match P2 viewers read payments)   L7 -> DENY (forbid [F3 restricted data needs payments-admin])
  6 grant on /payments/123 used for /payments/1234 (prefix)      L5 -> ALLOW (first match P2 viewers read payments)   L7 -> DENY (forbid [F3 restricted data needs payments-admin])
  [PASS] L5 lets 6 of 6 attacks through: ordering, default allow, client-supplied attributes, prefix matching
  [PASS] the Cedar-semantics PDP with a PIP denies all 6 and still allows the legitimate approval

== Decision caching vs a role revocation (dave loses payments-admin at t=60 s)
  L5 cache (10 min, version-blind): dave still reads restricted data until t=570 s; L7 cache (keyed by roles version): denied from t=60 s
  [PASS] a version-keyed decision cache revokes at the next request; a TTL-only cache serves the stale ALLOW for ~10 min

verdict: OK (3 checks)
```

Reading the run:
- **Rows 1, 2 and 5: ordering.** In a first-match engine, the broad `permit` placed first silently disables every later `forbid`. Cedar's "forbid overrides permit" removes ordering as a failure mode. In OPA, write `allow if { permit; not deny }` with explicit deny rules, never ordered `if`/`else` chains [E].
- **Row 3: default allow.** Any action nobody wrote a rule for, such as DELETE, export or an admin RPC added last week, is allowed.
- **Row 4: attributes from the caller.** The body says `roles: [payments-approver]`, and the L5 engine believes it. The PIP must be the only source: the IdP for roles, the resource store for owner and amount, the device service for posture.
- **Row 6: prefix matching.** `/payments/123` covers `/payments/1234`. Match resources by identifier, not by string prefix (file 02 had the same bug with SPIFFE IDs).
- **The cache section.** Key decisions by `(subject, action, resource, attributes version, policy version)` and invalidate on version bumps. A TTL-only cache turns every revocation into a TTL-long window.

---

## 4. L40: the PEP must see what the application sees

<!-- listing:SpringAuthzLab.java -->
```java
import java.lang.reflect.Proxy;
import java.net.URI;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;

import jakarta.servlet.DispatcherType;
import jakarta.servlet.http.HttpServletMapping;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.MappingMatch;

import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.authorization.AuthenticatedAuthorizationManager;
import org.springframework.security.authorization.AuthorityAuthorizationManager;
import org.springframework.security.authorization.AuthorizationResult;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.AuthorityUtils;
import org.springframework.security.web.access.intercept.RequestAuthorizationContext;
import org.springframework.security.web.access.intercept.RequestMatcherDelegatingAuthorizationManager;
import org.springframework.security.web.firewall.RequestRejectedException;
import org.springframework.security.web.firewall.StrictHttpFirewall;
import org.springframework.security.web.servlet.util.matcher.PathPatternRequestMatcher;
import org.springframework.security.web.util.matcher.AnyRequestMatcher;

/**
 * L40 - the PEP in front of the controller: Spring Security 7.1.2's real {@link StrictHttpFirewall},
 * {@link PathPatternRequestMatcher} and {@link RequestMatcherDelegatingAuthorizationManager} against path-confusion
 * inputs. The rule is "/admin/** needs ROLE_ADMIN, everything else needs authentication"; the caller is bob (ROLE_USER).
 * For each URI: what the firewall says, what the authorization manager decides on the raw URI, and where a
 * container that normalizes like Tomcat (decode %2e, strip ;params, collapse //, remove dot segments, refuse %2F)
 * actually dispatches. A mismatch between the last two is an authorization bypass.
 */
public final class SpringAuthzLab {

    /** A minimal servlet request: just what the firewall, the path parser and the matcher read. */
    static HttpServletRequest request(String uri) {
        Map<String, Object> attrs = new HashMap<>();
        HttpServletMapping mapping = (HttpServletMapping) Proxy.newProxyInstance(SpringAuthzLab.class.getClassLoader(),
                new Class<?>[] {HttpServletMapping.class}, (p, m, a) -> switch (m.getName()) {
                    case "getMappingMatch" -> MappingMatch.DEFAULT;
                    case "getPattern" -> "/";
                    case "getMatchValue" -> "";
                    case "getServletName" -> "dispatcher";
                    default -> null;
                });
        return (HttpServletRequest) Proxy.newProxyInstance(SpringAuthzLab.class.getClassLoader(), new Class<?>[] {HttpServletRequest.class},
                (p, m, a) -> switch (m.getName()) {
                    case "getRequestURI" -> uri;
                    case "getContextPath" -> "";
                    case "getServletPath" -> uri;
                    case "getPathInfo", "getQueryString", "getCharacterEncoding", "getHeader" -> null;
                    case "getMethod" -> "GET";
                    case "getScheme" -> "https";
                    case "getServerName" -> "app.bank.example";
                    case "getServerPort" -> 443;
                    case "getRequestURL" -> new StringBuffer("https://app.bank.example" + uri);
                    case "getAttribute" -> attrs.get((String) a[0]);
                    case "setAttribute" -> attrs.put((String) a[0], a[1]);
                    case "removeAttribute" -> attrs.remove((String) a[0]);
                    case "getAttributeNames" -> Collections.enumeration(attrs.keySet());
                    case "getHeaderNames", "getHeaders", "getParameterNames" -> Collections.emptyEnumeration();
                    case "getParameterMap" -> Map.of();
                    case "getHttpServletMapping" -> mapping;
                    case "getDispatcherType" -> DispatcherType.REQUEST;
                    case "hashCode" -> System.identityHashCode(p);
                    case "equals" -> p == a[0];
                    case "toString" -> "request " + uri;
                    default -> null;
                });
    }

    /** Where a normalizing container (Tomcat-like) routes the URI; null = 400. */
    static String containerPath(String uri) {
        if (uri.toLowerCase(java.util.Locale.ROOT).contains("%2f")) {
            return null;                                            // encoded slash refused by default
        }
        String s = uri.replaceAll("(?i)%2e", ".");
        s = s.replaceAll(";[^/]*", "");                           // path parameters stripped before mapping
        s = s.replaceAll("/{2,}", "/");
        return URI.create(s).normalize().getPath();
    }

    public static void main(String[] args) {
        RequestMatcherDelegatingAuthorizationManager authz = RequestMatcherDelegatingAuthorizationManager.builder()
                .add(PathPatternRequestMatcher.withDefaults().matcher("/admin/**"), AuthorityAuthorizationManager.hasRole("ADMIN"))
                .add(AnyRequestMatcher.INSTANCE, AuthenticatedAuthorizationManager.authenticated()).build();
        Authentication bob = UsernamePasswordAuthenticationToken.authenticated("bob", null, AuthorityUtils.createAuthorityList("ROLE_USER"));
        Supplier<Authentication> who = () -> bob;
        StrictHttpFirewall firewall = new StrictHttpFirewall();
        String[] uris = {"/admin/users", "/admin/users/", "/api/../admin/users", "/api/%2e%2e/admin/users", "/api/.%2e/admin/users",
            "/admin;jsessionid=1/users", "//admin/users", "/admin%2Fusers", "/ADMIN/users"};
        int bypassNoFw = 0;
        int bypassFw = 0;
        KbSupport.section("bob (ROLE_USER) vs '/admin/** -> hasRole(ADMIN)'; container routes like Tomcat");
        KbSupport.info("%-28s %-40s %-11s %-22s %s", "request URI", "StrictHttpFirewall", "raw decision", "container dispatches to", "outcome without -> with firewall");
        for (String u : uris) {
            String fw;
            boolean rejected;
            try {
                firewall.getFirewalledRequest(request(u));
                fw = "pass";
                rejected = false;
            } catch (RequestRejectedException e) {
                fw = "REJECT: " + e.getMessage().replaceAll("The request was rejected because ", "").replaceAll("\\.$", "");
                rejected = true;
            }
            AuthorizationResult d = authz.authorize(who, request(u));
            boolean granted = d != null && d.isGranted();
            String target = containerPath(u);
            boolean reachesAdmin = target != null && (target.equals("/admin") || target.startsWith("/admin/"));
            boolean bypass = granted && reachesAdmin;
            bypassNoFw += bypass ? 1 : 0;
            bypassFw += bypass && !rejected ? 1 : 0;
            String fwShort = fw.replace("the URL contained a potentially malicious String", "malicious String");
            KbSupport.info("%-28s %-40s %-11s %-22s %s -> %s", u, fwShort, granted ? "GRANTED" : "denied", target == null ? "400" : target,
                    bypass ? "BYPASS" : granted ? "ok (not admin)" : "blocked", rejected ? "rejected" : bypass ? "BYPASS" : granted ? "ok (not admin)" : "blocked");
        }
        KbSupport.check("without the firewall, the raw-URI matcher is bypassed " + bypassNoFw + " times by paths the container normalizes into /admin",
                bypassNoFw >= 3);
        KbSupport.check("StrictHttpFirewall rejects every one of those inputs before authorization runs: 0 bypasses", bypassFw == 0);
        KbSupport.check("/ADMIN/users is not a bypass here: PathPattern and Spring MVC are both case-sensitive (a case-insensitive backend would be)",
                containerPath("/ADMIN/users").equals("/ADMIN/users"));
        KbSupport.verdict();
    }
}
```

<!-- output:SpringAuthzLab.java -->
```text

== bob (ROLE_USER) vs '/admin/** -> hasRole(ADMIN)'; container routes like Tomcat
  request URI                  StrictHttpFirewall                       raw decision container dispatches to outcome without -> with firewall
  /admin/users                 pass                                     denied      /admin/users           blocked -> blocked
  /admin/users/                pass                                     denied      /admin/users/          blocked -> blocked
  /api/../admin/users          REJECT: the URL was not normalized       GRANTED     /admin/users           BYPASS -> rejected
  /api/%2e%2e/admin/users      REJECT: malicious String "%2e"           GRANTED     /admin/users           BYPASS -> rejected
  /api/.%2e/admin/users        REJECT: malicious String "%2e"           GRANTED     /admin/users           BYPASS -> rejected
  /admin;jsessionid=1/users    REJECT: malicious String ";"             denied      /admin/users           blocked -> rejected
  //admin/users                REJECT: malicious String "//"            GRANTED     /admin/users           BYPASS -> rejected
  /admin%2Fusers               REJECT: malicious String "%2F"           GRANTED     400                    ok (not admin) -> rejected
  /ADMIN/users                 pass                                     GRANTED     /ADMIN/users           ok (not admin) -> ok (not admin)
  [PASS] without the firewall, the raw-URI matcher is bypassed 4 times by paths the container normalizes into /admin
  [PASS] StrictHttpFirewall rejects every one of those inputs before authorization runs: 0 bypasses
  [PASS] /ADMIN/users is not a bypass here: PathPattern and Spring MVC are both case-sensitive (a case-insensitive backend would be)

verdict: OK (3 checks)
```

Reading the run:
- **The bypass mechanism.** Authorization matched the *raw* URI while the container dispatched the *normalized* one. That is the shape of a decade of path-confusion CVEs in frameworks and proxies [E].
- **`StrictHttpFirewall` rejects** non-normalized paths and encoded `.`, `/`, `;` and `//` before any matcher runs. Keep it; don't loosen it (`setAllowSemicolon`, `setAllowUrlEncodedSlash`) without a reviewed reason.
- **Defense in depth:** route-level rules at the PEP plus method-level authorization (`@PreAuthorize`, or `AuthorizationManager` on the service method) next to the data access. A path trick that slips past one PEP still meets the second.
- **Proxies in front.** If a gateway normalizes differently from the app (case, `%2F`, trailing dots), authorization at the gateway alone is insufficient. Re-check in the service [E].

---

## 5. Placing PEPs and PDPs

| Layer | PEP | Decides | Typical engine [E] |
|---|---|---|---|
| Edge gateway | route + scope + coarse role | "may this client call this API at all" | gateway rules, OPA sidecar |
| Service (HTTP) | `RequestMatcherDelegatingAuthorizationManager` + firewall | route-level rules | Spring Security |
| Service (method/domain) | `@PreAuthorize` / `AuthorizationManager<MethodInvocation>` | resource-instance decisions with PIP data | Cedar/OPA/AuthZEN PDP, Zanzibar check (file 04) |
| Data layer | row-level security, partial-evaluation filters | list/search results | OPA partial eval → SQL, Zanzibar `ListObjects` |

The OpenID **AuthZEN** working group standardizes the PEP→PDP API (`/access/v1/evaluation` with subject, action, resource, context), so PEPs can switch PDPs without code changes [D: AuthZEN Authorization API].

---

## 6. The vulnerable L5 implementation vs the hardened L7 zero-trust implementation

```java
// L5 - DO NOT USE: authorization from request data, first-match rules, permissive default.
@PostMapping("/payments/{id}/approve")
void approve(@PathVariable String id, @RequestBody ApproveRequest body) {
    if (body.roles().contains("payments-approver")) {        // caller-supplied attribute
        paymentService.approve(id);                           // no SoD, no amount/MFA rule, no resource lookup
    }
}
// SecurityFilterChain: .requestMatchers("/admin/**").hasRole("ADMIN").anyRequest().permitAll()
// http.with(new DefaultHttpFirewallConfig()) // "the strict firewall broke our legacy URLs"
```

```java
// L7 - deny by default at the route level, resource-instance decisions in a PDP with PIP attributes.
@Bean
SecurityFilterChain api(HttpSecurity http) throws Exception {
    http.authorizeHttpRequests(a -> a
            .requestMatchers(HttpMethod.POST, "/payments/*/approve").hasAuthority("SCOPE_payments:approve")
            .requestMatchers("/admin/**").hasRole("ADMIN")
            .anyRequest().denyAll())                          // explicit routes only; everything else denied
        .oauth2ResourceServer(o -> o.jwt(Customizer.withDefaults()));
    return http.build();                                      // StrictHttpFirewall is the default: keep it
}

@Service
class PaymentApprovals {
    private final PolicyDecisionPoint pdp;                    // your client: Cedar (Verified Permissions) / OPA / AuthZEN
    private final PaymentRepository payments;                 // PIP: resource attributes
    private final DirectoryClient directory;                  // PIP: roles@version, department, MFA from the token's acr/amr

    @Transactional
    public void approve(Jwt caller, String paymentId) {
        Payment p = payments.findForUpdate(paymentId);        // the resource as the system of record sees it
        Principal who = directory.principal(caller.getSubject(), caller.getClaimAsStringList("amr"));
        Decision d = pdp.decide(who, "approve", p.asResource(), Map.of("mfa", who.mfa()));
        audit.record(d.id(), who.id(), "approve", paymentId, d.policyVersion(), who.attributesVersion());
        if (!d.allowed()) {
            throw new AccessDeniedException(d.reason());      // 403 with the decision id
        }
        p.approve(who.id());
    }
}
```

| Concern | L5 | L7 |
|---|---|---|
| Default | allow when nothing matches | deny (`denyAll()`, Cedar default deny, OPA `default allow := false`) |
| Combining | first match wins | forbid overrides permit; order irrelevant |
| Attributes | from the request | from the PIP (IdP, HR, resource store, device) with versions |
| Resource matching | string prefix | identifiers; segment-aware patterns |
| PEP placement | one filter | gateway + route + method next to data |
| Path handling | loosened firewall | `StrictHttpFirewall` defaults; no raw-vs-normalized mismatch |
| Caching | TTL only | keyed by attribute + policy version; short TTL |
| Policy lifecycle | code + config drift | policy repo, tests (allow and deny cases), signed bundles, decision logs |

---

## 7. Real-world attack vectors & mitigations

### A1 · Default-allow and missing rules

**Attack.** A new endpoint or action, such as an export, a DELETE or an admin RPC, ships without a rule, and the engine allows "no match" (L39 row 3).
**Wire signature.** Successful calls whose decision log shows no matching policy.
**Root cause.** A permissive default; policy written as exceptions.
**Mitigation.** Deny by default everywhere: `anyRequest().denyAll()`, Cedar default deny, OPA `default allow := false`. CI fails when a new route has no policy test.
**Detection.** Alert on decisions with "no policy matched".

### A2 · Rule ordering shadows a forbid

**Attack.** A broad permit placed above a narrow forbid (SoD, MFA threshold) makes the forbid dead code (L39 rows 1, 2, 5).
**Wire signature.** Allowed requests that a forbid rule matches.
**Root cause.** First-match-wins combining.
**Mitigation.** Deny-overrides combining (Cedar's semantics). Static analysis, such as Cedar's validator or policy tests, that every forbid is reachable.
**Detection.** Decision logs record every matching policy, not just the first.

### A3 · Attribute injection

**Attack.** The caller supplies `roles`, `ownerId`, `tenantId` or `mfa` in the body, headers or JWT custom claims that the PDP trusts (L39 row 4).
**Wire signature.** Authorization-relevant fields in requests from untrusted clients.
**Root cause.** The PEP passes request data as PIP data.
**Mitigation.** Attributes only from systems of record (or signed claims from your own IdP), with the resource loaded server-side.
**Detection.** Diff the request-supplied fields against PIP values and alert on mismatch.

### A4 · Path confusion between PEP and application

**Attack.** `/api/../admin/users`, `%2e%2e` or `//admin` are matched raw by the PEP and normalized by the container (L40: 4 bypasses without the firewall).
**Wire signature.** Requests with dot segments, encoded dots or slashes, double slashes or semicolons.
**Root cause.** Two parsers.
**Mitigation.** `StrictHttpFirewall` (default in Spring Security), method-level authorization, and identical normalization at gateway and app.
**Detection.** Firewall rejection logs: `RequestRejectedException` counts by pattern.

### A5 · Stale decisions after revocation

**Attack.** A removed admin keeps access through a decision cache (L39: until t = 570 s), or a PDP sidecar keeps a stale data bundle.
**Wire signature.** Allowed decisions with an attribute version older than the latest.
**Root cause.** TTL-only caches; bundle polling intervals.
**Mitigation.** Version-keyed caches, push invalidation (CAEP / directory events), bundle-revision checks, and short TTLs for privileged decisions.
**Detection.** Decision logs carrying attribute and policy versions; alert on old versions.

### A6 · Missing PEP on an alternate path

**Attack.** The same operation is reachable via GraphQL, a batch endpoint, an internal RPC or a message consumer that skips the HTTP filter.
**Wire signature.** Operations executed without a corresponding PDP decision id.
**Root cause.** Authorization only at the HTTP edge.
**Mitigation.** Authorize in the domain service (method-level) where every path converges, and require a decision id in the audit record for every state change.
**Detection.** Reconcile state changes with decision logs.

### A7 · Role explosion and privilege creep

**Attack.** No attacker is needed. Hundreds of roles accrete and nobody can say who can approve payments, so access reviews rubber-stamp.
**Wire signature.** Users with many roles; roles with one member.
**Root cause.** RBAC used for what ABAC or ReBAC express naturally.
**Mitigation.** Keep a few job-function roles, express conditions as attributes (department, limit, MFA), relationships as ReBAC, and run periodic access reviews with usage data.
**Detection.** Unused-permission reports.

---

## 8. FAANG / FinTech L7 bar-raiser Q&A chains

<details><summary><b>Q1 · RBAC, ABAC or ReBAC for a payments approval system?</b></summary>

**Initial Prompt.** Approvers per department, limits by amount, SoD, MFA over 100k.

**L5 Textbook Answer.** "RBAC: create roles per department and limit band."

**How an Attacker Bypasses L5.** Role explosion (department × limit × region) breeds mis-assignments. SoD ("not your own payment") isn't expressible as a role at all, so it lives in ad-hoc code that some path forgets (L39 row 1).

**L7 Principal Defense.**
- **Hybrid:** RBAC for the job function (`payments-approver`) and ABAC conditions (same department, amount, MFA, SoD).
- **Combining:** in a PDP with forbid-overrides semantics.
- **Attributes:** from the PIP.
- **Ownership or sharing** (who can see a payment) as ReBAC if it's relationship-shaped.
- **Proof:** policy tests for every allow and deny case.

</details>

<details><summary><b>Q2 · Your policy engine evaluates rules top-down and stops at the first match. Problem?</b></summary>

**Initial Prompt.** A homegrown engine.

**L5 Textbook Answer.** "Put deny rules first."

**How an Attacker Bypasses L5.** Ordering is a property every future edit must preserve. One broad permit added above a forbid silently disables it (L39 rows 1, 2, 5). Nobody notices until an incident.

**L7 Principal Defense.**
- **Order-independent semantics:** any forbid wins, otherwise any permit, otherwise deny (Cedar).
- **In OPA,** write it explicitly: `allow if { some permit; not deny }`.
- **Log every matching policy.**
- **Lint for unreachable forbids.**

</details>

<details><summary><b>Q3 · Where do authorization attributes come from?</b></summary>

**Initial Prompt.** A mobile app sends `{"accountOwner": "bob"}` with the request.

**L5 Textbook Answer.** "From the request; the app knows the context."

**How an Attacker Bypasses L5.** The client is attacker-controlled. Any attribute it supplies is a claim it can forge (L39 row 4).

**L7 Principal Defense.** The PIP:
- roles and groups from the IdP or directory (versioned);
- resource attributes loaded server-side by id;
- device posture from MDM;
- risk from the risk engine;
- MFA from the token's `acr`/`amr`, which the AS asserts.

The request contributes only the *identifiers* of principal, action and resource.

</details>

<details><summary><b>Q4 · Why does Spring Security reject URLs with `;` or `%2e`? Can we turn that off for legacy clients?</b></summary>

**Initial Prompt.** An old client sends `;jsessionid` URLs.

**L5 Textbook Answer.** "Set `allowSemicolon(true)` and `allowUrlEncodedPeriod(true)`."

**How an Attacker Bypasses L5.** You re-open the gap between what the matcher sees and what the container dispatches. L40 measures 4 bypasses of `/admin/**` without the firewall.

**L7 Principal Defense.**
- **Fix the client** (cookies, not URL session ids).
- **If a loosening is unavoidable,** scope it to one path with a dedicated filter chain that has no privileged routes.
- **Keep method-level authorization.**
- **Test bypass strings in CI.**

</details>

<details><summary><b>Q5 · How do you cache authorization decisions safely?</b></summary>

**Initial Prompt.** The PDP adds 5 ms per call; the team wants a 10-minute cache.

**L5 Textbook Answer.** "Cache by user + action + resource for 10 minutes."

**How an Attacker Bypasses L5.** A revoked admin keeps access for the TTL (L39: until t = 570 s). A role change has no effect until expiry.

**L7 Principal Defense.**
- **Cache key:** include the attributes version and the policy version.
- **Invalidate by push:** directory change events, CAEP.
- **Privileged decisions:** short TTLs.
- **Partial evaluation:** precompute for hot paths.
- **Measure:** a sub-millisecond embedded PDP (Cedar or OPA as a library) usually removes the need for long caches.

</details>

<details><summary><b>Q6 · OPA or Cedar?</b></summary>

**Initial Prompt.** Choosing a policy engine for 200 services.

**L5 Textbook Answer.** "OPA: it's the CNCF standard."

**How an Attacker Bypasses L5.** No attack as such. The risk is policies with permissive defaults or ordering bugs that nobody can analyze.

**L7 Principal Defense.** Choose by need [E]:
- **OPA:** general-purpose (Kubernetes admission, infrastructure, data filtering via partial evaluation), with Rego's flexibility.
- **Cedar:** application authorization with fixed deny-by-default and forbid-overrides semantics, schema validation, analyzability, and a managed PDP (AWS Verified Permissions).

Either way: deny-by-default, policy tests, signed bundles, decision logs, and an AuthZEN-shaped PEP→PDP interface so the engine can change.

</details>

<details><summary><b>Q7 · Where do you put PEPs in a microservice?</b></summary>

**Initial Prompt.** "The gateway does authorization."

**L5 Textbook Answer.** "At the gateway only; services trust it."

**How an Attacker Bypasses L5.** Any alternate path skips it: GraphQL, a batch job, a message consumer, an internal call, a path-confusion trick (A4, A6).

**L7 Principal Defense.**
- **Gateway:** coarse checks (authenticated, scope).
- **Service:** route rules with deny-by-default.
- **Domain:** resource-instance decisions where all paths converge, with PIP data and audit decision ids.
- **Data layer:** filters for list queries.

</details>

<details><summary><b>Q8 · How do you test authorization policy?</b></summary>

**Initial Prompt.** There are no tests today.

**L5 Textbook Answer.** "Integration tests for the happy path."

**How an Attacker Bypasses L5.** Happy-path tests prove allows. Every L39 attack is a missing *deny* test.

**L7 Principal Defense.**
- **A test matrix per policy:** allow cases, deny cases (SoD, limits, MFA, classification), and near-misses (prefixes, case, encoded paths).
- **Run it in CI against the exact bundle that ships.**
- **Analyze:** Cedar validation, OPA `test`.
- **Watch production:** decision-log sampling, and drift alerts between policy version and deployed version.

</details>

---

## 9. Invariants checklist

- [ ] Deny by default at every layer (`anyRequest().denyAll()`, PDP default deny).
- [ ] Order-independent combining: any forbid wins; policies log every matching rule.
- [ ] Attributes only from the PIP (IdP, directory, resource store, device, risk) with versions; requests carry identifiers only.
- [ ] Resources matched by identifier or segment-aware patterns, never string prefix.
- [ ] `StrictHttpFirewall` defaults kept; method-level authorization in domain services; gateway and app normalize identically.
- [ ] Decision caches keyed by attribute + policy version, invalidated by push; short TTL for privileged actions.
- [ ] Policy-as-code: repo, review, allow/deny/near-miss tests, signed bundles, decision logs with versions.
- [ ] Every state change has a decision id in the audit log.

---

## 10. References

- NIST SP 800-162 *Guide to Attribute Based Access Control* — <https://csrc.nist.gov/pubs/sp/800/162/upd2/final>
- NIST RBAC model (ANSI INCITS 359) overview — <https://csrc.nist.gov/projects/role-based-access-control>
- Cedar policy language documentation — <https://docs.cedarpolicy.com/>
- Open Policy Agent documentation — <https://www.openpolicyagent.org/docs/latest/>
- OpenID AuthZEN Authorization API — <https://openid.net/wg/authzen/>
- Spring Security reference, *HttpFirewall* — <https://docs.spring.io/spring-security/reference/servlet/exploits/firewall.html>

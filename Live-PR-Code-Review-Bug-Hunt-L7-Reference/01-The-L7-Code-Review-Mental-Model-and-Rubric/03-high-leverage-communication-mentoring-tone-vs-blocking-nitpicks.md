# High-Leverage Review Communication: Mentoring Tone vs Blocking Nitpicks

> **What this file is.** Dimension D6 of the rubric ([01 §2](01-how-companies-grade-live-pr-review-rounds-l5-vs-l6-vs-l7.md#2-the-eight-dimension-rubric-composite-)), in depth. It covers how to write review comments that get the fix, protect the relationship and teach the bug class, in a live round where the interviewer often plays the author. Every PR-00 finding appears twice, once as an L5 would write it and once as an L7 would. A small linter (`review_lint.py`) checks the L7 versions for tone and for the three things every blocking comment must carry.

| Listing | Lang | What it does | Output |
|---|---|---|---|
| `review_lint.py` | Python 3.12+ | Lints ` ```comment-l5 ` / ` ```comment-l7 ` blocks: Conventional Comments label, 11 tone patterns, and impact + evidence + proposal on every blocking comment; includes a self-test | Output (verified), run over this file |

**Verification.** `python -I review_lint.py --selftest` passes, and the linter is then run over this very file (§11). Result: every L7 comment clean, every L5 comment flagged. Comment texts are original. Labels follow the public Conventional Comments spec and Google's public reviewer guide.

---

## 0. Orientation

### 0.1 Why communication is scored in a bug-hunt round

A review comment is a product with one user, the author, and one job: getting the right change made, quickly, by someone who feels respected enough to keep asking you for reviews. In a live round, the interviewer is grading three readers at once:

1. **The author.** Will they understand what to change and why, without a meeting?
2. **The future reader.** Will someone who finds this thread in two years understand the decision?
3. **The interviewer.** Does this person make teams faster, or do teams route around them?

A correct Sev-1 comment phrased as an accusation scores lower than the same finding phrased as a proposal, and not because interviewers are sentimental. Comments that trigger defensiveness get argued with, delayed, or "fixed" minimally to make the reviewer go away. **Tone is a correctness property of the review process.**

### 0.2 What changes from L5 to L7

| L5 habit | What it costs | L7 replacement |
|---|---|---|
| Unlabeled comments | Author can't tell the Sev-1 from the nit; fixes them in file order | Every comment starts with a label and a blocking/non-blocking decoration |
| "Why did you…?" | Interrogates the person; invites justification instead of a fix | "This line does X; under Y that leads to Z. Suggest W." |
| Verdict without mechanism ("this is wrong") | Unfalsifiable; author pushes back or ignores | Mechanism + concrete evidence (number, interleaving, probe) |
| Socratic questions you know the answer to | Feels like a quiz; wastes a round trip | State it directly, with humility about what you might be missing |
| Twenty nits inline | Drowns the blockers; feels like a pile-on | One batched, explicitly non-blocking nit comment, or leave it to the formatter |
| Rewrite-in-comments | Unreviewable; removes the author's ownership | Smallest safe change + follow-up ticket; offer to pair |
| No summary | Author has to reconstruct your priorities | One top-level summary: verdict, blockers, follow-ups, praise, offer |
| Praise omitted, or hollow praise | Every comment is negative, or the positive ones aren't credible | One specific, sincere praise per review |

---

## 1. First principles

### 1.1 A comment's cost is paid by the author

Each comment costs the author reading time, interpretation time ("is this blocking?"), and often a context switch. A reviewer who leaves 30 comments to raise 4 important points has imposed 26 comments of overhead and hidden the 4. **The L7 goal is the fewest words that produce the right change.** Google's public guide makes the same point from the other side: favor approving once a change "definitely improves the overall code health … even if the CL isn't perfect," because, in the guide's words, perfect code does not exist: "there is only better code."

### 1.2 Understanding is the scarce resource

Bacchelli and Bird found that "code and change understanding is the key aspect of code reviewing," and that reviews deliver knowledge transfer and team awareness as much as defect-finding. A comment that explains the *mechanism* transfers understanding. A comment that only names a pattern ("race condition") doesn't, and the same author will write the same bug next quarter.

### 1.3 Severity must be explicit, not inferred

Authors can't read your mind about what matters. Two public conventions solve this:

- **Google's reviewer guide** suggests prefixes: "Nit:" (minor, "technically you should do it, but it won't hugely impact things"), "Optional (or Consider):" (a good idea, "not strictly required"), and "FYI:" (no action expected in this change).
- **Conventional Comments** defines a format: `<label> [decorations]: <subject>`. The labels are praise, nitpick, suggestion, issue, todo, question, thought, chore and note, and the decorations include `(blocking)`, `(non-blocking)` and `(if-minor)`.

This KB uses Conventional Comments, because the decorations make blocking status machine-checkable (and the linter checks them).

### 1.4 Critique the code; respect the coder

Google's guide: comment on the code, not the developer. In practice that means grammatical subjects like "this method," "line 40" and "this path," not "you." It means explaining the reasoning ("explain why"), and it means letting the developer own the fix while still being helpful with a suggestion or code when that's faster. This is not softness. It is precision: the bug lives in the code, so that's where the sentence should point.

### 1.5 Calibrated confidence is a seniority signal

Over-confidence makes your false positives expensive. Under-confidence makes your true positives ignorable. L7 reviewers state their confidence and how to settle it: "I'm fairly sure two pods can both pass this. If we only ever run one replica, ignore this." The author can resolve that in one reply.

---

## 2. The comment taxonomy

### 2.1 Labels, decorations, and when to use each

| Label + decoration | Use it for | Severity tier ([01 §4.1](01-how-companies-grade-live-pr-review-rounds-l5-vs-l6-vs-l7.md#41-the-answer-key-has-tiers)) | Merge effect |
|---|---|---|---|
| `issue (blocking):` | A defect that will cause incorrect behavior, data loss, a security hole or a compat break in production | Sev-1, Sev-2 | Must resolve before merge |
| `issue (non-blocking):` | A real defect with low blast radius, or one that can safely be fixed in a tracked follow-up | Sev-3 | Resolve now or file a ticket, author's choice |
| `todo (blocking):` | A small, necessary, non-controversial change (a missing test for a found bug, a stale doc line) | — | Must resolve |
| `suggestion (non-blocking):` | A better approach the author may adopt | — | Optional |
| `question:` | You genuinely don't know: a fact you need (replica count, consumer list) | — | Needs an answer; may become an issue |
| `nitpick (non-blocking):` | Style, naming, wording; batch these | Nit | Never blocks |
| `thought (non-blocking):` | A broader idea sparked by the PR (a platform guardrail, a design doc) | — | No action in this PR |
| `praise:` | Something done well, specifically | — | — |
| `note:` | Context the author should know (a related incident, a doc) | — | — |
| `chore (blocking):` | Process steps (changelog, migration ticket, schema registration) | — | Must resolve |

### 2.2 The two-question gate for "blocking"

Ask yourself, in order:

1. **If this merges as-is and ships, will something observable go wrong in production?** That means incorrect results, lost or corrupted data, a security exposure, a broken deployed consumer, or an outage under realistic conditions. If yes, it is **blocking**.
2. **Will it make the next change materially riskier or slower?** That covers a design that forces future bugs, or a missing test for a defect you just found. If yes, it is **blocking only if cheap to fix now**; otherwise `issue (non-blocking)` plus a ticket with an owner.

Everything else (style, naming, alternative-but-equivalent designs, personal preference) is **never blocking**. If a style point matters enough to block, it belongs in the formatter or linter config, not in a human comment.

### 2.3 What should never appear as a human comment

- Formatting the formatter would fix. Ask for the formatter in CI instead, once.
- Issues already caught by a configured static-analysis tool. Point at the tool's finding, or ask for the tool.
- A re-litigation of a design decision already approved in a design doc, unless the code reveals new information. Then say exactly what's new.

---

## 3. Anatomy of a blocking comment: O-I-E-P-O

Every blocking comment that survives pushback has five parts. Most are one sentence each.

| Part | Question it answers | PR-00 F3 example |
|---|---|---|
| **O**bservation | What, exactly, and where? | "`synchronized` on line 31 serializes threads within one pod." |
| **I**mpact | What goes wrong in production, for whom? | "We run six pods, so two partial refunds can both pass the balance check, which means the network pays more than the charge." |
| **E**vidence | How do we know? | "Interleaving: pod A and pod B both read `refunded = 0`… The two-pod probe over-refunds in 20/20 trials." |
| **P**roposal | What's the smallest safe change? | "Suggest `tryReserve` (one conditional UPDATE) and dropping `synchronized`." |
| **O**ffer | How do I help? | "Happy to pair on the test with two service instances." |

Three rules make the anatomy work:

1. **Lead with the label and the claim.** The first line is what shows in notification emails and collapsed threads: `issue (blocking): two pods can both pass the balance check (over-refund)`.
2. **Evidence beats authority.** "In my experience this races" invites "in my experience it doesn't." An interleaving or a number ends the discussion.
3. **Propose, don't prescribe.** "Suggest…" or "Could we…?" keeps the author as owner. When the fix is mechanical, a GitHub suggestion block is the kindest form, because it's one click:

````markdown
```suggestion
        Charge charge = charges.findForMerchant(merchantId, req.chargeId());
```
````

---

## 4. PR-00, comment by comment

Each pair below is the same finding, once as an L5 typically writes it and once as an L7 would. The L5 versions aren't strawmen: they're how capable engineers write when moving fast. The linter in §11 checks every block in this section.

### 4.1 F1 · authorization (line 36)

```comment-l5
Why didn't you check the merchant here? This is a security hole.
```

```comment-l7
issue (blocking): any merchant can refund any charge they can name

Line 36 loads the charge by id alone; `merchantId` (documented as the authenticated merchant) is only copied into the record on line 51. Since this PR makes the endpoint public, the impact is direct: for example, an attacker opens a merchant account, buys from a victim merchant, then refunds their own purchase against the victim's charge id. The P1 probe shows exactly that succeeding.

Suggest `charges.findForMerchant(merchantId, req.chargeId())` and returning the same rejection as for a missing charge, so ids can't be probed. A test using a second merchant's key would pin it.
```

**Why the L7 version wins.** It names the contract change that made this a bug (internal to public), gives a concrete exploit, points at the evidence, offers a one-line fix *and* the test, and avoids "you."

### 4.2 F8 · the renamed field (lines 55–57)

```comment-l5
You broke the ledger. amountCents is used downstream!!
```

```comment-l7
issue (blocking): renaming `amountCents` on `refunds.v1` zeroes amounts in the deployed ledger

The motivation is right ("cents" is wrong for JPY and KWD). The catch is that `ledger-service` v1 consumes this topic and reads `amountCents`; after deploy it would get its default (0), so every refund books as zero, silently. Rollback wouldn't repair the rows already written. The P8 probe shows the v1 reader seeing 0 for a 1,200 refund.

Could we make it additive: emit both fields on v1 and mark `amountCents` deprecated in the schema, then remove it once the consumer registry shows no reader? Or publish `refunds.v2`. Either makes deploy order irrelevant.
```

**Why.** It credits the author's intent before stating the problem, names the specific deployed reader, quantifies the impact and offers two safe paths.

### 4.3 F3 · the per-JVM lock (lines 31, 40, 54)

```comment-l5
synchronized won't work in prod. Use a distributed lock.
```

```comment-l7
issue (blocking): two pods can both pass the balance check (over-refund)

`synchronized` serializes threads within one JVM, but we run six pods against the same charge row. When two partial refunds for one charge land on different pods, both read `refunded = 0` and both pass, so the network pays 12,000 on a 10,000 charge; then the blind `setRefunded(newTotal)` loses one update, so the ledger says 6,000. The two-pod probe reproduces this in 20/20 trials (interleaving in the thread below).

Suggest `charges.tryReserve(...)`: one conditional UPDATE that compares and adds atomically in the database, so the lock isn't needed. A distributed lock would add a lease without a fencing token, which brings a different set of failure modes. Happy to pair on a two-instance test.
```

**Why.** The L5 comment is directionally right but proposes a worse fix (a distributed lock without fencing) and gives no mechanism. The L7 comment explains why the JVM lock fails, proves it, proposes the simpler database-native fix, and pre-empts the obvious alternative with a reason.

### 4.4 F6 · timeout as failure (lines 47–49)

```comment-l5
Timeout isn't a failure.
```

```comment-l7
issue (blocking): a gateway timeout is reported as "failed, please retry", which invites a double payout

The `PaymentGateway` Javadoc says a timeout means the refund "may or may not have executed", while a decline means it definitely didn't. Line 47 handles both the same way and tells the merchant to retry. Dashboards and many SDK integrations retry a "failed" refund with a new key, which means the network pays again. The P6 probe shows a 5,000 charge paying out 10,000 this way.

Proposal: three outcomes. Decline releases the reservation and returns 4xx; timeout records UNKNOWN, keeps the reservation and returns 202; success commits. A reconciler can settle UNKNOWN rows via `gateway.lookup(key)`; that part could be a follow-up ticket.
```

**Why.** "Timeout isn't a failure" is true and useless: it gives no consequence and no fix. The L7 version quotes the contract, shows the money impact and separates the blocking part from the follow-up.

### 4.5 F2 · overflow (lines 40–41)

```comment-l5
This can overflow. Should be long.
```

```comment-l7
issue (blocking): `int` overflow on line 40 turns the balance check into a bypass

For large-denomination currencies the sum wraps: for example 1,500,000,000 refunded + 1,000,000,000 requested = -1,794,967,296, which passes `newTotal > amountMinor`; line 54 then persists the negative total, so later refunds on that charge pass too. The P2 probe shows exactly these numbers.

Widening to `long` here wouldn't compile against `setRefunded(int)` and the INT column. Suggest letting `tryReserve` do the arithmetic in BIGINT in SQL, which also fixes the two-pod issue above. Widening the columns could be a follow-up migration.
```

### 4.6 F4 · idempotency claimed too late (lines 32–35, 53)

```comment-l5
Idempotency check is racy.
```

```comment-l7
issue (blocking): the idempotency key is claimed after the payout, so concurrent deliveries both proceed

The replay check reads the key on line 32 but the row is written on line 53, after `gateway.refund()`. If two deliveries of one request land on two pods (a client or load-balancer retry), both miss the check. The gateway dedups the money, but we write two records and publish two `RefundIssued` events, which means the ledger double-counts. The P4 probe shows duplicate events in 20/20 trials.

Suggest claiming the key first with `refunds.insertIfAbsent(...)` as a PENDING row (the unique constraint makes concurrent deliveries converge), and rejecting reuse of a key with a different body.
```

### 4.7 F5 · lock across the network call (lines 31, 46)

```comment-l5
Holding a lock while calling the gateway is bad practice.
```

```comment-l7
issue (blocking): the monitor is held across `gateway.refund()`, so a gateway brownout becomes our outage

Every refund on a pod waits for the slowest in-flight gateway call. At a 2 s gateway timeout that's 0.5 refunds/s per pod, and request threads pile up until health checks fail and pods restart into the same state. The P5 probe shows 16 refunds taking about 16 × the gateway latency.

Once the balance moves into `tryReserve`, no lock is needed, so this resolves with the fix above. Worth noting: a `SELECT ... FOR UPDATE` replacement would move the same problem into the database's connection pool.
```

### 4.8 F7 · no durable trace before the payout (lines 46, 53–57)

```comment-l5
What if the save fails?
```

```comment-l7
issue (blocking): money moves before anything durable exists, so a failover can lose all trace of a refund

The order is pay (46), then save (53), then update the ledger (54), then publish (56). If the primary fails over between 46 and 53, the network has paid and nothing in our database knows; the only way to find it is a settlement-file diff. A failure between 53 and 56 drops the event (a dual write). The P7 probe injects a failover after the payout and finds no trace.

Suggest writing a PENDING claim before the call (the idempotency fix above gives us this) and committing the outcome together with the event via `saveWithOutbox`.
```

### 4.9 F9 · metric cardinality (lines 48, 58)

```comment-l5
Don't use refund_id as a tag, that's terrible for Prometheus.
```

```comment-l7
issue (non-blocking): `refund_id` as a metric label creates one series per refund

Prometheus's naming guide advises against unbounded label values; at our volume this would add a series per refund, which slows queries and can hurt the shared backend. Suggest labels like `outcome` and `currency`, with the id in logs or traces. Fine as a fast follow if you'd rather keep this PR focused.
```

### 4.10 T1 · tests that pin the bugs (test lines 53, 60–63)

```comment-l5
Tests are incomplete.
```

```comment-l7
todo (blocking): two tests assert behavior we want to change, and four scenarios are missing

`gatewayTimeoutIsRetryable` asserts the "failed, please retry" path and `publishesRefundIssuedEvent` asserts the renamed field; against the fixed service exactly these two fail, so they'll need updating with the fixes. The scenarios that would have caught the blocking issues: two service instances sharing the stores, a gateway that times out after executing, a second merchant's key, and amounts near `Integer.MAX_VALUE`. Suggest adding those four; the shared fakes already support all of them.
```

### 4.11 D1 · the Javadoc's thread-safety claim (lines 26–27)

```comment-l5
Javadoc is wrong.
```

```comment-l7
issue (blocking): the Javadoc promises a guarantee the deployment doesn't provide

Lines 26–27 say two concurrent partial refunds "can never both pass the balance check". That holds per JVM, not across our six pods, so a future reader would trust it and skip the scenario in the two-pod comment above. Suggest replacing it with the real mechanism once the fix lands (unique key plus conditional UPDATE), or removing it.
```

### 4.12 The nits, batched

```comment-l5
gatewayRef -> networkRefundId
```

```comment-l7
nitpick (non-blocking): a few small readability items, batched so they don't distract from the issues above

`gatewayRef` reads ambiguously next to `rec`; consider `networkRefundId`. `"refunds.v1"` appears in a string literal; a constant would make the topic easy to find. None of these block; take or leave.
```

### 4.13 The praise

```comment-l5
LGTM otherwise.
```

```comment-l7
praise: the test class is easy to extend

The fakes and the `@BeforeEach` seed make each test three lines; that's what will make the two-pod and timeout-after-execute tests cheap to add. Nice structure.
```

---

## 5. Tone engineering

### 5.1 Words that cost you, and why

Each entry is a phrase that changes how the author reads everything around it. The linter in §11 checks all of them except the appeal to common knowledge, which is too context-dependent to match lexically.

| Phrase | What the author hears | Replace with |
|---|---|---|
| "just …" ("just use a lock") | "This is trivial and you missed it" | State the change and its cost honestly: "Suggest X; it touches two call sites" |
| "simply", "obviously", "clearly", "trivial" | "You should have seen this" | Remove the adverb; give the mechanism |
| "Why did you / why would you …?" | "Justify yourself" | "This line does X; under Y that leads to Z" |
| "You forgot / you broke / you didn't …" | Blame | Make the code the subject: "This path doesn't release the permit on throw" |
| "This is wrong / bad / terrible" | A verdict with no handle | "This returns X when Y; expected Z" |
| "?!", "!!" | Shouting | One period |
| "Everyone knows …" | "You're behind" | Link the doc or incident that taught us |
| "lol", "ugh", "wtf" | Contempt | Nothing; delete it |

### 5.2 "This code" and "we," not "you"

Compare *"You're holding the lock across the network call"* with *"The monitor is held across `gateway.refund()`."* The second points at the code, which is where the fix goes. Use "we" for shared ownership of outcomes: "we run six pods," "we'd page on this." Use "I" for your own uncertainty: "I may be missing a replica constraint."

### 5.3 Questions: genuine vs rhetorical

A **genuine question** asks for a fact you lack: "How many replicas does this run with?", "Does the ledger read `amountCents`?" Ask these early and plainly. A **rhetorical question** is a statement in disguise: "Have you considered what happens with two pods?" When you already know the answer, it reads as a quiz. Say it directly and attach your uncertainty instead: "I think two pods can both pass this check (interleaving below). If we only run one replica, ignore me."

### 5.4 Calibrated confidence phrases

| Confidence | Phrase | Use when |
|---|---|---|
| Certain, proven | "This over-refunds when …; the probe reproduces it." | You have a number, interleaving or failing test |
| High | "I'm fairly sure … Here's the scenario. Can you confirm …?" | Mechanism clear, one deployment fact unconfirmed |
| Medium | "I think this might … I'd check by …" | Plausible mechanism, unverified |
| Low | "question: does this path ever see …?" | You need a fact before forming an opinion |

Never present a medium-confidence suspicion with high-confidence words. In a live round, a single confidently wrong Sev-1 costs more credit than a hedged miss.

### 5.5 Praise that's believable

Conventional Comments recommends at least one praise per review, and only when sincere. Specific praise is credible ("the fakes make each test three lines"); generic praise ("great work!") isn't, and it devalues your later praise. Praise also has a functional job: it tells the author what to keep doing, which is half of mentoring.

---

## 6. Blocking vs non-blocking, and the review state

### 6.1 The decision procedure

```text
Will this, merged as-is, cause incorrect behavior, data loss/corruption, a security
exposure, a broken deployed consumer, or an outage under realistic conditions?
 ├─ yes → issue (blocking). State the mechanism and the minimal fix.
 └─ no  → Will it make the next change materially riskier, or is it a missing test for
          a defect we just found?
           ├─ yes, cheap now → todo (blocking)
           ├─ yes, expensive → issue (non-blocking) + ticket with an owner and a date
           └─ no  → Is it a preference, naming or style?
                     ├─ yes → nitpick (non-blocking), batched, or a formatter/linter rule
                     └─ no  → suggestion (non-blocking) or thought (non-blocking)
```

### 6.2 Which review state to submit

| State | Use when | Say in the summary |
|---|---|---|
| **Request changes** | At least one blocking item | "Not safe to merge yet; here are the N blockers. Everything else is optional." |
| **Comment** | You have questions whose answers decide blocking status | "Holding my verdict on one answer: replica count." |
| **Approve** | No blockers (non-blocking items may remain) | "Approving; the nits and the follow-up ticket are your call." |
| **Approve with conditions** | Blockers are trivial and you trust the author to apply them (team-norm dependent) | "Approve once the two one-liners land; no need for another look." |

"Request changes" is a statement about the code's readiness, not about the author. Saying that explicitly in the summary removes most of the sting.

### 6.3 The follow-up ticket pattern

When a real issue is too big for this PR (a reconciler, a v2 topic, a column migration), the L7 move is: `issue (non-blocking)` + "I've filed PAY-4131 for the reconciler; can you own it, or should I?" + a date. A follow-up with no owner is a polite way of never doing it, and interviewers know that.

---

## 7. Handling pushback (the interviewer plays the author)

In many live rounds the interviewer switches roles: "OK, I'm the author now. I disagree." This tests D6 under pressure. A reliable pattern:

1. **Acknowledge what's true** in their position.
2. **Restate the risk** in one sentence, with the evidence.
3. **Offer an experiment or options**, ideally one the author controls.
4. **Agree on a decision rule**, and accept it if the evidence goes their way.

| Author says | L5 reply | L7 reply |
|---|---|---|
| "Tests pass." | "Tests don't cover it." | "They do cover the single-instance path well. This needs two instances. Could we add one test with two `RefundService`s on shared stores? If it passes, I'll withdraw the comment." |
| "It's a rare race." | "Races are always bad." | "The window is the full gateway round trip, about 20 ms, not nanoseconds. At our refund rate that's several overlaps a day. The probe hits it every time." |
| "Out of scope for this PR." | "It's still a bug." | "Agreed for the reconciler and the v2 topic; I've marked those non-blocking with tickets. The ownership check and the field rename are introduced by this PR, so I'd keep those two blocking. Both are one-liners." |
| "We've always done it this way." | "That doesn't make it right." | "That was safe while only the single console instance called it. This PR changes the caller and the instance count, and that's what turns it into a bug." |
| "The ledger team agreed to switch fields." | "OK then." | "Great, that's the right end state. Until their deploy lands first everywhere, there's a window of zeroed amounts. Emitting both fields removes the ordering dependency. Can we do that and drop the old one later?" |
| "A distributed lock is the standard fix." | "No it isn't." | "It can work, but it needs fencing to be safe, and it adds a dependency on the hot path. The conditional UPDATE gets us atomicity from the database we already write to, in one statement." |

**When to escalate.** If you still disagree after evidence and options, the L7 move is to say so plainly and name the decision-maker: "I still think this is blocking because of X. Shall we ask the payments tech lead to make the call?" Google's guide has a dedicated section on pushback. It reminds reviewers that developers are often "closer to the code than you are," so a valid argument should win. It notes that "upsets are usually more about the way comments are written" than about insisting on quality. And it warns that "letting people 'clean things up later' is a common way for codebases to degenerate." Don't concede a Sev-1 to avoid friction, and don't hold a nit hostage to win an argument.

---

## 8. Mentoring through review

### 8.1 Teach the class, not the instance

A comment that fixes one line helps once. A comment that names the *class* changes the author's next hundred lines:

- Instance: "Move the check into the UPDATE."
- Class: "General rule: when state lives in a shared database, the coordination must live there too (unique keys, conditional updates). A JVM lock only coordinates one pod. That rule also explains the idempotency and timeout comments."

### 8.2 Ask for the test that would have caught it

The highest-leverage mentoring request is "add the test that fails on the current code." It forces the author to model the failure, it pins the fix, and it leaves a teaching artifact for the next engineer. In PR-00 that's the two-instance test, which `RefundServiceTest.twoPodsCannotOverRefund` in the fixed suite implements ([02 §11.3](02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md#113-the-refactored-refundservice)).

### 8.3 Leave room for the author to find it

For a junior author and a non-urgent issue, a pointed question can teach better than an answer: "What does the gateway's Javadoc say a timeout means?" Use this only when (a) it's not a live-round Sev-1, where clarity beats pedagogy, and (b) you'd be happy with either answer. In a live round, state the finding, then add the teaching line.

### 8.4 Offer to pair

"Happy to pair on the two-pod test" costs you 30 minutes and saves the author a day. It also shows the interviewer the behavior that makes Staff+ engineers multipliers.

---

## 9. Narrating in a live round

The interviewer can only award what they hear. Narration should expose your *model*, not your keystrokes.

| Moment | Say | Don't say |
|---|---|---|
| Opening | "I'll read the ticket first to see which contracts change, then go to the riskiest hunk. I'll batch style for the end." | "Let me start from the top." |
| Asking a fact | "One question that decides several things: how many replicas run this?" | "What does this method do?" (when it's readable) |
| Noting a suspicion | "Suspicion: lock held across the gateway call. Noting it; I'll prove it after the first pass." | (silence for four minutes) |
| Proving | "Two columns: pod A reads 0 at t0, pod B reads 0 at t1, both pass at t2…" | "This is definitely a race." |
| Unifying | "These five share one cause: the JVM is acting as the source of truth for shared state." | "Another bug here, and another…" |
| Taking a hint | "Good point, let me follow that fully before moving on." | "Yeah, maybe." (and moving on) |
| Running late | "I have eight minutes. I'll write the summary now and list the layers I didn't finish." | Keep digging until time runs out |
| Uncertain | "I'm not sure the gateway dedups. If it doesn't, F4 becomes a Sev-1. Can you tell me?" | Guessing confidently |

---

## 10. The review summary comment

Every L7 review ends with one top-level comment that the author can act on without reading anything else.

**Template.**
1. **Verdict and why**, in one sentence.
2. **Merge blockers**, ranked, each with a one-line reason and a link to its thread.
3. **The root cause**, if several blockers share one, plus the single fix that addresses them.
4. **Follow-ups** with owners.
5. **Non-blocking items**, mentioned as optional.
6. **Praise**, specific.
7. **Offer.**

```summary-l5
LGTM mostly, just a few things. Fix the overflow and the synchronized thing, obviously the event rename too. Some nits inline.
```

```summary-l7
Verdict: request changes. Partial refunds are a great addition and the test structure makes the fixes cheap; four items need to land before this is safe to expose publicly.

Blockers, in order:
1. Ownership check (line 36): any merchant can refund any charge. One line with findForMerchant.
2. Event compatibility (lines 55-57): the deployed ledger reads amountCents and would book every refund as 0. Emit both fields on v1.
3. Source of truth (lines 31-58): six threads (two-pod over-refund, overflow, late idempotency claim, lock across the gateway call, timeout handled as failure, no trace before the payout) share one root cause: correctness lives in a JVM monitor and in call order, but the state is shared across pods, retries and failures. The platform already has the pieces: claim the key first (insertIfAbsent), reserve with one conditional UPDATE (tryReserve), classify decline / timeout / success, commit with the outbox. About 60 lines; I've sketched it in the F3 thread.
4. Tests: two tests assert the old behavior (timeout path, renamed field) and will change with the fixes; adding two-instance, timeout-after-execute, other-merchant and near-max-amount tests would pin all of the above.

Follow-ups (non-blocking, tickets filed): reconciler for UNKNOWN refunds (PAY-4131); refunds.v2 topic and schema-compat check in CI (PAY-4132); BIGINT migration for charge amounts (PAY-4133). Happy to own the CI check.

Non-blocking: metric labels (use outcome/currency rather than refund_id); a couple of naming nits.

Happy to pair on the source-of-truth change this afternoon if useful.
```

---

## 11. The linter: `review_lint.py`

A small, honest tool. It cannot judge whether a comment is *right*; it checks the things that are mechanical and that candidates reliably get wrong under pressure:

1. **Label.** Every comment starts with a Conventional Comments label (`issue`, `suggestion`, `nitpick`, `question`, `todo`, `praise`, `thought`, `chore`, `note`) and optional decorations.
2. **Tone.** None of 11 patterns that read as dismissive, blaming or shouting.
3. **Completeness.** Every blocking comment (`issue`, or anything decorated `blocking`, unless decorated `non-blocking`) has an *impact* phrase, an *evidence* phrase and a *proposal* phrase.

Top-level summaries (` ```summary-l7 `) are checked for tone only. Use it on your own practice comments for the PRs in Folders 02–05.

```python
# review_lint.py - lint code-review comments for tone and for the parts a blocking comment must carry.
# Usage: python review_lint.py FILE.md   (checks ```comment-l5/-l7 and ```summary-l5/-l7 fenced blocks;
#                                          exits 1 if any L7 block is flagged)
#        python review_lint.py --selftest
import re
import sys

LABELS = ("praise", "nitpick", "suggestion", "issue", "todo", "question", "thought", "chore", "note")
HEADER = re.compile(r"^(?P<label>[a-z]+)\s*(?:\((?P<decor>[a-z, -]+)\))?:\s*\S")

TONE = [  # (name, pattern, why it costs you in a live round)
    ("just", r"\bjust\b", "minimizes the author's work"),
    ("simply", r"\bsimply\b", "implies the fix is obvious"),
    ("obviously", r"\bobvious(ly)?\b", "implies the author missed something obvious"),
    ("clearly", r"\bclearly\b", "asserts instead of showing"),
    ("trivial", r"\btrivial\b", "dismissive"),
    ("why did you", r"\bwhy (did|would|didn't) you\b", "interrogates the person, not the code"),
    ("you broke", r"\byou (forgot|broke|missed|didn't|should have)\b", "assigns blame to the author"),
    ("this is wrong", r"\b(this|that) is (wrong|bad|terrible|broken)\b", "a verdict with no mechanism"),
    ("terrible", r"\bterrible\b", "a verdict with no mechanism"),
    ("lol/ugh", r"\b(lol|ugh|wtf)\b", "unprofessional"),
    ("!!", r"\?!|!!", "shouting"),
]
PARTS = [  # what every blocking comment must carry
    ("impact", re.compile(r"\b(impact|because|so that|which means|this means|results? in|leads? to|causes?|would|then)\b",
                          re.I)),
    ("evidence", re.compile(r"\b(repros?|scenarios?|tests?|probes?|traces?|for example|steps?|when two|if two|"
                            r"interleavings?)\b|\be\.g\.", re.I)),
    ("proposal", re.compile(r"```suggestion|\b(suggest|proposal|could we|consider|instead|fix|replace|move|use)\b", re.I)),
]


def lint(comment: str, summary: bool = False) -> list[str]:
    """Problems with one comment. A top-level summary is checked for tone only (it carries no single label).
    An unlabeled comment is judged as the blocker it implicitly is, so its missing parts are reported too."""
    problems = []
    first = comment.strip().splitlines()[0] if comment.strip() else ""
    m = None if summary else HEADER.match(first)
    labeled = bool(m) and m.group("label") in LABELS
    if not summary and not labeled:
        problems.append("no label")
    problems += [f"tone '{name}'" for name, pat, _ in TONE if re.search(pat, comment, re.I)]
    decor = (m.group("decor") or "").split(", ") if labeled else []
    blocking = not summary and (not labeled or m.group("label") == "issue" or "blocking" in decor)
    if "non-blocking" in decor:
        blocking = False
    if blocking:
        missing = [name for name, pat in PARTS if not pat.search(comment)]
        if missing:
            problems.append("blocker without " + " + ".join(missing))
    return problems


def blocks(md: str, kind: str) -> list[str]:
    return re.findall(r"^```" + kind + r"\n(.*?)^```", md, flags=re.M | re.S)


def selftest() -> None:
    assert lint("Why did you hold a lock here?? This is wrong.") == [
        "no label", "tone 'why did you'", "tone 'this is wrong'", "blocker without impact + evidence + proposal"]
    # Lexical limit, kept visible: the "would" in "why would you" passes as an impact phrase.
    assert "blocker without evidence + proposal" in lint("Why would you hold a lock here?? This is wrong.")
    good = ("issue (blocking): two pods can both pass the balance check\n\nWhen two requests interleave, both read "
            "refunded=0, which means a 12,000 payout on a 10,000 charge. Suggest a conditional UPDATE.")
    assert lint(good) == [], lint(good)
    assert lint("nitpick (non-blocking): `gatewayRef` reads oddly next to `rec`; consider `networkRef`.") == []
    assert lint("issue (blocking): overflow. Use long, because it wraps.") == ["blocker without evidence"]
    assert lint("Verdict: request changes. Obviously broken.", summary=True) == ["tone 'obviously'"]
    assert lint("Verdict: request changes. Four blockers below.", summary=True) == []
    print("selftest ok")


def main() -> None:
    if sys.argv[1:] == ["--selftest"]:
        selftest()
        return
    md = open(sys.argv[1], encoding="utf-8").read()
    dirty_l7 = 0
    for kind in ("comment-l5", "comment-l7", "summary-l5", "summary-l7"):
        found = blocks(md, kind)
        print(f"{kind}: {len(found)} checked")
        flagged = 0
        for i, c in enumerate(found, 1):
            probs = lint(c, summary=kind.startswith("summary"))
            flagged += bool(probs)
            dirty_l7 += kind.endswith("l7") and bool(probs)
            print(f"  #{i:<2} {'FLAGGED: ' + '; '.join(probs) if probs else 'clean'}")
        print(f"  -> {flagged} of {len(found)} flagged")
    sys.exit(1 if dirty_l7 else 0)


if __name__ == "__main__":
    main()
```

**Output (verified).** The self-test, then the linter run over this file's 13 comment pairs and 1 summary pair:

```text
$ python -I review_lint.py --selftest
selftest ok
$ python -I review_lint.py 03-high-leverage-communication-mentoring-tone-vs-blocking-nitpicks.md
comment-l5: 13 checked
  #1  FLAGGED: no label; tone 'why did you'; blocker without impact + evidence + proposal
  #2  FLAGGED: no label; tone 'you broke'; tone '!!'; blocker without impact + evidence + proposal
  #3  FLAGGED: no label; blocker without impact + evidence
  #4  FLAGGED: no label; blocker without impact + evidence + proposal
  #5  FLAGGED: no label; blocker without impact + evidence + proposal
  #6  FLAGGED: no label; blocker without impact + evidence + proposal
  #7  FLAGGED: no label; blocker without impact + evidence + proposal
  #8  FLAGGED: no label; blocker without impact + evidence + proposal
  #9  FLAGGED: no label; tone 'terrible'; blocker without impact + evidence
  #10 FLAGGED: no label; blocker without impact + proposal
  #11 FLAGGED: no label; blocker without impact + evidence + proposal
  #12 FLAGGED: no label; blocker without impact + evidence + proposal
  #13 FLAGGED: no label; blocker without impact + evidence + proposal
  -> 13 of 13 flagged
comment-l7: 13 checked
  #1  clean
  #2  clean
  #3  clean
  #4  clean
  #5  clean
  #6  clean
  #7  clean
  #8  clean
  #9  clean
  #10 clean
  #11 clean
  #12 clean
  #13 clean
  -> 0 of 13 flagged
summary-l5: 1 checked
  #1  FLAGGED: tone 'just'; tone 'obviously'
  -> 1 of 1 flagged
summary-l7: 1 checked
  #1  clean
  -> 0 of 1 flagged
exit code 0
```

**What the result means.** All L7 blocks pass and all L5 blocks are flagged. Every L5 comment fails the label check. Because an unlabeled comment reads to the author as a blocker, the linter also reports which of impact, evidence and proposal it lacks, and most lack all three. Even the L5 nit and the "LGTM otherwise" are flagged, and that is the point: without a label the author cannot tell them from the Sev-1s. The checks are lexical. The self-test keeps one known limit visible: the "would" in "why would you" passes as an impact phrase. So treat a clean result as necessary, not sufficient. A comment can pass the linter and still be wrong.

---

## 12. Failure modes

| Failure mode | Symptom | Fix |
|---|---|---|
| **Unlabeled severity** | Author fixes nits first; a Sev-1 ships | Label every comment; one summary ranks the blockers |
| **Interrogation** | "Why did you…?" draws a defensive reply and a slower fix | Make the code the subject; state the mechanism |
| **Verdict without evidence** | "This is wrong" → "No it isn't" → stalemate | Number, interleaving or probe in every blocking comment |
| **Pile-on** | 30 comments, 4 that matter | Batch nits; drop preferences; use formatters |
| **Rewrite-in-comments** | Author loses ownership; review becomes a design fight | Minimal safe change + follow-up ticket + offer to pair |
| **Over-hedging** | Sev-1 phrased as "maybe consider possibly…" | Calibrate: certain findings get certain words |
| **Rhetorical questions** | Quiz feeling; extra round trip | Ask only for facts you lack; state what you know |
| **Hollow praise** | "Great job!" on a PR with three blockers | Specific praise or none |
| **Unowned follow-ups** | "We should fix this later" never happens | Ticket + owner + date in the comment |
| **Conceding Sev-1s under pushback** | Author pushes; reviewer folds | Acknowledge, restate with evidence, offer an experiment, escalate if needed |

---

## 13. Bar-raiser chains

<details><summary><b>Q1 · "Rewrite this comment as you'd post it: 'why would you hold a lock while calling the gateway??'"</b></summary>

**Initial Prompt.** Tone transformation on the spot.

**L5 Answer.** "Holding a lock while calling the gateway is bad practice, please fix."

**Why L5 Stalls.** Less hostile, still no mechanism, no impact and no fix. "Bad practice" invites "it works fine in tests."

**L7 Answer.** "`issue (blocking): the monitor is held across gateway.refund(), so a gateway brownout becomes our outage.` Then one sentence of impact (refunds per pod drop to 1 per gateway-latency; threads pile up; health checks fail), one of evidence (the 16-refund probe takes about 16× the latency), and one of proposal (once the balance check moves into `tryReserve`, no lock is needed; a row lock would move the problem into the DB pool)."

</details>

<details><summary><b>Q2 · "You left 14 comments. The author asks which ones actually matter. What do you say?"</b></summary>

**Initial Prompt.** Prioritization made explicit.

**L5 Answer.** "They all matter, ideally fix all of them."

**Why L5 Stalls.** Abdicates prioritization to the person with the least context on the risks.

**L7 Answer.** "Four block the merge, in this order: ownership check, event field, the source-of-truth change, and the two tests that assert old behavior. They're labeled `blocking`, and the summary links them. Three are follow-ups with tickets. The rest are nits; take or leave them. Should I collapse the nits into one comment so the thread is easier to scan?"

</details>

<details><summary><b>Q3 · "When is a question better than a statement in review?"</b></summary>

**Initial Prompt.** Genuine vs rhetorical questions.

**L5 Answer.** "Questions are always more polite, so I phrase everything as a question."

**Why L5 Stalls.** Rhetorical questions about things you know read as passive-aggressive and cost a round trip. "Have you considered multiple pods?" makes the author guess what you mean.

**L7 Answer.** "When I genuinely lack a fact that decides the severity: replica count, consumer list, gateway semantics. Then the question is the most efficient comment. When I know the answer, I state it with my confidence and how to check: 'I think two pods can both pass this; if we only run one replica, ignore me.' For a junior author on a non-urgent issue, a guiding question can be good teaching, but not for a Sev-1 in a live round."

</details>

<details><summary><b>Q4 · The interviewer, as author: "This review feels like a pile-on. I've been here six years."</b></summary>

**Initial Prompt.** Emotional pushback; seniority asymmetry.

**L5 Answer.** "Sorry, I didn't mean to offend. Feel free to ignore the ones you disagree with."

**Why L5 Stalls.** Apologizing *and* abandoning the Sev-1s protects neither the relationship nor production.

**L7 Answer.** "That's fair feedback on volume. Let me collapse it. The structure and tests here are good, and I said so in the summary. Most of my comments are optional. Four things block, and they aren't about style: they come from the PR changing who can call this and how many pods run it, which wasn't true when this code was written. Could we go through just those four together? Ten minutes on a call might beat ten threads."

</details>

<details><summary><b>Q5 · "Should every review include praise? Isn't that performative?"</b></summary>

**Initial Prompt.** Sincerity vs ritual.

**L5 Answer.** "I skip praise; the code speaks for itself."

**Why L5 Stalls.** Praise isn't decoration. It tells the author what to keep doing, and it makes your critical comments credible as being about the code.

**L7 Answer.** "Every review gets at least one specific, sincere praise. Conventional Comments recommends this, and the 'sincere' part is the rule that matters. If I can't find something sincere, I'm probably not reading generously enough. It's functional: 'the fakes make each test three lines' tells the author which pattern to repeat in the fix."

</details>

<details><summary><b>Q6 · "When do you approve a PR that still has open comments?"</b></summary>

**Initial Prompt.** Review-state judgment.

**L5 Answer.** "Never. All comments must be resolved first."

**Why L5 Stalls.** Turns every nit into a blocker and slows the team; contradicts the "improves code health even if not perfect" standard.

**L7 Answer.** "When everything open is non-blocking by its label: nits, suggestions, follow-ups with owners. I approve and say so explicitly: 'Approving; the nits and the reconciler ticket are your call.' If a blocker is a trivial one-liner and the team norm allows it, 'approve once X lands' is fine. Never with an open authz, data-correctness or compatibility issue."

</details>

<details><summary><b>Q7 · "How do you mentor through review without being condescending?"</b></summary>

**Initial Prompt.** Teaching style.

**L5 Answer.** "I link to articles about best practices."

**Why L5 Stalls.** A link without a connection to *this* code reads as "go educate yourself."

**L7 Answer.** "Three moves. Name the class after fixing the instance: 'shared state needs coordination where the state lives.' Ask for the test that would have caught it, which teaches the failure model better than prose. And offer to pair on the hardest piece. I keep the teaching sentence separate from the blocking sentence, so the author can act on the fix without feeling lectured."

</details>

<details><summary><b>Q8 · "You're at minute 40 with six findings written up. What exactly do you write in the last five minutes?"</b></summary>

**Initial Prompt.** Landing the review.

**L5 Answer.** Keeps looking for more bugs.

**Why L5 Stalls.** An unranked set of comments makes the author (and the interviewer) do the synthesis.

**L7 Answer.** "The summary comment: verdict in one line; blockers ranked with one-line reasons; the shared root cause and its single fix; follow-ups with owners; non-blocking items as optional; one specific praise; an offer to pair. Then out loud: which layers I covered fully and which I'd still check with more time. Being explicit about coverage is part of the signal."

</details>

<details><summary><b>Q9 · "The author says: 'Can you just tell me what code to write?'"</b></summary>

**Initial Prompt.** Guidance vs solution.

**L5 Answer.** Writes the entire refactor into a comment.

**Why L5 Stalls.** Takes over ownership, produces an unreviewed design inside a review, and teaches nothing.

**L7 Answer.** "For mechanical fixes, yes: a GitHub suggestion block for the one-liners (`findForMerchant`, the second event field). For the design-level change, I sketch the shape in five or six lines (claim, ownership, reserve, call, classify, commit with outbox), point at the existing primitives, and offer to pair. Google's guide covers this balance: the developer owns the fix, and a reviewer can still give direct suggestions or code when that is more helpful."

</details>

<details><summary><b>Q10 · "How would you know your review comments are actually good, beyond 'the author fixed them'?"</b></summary>

**Initial Prompt.** Measuring review quality.

**L5 Answer.** "If the PR merges, the review worked."

**Why L5 Stalls.** Merging is the weakest signal. Bad reviews merge too, after friction.

**L7 Answer.** "A few signals. Escaped defects in code I reviewed, by layer, to see which layer I'm blind to. Round trips per comment: did the author need to ask what I meant? Whether authors seek me out for reviews or route around me. And whether the *class* of bug recurs in that author's later PRs, which shows whether the mentoring landed. Mechanically, a lint like `review_lint.py` keeps the tone and completeness basics automatic, so attention goes to the hard part: being right."

</details>

---

## 14. Checklist

**Per comment**
- [ ] Starts with a label and a blocking/non-blocking decoration.
- [ ] The code is the grammatical subject; no "you forgot/broke," no "just/obviously/simply."
- [ ] Blocking comments carry observation, impact, evidence, proposal, and an offer where useful.
- [ ] Confidence is stated and matches the evidence.
- [ ] Mechanical fixes use a suggestion block.

**Per review**
- [ ] Nits batched into one non-blocking comment, or left to the formatter.
- [ ] One specific, sincere praise.
- [ ] Follow-ups have tickets, owners and dates.
- [ ] One summary comment: verdict, ranked blockers, root cause, follow-ups, praise, offer.
- [ ] Review state matches the labels (Request changes ⇔ at least one blocker).

**In the live round**
- [ ] Narrated the model, not the keystrokes.
- [ ] Asked only decisive questions.
- [ ] Handled author pushback with acknowledge → evidence → experiment → decision rule.
- [ ] Landed the summary with time to spare and stated coverage honestly.

---

## 15. References

- Conventional Comments: format, labels and decorations. https://conventionalcomments.org/
- Google Engineering Practices: *How to write code review comments.* https://google.github.io/eng-practices/review/reviewer/comments.html
- Google Engineering Practices: *Handling pushback in code reviews.* https://google.github.io/eng-practices/review/reviewer/pushback.html
- Google Engineering Practices: *The Standard of Code Review.* https://google.github.io/eng-practices/review/reviewer/standard.html
- Google Engineering Practices: *Speed of Code Reviews.* https://google.github.io/eng-practices/review/reviewer/speed.html
- Bacchelli, A. & Bird, C. *Expectations, Outcomes, and Challenges of Modern Code Review.* ICSE 2013. https://www.microsoft.com/en-us/research/publication/expectations-outcomes-and-challenges-of-modern-code-review/
- GitHub Docs: *Incorporating feedback in your pull request* (suggested changes). https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/incorporating-feedback-in-your-pull-request
- Prometheus: *Metric and label naming.* https://prometheus.io/docs/practices/naming/
- Within this KB: [01 · How rounds are graded](01-how-companies-grade-live-pr-review-rounds-l5-vs-l6-vs-l7.md) · [02 · The 7-layer fault scan](02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md) · [README](../README.md)

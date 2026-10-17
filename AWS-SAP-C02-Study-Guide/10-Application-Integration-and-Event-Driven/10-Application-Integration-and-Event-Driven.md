# Chapter 10 — Application Integration: APIs, Messaging, Events & Workflows

> **Exam mapping:** D2 Task 2.1, D2 Task 2.4, D2 Task 2.5, D3 Task 3.3, D3 Task 3.4, D4 Task 4.4 | **Weight signal:** High | **Study time:** ~7 h
> [← Previous](../09-Databases-and-Caching/09-Databases-and-Caching.md) · [Index](../00-README-Start-Here.md) · [Next →](../11-Analytics-Streaming-and-AI-ML/11-Analytics-Streaming-and-AI-ML.md)

---

## 1. What the exam really tests here

At Associate level you learned "SQS decouples, SNS fans out." At Professional level the exam gives you a **messy existing system** or a **demanding new requirement** and asks you to choose the integration fabric, its semantics, and its failure handling. Expect these question shapes:

| Scenario shape | What you must decide |
|---|---|
| A monolith or tightly coupled tier fails under spikes; the database falls over | Put a **queue in front of the writer** (request buffering), scale consumers on **backlog per instance**, keep DB connections bounded |
| "Process each order exactly once, in order per customer" | **SQS FIFO** with `MessageGroupId = customerId`, deduplication ID, high-throughput mode; or Kinesis with partition key — and know which one fits |
| One event must reach many independent consumers | **SNS → SQS fan-out** vs **EventBridge** rules vs Kinesis multiple consumers — based on filtering, replay, throughput, targets |
| Multi-step business process with retries, human approval, compensation | **Step Functions Standard** (callback task token, Retry/Catch, saga) vs Express |
| Expose backend to partners with quotas, keys, private access, long-running requests | **API Gateway REST** (usage plans, private endpoint, resource policy, WAF, caching) vs HTTP API vs AppSync; async pattern when > 29 s |
| Migrate on-prem JMS/AMQP/MQTT apps with minimal code change | **Amazon MQ** (lift-and-shift) vs re-architect to SQS/SNS |
| Multi-account / multi-Region event routing and DR | EventBridge cross-account/cross-Region targets, **global endpoints**, archive & replay; SNS cross-account subscriptions |
| Modernize a monolith gradually | **Strangler fig** behind API Gateway / ALB, events via EventBridge (see [Chapter 13](../13-Migration-and-Modernization/13-Migration-and-Modernization.md)) |

The decisive skills:

1. **Semantics:** at-least-once vs exactly-once processing, ordering scope, duplicates, poison messages, idempotency.
2. **Limits that force design:** API Gateway 29 s integration timeout (and when it can be raised), 10 MB API payload, SQS/EventBridge 1 MiB messages (raised from 256 KiB), Step Functions 256 KiB state payload, 25,000-event Standard history, 5-minute Express max.
3. **Failure handling:** DLQs everywhere (SQS redrive, SNS subscription DLQ, EventBridge target DLQ, Lambda on-failure destinations), retries with backoff, partial batch responses.
4. **Choosing the least operational overhead** managed service that meets ordering/replay/throughput requirements.

---

## 2. Core concepts & services — deep dive

### 2.1 Amazon SQS (Simple Queue Service)

**What it is:** fully managed, pull-based message queue. Producers `SendMessage`; consumers poll with `ReceiveMessage`, process, then `DeleteMessage`. Messages are stored redundantly across multiple AZs in a Region. Unlimited backlog.

#### Standard vs FIFO

| Property | Standard queue | FIFO queue (`name.fifo`) |
|---|---|---|
| Delivery | **At-least-once** (occasional duplicates) | **Exactly-once processing** (dedup within a 5-minute interval) |
| Ordering | Best-effort | **Strict per message group** (`MessageGroupId`) |
| Throughput | Nearly unlimited API calls per second | Per partition: **300 TPS per API action** (send/receive/delete), **3,000 msg/s with batching** (10 per batch). **High-throughput mode** raises this per Region — e.g. up to **70,000 TPS non-batched / 700,000 msg/s batched** in us-east-1, us-west-2, eu-west-1; lower in other Regions (as low as 2,400 TPS default) |
| In-flight messages | ~120,000 (soft) | 120,000 (raised in 2024 from 20,000; can request more) |
| Per-message delay (timers) | Yes | No — queue-level delay only |
| Use | Max throughput, idempotent consumers | Order + no duplicates (financial, inventory, command sequences) |

**FIFO mechanics you must know:**
- **`MessageGroupId`** (required): ordering unit. Messages in the same group are delivered in order and **one group is processed by only one consumer at a time** (while a message of the group is in flight, later messages of that group are blocked). Parallelism = number of active groups. Use many distinct group IDs (e.g. per customer/order) to scale; a single group ID serializes everything.
- **Deduplication:** `MessageDeduplicationId` explicit, or **content-based deduplication** (SHA-256 of body). Duplicates sent within the **5-minute dedup interval** are accepted but not delivered twice.
- **High-throughput FIFO:** set `DeduplicationScope = messageGroup` and `FifoThroughputLimit = perMessageGroupId`. SQS hashes the group ID to partitions; throughput scales with partitions, so you need **many group IDs**.
- **Fair queues (2025, standard queues):** setting `MessageGroupId` on a *standard* queue now acts as a **tenant identifier** for noisy-neighbour mitigation — SQS prioritizes quiet tenants' messages when one tenant builds a backlog. It does **not** impose ordering. Useful for multi-tenant SaaS queues.

#### Key settings and limits (verified)

| Setting | Value |
|---|---|
| **Max message size** | **1 MiB (1,048,576 bytes)** — raised from 256 KiB in **August 2025** for standard and FIFO. Larger → **Extended Client Library** (Java, Python) stores payload in S3, up to 2 GB |
| Retention | 1 min – **14 days**, default **4 days** |
| Visibility timeout | 0 s – **12 h**, default **30 s** |
| Delay (queue or message timer) | 0 – **15 min** |
| Long polling wait | 1 – **20 s** (`WaitTimeSeconds` / `ReceiveMessageWaitTimeSeconds`) |
| Batch | up to **10 messages** per Send/Receive/Delete batch |
| Message attributes | up to 10 |
| Pricing | per request; each **64 KB chunk** of a payload is billed as one request — batching and long polling cut cost |

**Visibility timeout:** after a consumer receives a message, it is hidden for the visibility timeout. If not deleted in time, it reappears (→ duplicate processing). Set it to cover worst-case processing; extend in flight with `ChangeMessageVisibility` (heartbeat). For Lambda consumers set it to **≥ 6× the function timeout** (plus batching window).

**Short vs long polling:** short polling samples a subset of servers and can return empty even when messages exist; **long polling** waits up to 20 s and queries all servers → fewer empty responses, lower cost. Exam: "reduce cost of empty receives / reduce latency without busy-waiting" → **long polling**.

**Delay queues vs visibility timeout:** delay hides a message *when it is first enqueued*; visibility timeout hides it *after it is received*.

#### Dead-letter queues and redrive
- **Redrive policy** on the source queue: `deadLetterTargetArn` + **`maxReceiveCount`** (receives before moving to DLQ). Lambda guidance: `maxReceiveCount ≥ 5`.
- **Redrive allow policy** on the DLQ: allow all / specific (up to 10) / deny all source queues.
- DLQ must be the **same type** (FIFO source → FIFO DLQ), **same account and Region**.
- **DLQ redrive** (console/API `StartMessageMoveTask`) moves messages back to the source (or another) queue after fixing the bug.
- **Retention trap:** for **standard** queues, expiration is based on the **original enqueue timestamp** — set DLQ retention **longer** than the source queue. For FIFO the timestamp resets when moved.
- For FIFO, a DLQ can break strict ordering — acceptable for most apps, not for sequence-dependent commands.

#### Security
- **SSE-SQS** (SQS-managed keys) or **SSE-KMS** (customer managed key; producers need `kms:GenerateDataKey`, consumers `kms:Decrypt`; SNS/EventBridge publishing to an SSE-KMS queue needs the key policy to allow that service principal).
- **Queue (resource) policy** for cross-account access and for allowing `sns.amazonaws.com` / `events.amazonaws.com` with `aws:SourceArn` condition.
- **VPC interface endpoint** (PrivateLink) for private access; endpoint policies restrict which queues.

#### Scaling consumers — backlog per instance (exam favourite)
Do **not** scale an EC2/ECS consumer fleet on CPU or raw `ApproximateNumberOfMessagesVisible` alone. AWS's recommended pattern:

```text
backlog_per_instance = ApproximateNumberOfMessagesVisible / RunningCapacity
acceptable_backlog   = acceptable_latency (s) / avg_processing_time_per_msg (s)
Target tracking policy on the custom metric (metric math) with target = acceptable_backlog
```

Example: 10 s acceptable latency, 0.1 s per message → target 100 messages per instance. ECS Service Auto Scaling and EC2 Auto Scaling both support target tracking on a metric-math expression. **KEDA**/Karpenter equivalent on EKS.

#### Lambda event source mapping (ESM) for SQS
- Lambda **polls** the queue for you (no charge for polling beyond SQS requests); queue and function in **same Region**, can be **different accounts**.
- **Batch size:** standard up to **10,000** (need `MaximumBatchingWindowInSeconds ≥ 1` for > 10); FIFO max **10**. Batching window up to 300 s (standard only).
- **Scaling (standard queues):** starts with 5 concurrent invokes, adds up to **300 concurrent invokes per minute**, max **1,250** concurrent per ESM by default. FIFO concurrency ≤ number of active message groups.
- **Maximum concurrency** (ESM setting, **2–1,000**): caps how many concurrent invocations this queue drives — protects downstream DBs and prevents one queue from starving others. Preferred over reserved concurrency for throttling SQS consumers (reserved concurrency causes throttles → messages return to queue → can land in DLQ).
- **Provisioned mode** (2025): dedicated event pollers (min 2–200, max 2–2,000), ~3× faster scaling, up to 100,000 concurrent invocations; **mutually exclusive** with maximum concurrency; extra cost.
- **Partial batch response:** enable `ReportBatchItemFailures` and return `batchItemFailures` with failed message IDs. Without it, **one failure returns the whole batch** to the queue (reprocessing successes). For FIFO, stop processing at first failure and return that and all subsequent messages.
- **Filter criteria** on the ESM drop non-matching messages before invocation (they are deleted from the queue — not retried).

#### SQS as a write buffer for databases
```text
Clients -> API GW / ALB -> producer (Lambda/ECS) -> SQS -> consumers (bounded concurrency) -> RDS/Aurora
```
- Smooths spikes; DB sees steady write rate; consumers can batch inserts.
- Bound consumer concurrency (Lambda max concurrency or ASG max) to stay below DB connection limits; pair with **RDS Proxy**.
- Trade-off: API returns **202 Accepted**, so the client needs a status endpoint or callback (async API pattern).

---

### 2.2 Amazon SNS (Simple Notification Service)

**What it is:** managed **pub/sub push** service. Publishers send to a **topic**; SNS pushes copies to all subscriptions. No persistence for later consumers (messages not retained — except FIFO archive, below).

**Subscription protocols:** SQS, Lambda, HTTP/S, email/email-JSON, SMS, mobile push (APNs, FCM, ADM, Baidu, etc.), **Amazon Data Firehose** (archive to S3/Redshift/OpenSearch).

#### Standard vs FIFO topics

| | Standard topic | FIFO topic (`.fifo`) |
|---|---|---|
| Ordering | Best-effort | Strict per `MessageGroupId` |
| Duplicates | Possible | Deduplicated (5-min window, content-based option) |
| Subscribers | All protocols | **SQS queues** (FIFO for strict order/dedup end-to-end; a standard queue subscriber loses those guarantees) |
| Subscriptions/topic | 12,500,000 | 100 |
| Throughput | Regional account publish quota (e.g. 30,000 msg/s in us-east-1, lower elsewhere; soft) | 300 msg/s per message group; **3,000 msg/s or 20 MB/s per topic** when `FifoThroughputScope = Topic`; higher per-topic throughput when scope = `MessageGroup` |
| Archive & replay | No | **Yes** — topic-owner archive policy, subscriber replay |

**Message size:** default max **256 KiB**; can be raised to **1 MiB** by setting the topic's `MaximumMessageSize` attribute (2025–26 change); larger via **SNS Extended Client Library** (S3, up to 2 GB). Batch publish (`PublishBatch`) up to 10 messages.

#### Message filtering
- **Subscription filter policy** (JSON) so each subscriber receives only matching messages; the topic delivers to subscribers selectively instead of each consumer discarding irrelevant messages.
- `FilterPolicyScope`: `MessageAttributes` (default) or **`MessageBody`** (payload-based filtering).
- Operators: exact, prefix, suffix, anything-but, numeric ranges, exists, IP address, `$or`.
- Quotas: 200 filter policies per topic, 10,000 per account (default).

#### Delivery retries and DLQ
- **AWS-managed endpoints (SQS, Lambda):** 100,015 attempts over **23 days**.
- **Customer-managed (SMTP, SMS, mobile push):** 50 attempts over 6 hours.
- **HTTP/S:** customizable delivery policy (backoff function, `maxReceivesPerSecond` throttle), total retry time ≤ 3,600 s.
- After retries are exhausted the message is **dropped unless a subscription DLQ** (an SQS queue, set via the subscription's redrive policy) is configured. Client-side errors (e.g. deleted endpoint, policy denial) go to the DLQ without retries. FIFO topic → FIFO DLQ.

#### Cross-account and cross-Region
- Topic **access policy** grants `sns:Subscribe`/`sns:Publish` to other accounts or an organization (`aws:PrincipalOrgID`).
- For SNS → SQS cross-account: the **SQS queue policy** must allow `sns.amazonaws.com` `sqs:SendMessage` with `aws:SourceArn = topic ARN`; subscription confirmation is done by the queue owner (or the topic owner if they have permission).
- SNS can deliver to SQS queues and Lambda functions **in other Regions**.
- **SSE-KMS** on the topic: publishers need `kms:GenerateDataKey`/`Decrypt`; for KMS-encrypted SQS subscribers the key policy must allow SNS.
- **Message data protection** policies can detect/mask PII in transit (audit, de-identify, deny).

#### Raw message delivery
For SQS/HTTP/Firehose subscriptions, enable **raw message delivery** to send the original payload without the SNS JSON envelope (smaller, simpler consumers; loses SNS metadata).

#### Mobile push / SMS
- Platform applications + endpoints per device token; "direct publish" to one endpoint or to a topic.
- SMS sending is backed by **AWS End User Messaging SMS** (the former Pinpoint SMS); spend thresholds, origination identities, and sandbox apply. For two-way/campaign messaging, that service (not SNS) is the better fit.

---

### 2.3 Amazon EventBridge (formerly CloudWatch Events)

**What it is:** serverless **event router**. Producers put JSON events onto an **event bus**; **rules** with **event patterns** match events and route them to up to **5 targets** per rule, with optional **input transformation**. Content-based routing, many native AWS targets, SaaS integration.

#### Buses
| Bus | Purpose |
|---|---|
| **Default bus** | Receives events from AWS services (EC2 state changes, CodePipeline, Health, GuardDuty findings, S3 via EventBridge notifications, CloudTrail API calls) |
| **Custom bus** | Your applications' domain events (`PutEvents`) — one per domain/team is common |
| **Partner bus** | SaaS partner events (Salesforce, Zendesk, Datadog, Auth0, etc.) |

**Event structure:** `version, id, detail-type, source, account, time, region, resources[], detail{}`. Max event size **1 MB** (raised from 256 KB in **January 2026** in most commercial Regions; a few newer Regions excepted — verify Region if a question hinges on it). `PutEvents` accepts up to 10 entries per request on classic buses (100 on the new Custom Event Bus).

#### Rules and patterns
- Pattern matching on any field: exact, **prefix**, **suffix**, **anything-but**, **numeric** ranges, **exists**, **IP address/CIDR**, **wildcard**, `$or`, equals-ignore-case.
- **Scheduled rules** (cron/rate) still exist but **EventBridge Scheduler** is the recommended replacement.
- Default quota: 300 rules per bus (adjustable), **5 targets per rule (hard)** — need more → fan out to SNS or another bus.
- **Input transformer:** `InputPathsMap` extracts fields; `InputTemplate` builds a custom payload (e.g. a readable Slack/SNS message, or the exact JSON an API destination expects).

#### Delivery, retries, DLQ
- Retry policy per target: up to **185 attempts** and up to **24 hours** max event age (defaults). After that, event goes to a **target DLQ (SQS)** if configured, otherwise dropped.
- At-least-once delivery; consumers must be idempotent (use the event `id`).
- Invocations throttle quota per Region (e.g. 18,750/s us-east-1) and `PutEvents` TPS quota (e.g. 10,000/s us-east-1); both soft.

#### Cross-account and cross-Region routing
- **Bus-to-bus:** rule in sender account targets an **event bus in another account and/or Region**. Receiver bus needs a **resource policy** (account IDs or `aws:PrincipalOrgID`). Since March 2023 new cross-account bus targets require an **IAM role** on the sender rule (so SCPs apply).
- **Direct cross-account targets (January 2025):** a rule can target **SQS, Lambda, SNS, Kinesis Data Streams, API Gateway** in another account directly, provided the target has a resource-based policy allowing it — no intermediate bus needed in the receiving account.
- **No multi-hop:** events received from another account are **not forwarded again** to a third account by the receiver's rules (and bus→bus→bus chains within an account don't propagate). Design a hub topology deliberately.
- Central pattern: all accounts send security/ops events (GuardDuty, Config, Health) to a **central bus in a security/ops account** via an organization-wide resource policy.
- Cross-Region bus targets are supported to the listed destination Regions; events sent cross-account are billed to the sender.

#### Archive & replay
- **Archive** stores events from a bus (optionally filtered by pattern) with a retention period (or indefinite).
- **Replay** re-sends archived events for a time window **back to the source bus** (you can limit to specific rules). Replayed events carry a `replay-name` field — consumers can detect them.
- Uses: recover after a consumer bug, backfill a new consumer, testing. Not ordered; not a substitute for a durable log like Kinesis/MSK where consumers control position.

#### Schema registry
- Stores **OpenAPI/JSONSchema** schemas for AWS events, partner events, and your custom events; **schema discovery** on a bus infers schemas automatically. Generates **code bindings** (Java, Python, TypeScript, Go). Supports contract-first event-driven development.

#### EventBridge Pipes
Point-to-point integration: **Source → (Filter) → (Enrichment) → Target**, no glue code.
- **Sources:** SQS, Kinesis Data Streams, DynamoDB Streams, Amazon MSK, self-managed Kafka, Amazon MQ (ActiveMQ/RabbitMQ).
- **Enrichment:** Lambda, Step Functions **Express** (sync), API Gateway, API destination.
- **Targets:** most EventBridge targets (Step Functions, SQS, SNS, Kinesis, Firehose, ECS task, Lambda, event bus, API destination, etc.).
- Batching, ordering preserved for ordered sources (e.g. Kinesis shard / DynamoDB stream / FIFO group), filtering reduces downstream cost.
- Exam cue: "DynamoDB Stream → filter only `INSERT` of status=NEW → start Step Functions workflow **with no custom code**" → **Pipes**. Pipes is **1:1**; for 1:many use a bus.

#### EventBridge Scheduler
- Serverless scheduler: **one-time** (`at()`) and **recurring** (`rate()`, `cron()`) schedules, **time zones and DST**, **flexible time windows**, retries + DLQ, **universal targets** (thousands of AWS API actions via SDK integration) plus templated targets (Lambda, SQS, SNS, Step Functions, ECS RunTask, etc.).
- Default quota **10,000,000 schedules per Region** (adjustable to billions), invocations throttle 1,000 TPS in major Regions (adjustable), target `Input` ≤ 256 KB. `ActionAfterCompletion = DELETE` cleans up one-time schedules.
- Exam cue: "millions of per-user reminders / delete trial accounts after 30 days / per-tenant schedules" → **Scheduler** (not cron on EC2, not one EventBridge rule per schedule).

#### Global endpoints (Regional failover for event ingestion)
```text
            PutEvents (endpointId)  -- SigV4A --
Producer ─────────────────────────────▶ Global endpoint
                                         │ Route 53 health check (CloudWatch alarm on bus metrics)
                         healthy ▼                       ▼ unhealthy
                Primary Region custom bus      Secondary Region custom bus (same name)
                          └──── event replication (optional, recommended) ────┘
```
- Assign a **Route 53 health check**; on failure, custom events route to the secondary Region's bus. AWS guidance: **RTO and RPO ~360 s (max 420 s)** with recommended alarm configuration.
- Requires a **same-named custom bus in both Regions** in the same account; rules/targets must exist in both.
- **Event replication** (extra cost) sends events to both Regions; needed for **automatic fail-back**; consumers must be idempotent and handle events processed in both Regions.
- Only for **custom events** you publish (not AWS service events). Producers use the SDK with the CRT library (SigV4A).

#### API destinations
- Rule/pipe target = any **HTTPS endpoint** (SaaS or your own) with a **connection** holding auth (Basic, API key, OAuth client credentials) stored in **Secrets Manager**. Connections also support private endpoints in a VPC (via VPC Lattice resource configurations).
- **Rate limiting per destination** (default 300 invocations/s, adjustable) protects the endpoint; **5-second client timeout**; retries on 401/407/409/429/5xx honour `Retry-After`.
- Exam cue: "send events to a third-party SaaS webhook with OAuth and throttle to its rate limit, without Lambda" → **API destination**.

> **Emerging (not core SAP-C02):** In **September 2026** AWS launched an enhanced **Custom Event Bus** (existing buses renamed "Custom event bus – classic"). It uses **Subscribers** instead of rules/targets, has built-in retention (24 h, extendable to 1 year) with replay from a position, ordered delivery, content-based deduplication, and cross-account sharing via **AWS RAM**. Exam questions written for SAP-C02 assume the classic rules/targets model.

---

### 2.4 AWS Step Functions

**What it is:** serverless **orchestrator**. You define a state machine in **Amazon States Language (ASL)** (JSON; JSONPath or **JSONata** query language, plus workflow **variables** since late 2024). States: `Task`, `Choice`, `Wait`, `Parallel`, `Map`, `Pass`, `Succeed`, `Fail`. Integrates with 200+ AWS services via optimized integrations and the **AWS SDK integration** (thousands of API actions), plus the **HTTP Task** (call any HTTPS API using an EventBridge connection for auth).

#### Standard vs Express (memorize)

| | **Standard** | **Express** |
|---|---|---|
| Max duration | **1 year** | **5 minutes** |
| Execution semantics | **Exactly-once** (tasks never run twice unless you configure Retry) | **Async Express: at-least-once**; **Sync Express: at-most-once** |
| Pricing | Per **state transition** | Per **execution + duration + memory** |
| Execution history | Stored by service for **90 days**, visual debugging; max **25,000 events** per execution | Not stored — enable **CloudWatch Logs** |
| State transition rate | Throttled (token bucket, soft quota; e.g. 5,000/s in us-east-1/us-west-2/eu-west-1) | Effectively unlimited |
| Start rate | Lower (e.g. 300/s refill in large Regions, soft) | Much higher (e.g. 6,000/s, soft) |
| `.sync` and `.waitForTaskToken` | **Supported** | **Not supported** |
| Distributed Map / Activities | Supported | Not supported (but Distributed Map *children* can be Express) |
| Redrive failed executions | Yes (within 14 days) | No |
| Best for | Long-running, auditable, **non-idempotent** steps (payments, EMR jobs, human approval) | High-volume, short, **idempotent** event processing (IoT ingestion, stream transforms, synchronous API backends) |

Workflow type is **immutable** after creation. Common hybrid: a **Standard parent** orchestrates the long process and calls **Express children** for high-volume short sub-steps (cheaper).

Payload limit: **256 KiB** per state input/output/execution (unchanged — Lambda async, SQS and EventBridge went to 1 MB, Step Functions did not). Larger → store in S3 and pass a pointer (claim check), or use Distributed Map `ItemReader`/`ResultWriter`.

#### Service integration patterns

| Pattern | ARN suffix | Behaviour | Example |
|---|---|---|---|
| **Request-response** | (none) | Call the API and move on as soon as the HTTP response returns | Publish to SNS, put item in DynamoDB, start a Glue job without waiting |
| **Run a job** | **`.sync`** | Call the API and **wait for the job to complete** | `glue:startJobRun.sync`, `ecs:runTask.sync`, `batch:submitJob.sync`, nested `states:startExecution.sync:2`, EMR, SageMaker AI training, CodeBuild |
| **Wait for callback** | **`.waitForTaskToken`** | Pass a **task token** to an external system; the workflow **pauses** (up to 1 year in Standard) until something calls **`SendTaskSuccess` / `SendTaskFailure`** with the token; optional `HeartbeatSeconds` + `SendTaskHeartbeat` | **Human approval**, waiting on a legacy on-prem system via SQS, third-party processing |

Human-approval pattern:
```text
Step Functions (Standard)
  └─ Task: sns:publish.waitForTaskToken  (email contains approve/reject links carrying the token)
        └─ Approver clicks link -> API Gateway -> Lambda -> SendTaskSuccess(token, {"approved":true})
  └─ Choice: approved? -> continue : notify & end
  (TimeoutSeconds / HeartbeatSeconds guard against approvers who never respond)
```

#### Error handling
- **Retry** (per state): `ErrorEquals` (e.g. `States.TaskFailed`, `States.Timeout`, `Lambda.TooManyRequestsException`, custom error names), `IntervalSeconds`, `MaxAttempts`, `BackoffRate`, `MaxDelaySeconds`, `JitterStrategy: FULL`.
- **Catch**: after retries are exhausted, route to a fallback state; use `ResultPath` (e.g. `$.error`) to keep the original input plus the error.
- `States.ALL` catches everything (must be last). Always set `TimeoutSeconds` on callback tasks.
- **Redrive** a failed Standard execution from the failed step instead of restarting from scratch.

#### Map and Distributed Map
- **Inline Map:** iterations run inside the parent execution; up to 40 concurrent iterations; shares the 25,000-event history and 256 KiB payload limits.
- **Distributed Map:** each iteration is a **child workflow execution** (Standard or Express) with its own history. **Up to 10,000 parallel child executions**; reads items directly from **S3** (`ItemReader`: object listing, JSON/JSONL, CSV, Parquet, S3 Inventory manifest), batches items (`ItemBatcher`), writes results to S3 (`ResultWriter`), supports `ToleratedFailurePercentage/Count` and Map Run redrive. Parent must be **Standard**.
- Use when the dataset is > 256 KiB, history would exceed 25,000 events, or you need > 40 concurrency. Exam cue: "process millions of S3 objects/CSV rows in parallel, serverless, minimal code" → **Distributed Map** (EMR/Glue for real big-data transformation; AWS Batch for long-running containers).

#### Saga / compensation
Each step has a compensating action; on failure, `Catch` routes to compensations in reverse order:
```text
ReserveInventory ─▶ ChargePayment ─▶ ShipOrder ─▶ Success
      │ Catch            │ Catch          │ Catch
      ▼                  ▼                ▼
    Fail          ReleaseInventory ◀─ RefundPayment
                         │
                         ▼
                  Fail("OrderFailed")
```
A Standard workflow (exactly-once, durable, auditable) is the default choice for sagas; compensations must be idempotent.

---

### 2.5 Amazon API Gateway

**What it is:** managed front door for REST, HTTP and WebSocket APIs: auth, throttling, transformation, caching, monitoring. It integrates with Lambda, HTTP backends, AWS services directly (e.g. API Gateway → SQS / Step Functions / DynamoDB / Kinesis **without Lambda**), and private resources via VPC links.

#### REST vs HTTP vs WebSocket APIs

| Feature | **REST API** (v1) | **HTTP API** (v2) | **WebSocket API** |
|---|---|---|---|
| Positioning | Full-featured API management | Low-latency, **lower-cost** proxy | Persistent bidirectional connections |
| Endpoint types | **Edge-optimized, Regional, Private** | Regional only | Regional |
| Auth | **IAM (SigV4), Cognito user pools, Lambda authorizer (token/request)**, resource policies; API keys identify clients | IAM, **JWT authorizer** (Cognito or any OIDC), Lambda authorizer | IAM, Lambda authorizer (on `$connect`) |
| Usage plans & API keys | **Yes** | No | No |
| Caching | **Yes** (stage cache 0.5–237 GB, TTL 0–3,600 s, default 300 s) | No | No |
| Request validation, VTL mapping templates | **Yes** | Parameter mapping only | Yes (VTL) |
| AWS WAF | **Yes** | No (put CloudFront + WAF in front) | No |
| Resource policies | **Yes** | No | No |
| Private integrations (VPC link) | **NLB; ALB directly via VPC link v2 (Nov 2025)** | ALB, NLB, **Cloud Map** | Private integration via VPC link |
| mTLS | Yes (custom domain) | Yes (custom domain) | No |
| Canary deployments | **Yes** | No | No |
| X-Ray tracing | Yes | No | No |
| Integration timeout | 50 ms–**29 s default**; **Regional and private** REST APIs can raise it above 29 s via Service Quotas (may require a lower account throttle quota); edge-optimized fixed at 29 s | **30 s max (hard)** | 29 s (hard) |
| Payload | **10 MB** | 10 MB | 128 KB message (32 KB frames) |
| Response streaming | **Yes (Nov 2025)** — progressive responses, integrations up to 15 min, responses > 10 MB | No | n/a |

**WebSocket specifics:** routes `$connect`, `$disconnect`, `$default` and custom routes selected by a JSON field; the backend pushes to clients through the **`@connections` callback API** (`POST https://{api-id}.execute-api.{region}.amazonaws.com/{stage}/@connections/{connectionId}`); you store connection IDs (e.g. in DynamoDB). Limits: **2-hour max connection duration, 10-minute idle timeout**, 500 new connections/s per account per Region (soft). Use cases: chat, live dashboards, notifications.

#### Endpoint types
- **Edge-optimized** (REST only): requests enter through an AWS-managed CloudFront network that you can't customize; good for geographically distributed clients. Custom-domain ACM certificate must be in **us-east-1**.
- **Regional:** clients in the same Region, or **your own CloudFront distribution** in front (full control: WAF at the edge, cache policies, multiple origins). Certificate in the API's Region. Also the building block for **multi-Region active-active/failover with Route 53** on a custom domain.
- **Private** (REST only): reachable only through an **interface VPC endpoint for `execute-api`**. Requires a **resource policy** allowing the endpoint (`aws:SourceVpce`) or VPC (`aws:SourceVpc`). Can be shared cross-account (the resource policy allows another account's VPC endpoint) and reached from on-premises over Direct Connect/VPN via the endpoint. **Private custom domain names** are supported (2024). Gotcha: enabling **private DNS** on the `execute-api` endpoint makes every `*.execute-api` hostname resolve to the endpoint from that VPC, so *public* APIs become unreachable from that VPC by their default hostname.

#### Throttling and quotas
- **Account-level default:** **10,000 RPS** per account per Region **with a burst of 5,000** (token bucket), shared across REST, HTTP and WebSocket APIs — **soft** (raise via Service Quotas; AWS sets the burst). Some newer Regions default to 2,500/1,250.
- Throttling hierarchy (narrower limits can't exceed broader ones): **per-client per-method (usage plan) → per-client (usage plan) → per-method (stage) → stage → account/Region**.
- **Usage plans + API keys** (REST only): per-key **throttle** (rate + burst) and **quota** (requests per day/week/month). API keys are for **metering and identifying** clients, **not** authentication — combine them with IAM, Cognito or a Lambda authorizer.
- Throttled requests return **429 Too Many Requests**; clients retry with exponential backoff and jitter.

#### Error codes to interpret
| Code | Meaning | Typical fix |
|---|---|---|
| **403 Forbidden** | Missing/invalid auth, WAF block, resource-policy deny, missing API key, calling a private API from outside its VPC endpoint | Check authorizer, resource policy, WAF, endpoint type |
| **429** | **Throttled** (account/stage/method/usage plan) or usage-plan quota exhausted | Raise limits, usage plans, client backoff, caching |
| **500** | Integration or mapping error | Fix the template or backend error handling |
| **502 Bad Gateway** | Backend returned an **invalid response** (e.g. Lambda proxy output in the wrong format, unhandled Lambda error) | Fix the Lambda response format and error handling |
| **503** | Backend unavailable | Health, capacity |
| **504 Gateway Timeout** | **Integration timed out** (> 29 s default) or endpoint unreachable | Make it **async** (202 + polling/callback/WebSocket), raise the Regional/private timeout quota, response streaming, optimize the backend |

#### Caching
Stage-level cache (REST only) with per-method overrides; cache keys from headers, query strings and path parameters. Clients can send `Cache-Control: max-age=0` to bypass the cache — require authorization for that. Encrypt the cache; billed hourly by size. Use it to cut backend load and latency for read-heavy endpoints.

#### Authorizers
- **IAM (SigV4):** AWS principals (services, cross-account roles, IAM Identity Center users with temporary credentials); combine with a **resource policy** for cross-account access.
- **Cognito user pool authorizer** (REST) / **JWT authorizer** (HTTP): validate tokens from user pools or any OIDC IdP; scopes for fine-grained access.
- **Lambda authorizer:** custom logic (third-party tokens, header/IP checks); returns an IAM policy (REST) or a simple boolean response (HTTP); **cache** results (TTL up to 1 h) to cut cost and latency.
- **Resource policy** (REST): allow/deny by account, source IP CIDR, VPC or VPC endpoint — the only native way to secure private APIs and restrict by IP.

#### mTLS
Mutual TLS on a **custom domain name** for REST and HTTP APIs: upload a **truststore** (PEM bundle of CA certificates, up to 1,000) to S3; clients must present certificates signed by those CAs. **Disable the default `execute-api` endpoint** so clients can't bypass mTLS. Typical for B2B, IoT, open banking.

#### VPC links / private integrations
- **REST API:** VPC link to an **NLB** (v1, AWS now recommends against new v1 links) or, since **November 2025**, **VPC link v2 directly to an ALB** (no NLB in front). The load balancer, VPC link and API must be in the same account.
- **HTTP API:** VPC link to **ALB, NLB, or AWS Cloud Map** services (e.g. ECS service discovery).
- Exam cue: "expose ECS services in private subnets through API Gateway without making them public" → **VPC link**.

#### Deployments, CORS
- **Stages** (dev/test/prod) with **stage variables**; **canary release** on REST stages sends a configurable % of traffic to a new deployment with separate metrics/logs, then you promote it. For Lambda backends, also use **Lambda aliases with weighted routing / CodeDeploy**.
- **CORS:** for browser calls from another origin, enable CORS (preflight `OPTIONS` returning `Access-Control-Allow-Origin/Methods/Headers`). With **Lambda proxy integration, the function itself must return the CORS headers** on real responses. Classic symptom: "works with curl, fails in the browser with a CORS error" → configure CORS / return the headers.

---

### 2.6 AWS AppSync

- Managed **GraphQL** API service (plus **AppSync Events**, 2024, for serverless WebSocket pub/sub channels). Resolvers (JavaScript or VTL; unit or pipeline) connect to DynamoDB, Aurora (Data API), OpenSearch, Lambda, HTTP endpoints, EventBridge and Bedrock.
- **Real-time subscriptions** over managed WebSockets — clients subscribe to mutations; AppSync manages connection state for you (with API Gateway WebSocket you store connection IDs yourself).
- Auth modes: API key, IAM, Cognito user pools, OIDC, Lambda; multiple modes per API.
- Server-side **caching**, **private APIs** (VPC endpoint), WAF.
- **Merged APIs:** combine several team-owned **source APIs** (schemas, resolvers, data sources) into one merged endpoint, composed at **build time**; source APIs can live in other accounts via **AWS RAM**; auto-merge on change; default 10 source APIs per merged API (adjustable). Exam cue: "multiple teams own separate GraphQL domains, want one endpoint with independent deployments, cross-account" → **AppSync Merged API**.
- Choose AppSync when mobile/web clients need **flexible queries that aggregate several data sources in one round trip**, offline sync (Amplify), and real-time updates.

---

### 2.7 Amazon MQ

- Managed **Apache ActiveMQ** and **RabbitMQ** brokers speaking industry-standard protocols and APIs: **JMS, AMQP, MQTT, STOMP, OpenWire, WebSocket**.
- **When to choose it:** **lift-and-shift** of applications that already use these protocols or brokers (on-premises ActiveMQ/RabbitMQ, or other JMS brokers) **without rewriting** messaging code. For **new** cloud-native apps, SQS/SNS/EventBridge are cheaper, scale further and need less operations.
- **Deployment modes:**
  - ActiveMQ: **single-instance** (one AZ; EBS or EFS storage) or **active/standby** (two brokers in two AZs sharing **EFS** storage; clients use the **failover transport** URL listing both endpoints; reboots and maintenance windows trigger failover). Network of brokers for scale-out; **cross-Region data replication** for DR.
  - RabbitMQ: single-instance or **3-node cluster** across AZs.
- Runs **in your VPC** (private) or publicly accessible; priced per broker-instance hour plus storage — **not serverless**, so you size capacity.
- Exam traps: Amazon MQ is **not** for unlimited scale; SQS is **not** a drop-in JMS broker (the SQS JMS client supports only a subset). "Minimal code changes for a JMS/AMQP/MQTT app" → **Amazon MQ**.

---

### 2.8 Amazon AppFlow

- Fully managed, no-code **bidirectional data flows** between **SaaS** applications (Salesforce, SAP via OData, ServiceNow, Zendesk, Slack, Google Analytics, Marketo, etc.) and AWS (S3, Redshift, EventBridge, and back to SaaS such as Salesforce).
- Triggers: **on demand, scheduled, or event-driven** (e.g. Salesforce change events). Transformations: field mapping, filtering, masking, validation, S3 output in Parquet/CSV/JSON with partitioning/aggregation.
- **AWS PrivateLink** for SaaS providers that support it (traffic stays off the public internet); KMS encryption.
- Exam cue: "ingest Salesforce data into S3/Redshift daily, no custom code" → **AppFlow** (not Lambda polling scripts, not custom Glue connectors).

---

### 2.9 Streaming neighbours — Kinesis Data Streams and Amazon MSK (detail in Chapter 11)

- **Kinesis Data Streams:** ordered **per shard** (partition key); retention **24 h default, up to 365 days**; consumers **replay** from any position; many consumers read the same data (shared 2 MB/s per shard, or **enhanced fan-out** at 2 MB/s per consumer per shard); on-demand or provisioned capacity.
- **Amazon MSK:** managed **Apache Kafka** (provisioned, Serverless, Express brokers): topics/partitions, consumer groups, long retention, Kafka ecosystem (Connect, Streams). Choose it for Kafka API compatibility or migrating existing Kafka.
- Queue vs stream: a **queue** removes a message once one consumer processes it (competing consumers); a **stream** is a durable log that many consumers read independently and can **replay**.

---

## 3. Architecture patterns

### 3.1 Decoupling with a queue (load levelling / request buffering)
```text
Web/API tier ──SendMessage──▶ [ SQS ] ──poll──▶ Worker ASG / ECS service / Lambda (max concurrency N)
                                │                         │
                                └── DLQ (maxReceiveCount) └──▶ Aurora/RDS (via RDS Proxy)
```
- **When:** producer and consumer scale differently; spikes would overwhelm a database or legacy system; consumers can be briefly unavailable.
- **Trade-offs:** eventual consistency; client gets `202 Accepted`; must handle duplicates (standard queue) and poison messages (DLQ).
- **Protect the DB:** cap consumer concurrency (Lambda ESM **maximum concurrency**, ASG max size), batch writes, RDS Proxy for connection pooling.

### 3.2 Competing consumers
Many identical workers poll one queue; each message goes to one worker. Scale on **backlog per instance**. Set the visibility timeout above worst-case processing time; make processing idempotent. With FIFO, parallelism = number of active message groups.

### 3.3 Fan-out (pub/sub)
```text
                    ┌─▶ SQS: inventory  ─▶ Lambda
Order svc ─▶ SNS ───┼─▶ SQS: shipping   ─▶ ECS        (filter policy: type=physical)
  topic             ├─▶ SQS: analytics  ─▶ Firehose → S3
                    └─▶ HTTPS webhook (partner)       (DLQ per subscription)
```
- **SNS → SQS** gives each consumer its **own durable buffer**, independent retries and scaling. Use **filter policies** so consumers get only relevant messages. Use **SNS FIFO → SQS FIFO** for ordered fan-out.
- **EventBridge alternative:** use it when you need content-based routing on any field, many AWS targets, SaaS sources, schema registry, archive/replay, or cross-account bus routing. Use **SNS** for very high fan-out (millions of subscriptions), SMS/email/mobile push, or the lowest latency.
- **S3 event fan-out:** an S3 event notification can't send the *same* event type/prefix to multiple destinations → send to **SNS (fan out)** or enable **EventBridge notifications** on the bucket.

### 3.4 Choreography vs orchestration
| | **Choreography** (EventBridge/SNS events) | **Orchestration** (Step Functions) |
|---|---|---|
| Control | Each service reacts to events; no central coordinator | A central workflow calls services in order |
| Coupling | Loosest; easy to add consumers | Workflow knows every participant |
| Visibility | Hard to see end-to-end state; needs tracing (X-Ray) and correlation IDs | Visual execution history, central error handling |
| Failure handling | Distributed; compensations triggered by failure events | Retry/Catch and saga compensation in one place |
| Best for | Broadcasting domain facts across bounded contexts/teams | Business transactions with ordering, timeouts, human steps |

Professional answer: **both** — choreography *between* domains (events on buses), orchestration *within* a domain's business process (Step Functions).

### 3.5 Saga (distributed transaction without 2PC)
- **Orchestrated saga:** Step Functions Standard with `Catch` → compensating steps in reverse (see 2.4).
- **Choreographed saga:** each service emits success/failure events; others listen and compensate. Harder to reason about.
- Every step and compensation must be **idempotent**; record saga state (Step Functions history or a DynamoDB saga log).

### 3.6 Claim check (large payloads)
```text
Producer ─PutObject─▶ S3 (payload)      Consumer ◀─GetObject── S3
    └──── message {bucket,key,metadata} ──▶ SQS/SNS/EventBridge/Step Functions ──▶ Consumer
```
- For payloads above **1 MiB** (SQS, EventBridge, SNS with a raised limit) or **256 KiB** (Step Functions, SNS default). The **SQS/SNS Extended Client Libraries** do this automatically (up to 2 GB).
- Add an S3 lifecycle rule to expire payloads; secure with bucket policy and KMS; consumers need S3 permissions.

### 3.7 Priority queues
SQS has **no message priority**. Use **separate queues** (high/low): consumers poll the high-priority queue first, or dedicate more consumers/higher Lambda maximum concurrency to it. For multi-tenant fairness rather than priority, use **SQS fair queues** (`MessageGroupId` on a standard queue).

### 3.8 Idempotency
At-least-once delivery is the norm (SQS standard, SNS, EventBridge, Lambda async, Express async). Make consumers idempotent:
- **Powertools for AWS Lambda — Idempotency utility** (Python, TypeScript, Java, .NET): hashes the event (or a JMESPath-selected key), stores the status and result in **DynamoDB** with a TTL, returns the stored result on duplicates, handles in-progress locking.
- **DynamoDB conditional writes:** `PutItem ... ConditionExpression attribute_not_exists(pk)` with an idempotency key (order ID / event `id`) — a duplicate fails the condition and is ignored.
- Natural idempotency: upserts, `SET status = 'PAID'` rather than increments.
- Client-supplied **idempotency keys** on APIs (header), stored with the result.
- FIFO deduplication covers only the **5-minute** window and only the send side — it doesn't replace consumer idempotency for side effects.

### 3.9 Transactional outbox
Problem: updating a database **and** publishing an event isn't atomic (dual write).
```text
Service ──(one transaction)──▶ orders table + outbox table
                                      │
            DynamoDB Streams / Aurora CDC (DMS) / poller
                                      ▼
                           EventBridge Pipes ──▶ event bus / SNS / SQS
```
- With **DynamoDB**: write the item (optionally in a `TransactWriteItems` with an outbox item) and let **DynamoDB Streams → EventBridge Pipes** publish the event — the stream itself is the outbox.
- With **RDS/Aurora**: outbox table read by a poller (Lambda on a schedule) or CDC; mark rows as published; consumers deduplicate.

### 3.10 Circuit breaker
Stop calling a failing downstream dependency for a cool-down period, fail fast or degrade gracefully, then probe with a half-open state.
- Implement in code (libraries) with state in **DynamoDB/ElastiCache**, or with **Step Functions** checking a circuit-status item before calling the dependency.
- Combine with **timeouts, retries with exponential backoff and jitter, bulkheads** (separate queues/concurrency per dependency), and **load shedding**.

### 3.11 Asynchronous API (long-running requests > 29 s)
```text
Client ─POST /jobs─▶ API Gateway ──(direct integration)──▶ SQS  or  Step Functions StartExecution
   ◀── 202 Accepted {jobId, statusUrl}
Client ─GET /jobs/{id}─▶ API GW ─▶ Lambda ─▶ DynamoDB job status   (polling)
   or: completion → SNS/webhook callback, or push over a WebSocket API / AppSync subscription
```
- Fixes 504s from the 29 s integration timeout and protects backends. Alternatives: raise the timeout quota (Regional/private REST APIs only), **Synchronous Express** workflows for orchestration under ~29 s, **response streaming** for progressive output.

### 3.12 Strangler fig (modernization)
```text
Clients ─▶ API Gateway / ALB (path-based routing)
              ├── /orders/*  ─▶ new microservice (Lambda/ECS) ──events──▶ EventBridge
              └── /*         ─▶ legacy monolith (VPC link / private integration)
```
Route functionality piece by piece to new services; **events** (EventBridge, or CDC from the legacy DB) keep old and new data in sync; retire the monolith gradually. Pair with **AWS Migration Hub Refactor Spaces** (manages the routing and network plumbing). Full treatment in [Chapter 13](../13-Migration-and-Modernization/13-Migration-and-Modernization.md).

### 3.13 Multi-account event hub
```text
Workload accts (default bus: GuardDuty, Health, Config, custom events)
      └─ rule → central bus (ops/security acct)  [bus policy: aws:PrincipalOrgID]
               ├─ rule → SNS (paging) / Step Functions (auto-remediation)
               ├─ rule → Firehose → S3 (audit)
               └─ archive (replay for forensics)
```
Watch the **no-multi-hop** behaviour; use direct cross-account targets (2025) to deliver straight into a team's SQS queue or Lambda function.

### 3.14 Regional resilience for event-driven apps
- **EventBridge global endpoints** for ingestion failover (RTO/RPO ~6–7 min), with event replication.
- SNS/SQS are Regional: for DR, deploy the stack in both Regions, have producers publish to the active Region (Route 53/ARC routing), or replicate by subscribing a queue in Region B to the topic in Region A (SNS supports cross-Region SQS subscriptions).
- Step Functions are Regional: deploy state machines via IaC in both Regions; long-running executions don't migrate.
- See [Chapter 12](../12-Resilience-HA-and-Disaster-Recovery/12-Resilience-HA-and-Disaster-Recovery.md).

---

## 4. Decision tables / "X vs Y"

### 4.1 Messaging and eventing selector

| Requirement | **SQS** | **SNS** | **EventBridge** | **Kinesis Data Streams** | **Amazon MSK** |
|---|---|---|---|---|---|
| Model | Queue, **pull**, competing consumers | Pub/sub **push** | Event bus, **push**, content-based routing | Durable log/stream, pull | Kafka log, pull |
| Ordering | FIFO: per message group | FIFO topic: per group | No ordering on classic buses | **Per shard** (partition key) | **Per partition** |
| Duplicates | Standard: possible; FIFO: dedup 5 min | Standard possible; FIFO dedup | At-least-once | At-least-once (producer retries) | At-least-once; exactly-once with Kafka transactions |
| **Replay** | No (deleted after processing) | FIFO topics: archive & replay | **Archive & replay** to bus | **Yes** (24 h–365 d retention; consumers choose position) | **Yes** (configurable/long retention) |
| Fan-out | No (one consumer per message) — combine with SNS | **Yes**, up to 12.5 M subscriptions | Yes, 5 targets per rule, many rules | Multiple consumers (EFO) | Multiple consumer groups |
| Filtering | Lambda ESM filter only | **Filter policies** (attributes/body) | **Rich patterns** on any field | Lambda ESM filter | Consumer-side |
| Throughput | Standard ~unlimited; FIFO 300/3,000/s per partition, high-throughput up to 70k TPS | Very high (Regional publish quota) | PutEvents quota (e.g. 10k/s us-east-1, soft) | Scales with shards / on-demand | Very high (brokers/partitions) |
| Max message | 1 MiB | 256 KiB (up to 1 MiB configurable) | 1 MB | 10 MiB record (exam-era: 1 MB) | Configurable (default 1 MB) |
| Retention | Up to 14 days | None (except FIFO archive) | Archive (configurable) | 24 h – 365 d | Configurable / tiered storage |
| Typical use | Decouple, buffer, work queues | Notifications, fan-out, mobile/SMS/email | SaaS/AWS service events, cross-account routing, microservice choreography | Real-time analytics, clickstream, ordered high-volume ingest with replay | Kafka workloads, migrations, Kafka ecosystem |

### 4.2 Orchestration and integration selector
| Need | Choose |
|---|---|
| Multi-step workflow, long-running, human approval, exactly-once | **Step Functions Standard** |
| High-volume (thousands/s), < 5 min, idempotent, cheap | **Step Functions Express** |
| Process millions of S3 items in parallel | **Step Functions Distributed Map** |
| Source → filter → enrich → target, point-to-point, no code | **EventBridge Pipes** |
| Cron/one-time schedules at scale, time zones | **EventBridge Scheduler** |
| SaaS ↔ AWS data sync without code | **Amazon AppFlow** |
| Existing JMS/AMQP/MQTT/STOMP app, minimal change | **Amazon MQ** |
| Data pipelines (Airflow DAGs) | **Amazon MWAA** (see Chapter 11) |
| Legacy SWF workflows | Migrate to **Step Functions** (SWF is legacy for new designs) |

### 4.3 API front door selector
| Need | Choose |
|---|---|
| Usage plans/API keys, caching, WAF, request validation, private endpoint, resource policy, canary | **API Gateway REST** |
| Simple Lambda/HTTP proxy, JWT/OIDC auth, lowest cost & latency | **API Gateway HTTP API** |
| Persistent bidirectional connections you manage (chat, push) | **API Gateway WebSocket** |
| GraphQL, aggregate many sources in one request, real-time subscriptions, offline mobile | **AWS AppSync** |
| Load balancing HTTP to containers/instances, no API management needed | **ALB** (cheaper at very high sustained RPS, no 29 s limit — idle timeout configurable) |
| Expose a service privately to other VPCs/accounts at TCP level | **PrivateLink (NLB endpoint service)** or **VPC Lattice** |

### 4.4 SQS standard vs FIFO quick picker
| Stem says | Pick |
|---|---|
| "Order must be preserved per customer/account", "no duplicates", "process exactly once" | **FIFO** (`MessageGroupId` = customer) |
| "Highest throughput", "order doesn't matter", "consumers are idempotent" | **Standard** |
| "Need ordered + very high throughput" | **FIFO high-throughput mode** with many group IDs (or Kinesis if replay/multiple consumers needed) |
| "One noisy tenant delays everyone" | **Standard queue with fair queues** (`MessageGroupId` = tenant) or per-tenant queues |

### 4.5 Retry/failure destinations by service
| Service | Where failures go |
|---|---|
| SQS consumer | Redrive policy → **SQS DLQ** after `maxReceiveCount` |
| SNS subscription | Subscription redrive policy → **SQS DLQ** |
| EventBridge target | Retry policy (≤ 185 attempts / 24 h) → **SQS DLQ** per target |
| Lambda async invoke (S3, SNS, EventBridge) | Retries (0–2) → **on-failure destination** (SQS, SNS, Lambda, EventBridge, S3) or DLQ |
| Lambda ESM (Kinesis/DynamoDB Streams) | Bisect batch, max retries/record age → **on-failure destination** |
| Lambda ESM (SQS) | Back to the queue → SQS redrive DLQ (configure on the queue, not on Lambda) |
| Step Functions | `Retry` → `Catch` → fallback state; redrive |
| EventBridge Pipes / Scheduler | Retry policy → DLQ |

---

## 5. Exam keyword → answer cheat list

| Keyword / phrase in stem | Likely answer |
|---|---|
| "Decouple", "absorb spikes", "database overwhelmed by writes" | **SQS** buffer + bounded consumers (+ RDS Proxy) |
| "Scale workers based on queue depth" | Target tracking on **backlog per instance** (metric math) |
| "Strict order per entity", "exactly-once processing" | **SQS FIFO** with `MessageGroupId` |
| "Same message to multiple systems, each processes independently" | **SNS → multiple SQS** (fan-out) |
| "Each subscriber only wants some messages" | **SNS filter policy** / EventBridge rule pattern |
| "React to AWS service events / SaaS events" | **EventBridge** (default/partner bus) |
| "Route events across accounts in the organization" | EventBridge bus resource policy with `aws:PrincipalOrgID`, cross-account targets |
| "Replay past events after fixing a bug" | **EventBridge archive & replay** (or Kinesis/MSK if consumers need positional replay) |
| "Source → filter → enrich → target without code" | **EventBridge Pipes** |
| "Millions of scheduled one-time tasks", "time zones" | **EventBridge Scheduler** |
| "Regional failover for event ingestion" | **EventBridge global endpoints** |
| "Call third-party HTTP API with OAuth, rate-limited" | **EventBridge API destination** |
| "Human approval step", "wait for external system" | Step Functions **`.waitForTaskToken`** |
| "Run Glue/ECS/Batch job and wait for completion" | Step Functions **`.sync`** |
| "Workflow up to a year, audit trail, non-idempotent" | **Step Functions Standard** |
| "100,000 events/s, short-lived, cheapest workflow" | **Step Functions Express** |
| "Distributed transaction across microservices with rollback" | **Saga** with Step Functions `Catch` compensations |
| "Process millions of files in S3 in parallel" | **Distributed Map** |
| "Payload larger than message limit" | **Claim check** — S3 + pointer / Extended Client Library |
| "Partner API keys, per-customer quotas" | API Gateway REST **usage plans + API keys** |
| "API reachable only from inside VPCs / on-premises" | **Private REST API** + interface VPC endpoint + resource policy |
| "Certificate-based client authentication" | API Gateway **mTLS** on custom domain |
| "Request takes 2–10 minutes; clients get 504" | **Async pattern** (202 + poll/callback) or raise timeout (Regional/private REST) |
| "429 errors from API Gateway" | Throttling → raise quota, usage plans, caching, client backoff |
| "502 from Lambda proxy" | Malformed Lambda response / unhandled error |
| "Lowest-cost API in front of Lambda with JWT" | **HTTP API** |
| "GraphQL", "real-time subscriptions", "many teams one graph" | **AppSync** (Merged APIs) |
| "Existing JMS/AMQP/MQTT app, minimal code changes" | **Amazon MQ** (active/standby for HA) |
| "Salesforce → S3/Redshift, no code" | **AppFlow** |
| "Lambda processing SQS overloads downstream DB" | ESM **maximum concurrency** |
| "One bad message makes whole batch reprocess" | **Partial batch response** (`ReportBatchItemFailures`) |
| "Duplicates cause double charges" | **Idempotency** (Powertools / DynamoDB conditional write) |
| "DB update and event publish must not diverge" | **Transactional outbox** (DynamoDB Streams → Pipes) |
| "Incrementally replace monolith" | **Strangler fig** (API Gateway/ALB routing, Refactor Spaces) |
| "Reduce SQS cost / empty responses" | **Long polling** + batching |

---

## 6. Traps & distractors

1. **"Use SQS FIFO for 50,000 messages/s"** without high-throughput mode or many group IDs — default FIFO is 300 TPS (3,000 msg/s batched) per partition; a **single message group ID** serializes processing no matter what.
2. **"Use SNS to store messages until the consumer is back online"** — SNS doesn't persist for later consumption; put **SQS** behind it.
3. **"Kinesis for simple decoupling of a work queue"** — Kinesis needs shard/consumer management and has no per-message delete or visibility timeout; **SQS** is simpler. Conversely, "multiple consumers must re-read the same ordered data" → Kinesis/MSK, not SQS.
4. **"Increase Lambda reserved concurrency to throttle SQS consumption"** — low reserved concurrency throttles invocations, messages return to the queue and may hit the DLQ. Use **ESM maximum concurrency**.
5. **"Set visibility timeout lower than processing time to go faster"** — causes duplicate processing. Set it ≥ processing time (≥ 6× Lambda timeout).
6. **DLQ retention shorter than source queue** (standard queue) — messages expire early because the original enqueue timestamp is kept.
7. **"Express workflow for a 3-hour process or human approval"** — Express max is 5 minutes and it doesn't support `.waitForTaskToken`/`.sync`.
8. **"Standard workflow for 100,000 short executions/s"** — expensive (per transition) and throttled; use **Express**.
9. **"API keys secure my API"** — API keys identify and meter; use IAM/Cognito/Lambda authorizers for authentication.
10. **"HTTP API with usage plans / WAF / caching / private endpoint"** — those are **REST API** features.
11. **"Edge-optimized API to put WAF rules at CloudFront"** — you can't attach your own WAF/cache behaviours to the managed edge distribution; use **Regional API + your own CloudFront** distribution.
12. **"Raise the 29 s timeout on an edge-optimized or HTTP API"** — only **Regional and private REST APIs** can go above 29 s; HTTP API is hard-capped at 30 s.
13. **"EventBridge rule forwards events received from account A on to account C"** — no multi-hop; design direct routes.
14. **"EventBridge guarantees ordering"** — classic buses don't; use SQS FIFO/Kinesis when order matters.
15. **"Amazon MQ for a new cloud-native high-scale app"** — over-engineered and capacity-bound; use SQS/SNS/EventBridge. And "rewrite the JMS app for SQS" is wrong when the stem says **minimal code changes**.
16. **"Step Functions passes a 5 MB document between states"** — 256 KiB limit; use S3 pointers.
17. **"S3 event notification to two Lambda functions for the same event"** — overlapping notification configurations are rejected; use SNS fan-out or EventBridge.
18. **"Message timers on FIFO queues"** — not supported per message; only queue-level delay.
19. **"SNS FIFO topic → Lambda/HTTP subscriber"** — FIFO topics deliver to SQS queues.
20. **"Use SWF for new workflows"** — Step Functions is the modern answer unless the stem is about existing SWF deciders.
21. **"Old 256 KB limits"** — SQS and EventBridge are now 1 MiB/1 MB; Lambda async invoke 1 MB. If an older-style question says "messages up to 400 KB" and offers the Extended Client Library, recognise that **as of 2025 SQS handles it natively**; pick the option that meets requirements with the least complexity.

---

## 7. Professional architect focus

- **Semantics first, service second.** Before choosing, write down: ordering scope, duplicate tolerance, replay need, fan-out count, latency budget, throughput (avg/peak), payload size, retention, cross-account/Region needs. The service usually falls out of that list.
- **Design for at-least-once everywhere.** Even with FIFO and Standard workflows, retries at the edges (client, Lambda, EventBridge) create duplicates. Idempotency keys + conditional writes are cheap insurance. Tell stakeholders "exactly-once *delivery* doesn't exist end-to-end; we build exactly-once *effects*."
- **Every async hop needs a failure destination and an alarm.** DLQ depth (`ApproximateNumberOfMessagesVisible` on DLQ > 0), `ApproximateAgeOfOldestMessage`, EventBridge `FailedInvocations`, Step Functions `ExecutionsFailed`. Build a redrive runbook.
- **Back-pressure is a feature.** Queues let you choose throughput deliberately; cap concurrency to protect databases and third-party APIs; shed load at API Gateway (throttling, usage plans) instead of melting backends.
- **Observability across async boundaries:** propagate correlation IDs in message attributes; use **AWS X-Ray** (SQS, SNS, EventBridge, Step Functions, API Gateway REST support tracing) and structured logs (Powertools).
- **Event contracts are APIs.** Version events (`detail-type` + version field), publish schemas (schema registry), keep events backward compatible, prefer "thin events + fetch" or "fat events" deliberately (fat events reduce chatty callbacks but leak data and couple schemas).
- **Cost levers:** SQS batching/long polling (64 KB request chunks), Express vs Standard (transitions vs duration), HTTP API vs REST, EventBridge Pipes filtering (pay only for matching events), API Gateway caching vs backend cost, direct service integrations instead of "Lambda as glue".
- **Security:** least-privilege resource policies with `aws:SourceArn`/`aws:SourceAccount` (confused deputy), KMS key policies that allow the publishing service principals, VPC endpoints for SQS/SNS/EventBridge/Step Functions/execute-api, WAF on public APIs, mTLS for B2B.
- **Multi-account governance:** central event bus per organization, SCPs to prevent deleting org-wide rules, RAM sharing (AppSync merged APIs, new EventBridge buses), and naming/tagging conventions for event sources.
- **Anti-patterns to call out:** Lambda functions that only move data between services (use direct integrations/Pipes); synchronous call chains across 5 microservices (latency and availability multiply — go async); a giant "god" event bus without schemas or ownership; using a database table as a queue (polling, locking contention).

---

## 8. Skills checklist

- [ ] I can choose SQS standard vs FIFO and explain message group IDs, deduplication IDs, the 5-minute dedup window, and high-throughput FIFO prerequisites.
- [ ] I can state current SQS limits: 1 MiB message, 14-day retention (4-day default), 12 h visibility timeout, 15 min delay, 20 s long poll, 10 per batch.
- [ ] I can configure DLQs correctly (maxReceiveCount, redrive allow policy, retention longer than source, redrive back to source).
- [ ] I can design consumer auto scaling on backlog per instance.
- [ ] I can tune a Lambda SQS event source mapping: batch size/window, maximum concurrency vs reserved concurrency, provisioned mode, partial batch responses, visibility timeout ≥ 6× function timeout.
- [ ] I can design SNS fan-out with filter policies, FIFO topics, subscription DLQs, cross-account and cross-Region subscriptions, and KMS permissions.
- [ ] I can design EventBridge routing: buses, patterns, input transformers, retry/DLQ, cross-account (bus and direct targets), no multi-hop, archive & replay, schema registry.
- [ ] I know when to use EventBridge Pipes, Scheduler, global endpoints and API destinations.
- [ ] I can pick Step Functions Standard vs Express and explain duration, pricing, and execution semantics.
- [ ] I can apply `.sync`, `.waitForTaskToken` (human approval), Retry/Catch, Distributed Map and saga compensation.
- [ ] I can compare REST vs HTTP vs WebSocket APIs and pick endpoint types (edge/Regional/private + VPC endpoint + resource policy).
- [ ] I know API Gateway throttling (10,000 RPS / 5,000 burst, soft), usage plans, caching, authorizers, mTLS, VPC links (NLB, ALB via v2), canary, CORS.
- [ ] I can diagnose 403/429/502/504 and design around the 29 s timeout.
- [ ] I can justify AppSync (and Merged APIs), Amazon MQ (lift-and-shift, active/standby) and AppFlow.
- [ ] I can apply claim check, outbox, circuit breaker, priority queues, idempotency, async API and strangler fig patterns.

---

## 9. Practice questions

> Original SAP-C02-style questions. Answers follow in the next subsection.

**Q1.** A ticketing company runs its checkout API on Amazon ECS behind an Application Load Balancer. Each checkout writes several rows to an Amazon Aurora PostgreSQL cluster. During flash sales, traffic rises from 200 to 15,000 requests per second within a minute, the database runs out of connections, and checkouts fail. The business accepts that order confirmation can arrive by email up to 2 minutes later, but no order may be lost and no customer may be charged twice. The team wants the least operational overhead. Which solution meets these requirements?

- A. Increase the Aurora instance size and add three Aurora Replicas, and configure the ECS service to scale on CPU utilization.
- B. Have the API publish each order to an Amazon SQS standard queue and return 202 Accepted. Process the queue with an AWS Lambda function using an event source mapping with maximum concurrency set to keep database connections within limits, connect through RDS Proxy, make processing idempotent with a conditional write on the order ID, and configure a dead-letter queue.
- C. Have the API publish each order to an Amazon SNS standard topic with an Aurora PostgreSQL subscription so writes are pushed to the database at a controlled rate.
- D. Have the API write orders to an Amazon Kinesis Data Streams stream with one shard per 1,000 requests, and use a Lambda consumer with reserved concurrency of 1,000.

**Q2.** A bank processes account transactions from a mainframe export. Each account's transactions must be applied in the order they were generated, and a transaction must never be applied twice. Volume is 25,000 transactions per second at peak across about 2 million accounts. The bank runs in us-east-1. Consumers run on Amazon ECS. Which design meets the requirements with the least custom code?

- A. An SQS standard queue with a sequence number in each message; consumers sort messages in memory before applying them.
- B. An SQS FIFO queue with high-throughput mode enabled, `MessageGroupId` set to the account ID, a deduplication ID set to the transaction ID, and producers using batch sends.
- C. An SQS FIFO queue with `MessageGroupId` set to a constant value so that all transactions remain in global order, with content-based deduplication.
- D. An Amazon SNS standard topic with an SQS standard queue per ECS task, with a filter policy on account ID ranges.

**Q3.** A media company's upload service publishes an event every time a video is uploaded. Five teams in five different AWS accounts in the same AWS Organization must react: transcoding (needs every event), thumbnails (only videos longer than 60 seconds), compliance (only uploads from EU customers), analytics (needs to reprocess all events from the last 30 days whenever its model changes), and billing. Teams want to own their consumers and not depend on the upload team for changes. Which TWO actions should the solutions architect take? (Select TWO.)

- A. Create a custom EventBridge event bus in the upload account with a resource policy allowing the organization, and have each team create rules with event patterns (for example numeric matching on duration and matching on region) that deliver to targets in their own accounts.
- B. Enable an EventBridge archive on the custom bus with 30-day retention so that events can be replayed for the analytics consumer.
- C. Publish events to an SQS standard queue that all five teams poll, using message attributes to skip irrelevant messages.
- D. Create an SNS standard topic and configure the upload service to call each team's HTTPS endpoint directly with retries in the application code.
- E. Store events in an Amazon S3 bucket and have each team run a scheduled Lambda function that lists new objects every minute.

**Q4.** An insurance company is building a claims workflow. A claim is validated, a fraud score is calculated by an Amazon SageMaker AI endpoint, and claims scoring above a threshold require approval by a human adjuster, which can take up to 10 days. Approved claims trigger a payment through a third-party payment API that is not idempotent. Auditors require a complete execution history for each claim. Which solution meets these requirements?

- A. Step Functions Express workflow that invokes the SageMaker AI endpoint, then uses a `.waitForTaskToken` task to wait for adjuster approval.
- B. Step Functions Standard workflow that invokes the SageMaker AI endpoint, sends the adjuster a notification containing a task token through a `.waitForTaskToken` integration, resumes when an approval API calls `SendTaskSuccess`, and calls the payment API with Retry configured only for errors known to occur before the payment is submitted.
- C. A chain of Lambda functions connected by SQS queues, with the approval stored in DynamoDB and a Lambda function polling the table every minute for 10 days.
- D. Step Functions Standard workflow that uses a Wait state of 10 days, then checks DynamoDB for the adjuster's decision.

**Q5.** A SaaS provider exposes a REST API on Amazon API Gateway (Regional endpoint) backed by Lambda. Enterprise partners report three problems: (1) some partners receive HTTP 429 errors during their nightly batch, (2) a report-generation endpoint frequently returns HTTP 504 because reports take 2–6 minutes to build, and (3) the provider cannot enforce different request quotas per partner. Which combination of actions resolves all three problems? (Select THREE.)

- A. Create usage plans with throttle and quota settings per partner tier, issue an API key to each partner, and require API keys on the methods.
- B. Change the report endpoint to start an asynchronous job (for example, start a Step Functions execution through a direct service integration), return 202 with a job ID, and provide a status endpoint or callback when the report is ready.
- C. Migrate the API to an HTTP API to remove the 29-second timeout.
- D. Request an increase of the account-level throttle quota for the Region if aggregate traffic legitimately exceeds it, and have partners implement exponential backoff with jitter.
- E. Switch the endpoint type to edge-optimized so that requests are throttled at CloudFront edge locations instead of in the Region.
- F. Enable API caching on the report-generation endpoint with a 3,600-second TTL.

**Q6.** A company processes images uploaded to Amazon S3. An S3 event notification sends events to an SQS standard queue consumed by a Lambda function with a batch size of 10. Occasionally a corrupt image makes the function throw an exception. Operators notice that, when that happens, nine valid images in the same batch are reprocessed several times, and the corrupt message stays in the queue for 4 days, blocking alarms from meaningful signal. Which TWO changes should the solutions architect make? (Select TWO.)

- A. Enable `ReportBatchItemFailures` on the event source mapping and return only the failed message IDs in `batchItemFailures`.
- B. Configure a redrive policy on the source queue with a dead-letter queue and a `maxReceiveCount` of 5, and alarm on the DLQ's visible message count.
- C. Set the Lambda function's reserved concurrency to 1 so failures are processed sequentially.
- D. Reduce the queue's visibility timeout to 5 seconds so failed messages are retried faster.
- E. Configure a Lambda on-failure destination on the event source mapping for the SQS queue.

**Q7.** A logistics company must expose an internal shipment-tracking REST API, running on Amazon ECS tasks behind an internal Application Load Balancer, to (a) applications in three VPCs in other AWS accounts and (b) on-premises systems connected through AWS Direct Connect. The API must not be reachable from the internet, and access must be limited to the specific consumers. The team wants to use API Gateway features such as request validation and per-consumer throttling. Which solution meets these requirements?

- A. Create a public Regional REST API with an AWS WAF IP set allowing only the on-premises CIDR ranges and the NAT gateway IPs of the consumer VPCs.
- B. Create a private REST API, integrate it with the ALB through a VPC link, create interface VPC endpoints for `execute-api` in the consumer VPCs (and an endpoint reachable from on-premises over Direct Connect), and attach a resource policy that allows only those VPC endpoint IDs.
- C. Create an HTTP API with a VPC link to the ALB and a JWT authorizer, and share the API with the other accounts using AWS RAM.
- D. Create an edge-optimized REST API with a Lambda authorizer that checks the caller's source IP address.

**Q8.** A retailer is migrating an on-premises order management application to AWS. The application uses Apache ActiveMQ with JMS queues and topics and is written against the JMS API; the business wants the migration completed in 6 weeks with minimal code changes, and the messaging layer must survive the loss of an Availability Zone. Which solution meets these requirements?

- A. Rewrite the producers and consumers to use Amazon SQS and Amazon SNS through the AWS SDK.
- B. Deploy Amazon MQ for ActiveMQ in an active/standby deployment across two Availability Zones, and update the application's connection URL to use the failover transport with both broker endpoints.
- C. Deploy Amazon MQ for ActiveMQ as a single-instance broker with Amazon EBS storage and take daily snapshots.
- D. Deploy Amazon MSK and use a JMS-to-Kafka bridge running on EC2.

**Q9.** A fintech company uses Amazon EventBridge custom event buses in us-east-1 for payment events published by dozens of microservices. A regulator now requires that event ingestion continue if us-east-1 is impaired, with a recovery time of under 10 minutes, and that operations can automatically resume in the primary Region afterwards. Which TWO actions should the solutions architect take? (Select TWO.)

- A. Create an EventBridge global endpoint with us-east-1 as primary and us-west-2 as secondary, attach a Route 53 health check based on a CloudWatch alarm, and enable event replication.
- B. Create an identically named custom event bus with the same rules and targets in us-west-2, and update producers to call `PutEvents` with the global endpoint ID using an SDK that supports SigV4A.
- C. Configure a rule on the us-east-1 bus that forwards all events to a bus in us-west-2 and have producers switch to us-west-2 manually during an incident.
- D. Enable an archive on the us-east-1 bus and replay it into us-west-2 during an outage.
- E. Replace EventBridge with an SQS FIFO queue replicated across Regions.

**Q10.** A healthcare analytics company receives a nightly manifest listing 4 million small JSON files in Amazon S3. Each file must be validated, enriched by calling an internal API (limited to 2,000 concurrent requests), and written to Amazon DynamoDB. Failed files must be reported without failing the whole run unless more than 5% fail. The current solution is a fleet of EC2 instances running a custom scheduler that the company wants to retire. Which solution meets these requirements with the least operational overhead?

- A. A Step Functions Standard workflow with an inline Map state iterating over the manifest, passing the full list of 4 million keys as state input.
- B. A Step Functions Standard workflow with a Distributed Map state that reads the S3 inventory manifest with `ItemReader`, batches items with `ItemBatcher`, runs Express child workflows that call the API and write to DynamoDB, sets `MaxConcurrency` to respect the API limit, sets `ToleratedFailurePercentage` to 5, and writes results to S3 with `ResultWriter`.
- C. An Amazon EMR cluster running a Spark job that calls the internal API from each executor.
- D. An S3 event notification on each object that invokes a Lambda function, with the function's reserved concurrency set to 2,000.

---

### Answers & explanations

<details><summary>Show answer — Q1</summary>

**Correct: B.**
- **Why:** The queue absorbs the spike (request buffering); Lambda ESM **maximum concurrency** bounds concurrent DB writers; **RDS Proxy** pools connections; **idempotent conditional writes** stop duplicate charges despite at-least-once delivery from a standard queue; the **DLQ** makes sure no order is lost silently. The 2-minute confirmation tolerance allows the async `202` design. All serverless, so low operational overhead.
- **A:** Bigger instances and replicas don't fix write-connection exhaustion (replicas don't take writes) and CPU scaling of ECS *increases* DB pressure.
- **C:** SNS can't subscribe a database and doesn't buffer or rate-limit.
- **D:** Kinesis can work, but shard sizing and reserved concurrency of 1,000 would hit the DB harder; nothing addresses idempotency; more operations than SQS.
- **Refs:** [SQS Lambda scaling / maximum concurrency](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-scaling.html), [Amazon RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html)
</details>

<details><summary>Show answer — Q2</summary>

**Correct: B.**
- **Why:** Per-account ordering → `MessageGroupId = accountId`; no double application → FIFO dedup with transaction ID (and idempotent consumers). 25,000 TPS exceeds default FIFO limits but **high-throughput FIFO** in us-east-1 supports up to 70,000 TPS non-batched (700,000 msg/s batched), and 2 million group IDs spread load across partitions.
- **A:** Standard queues deliver out of order and duplicates; in-memory sorting across competing consumers doesn't work.
- **C:** A constant group ID forces **one consumer at a time** — throughput collapses; global order isn't required.
- **D:** SNS standard/SQS standard gives neither ordering nor deduplication.
- **Refs:** [High throughput for FIFO queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/high-throughput-fifo.html), [SQS message quotas](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/quotas-messages.html)
</details>

<details><summary>Show answer — Q3</summary>

**Correct: A, B.**
- **A:** A custom bus with an organization-wide resource policy lets each team own rules with **content-based patterns** (numeric on duration, match on region) and deliver to targets in their own accounts (direct cross-account targets or their own bus). The upload team isn't involved in consumer changes.
- **B:** **Archive & replay** meets analytics' 30-day reprocessing need without the producer resending.
- **C:** A shared queue delivers each message to **one** consumer (competing consumers), not all five.
- **D:** Point-to-point HTTPS calls from the producer couple it to every consumer — the opposite of the requirement.
- **E:** Polling S3 is high-latency, custom and costly.
- **Refs:** [EventBridge cross-account](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cross-account.html), [Archive and replay](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-archive.html), [Event patterns](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-patterns.html)
</details>

<details><summary>Show answer — Q4</summary>

**Correct: B.**
- **Why:** A 10-day human wait needs **Standard** (up to 1 year) with the **callback task token** pattern; Standard is **exactly-once** and keeps **execution history** (90 days, exportable via CloudWatch Logs for longer audit retention). Limiting Retry on a non-idempotent payment call avoids double payments (ideally also pass an idempotency key if the provider supports one).
- **A:** Express max duration is 5 minutes and it doesn't support `.waitForTaskToken`.
- **C:** Custom polling chain, no central history, high operational overhead.
- **D:** A fixed 10-day Wait delays every claim even when approval comes quickly, and doesn't handle approvals arriving early or late.
- **Refs:** [Standard vs Express](https://docs.aws.amazon.com/step-functions/latest/dg/choosing-workflow-type.html), [Wait for a callback with task token](https://docs.aws.amazon.com/step-functions/latest/dg/connect-to-resource.html)
</details>

<details><summary>Show answer — Q5</summary>

**Correct: A, B, D.**
- **A:** **Usage plans + API keys** give per-partner throttle and quota (problem 3) and isolate partners from each other.
- **B:** 2–6 minute reports exceed the 29 s default integration timeout → **asynchronous job + 202 + status/callback** fixes 504s (problem 2). (A Regional REST API *can* request a timeout above 29 s, but minutes-long synchronous HTTP calls are fragile; async is the robust pattern.)
- **D:** If aggregate traffic exceeds the **10,000 RPS / 5,000 burst** soft account quota, request an increase; client **backoff with jitter** is the correct response to 429s (problem 1).
- **C:** HTTP APIs are capped at **30 s** and don't support usage plans.
- **E:** Edge-optimized doesn't change account throttling and adds nothing here.
- **F:** Caching per-request reports for an hour returns wrong data and doesn't help the first request time out less.
- **Refs:** [Usage plans](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-api-usage-plans.html), [Throttling](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-request-throttling.html), [REST API quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-execution-service-limits-table.html)
</details>

<details><summary>Show answer — Q6</summary>

**Correct: A, B.**
- **A:** **Partial batch response** returns only the failed message to the queue, so the nine good images aren't reprocessed.
- **B:** A **redrive policy with a DLQ** moves the poison message out after `maxReceiveCount` (AWS recommends ≥ 5 for Lambda), so it stops cycling for 4 days and can be alarmed on and inspected.
- **C:** Reserved concurrency of 1 slows everything and can cause throttling-driven retries; it doesn't remove poison messages.
- **D:** Too short a visibility timeout causes in-flight messages to reappear while still being processed — more duplicates.
- **E:** For SQS event sources, failure handling is configured on the **queue** (redrive DLQ); on-failure destinations on the ESM apply to stream sources (Kinesis, DynamoDB Streams) and Kafka.
- **Refs:** [SQS ESM error handling / partial batch responses](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html), [SQS dead-letter queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)
</details>

<details><summary>Show answer — Q7</summary>

**Correct: B.**
- **Why:** A **private REST API** is reachable only through `execute-api` **interface VPC endpoints**; the **resource policy** restricts access to the specific endpoint IDs (`aws:SourceVpce`), including endpoints in other accounts' VPCs; on-premises clients reach an endpoint over Direct Connect. A **VPC link** (v2 now supports ALB directly for REST APIs) reaches the internal ALB. REST APIs keep request validation and usage-plan throttling.
- **A:** Public endpoint — violates "not reachable from the internet"; IP lists are brittle.
- **C:** HTTP APIs don't support private endpoints, resource policies or usage plans, and API Gateway APIs aren't shared via AWS RAM.
- **D:** Edge-optimized is public; a Lambda authorizer doesn't make it private.
- **Refs:** [Private REST APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-private-apis.html), [Private integrations for REST APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/private-integration.html)
</details>

<details><summary>Show answer — Q8</summary>

**Correct: B.**
- **Why:** **Amazon MQ for ActiveMQ** keeps JMS/OpenWire compatibility (minimal code changes — mainly the connection URL). **Active/standby** across two AZs with shared EFS storage survives an AZ loss; clients use the **failover transport**.
- **A:** A rewrite contradicts "minimal code changes" and the 6-week timeline.
- **C:** Single-instance in one AZ doesn't survive AZ failure; snapshots aren't HA.
- **D:** MSK isn't JMS; a self-managed bridge adds operations and code risk.
- **Refs:** [Amazon MQ for ActiveMQ deployment options](https://docs.aws.amazon.com/amazon-mq/latest/developer-guide/amazon-mq-broker-architecture.html)
</details>

<details><summary>Show answer — Q9</summary>

**Correct: A, B.**
- **A:** **Global endpoints** fail over ingestion using a Route 53 health check; AWS guidance gives RTO/RPO around 360 s (max 420 s) — under 10 minutes. **Event replication** is required for **automatic** fail-back.
- **B:** Failover requires a **same-named custom bus** (with matching rules/targets) in the secondary Region, and producers must publish to the **endpoint ID** with SigV4A-capable SDKs.
- **C:** Manual producer switching doesn't meet the automatic requirement and the forwarding rule lives in the impaired Region.
- **D:** The archive lives in us-east-1 and replay goes back to the source bus; not a failover mechanism.
- **E:** SQS has no native cross-Region replication, and this re-architects the whole event model.
- **Refs:** [EventBridge global endpoints](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-global-endpoints.html)
</details>

<details><summary>Show answer — Q10</summary>

**Correct: B.**
- **Why:** **Distributed Map** reads millions of items straight from S3 (manifest/inventory), runs up to 10,000 parallel child executions (Express children are cheap for short tasks), `MaxConcurrency` (with batching) protects the 2,000-concurrency API, `ToleratedFailurePercentage = 5` meets the failure rule, and `ResultWriter` produces a failure report. Fully serverless — retires the EC2 scheduler.
- **A:** 4 million keys far exceed the 256 KiB payload and 25,000-event history limits; inline Map caps at 40 concurrency.
- **C:** EMR is heavyweight for API-call-per-file work and needs cluster management and custom throttling.
- **D:** Files arrive in a nightly batch with a manifest (event notifications don't give a run-level failure threshold or report), and reserved concurrency alone doesn't give run-level failure tolerance.
- **Refs:** [Distributed Map](https://docs.aws.amazon.com/step-functions/latest/dg/state-map-distributed.html), [Step Functions quotas](https://docs.aws.amazon.com/step-functions/latest/dg/service-quotas.html)
</details>

---

## 10. References

**Amazon SQS**
- [Amazon SQS Developer Guide](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/welcome.html)
- [SQS message quotas](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/quotas-messages.html) · [Standard queue quotas](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/quotas-queues.html) · [FIFO queue quotas](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/quotas-fifo.html)
- [High throughput for FIFO queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/high-throughput-fifo.html)
- [SQS fair queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-fair-queues.html)
- [Dead-letter queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html)
- [What's New: SQS max payload 1 MiB (Aug 2025)](https://aws.amazon.com/about-aws/whats-new/2025/08/amazon-sqs-max-payload-size-1mib/)
- [Scaling based on Amazon SQS (backlog per instance)](https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-using-sqs-queue.html)

**AWS Lambda with SQS**
- [Configuring SQS event source mappings](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-configure.html)
- [Scaling behaviour, maximum concurrency, provisioned mode](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-scaling.html)
- [Error handling and partial batch responses](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html)
- [Powertools for AWS Lambda (Python) — Idempotency](https://docs.powertools.aws.dev/lambda/python/latest/utilities/idempotency/)

**Amazon SNS**
- [Amazon SNS Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/welcome.html)
- [SNS endpoints and quotas](https://docs.aws.amazon.com/general/latest/gr/sns.html)
- [Message filtering](https://docs.aws.amazon.com/sns/latest/dg/sns-message-filtering.html) · [Delivery retries](https://docs.aws.amazon.com/sns/latest/dg/sns-message-delivery-retries.html) · [Dead-letter queues](https://docs.aws.amazon.com/sns/latest/dg/sns-dead-letter-queues.html)
- [FIFO topics](https://docs.aws.amazon.com/sns/latest/dg/sns-fifo-topics.html)

**Amazon EventBridge**
- [EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html) · [Quotas](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-quota.html)
- [Cross-account events](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cross-account.html) · [Cross-Region events](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cross-region.html)
- [What's New: direct delivery to cross-account targets (Jan 2025)](https://aws.amazon.com/about-aws/whats-new/2025/01/amazon-eventbridge-direct-delivery-cross-account-targets/)
- [What's New: 1 MB event payloads (Jan 2026)](https://aws.amazon.com/about-aws/whats-new/2026/01/amazon-eventbridge-increases-event-payload-size-256-kb-1-mb/)
- [Archive and replay](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-archive.html) · [Global endpoints](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-global-endpoints.html) · [API destinations](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-api-destinations.html)
- [EventBridge Pipes](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-pipes.html) · [Schema registry](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-schema-registry.html)
- [EventBridge Scheduler User Guide](https://docs.aws.amazon.com/scheduler/latest/UserGuide/what-is-scheduler.html) · [Scheduler quotas](https://docs.aws.amazon.com/scheduler/latest/UserGuide/scheduler-quotas.html)

**AWS Step Functions**
- [Choosing workflow type (Standard vs Express)](https://docs.aws.amazon.com/step-functions/latest/dg/choosing-workflow-type.html)
- [Service integration patterns](https://docs.aws.amazon.com/step-functions/latest/dg/connect-to-resource.html)
- [Error handling](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-error-handling.html) · [Distributed Map](https://docs.aws.amazon.com/step-functions/latest/dg/state-map-distributed.html) · [Quotas](https://docs.aws.amazon.com/step-functions/latest/dg/service-quotas.html)

**Amazon API Gateway**
- [API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/welcome.html) · [Choose between REST and HTTP APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-vs-rest.html)
- [Account quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/limits.html) · [REST API quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-execution-service-limits-table.html) · [HTTP API quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-quotas.html) · [WebSocket quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-execution-service-websocket-limits-table.html)
- [Throttling](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-request-throttling.html) · [Usage plans](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-api-usage-plans.html) · [Caching](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-caching.html)
- [Private REST APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-private-apis.html) · [Private integrations (VPC links)](https://docs.aws.amazon.com/apigateway/latest/developerguide/private-integration.html) · [mTLS for REST APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/rest-api-mutual-tls.html)
- [Canary release deployments](https://docs.aws.amazon.com/apigateway/latest/developerguide/canary-release.html) · [CORS for REST APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/how-to-cors.html)
- [What's New: REST API response streaming (Nov 2025)](https://aws.amazon.com/about-aws/whats-new/2025/11/api-gateway-response-streaming-rest-apis/)

**Other services**
- [AWS AppSync Developer Guide](https://docs.aws.amazon.com/appsync/latest/devguide/what-is-appsync.html) · [Merged APIs](https://docs.aws.amazon.com/appsync/latest/devguide/merged-api.html)
- [Amazon MQ Developer Guide](https://docs.aws.amazon.com/amazon-mq/latest/developer-guide/welcome.html) · [ActiveMQ deployment options](https://docs.aws.amazon.com/amazon-mq/latest/developer-guide/amazon-mq-broker-architecture.html)
- [Amazon AppFlow User Guide](https://docs.aws.amazon.com/appflow/latest/userguide/what-is-appflow.html)

**Patterns and whitepapers**
- [Implementing Microservices on AWS (whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/microservices-on-aws/microservices-on-aws.html)
- [Cloud design patterns, architectures, and implementations (Prescriptive Guidance)](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/introduction.html) — saga, outbox, circuit breaker, strangler fig, retry with backoff, publish-subscribe, scatter-gather
- [Enabling data persistence in microservices — saga pattern](https://docs.aws.amazon.com/prescriptive-guidance/latest/modernization-data-persistence/saga-pattern.html)
- [AWS Well-Architected — Serverless Applications Lens](https://docs.aws.amazon.com/wellarchitected/latest/serverless-applications-lens/welcome.html)

---

[← Previous: Chapter 9 — Databases & Caching](../09-Databases-and-Caching/09-Databases-and-Caching.md) · [Index](../00-README-Start-Here.md) · [Next: Chapter 11 — Analytics, Streaming & AI/ML →](../11-Analytics-Streaming-and-AI-ML/11-Analytics-Streaming-and-AI-ML.md)

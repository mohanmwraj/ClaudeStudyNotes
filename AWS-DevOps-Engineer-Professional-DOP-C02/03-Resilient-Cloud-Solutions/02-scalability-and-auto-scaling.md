# Domain 3 · 02 · Scalability and Auto Scaling

> **Exam tasks:** 3.2 (scaling metrics, loose coupling, serverless, containers, auto scaling/load balancing/caching, remediating scaling issues), 4.3 (auto scaling across services). **Principles:** P7 (replacement), P9 (decouple and scale on backlog), P12 (managed).

## 1. First principles

1. **Scale on the metric that measures the work waiting, not on a proxy.**
   * A web tier is limited by requests per target or CPU.
   * A queue worker tier is limited by **messages waiting per worker**.
   * A memory-bound service needs a memory metric (CloudWatch agent or Container Insights).

   Scaling a queue worker on CPU can leave a growing backlog while CPU looks fine.
2. **Scaling speed = detection + provisioning + warm-up.** To scale faster, shorten one of the three:
   * **detection:** high-resolution metrics, lower thresholds, predictive scaling;
   * **provisioning:** warm pools, smaller AMIs, containers instead of instances;
   * **warm-up:** pre-baked AMIs, so less user-data work at boot.
3. **Decoupling turns a scaling problem into a buffering problem** (P9). With a queue in front, a slow scale-out delays work instead of dropping it.

---

## 2. EC2 Auto Scaling

### 2.1 Scaling policies

| Policy | How it works | Use |
|---|---|---|
| **Target tracking** | Keeps a metric at a target (e.g. average CPU 50%, `ALBRequestCountPerTarget` 1,000, or a custom metric). Creates and manages its own alarms. With several target-tracking policies, the ASG scales **out** if *any* policy says so and **in** only if *all* agree | The default choice |
| **Step scaling** | CloudWatch alarm thresholds with **steps** (e.g. +2 at 60%, +4 at 80%); continues to evaluate during warm-up | Aggressive, non-linear responses to spikes |
| **Simple scaling** | One adjustment per alarm, then waits for the **cooldown** | Legacy; avoid |
| **Scheduled actions** | Change min/max/desired at given times (cron) | Known events (business hours, a sale) |
| **Predictive scaling** | ML forecast from about 14 days of history (at least 24 hours) launches capacity **ahead of** forecast load; *forecast-only* mode to evaluate first | Recurring daily or weekly patterns where boot time makes reactive scaling too late |

**Backlog-per-instance scaling (SQS workers):**
1. Publish a custom metric `ApproximateNumberOfMessagesVisible ÷ InService instances`, from a Lambda on a schedule or by metric math.
2. Set target tracking to the **acceptable backlog per instance** = (acceptable latency ÷ average processing time per message).

Example: 10 s acceptable latency ÷ 0.1 s per message → target 100 messages per instance.

### 2.2 Lifecycle hooks

* **Hooks:** `autoscaling:EC2_INSTANCE_LAUNCHING` puts new instances in **`Pending:Wait`**; `autoscaling:EC2_INSTANCE_TERMINATING` puts terminating ones in **`Terminating:Wait`**.
* **Signalling:** a notification goes to **EventBridge** (or SNS/SQS). Your automation does the work, e.g. register in a CMDB, pull configuration, drain connections, copy logs to S3. It then calls **`CompleteLifecycleAction`** with `CONTINUE` or `ABANDON`, or extends the time with `RecordLifecycleActionHeartbeat`.
* **Timeouts:** heartbeat timeout 30–7,200 s (default 3,600 s); the **default result** (`CONTINUE` or `ABANDON`) applies when it expires.
* **Exam pattern:** "Before an instance is terminated by scale-in, upload its logs to S3" → termination lifecycle hook + EventBridge → SSM Run Command (or Lambda) → `CompleteLifecycleAction`.

### 2.3 Warm pools

* A pool of **pre-initialized** instances (stopped, hibernated or running) next to the ASG. Scale-out moves them in instead of launching and bootstrapping from scratch.
* Stopped instances cost only EBS.
* **Use when** boot or initialization takes minutes (large applications, cache warming) and scale-out latency matters.
* Lifecycle hooks also fire when instances **enter** the warm pool, so initialization can run then.

### 2.4 Instance refresh: rolling replacement for configuration changes

* Replaces instances to apply a new **launch template version**, AMI or user data.
* Settings:
  * **minimum healthy percentage** and optionally **maximum healthy percentage** (above 100% means launch new instances before terminating old ones);
  * **instance warm-up**;
  * **checkpoints** (pause at e.g. 20%, then 100%);
  * **skip matching** (don't replace instances that already match);
  * **automatic rollback** on failure or when specified **CloudWatch alarms** fire.
* **The answer to:** "roll the new golden AMI out to the existing ASG gradually with automatic rollback" (with EC2 Image Builder updating the launch template).

### 2.5 Other ASG features the exam touches

* **Health checks:** EC2 status checks (default), **ELB** (recommended behind a load balancer), VPC Lattice, or **custom** (`SetInstanceHealth`). The **health check grace period** gives booting instances time before they're judged.
* **Instance maintenance policy:** launch before terminate (or the reverse) during health-related replacements and instance refresh, so capacity doesn't drop.
* **Mixed instances policy:** several instance types, plus **Spot** with an allocation strategy (`price-capacity-optimized` recommended) and **capacity rebalancing** (proactively replace Spot instances at elevated risk of interruption).
* **Termination policies** decide which instance to terminate on scale-in:
  1. Balance AZs first.
  2. Then follow your policy, e.g. `OldestLaunchTemplate`.
  3. **Scale-in protection** exempts specific instances.
* **Suspend processes** (`Launch`, `Terminate`, `HealthCheck`, `ReplaceUnhealthy`, `AZRebalance`, `AlarmNotification`, `ScheduledActions`, `AddToLoadBalancer`, …) during troubleshooting or deployments.

## 3. Load balancing and caching

| Layer | Option | Scaling detail |
|---|---|---|
| L7 HTTP/HTTPS | **ALB** | Scales automatically. For a predictable, extreme spike, reserve capacity units in advance (LCU reservation) |
| L4 TCP/UDP/TLS, static IPs, extreme throughput | **NLB** | Scales automatically; one static IP per AZ |
| Edge caching | **CloudFront** | Offloads origins; cache policies and origin request policies; origin shield |
| In-memory cache | **ElastiCache** (Redis OSS / Valkey / Memcached) | **Lazy loading** (cache-aside, stale data possible) vs **write-through** (always fresh, writes cost more); TTLs |
| DynamoDB reads | **DAX** | Microsecond reads for read-heavy, eventually consistent access |
| API responses | **API Gateway caching** (REST APIs) | Per stage, TTL, can key on parameters |
| Relational reads | RDS/Aurora **read replicas** | Offload reads; asynchronous |

## 4. Containers

### 4.1 Amazon ECS

* **Service auto scaling** (Application Auto Scaling) changes the **desired task count**: target tracking on `ECSServiceAverageCPUUtilization`, `ECSServiceAverageMemoryUtilization` or `ALBRequestCountPerTarget`; step; scheduled.
* **Capacity providers** decide **where** tasks run:
  * **Fargate / Fargate Spot:** no instances to manage.
  * **ASG capacity provider with managed scaling:** ECS scales the ASG so that the cluster's `CapacityProviderReservation` meets the **target capacity %**, and **managed termination protection** keeps instances that run tasks from being scaled in.
  * A **capacity provider strategy** (base + weight) mixes them, e.g. base 2 on Fargate, then a 1:3 Fargate:Fargate Spot weight.
* **Tasks stuck in `PROVISIONING` / "unable to place task"** → not enough cluster capacity, so add a capacity provider with managed scaling.

### 4.2 Amazon EKS

| Scales | Tool |
|---|---|
| Pods | **Horizontal Pod Autoscaler** (CPU/memory/custom metrics); Vertical Pod Autoscaler (requests) |
| Nodes | **Cluster Autoscaler** (adjusts managed node group ASGs) or **Karpenter** (provisions right-sized nodes directly from pending pods; faster; consolidation) |
| No nodes at all | **EKS on Fargate** (a profile selects pods by namespace and labels) |

## 5. Serverless and managed scaling

| Service | Scaling facts the exam uses |
|---|---|
| **Lambda** | Account concurrency quota per Region (default 1,000; raisable). **Reserved concurrency** both **guarantees** and **caps** a function's concurrency (a cap of 0 = throttle everything). **Provisioned concurrency** keeps execution environments initialized, which removes cold starts; it's set on an alias or version and can be scaled by Application Auto Scaling (schedule or target tracking). Each function can scale by up to 1,000 concurrent executions every 10 seconds |
| **SQS → Lambda** | The event source mapping scales pollers with the backlog; **maximum concurrency** on the mapping caps it; failed batches → retries → a **DLQ on the queue** (redrive policy) |
| **API Gateway** | Account-level throttling (default 10,000 requests/s with a burst of 5,000 per Region); **usage plans + API keys** for per-client limits; stage and method throttles |
| **DynamoDB** | **On-demand** (no capacity planning; instantly handles prior peaks) or **provisioned + auto scaling** (target utilization). A **hot partition** (one key) isn't fixed by more capacity; fix the key design (write sharding) |
| **Aurora Serverless v2** | Scales in ACUs within a min/max range, in fine increments |
| **RDS storage auto scaling** | Grows storage when free space is low, up to a **maximum storage threshold** |
| **Kinesis Data Streams** | **On-demand** mode, or provisioned shards with resharding |
| **App Runner / Fargate** | Concurrency-based or task-count scaling without servers |

## 6. Identifying and remediating scaling issues

| Symptom | Likely cause | Remediation |
|---|---|---|
| Scale-out happens, but users still see errors for 5+ minutes | Long boot/initialization | Warm pools; bake software into the AMI; predictive scaling; lower thresholds |
| The ASG never scales past N | **Max size** reached, or an account quota (vCPU limit) | Raise max; request a quota increase |
| "Insufficient capacity" launching instances | One instance type in one AZ | Mixed instances policy with several types; more AZs |
| Instance count oscillates (flapping) | Simple scaling with short cooldowns, or thresholds too close | Target tracking; proper warm-up; wider gap between thresholds |
| Queue backlog grows while CPU is low | Scaling on CPU instead of backlog | Backlog-per-instance target tracking |
| Lambda throttles (`429`) although the account has headroom | Reserved concurrency set too low on the function, or the event source mapping's maximum concurrency | Raise or remove reserved concurrency |
| One Lambda function starves others | No reserved concurrency for critical functions | Reserve concurrency for critical functions |
| DynamoDB `ProvisionedThroughputExceededException` on one key | A hot partition | Key design / write sharding; DAX for reads; on-demand if the load is spiky |
| ECS tasks pending | No capacity | Capacity provider with managed scaling, or Fargate |
| Unhealthy instances replaced in a loop | Health check grace period too short, or a wrong health-check path | Lengthen the grace period; fix the health-check path and thresholds |

## 7. Exam traps

* **Memory-based scaling** needs the **CloudWatch agent** (EC2) or Container Insights (ECS). Detailed monitoring doesn't add memory.
* **Reserved concurrency is also a ceiling,** not just a guarantee.
* **Provisioned concurrency** fixes cold starts (latency), not throttling caused by a reserved-concurrency cap.
* **Target tracking scales in conservatively;** step scaling reacts in bigger jumps.
* **Changing the launch template doesn't replace instances.** Use an instance refresh.
* **Lifecycle hooks need `CompleteLifecycleAction`,** or instances wait until the timeout and the default result applies.

## References

* Target tracking scaling — <https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-target-tracking.html>
* Scaling based on Amazon SQS — <https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-using-sqs-queue.html>
* Predictive scaling — <https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-predictive-scaling.html>
* Lifecycle hooks — <https://docs.aws.amazon.com/autoscaling/ec2/userguide/lifecycle-hooks.html>
* Warm pools — <https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-warm-pools.html>
* Instance refresh — <https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-instance-refresh.html>
* ECS capacity providers — <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-capacity-providers.html>
* Lambda concurrency — <https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html>
* Lambda scaling behaviour — <https://docs.aws.amazon.com/lambda/latest/dg/scaling-behavior.html>
* API Gateway throttling — <https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-request-throttling.html>
* DynamoDB read/write capacity modes — <https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadWriteCapacityMode.html>

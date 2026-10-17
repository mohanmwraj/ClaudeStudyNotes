# Practice Paper 5 — Full Mixed (Hardest)
> Original SAP-C02-style questions (not real exam questions). 20 questions · suggested time 48 min (≈2.4 min/question, exam pace).
> Domain mix: D1 ×5, D2 ×6, D3 ×5, D4 ×4
> [← Practice Papers index](README.md) · [Study Guide start page](../00-README-Start-Here.md)

---

## How to use this paper

- This is the **hardest** paper in the set. The stems are long and the distractors are close: most wrong options are *almost* right and fail on one decisive detail, such as a quota, a default, or a feature limit. That is what the real SAP-C02 does.
- **10 of the 20 questions are multi-select.** On the real exam, a multi-select question earns credit only when you choose every correct option and no wrong ones.
- Take it **2–3 days before the exam**, under timed conditions (48 minutes, no notes). Flag every guess. Then read every solution, including the ones you got right.
- Facts were checked against AWS documentation as of **October 2026**. Where a newer feature appears (for example VPC Lattice), the solution says so.

---

## Section 1 — Questions

### Question 1
A retail company runs a shopping-cart and loyalty service in **us-east-1** and **eu-west-1** in an active-active design. Each Region has an ALB, an ECS service, and a replica of one Amazon DynamoDB global table created with default settings. Abandoned carts are removed by a DynamoDB **TTL** attribute. Users are sent to the nearest Region by Amazon Route 53 **latency-based** alias records. During load testing, the team finds two problems. First, when a traveller's requests alternate between Regions within the same second, some cart updates silently disappear, even though the application uses a `version` attribute with conditional writes. Second, when the ECS service in one Region is deliberately broken, users in that Region keep getting errors until an engineer edits DNS by hand. The company needs automatic Regional failover within about a minute and **no lost updates for any given user's cart**. It wants to keep using DynamoDB global tables and keep cross-Region write latency low.

Which combination of actions will meet these requirements? **(Select TWO.)**

- A. Rely on DynamoDB global tables to merge concurrent updates attribute by attribute, and change the application to update only the attributes that changed instead of writing the whole item.
- B. Associate Route 53 health checks that test the application's health endpoint with each latency record (or set Evaluate Target Health on the ALB alias records), so that Route 53 stops returning an unhealthy Region.
- C. Keep conditional writes on the `version` attribute. They detect conflicting writes made in the other Region and reject the second writer, which prevents lost updates.
- D. Switch every read to strongly consistent reads so that each Region always sees the latest version of an item, whichever Region wrote it last.
- E. Store a home Region on each user profile and send all cart **writes** for that user to the home Region's replica, while reads are served from the nearest Region. Move the home Region only during an evacuation.
- F. Convert the existing global table to multi-Region strong consistency (MRSC) so that every write is synchronously replicated and conflicts are rejected.

### Question 2
A payments company runs an **Aurora PostgreSQL global database** with its primary cluster in **us-east-1** and a secondary cluster in **us-west-2**. A regulator requires the company to run production from the secondary Region for one month every quarter, with **zero data loss** during each planned move. The company's DR plan must also handle a full Regional outage with an RPO of seconds and an RTO of minutes. Application teams say they will not change connection strings after a Region move. A reporting service that runs only in us-west-2 also inserts a few audit rows per minute. The team does not want to build its own logic to send those writes to whichever Region is currently the primary. All clusters run the same engine version, and the team wants the least operational overhead.

Which solution meets these requirements?

- A. Use a managed failover (`failover-global-cluster --allow-data-loss`) for both the quarterly moves and real disasters. Point applications at the Aurora global writer endpoint, and enable write forwarding on the secondary cluster.
- B. Use a switchover (`switchover-global-cluster`) for both the quarterly moves and real disasters. Point applications at the Aurora global writer endpoint, and enable write forwarding on the secondary cluster.
- C. Use a switchover for the quarterly moves and a managed failover with `--allow-data-loss` for an unplanned Regional outage. Point applications at the Aurora global writer endpoint, and enable write forwarding on the secondary cluster.
- D. Use a switchover for the quarterly moves. For an unplanned outage, detach the us-west-2 cluster from the global database, update applications to that standalone cluster's endpoint, and enable write forwarding on the secondary cluster.

### Question 3
A media company ingests video into Amazon S3 from applications in **us-east-1** and **us-west-2**. Applications must use **one global S3 endpoint** and must not change configuration during a Regional event. The company wants an **active-passive** design: all reads and writes go to us-east-1 normally, and operators must be able to move all S3 request traffic to us-west-2 within a few minutes. Compliance requires replication between the buckets to be backed by an SLA, with notifications for any object that misses the replication threshold. Objects written in us-west-2 during a failover must flow back to us-east-1 automatically, including metadata changes. Both buckets are in the same account.

Which solution meets these requirements?

- A. Put an Amazon CloudFront distribution in front of both buckets with an origin group (us-east-1 primary, us-west-2 secondary). Configure two-way S3 Cross-Region Replication (CRR) with S3 Replication Time Control (RTC), and point applications at the CloudFront domain for all GET and PUT requests.
- B. Create an S3 Multi-Region Access Point (MRAP) for both buckets and set us-east-1 to active and us-west-2 to passive. Configure two-way CRR with S3 RTC and replica modification sync. During an event, use the MRAP failover controls to swap the routing status.
- C. Create an S3 Multi-Region Access Point for both buckets in an active-passive configuration. Configure one-way CRR from us-east-1 to us-west-2 without RTC, and run S3 Batch Replication back to us-east-1 after each failover.
- D. Create a Route 53 failover record for a custom domain that points to the us-east-1 bucket endpoint as primary and the us-west-2 bucket endpoint as secondary, with a health check. Configure two-way CRR with S3 RTC.

### Question 4
A healthcare company keeps clinical documents in an S3 bucket in **Account A** (production, **us-east-1**). Objects use SSE-KMS with a customer managed key that Account A owns, and **S3 Bucket Keys** are enabled to reduce KMS request costs. Security now requires a copy of every new object in a bucket in **Account B** (a locked-down archive account) in **us-west-2**, encrypted with a customer managed key that **Account B** owns. An engineer added a replication rule and an IAM role in Account A. Unencrypted test objects replicate, but SSE-KMS objects never appear in the destination. CloudTrail shows no KMS calls for the destination key.

Which THREE actions are required to fix replication? **(Select THREE.)**

- A. Change the destination to use the AWS managed key `aws/s3` in Account B so that no key policy changes are needed for cross-account use.
- B. In the replication rule, add `SourceSelectionCriteria` with `SseKmsEncryptedObjects` set to `Enabled`, and set `ReplicaKmsKeyID` to the ARN of Account B's key in us-west-2.
- C. Turn off S3 Bucket Keys on the source bucket, because S3 Replication cannot replicate objects that were encrypted with a bucket-level key.
- D. Update the key policy of Account B's destination key to allow Account A's replication role to use the key, including the `kms:Encrypt` and `kms:Decrypt` permissions that replication with Bucket Keys needs.
- E. Update the replication role's IAM policy to allow `kms:Decrypt` on the source key and `kms:Encrypt` on the destination key. Write the `kms:EncryptionContext:aws:s3:arn` conditions using the **bucket** ARN, not object ARNs.
- F. Replace the source key with a multi-Region primary key and create a replica key in us-west-2, so that S3 can decrypt replicas in the destination Region with the related key.

### Question 5
A financial services company uses AWS Organizations with all features enabled. Its new data perimeter standard has three rules. **(1)** Identities in the organization must not be able to copy data to S3 buckets outside the organization, such as a personal bucket. **(2)** S3 buckets in member accounts must never be reachable by principals outside the organization, even if an account administrator writes a permissive bucket policy. AWS services that act on the company's behalf (for example, CloudTrail delivering logs) must keep working. **(3)** Traffic from the corporate VPCs to S3 goes only through gateway endpoints, and those endpoints must not reach buckets outside the organization. The security team wants preventive controls that member account administrators cannot change.

Which combination of controls meets these requirements? **(Select THREE.)**

- A. An SCP that denies S3 actions when `aws:ResourceOrgID` does not equal the organization ID, with narrow exceptions for AWS-owned resources the workloads need.
- B. An SCP that denies S3 actions when `aws:PrincipalOrgID` does not equal the organization ID.
- C. A resource control policy (RCP) that denies S3 actions when `aws:PrincipalOrgID` does not equal the organization ID, unless `aws:PrincipalIsAWSService` is `true`.
- D. An RCP that denies S3 actions when `aws:ResourceOrgID` does not equal the organization ID.
- E. Attach the RCP to the organization root and rely on it to also protect the buckets in the management account, which hold the organization's billing exports.
- F. A VPC endpoint policy on each S3 gateway endpoint that allows access only when `aws:ResourceOrgID` equals the organization ID, deployed and protected centrally.

### Question 6
A manufacturer runs workloads in **six AWS Regions**. Each Region has a transit gateway, and the transit gateways are joined in a full mesh of inter-Region peering attachments. The network team maintains static routes in dozens of transit gateway route tables by hand, and mistakes have caused two outages. The company wants a **centrally defined, policy-based global network** with these rules: production VPCs can talk to each other but never to development VPCs; development VPCs can talk to each other; both production and development VPCs must reach a shared-services segment; VPCs that belong to **third-party vendors** must reach shared services but **must never reach each other**. New VPC attachments must join the correct segment automatically based on a tag. The team wants the least operational overhead.

Which combination of actions meets these requirements? **(Select TWO.)**

- A. Keep the transit gateway mesh, create separate production, development, and vendor route tables in every transit gateway, and turn on route propagation on the inter-Region peering attachments so routes no longer need to be maintained by hand.
- B. Set `isolate-attachments` to `true` on the production and development segments so that the two environments cannot reach each other.
- C. Deploy an AWS Cloud WAN core network with edge locations in all six Regions. Define `production`, `development`, `vendor`, and `shared-services` segments, map attachments to segments with tag-based attachment policies, and add a `share` action that shares `shared-services` with `production`, `development`, and `vendor`.
- D. Share the `production` segment with the `development` segment, and add a `deny-filter` on `production` that blocks routes from `development`.
- E. Set `isolate-attachments` to `true` on the `vendor` segment.

### Question 7
A company bought a fintech startup and is moving the startup's 40 microservices into **12 new AWS accounts** in its organization. The services run on Amazon EKS, Amazon ECS, and AWS Lambda. Many of the startup's VPCs use **CIDR ranges that overlap** with each other and with the parent company's VPCs, and re-addressing is out of scope for this year. Services call each other over HTTPS. Security requires every call to be authenticated with the caller's **IAM identity** and authorized per service and per **URL path**, for example only the `ledger-reader` role may call `GET /balances`. The platform team does not want to run sidecar proxies, manage transit gateway route tables, or create a separate endpoint in every consumer VPC for every provider service.

Which solution meets these requirements with the least operational overhead?

- A. Attach all VPCs to a transit gateway, add a routable secondary CIDR and a private NAT gateway to each VPC, place each service behind an internal ALB, and use security groups to allow only the approved caller subnets.
- B. Publish each service as a PrivateLink endpoint service behind a Network Load Balancer, create interface endpoints for each provider service in each consumer VPC, and have each service check a JWT issued by a shared identity provider.
- C. Peer every consumer VPC with every provider VPC, use Route 53 private hosted zones for service discovery, and configure resource-based policies on each service's API to allow specific IAM roles.
- D. Create an Amazon VPC Lattice service network in a networking account, share it through AWS RAM, and associate the workload VPCs and services with it. Set the auth type to `AWS_IAM` on the service network and the services, write auth policies that use `aws:PrincipalOrgID`, principal ARNs, and `vpc-lattice-svcs:RequestPath` conditions, and have clients sign requests with SigV4.

### Question 8
After an acquisition, a company must let applications in its **VPC A** (10.0.0.0/16) call HTTPS services in the acquired company's **VPC B**, which is also **10.0.0.0/16**. Both VPCs are in the same Region and already attach to the parent company's transit gateway for other traffic. All connections start in VPC A. The acquired services run on EC2 instances that can sit behind a load balancer. Re-addressing VPC B will take at least nine months. The company wants a solution it can build in weeks, using its existing network constructs, without exposing either VPC to the internet.

Which solution meets these requirements?

- A. Add a non-overlapping secondary CIDR (for example, 100.64.1.0/24 to VPC A and 100.64.2.0/24 to VPC B). Create a private NAT gateway in a routable subnet in VPC A and an internal ALB in a routable subnet in VPC B. Attach the routable subnets to the transit gateway with static routes, and route traffic for VPC B's routable range from VPC A's workload subnets to the private NAT gateway.
- B. Create a VPC endpoint service backed by a Network Load Balancer in VPC A, create an interface VPC endpoint for that service in VPC B, and point the VPC A applications at the endpoint's DNS name.
- C. Create a VPC peering connection between VPC A and VPC B, and add more-specific routes for the subnets that host the acquired services so the overlap is resolved by longest-prefix match.
- D. Keep both VPC attachments on the transit gateway, and add static /24 routes in a dedicated transit gateway route table that point to VPC B's attachment for the subnets that host the acquired services.

### Question 9
A security team must deploy a baseline CloudFormation template to **every account in the `Workloads` OU** in three Regions. The baseline creates an IAM role for the security tooling, AWS Config rules, and a CloudWatch Logs subscription. Accounts that are created in or moved into the OU later must receive the baseline **automatically, with no manual steps**. When an account is moved out of the OU for decommissioning, forensic policy requires its baseline resources to **stay in place**. The organization's management account must not be used for day-to-day operations, so the team wants to run StackSet operations from its **security tooling account**. A few sandbox accounts sit inside `Workloads` temporarily, and someone suggests excluding them by account ID.

Which combination of actions meets these requirements? **(Select TWO.)**

- A. Create a StackSet with self-managed permissions, deploy the `AWSCloudFormationStackSetExecutionRole` to every account, and use an EventBridge rule on `CreateAccount` events to start a Lambda function that adds stack instances.
- B. Create a StackSet with service-managed permissions that targets the `Workloads` OU in the three Regions. Turn on automatic deployment and set the account removal behavior to **Retain stacks**.
- C. Turn on automatic deployment and add an account-level filter that excludes the sandbox account IDs, so that sandbox accounts added to the OU later are skipped automatically.
- D. From the management account, register the security tooling account as a delegated administrator for CloudFormation StackSets. Create and manage the StackSet from that account with `--call-as DELEGATED_ADMIN`.
- E. Target the organization root instead of the OU so that the management account also receives the baseline, and use the management account to run the StackSet.

### Question 10
A company with **40 member accounts** wants developers to provision approved infrastructure (an RDS PostgreSQL database, an encrypted S3 bucket, and an EC2 Auto Scaling group) without the broad `PowerUserAccess` permissions they have today. Security requires least privilege: developers must not have direct permissions for RDS, EC2, S3, or CloudFormation, only for self-service provisioning. Only approved instance classes may be selected. The central cloud team maintains one hub portfolio, shares it with all accounts through AWS Organizations, and wants the setup to stay the same in every account.

Which solution meets these requirements?

- A. Share the portfolio, and grant developers the AWS Service Catalog end-user policy plus `AWSCloudFormationFullAccess` and scoped RDS, EC2, and S3 permissions. Add template constraints that limit the allowed instance classes.
- B. Share the portfolio. Use StackSets to deploy an IAM launch role with the same name to every account, trusted by `servicecatalog.amazonaws.com` and granted the permissions the products' resources need. Add a launch constraint on each product that specifies the **local role name**, add template constraints for the allowed instance classes, and grant developers only Service Catalog end-user permissions.
- C. Share the portfolio, and create a launch constraint on each product that specifies the **ARN** of a launch role in the hub account. Add template constraints for the allowed instance classes, and grant developers only Service Catalog end-user permissions.
- D. Share the portfolio, and create a launch role that includes `servicecatalog:ProvisionProduct` and the resource permissions. Allow developers to assume the launch role directly, and add template constraints for the allowed instance classes.

### Question 11
A company's CI/CD pipeline runs in a central **tooling account** (us-east-1): CodePipeline with a source action, a CodeBuild build action, and CloudFormation deploy actions that target separate **staging** and **production** accounts. The artifact store is the default S3 bucket encrypted with the AWS managed key `aws/s3`. The deploy stages fail with access-denied errors when the target accounts try to read the build artifact. The company wants a secure fix that follows AWS guidance for cross-account pipelines.

Which THREE actions should the architect take? **(Select THREE.)**

- A. Refer to the KMS key in the pipeline's `artifactStore.encryptionKey` by its **alias** (`alias/pipeline-artifacts`) so that the cross-account deploy roles resolve the key in their own accounts.
- B. Create a symmetric customer managed KMS key in the tooling account in us-east-1, grant use of it to the pipeline service role and to the target accounts' deploy roles, and set the key ARN as the artifact store's encryption key.
- C. Turn on S3 Cross-Region Replication from the artifact bucket to a bucket in each target account so that deploy actions read artifacts from a local copy.
- D. Add an artifact bucket policy that lets the target accounts' cross-account roles get (and, where needed, put) objects in the artifact bucket.
- E. Keep the `aws/s3` key and edit its key policy to add the staging and production accounts as key users.
- F. In each target account, create a role that the tooling account's pipeline service role can assume. Give it CloudFormation permissions, `iam:PassRole` for a CloudFormation deployment role, and access to the artifact bucket and KMS key. Set this role as the deploy action's `roleArn`, and allow the pipeline service role to call `sts:AssumeRole` on it.

### Question 12
A logistics company runs a stateless REST API on **Amazon ECS on AWS Fargate** behind an ALB. To meet its availability SLA, at least **4 tasks** must always run on capacity that cannot be interrupted. During daily peaks, service auto scaling grows the service to as many as 40 tasks. Finance wants the lowest cost for the scaled portion. The team accepts interruption of tasks above the baseline and wants about **three quarters** of those extra tasks to run on spare capacity. Tasks must drain in-flight requests cleanly when they are interrupted.

Which capacity provider strategy and configuration meet these requirements?

- A. `FARGATE` with base 4 and weight 1, and `FARGATE_SPOT` with base 4 and weight 3. Set the container `stopTimeout` to 120 seconds.
- B. `FARGATE_SPOT` with base 4 and weight 3, and `FARGATE` with weight 1. Handle SIGTERM in the application, and set the ALB deregistration delay below the container `stopTimeout`.
- C. `FARGATE` with base 4 and weight 1, and `FARGATE_SPOT` with weight 3. Rely on ECS to launch replacement tasks on `FARGATE` automatically whenever Fargate Spot capacity is unavailable, so peak capacity is always met.
- D. `FARGATE` with base 4 and weight 1, and `FARGATE_SPOT` with weight 3. Handle SIGTERM in the application, set the container `stopTimeout` to up to 120 seconds, and set the ALB deregistration delay below that value.

### Question 13
A SaaS company ingests order events from hundreds of producer services that call `PutEvents` on a **custom event bus** in **us-east-1**. Rules on the bus fan the events out to Step Functions and SQS. A recent Regional impairment stopped event ingestion for 40 minutes. The company now needs event ingestion to fail over to **us-west-2** automatically, with an RTO and RPO of **under 10 minutes**, and to **return to us-east-1 automatically** once the Region is healthy, with no operator action. Producers can make small configuration changes but must not implement their own Region-selection logic.

Which solution meets these requirements?

- A. Create an EventBridge global endpoint with us-east-1 as primary and us-west-2 as secondary. Attach a Route 53 health check driven by a CloudWatch alarm on the primary bus's health metrics, and turn on event replication. Create a custom bus with the same name, plus the same rules and targets, in us-west-2. Update producers to pass the endpoint ID in `PutEvents`, using an SDK that supports SigV4a.
- B. Create an EventBridge global endpoint with us-east-1 as primary and us-west-2 as secondary, with a Route 53 health check driven by a CloudWatch alarm. Turn off event replication to avoid the extra cost, and create a same-named custom bus with the same rules in us-west-2. Update producers to pass the endpoint ID.
- C. Add a rule on the us-east-1 bus that sends all events to an event bus in us-west-2 as a cross-Region target, and duplicate the downstream rules and targets in us-west-2.
- D. Create a Route 53 failover CNAME record (`events.example.com`) that points to the EventBridge service endpoints in us-east-1 and us-west-2, with a health check on the primary, and configure producers to use the CNAME as their endpoint URL.

### Question 14
A company is closing its secondary colocation facility, which serves only as a disaster recovery site. The primary on-premises data center runs **150 servers**, a mix of VMware VMs and physical Windows and Linux servers, including several SQL Server and Oracle hosts. The new DR target is AWS. Requirements: an RPO of **seconds** and an RTO under **30 minutes** for all servers; low steady-state cost in AWS; quarterly DR drills that do not affect production or replication; and the ability to **fail back to the on-premises data center** after it is restored, without rebuilding servers by hand.

Which solution meets these requirements with the least operational overhead?

- A. Deploy AWS Backup gateway for the VMware VMs and the AWS Backup agent on the physical servers. Copy backups to AWS every hour, and restore them as EC2 instances during a disaster.
- B. Use AWS Transform MGN (AWS Application Migration Service) to replicate all servers continuously. During a disaster, launch cutover instances, and use MGN replication in the opposite direction to return to on premises.
- C. Use AWS Elastic Disaster Recovery: install the replication agent on each source server, replicate to a low-cost staging area subnet, set right-sized launch settings, run non-disruptive drills, and fail back by using the Elastic Disaster Recovery Failback Client.
- D. Build a pilot-light environment: keep a stopped EC2 copy of each server, keep databases in sync with native log shipping, keep file servers in sync with scheduled `rsync` jobs, and start everything with an automation runbook.

### Question 15
An insurance company runs a claims application in one Region: an ALB, an EC2 Auto Scaling group across three AZs, Aurora MySQL with one replica, and ElastiCache. The application owner has documented an **RTO of 15 minutes and an RPO of 5 minutes**. The CIO wants evidence before the next audit. First, an assessment of whether the current architecture can meet those targets, with specific recommendations. Second, a controlled **game day in production** that injects AZ-level and database failures and **stops automatically** if the customer-facing error rate passes 2%. The team wants to use managed AWS services and avoid custom tooling.

Which combination of actions meets these requirements? **(Select TWO.)**

- A. Define the application in AWS Resilience Hub from its CloudFormation stacks, attach a resiliency policy with RTO 15 minutes and RPO 5 minutes, run an assessment, and track the recommended changes.
- B. Turn on the AWS Trusted Advisor fault tolerance checks, and present the results as evidence that the application meets its RTO and RPO targets.
- C. Write AWS Systems Manager Run Command scripts that stop instances in one AZ and reboot the Aurora writer, and have engineers watch CloudWatch dashboards and stop the scripts by hand if errors rise.
- D. Create an AWS Fault Injection Service (FIS) experiment template with actions such as terminating instances in one AZ and failing over the Aurora cluster, and set a **stop condition** on a CloudWatch alarm for the ALB 5xx error rate above 2%.
- E. Create an AWS FIS experiment template with the same actions and no stop conditions, and limit the experiment's blast radius only through its maximum duration, run during a low-traffic window.

### Question 16
A data analytics company wants to cut a fast-growing AWS data transfer bill without lowering availability. A Cost and Usage Report analysis shows three main cost drivers. **(1)** Chatty microservices in one VPC call each other through internal ALBs with cross-zone load balancing on, so most calls cross AZs, producing hundreds of TB of regional data transfer each month. **(2)** About 300 TB per month flows between two specific VPCs (an ingest VPC and a processing VPC) in the same Region, through the company's transit gateway, which connects 30 VPCs. **(3)** Software downloads and static assets, about 500 TB per month, are served to internet users directly from an S3 bucket and an ALB.

Which combination of actions will reduce data transfer costs the most while keeping the current architecture's availability? **(Select THREE.)**

- A. Turn on S3 Transfer Acceleration for the download bucket so that internet users fetch objects through the nearest edge location.
- B. Move all microservices and their databases into a single Availability Zone to remove inter-AZ data transfer charges.
- C. Put Amazon CloudFront in front of the S3 bucket and the ALB for downloads and static assets, with suitable cache behaviors.
- D. Add a VPC peering connection between the ingest VPC and the processing VPC, with more-specific routes, so that this traffic avoids transit gateway data processing charges. Keep the transit gateway for all other traffic.
- E. Send traffic between the ingest and processing VPCs through a centralized inspection VPC so that it can be compressed and deduplicated before delivery.
- F. Turn off cross-zone load balancing on the internal ALBs' target groups, and use AZ-aware service discovery so that callers prefer targets in their own AZ, while keeping capacity in every AZ.

### Question 17
A holding company uses AWS Organizations with consolidated billing for 60 accounts. A newly acquired subsidiary runs all of its workloads in **one member account** and has its own P&L. The subsidiary bought a large Compute Savings Plan. Its CFO requires that the Savings Plan discount apply **only** to the subsidiary's account, and that the subsidiary **not receive** any discount from the parent's Reserved Instances or Savings Plans, so that the subsidiary's reported costs are arm's-length. The parent's finance team must keep the subsidiary in the organization and produce a monthly chargeback for every business unit that shows amortized commitment costs.

Which solution meets these requirements?

- A. Move the subsidiary's account into its own OU, and attach an SCP that denies `savingsplans:*` and `ec2:PurchaseReservedInstancesOffering` to stop discount sharing in either direction. Use AWS Budgets reports for chargeback.
- B. From the management account, deactivate Reserved Instance and Savings Plans discount sharing for the subsidiary's account in Billing preferences. Build chargeback with AWS Cost Categories and cost allocation tags, using amortized costs from Cost Explorer or Cost and Usage Report (CUR 2.0) data exports.
- C. Sign in to the subsidiary's member account, and deactivate Reserved Instance and Savings Plans discount sharing in that account's Billing preferences. Build chargeback with Cost Categories and amortized costs from the CUR.
- D. Remove the subsidiary's account from the organization and invite it into a separate organization with its own management account. Build chargeback for the remaining business units with Cost Categories.

### Question 18
A healthcare group is planning three workloads. **(1)** A medical imaging (PACS) system in a hospital: regulation requires patient images and the database to stay on the hospital's premises, and imaging devices need single-digit millisecond latency to the application. The team wants AWS APIs, EBS volumes, and a managed relational database. **(2)** A remote-radiology rendering service for clinicians across a large metropolitan area, which needs single-digit millisecond latency from the city to GPU instances. Data may be stored in AWS. **(3)** An augmented-reality guidance app for paramedics' 5G mobile devices, which needs the lowest possible latency from the devices on a telecom carrier's 5G network.

Which deployment choice fits each workload?

- A. (1) AWS Outposts rack with EBS-backed instances and Amazon RDS on Outposts; (2) an AWS Local Zone in that metro area; (3) an AWS Wavelength Zone in the carrier's network.
- B. (1) AWS Outposts servers with Amazon RDS on Outposts; (2) an AWS Local Zone in that metro area; (3) an AWS Wavelength Zone in the carrier's network.
- C. (1) An AWS Local Zone in the hospital's metro area; (2) an AWS Wavelength Zone in the carrier's network; (3) an AWS Local Zone in that metro area.
- D. (1) AWS Outposts rack with EBS-backed instances and Amazon RDS on Outposts; (2) an AWS Wavelength Zone in the carrier's network; (3) an AWS Local Zone in that metro area.

### Question 19
A company exposes a **Regional** Amazon API Gateway REST API with Lambda proxy integrations. After a product launch, operations reports three problems. **(1)** One partner, whose API key belongs to a usage plan limited to 100 requests per second by contract, gets `429 Too Many Requests` during its batch jobs. The partner's contract will not change. **(2)** `GET /reports` returns `504` responses after about 29 seconds. The Lambda function behind it routinely runs for 40–50 seconds, and its timeout is 120 seconds. The client contract requires a synchronous response. **(3)** During spikes, `POST /orders` returns 5xx errors. API Gateway execution logs show `Lambda invocation failed with status: 429` (TooManyRequestsException). A nightly batch Lambda function in the same account and Region consumes most of the account's concurrency.

Which actions will resolve the problems that should be fixed, with the least redesign? **(Select TWO.)**

- A. Increase the `/reports` Lambda function's memory and set its timeout to 900 seconds so that API Gateway waits for the function to finish.
- B. Raise the partner's usage plan rate limit and burst to 1,000 so that its batch jobs stop receiving 429 responses.
- C. Request an increase to the integration timeout quota for the Regional API, and set the `/reports` integration timeout above the function's typical duration, accepting that the account's Region-level throttle quota may need to be reduced.
- D. Raise the stage-level and method-level throttling limits for `POST /orders` so that API Gateway accepts more requests during spikes.
- E. Configure reserved concurrency on the batch Lambda function to cap it, and reserved concurrency on the `/orders` function to guarantee it capacity.

### Question 20
A company rehosted a Java web application onto EC2 instances in an Auto Scaling group behind an ALB. The application keeps HTTP **session state in memory** and depends on ALB **duration-based stickiness**. Since the migration, users are logged out whenever scale-in terminates an instance, and a few instances run hot while others sit idle, because sticky users pile up on the oldest instances. The company wants the tier to scale in and out freely with **no session loss**, an even load spread, and minimal code change. Sessions are about 10 KB each, expire after 30 minutes of inactivity, are read and written on every request, and need **sub-millisecond** access latency.

Which combination of actions meets these requirements? **(Select TWO.)**

- A. Increase the ALB stickiness duration to 7 days and enable connection draining so that users stay on their original instance for longer.
- B. Store sessions on an Amazon EFS file system mounted on every instance, and configure the servlet container's file-based session persistence.
- C. Move session state to Amazon ElastiCache (Valkey or Redis OSS) with Multi-AZ and automatic failover, using the framework's session-store integration (for example, Spring Session) with a 30-minute TTL.
- D. Switch to ALB application-based cookie stickiness so that the application controls the cookie and sessions survive when an instance is terminated.
- E. Move session state to an Amazon DynamoDB table with TTL, and use strongly consistent reads for every session lookup.
- F. After sessions are externalized, turn off stickiness on the target group and use the least outstanding requests routing algorithm.

---

## Section 2 — Answer key

| Q | Answer | Domain / Task | Topic |
|---|---|---|---|
| 1 | **B, E** | D2 Task 2.2 / 2.4 | DynamoDB global tables (MREC) last-writer-wins + Route 53 latency routing with health checks |
| 2 | **C** | D2 Task 2.2 | Aurora Global Database switchover vs failover, global writer endpoint, write forwarding |
| 3 | **B** | D2 Task 2.4 | S3 Multi-Region Access Point failover controls + two-way CRR with RTC |
| 4 | **B, D, E** | D2 Task 2.3 | Cross-account replication of SSE-KMS objects with S3 Bucket Keys |
| 5 | **A, C, F** | D1 Task 1.2 | Data perimeter: SCP `aws:ResourceOrgID`, RCP `aws:PrincipalOrgID`, VPC endpoint policy |
| 6 | **C, E** | D1 Task 1.1 | AWS Cloud WAN segments and `isolate-attachments` vs transit gateway mesh |
| 7 | **D** | D4 Task 4.3 | VPC Lattice service network with IAM auth policies (emerging) |
| 8 | **A** | D1 Task 1.1 | Overlapping CIDRs: private NAT gateway + transit gateway |
| 9 | **B, D** | D1 Task 1.4 | Service-managed StackSets with automatic deployment + delegated admin |
| 10 | **B** | D3 Task 3.2 | Service Catalog launch constraints (local role name) + template constraints |
| 11 | **B, D, F** | D3 Task 3.1 | Cross-account CodePipeline with a customer managed KMS key |
| 12 | **D** | D2 Task 2.6 | ECS capacity provider strategy: Fargate base + Fargate Spot weight |
| 13 | **A** | D2 Task 2.2 | EventBridge global endpoints with event replication |
| 14 | **C** | D4 Task 4.3 | AWS Elastic Disaster Recovery for on-premises → AWS with failback |
| 15 | **A, D** | D3 Task 3.4 | Resilience Hub assessment + FIS experiment with stop conditions |
| 16 | **C, D, F** | D3 Task 3.5 | Data transfer cost: CloudFront, peering vs transit gateway, AZ affinity |
| 17 | **B** | D1 Task 1.5 | RI/SP discount sharing turned off for one account + chargeback |
| 18 | **A** | D4 Task 4.3 | Outposts vs Local Zones vs Wavelength |
| 19 | **C, E** | D3 Task 3.3 / 3.4 | API Gateway 429 vs 5xx vs 504 with Lambda concurrency and integration timeout |
| 20 | **C, F** | D4 Task 4.4 | Externalizing session state (ElastiCache) and dropping ALB stickiness |

**Domain check:** D1 = Q5, Q6, Q8, Q9, Q17 (5) · D2 = Q1, Q2, Q3, Q4, Q12, Q13 (6) · D3 = Q10, Q11, Q15, Q16, Q19 (5) · D4 = Q7, Q14, Q18, Q20 (4).

---

## Section 3 — Detailed solutions

### Solution 1 — Answer: **B, E**

**Decisive keywords:** "global table created with default settings" (so MREC), "conditional writes … updates silently disappear", "TTL", "automatic Regional failover within about a minute", "no lost updates for any given user's cart", "keep cross-Region write latency low".

**Why B and E are correct**
- **B:** A latency record with no health check stays in the answer set even when the application behind it is broken. When you attach a health check (or set **Evaluate Target Health** on an alias to the ALB), Route 53 returns the record with the next-best latency once a Region is unhealthy. Fast health checks (10-second interval) with the default failure threshold of 3, plus a low TTL, keep failover around a minute.
- **E:** The default mode, **multi-Region eventual consistency (MREC)**, resolves concurrent writes to the same item with **last writer wins at the item level**, using an internal timestamp. Conditional writes are checked only against the **local** replica's version. To avoid conflicts while keeping MREC's low write latency, make sure an item is written in only one Region at a time. AWS documents this as the **"write to your Region" (mixed primary)** mode: each item gets a home Region, and writes go there. Reads can still be served from the nearest Region.

**Why the others are wrong**
- **A:** Global tables do **not** merge attributes. Conflict resolution works on the whole item, and the last writer wins.
- **C:** This is the trap. Under MREC, a condition expression is checked against the item version **in the Region that receives the write**. Two Regions can each pass their own check, and replication then keeps only the last write.
- **D:** A strongly consistent read returns the latest version only if the item was last updated **in the same Region**. It may return stale data for writes made elsewhere.
- **F:** You **cannot change** a global table's consistency mode after creation. MRSC must also be built from an **empty** table, needs **exactly three Regions** (three replicas, or two replicas plus a witness), does **not support TTL**, and adds cross-Region latency to every write. That conflicts with "keep cross-Region write latency low".

**Concept to remember:** MREC = last writer wins per item, and conditions are evaluated locally. To prevent lost updates, give each item a single writing Region, or use MRSC if its limits are acceptable.

**References**
- [How DynamoDB global tables work (consistency modes, MRSC limits)](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/V2globaltables_HowItWorks.html)
- [Write modes with DynamoDB global tables](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/bp-global-table-design.prescriptive-guidance.writemodes.html)
- [Route 53 latency-based routing](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy-latency.html) · [Route 53 DNS failover and health checks](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover.html)

---

### Solution 2 — Answer: **C**

**Decisive keywords:** "planned move … zero data loss", "full Regional outage", "will not change connection strings", "a few audit rows per minute" written from the secondary, "same engine version", "least operational overhead".

**Why C is correct**
- **Switchover** (formerly *managed planned failover*) waits until the secondary is **fully synchronized** before it promotes it, so **RPO = 0**. It keeps the replication topology, which makes it the documented tool for regulator-driven "Region rotation". It requires all clusters to be healthy.
- **Managed failover** (`failover-global-cluster --allow-data-loss`) is for an **unplanned** outage. It does not wait for synchronization, so RPO is the replication lag (typically seconds). Aurora tries to fence writes in the old primary, takes a snapshot of the old volume when it can, and re-adds the old Region as a secondary when it recovers.
- The **global writer endpoint** keeps the same DNS name after a switchover or failover, so applications don't change connection strings.
- **Write forwarding** sends write statements issued on a secondary cluster to the primary. Aurora manages the cross-Region networking and session context, so the team does not build its own routing logic.

**Why the others are wrong**
- **A:** A failover can **lose data**, so it breaks the "zero data loss" rule for the quarterly moves.
- **B:** Switchover is meant for healthy clusters. It **waits for the secondary to synchronize with the primary**, which cannot happen when the primary Region is down. It is not a DR mechanism.
- **D:** Detaching the cluster (a *manual* failover) breaks the global database topology, forces connection-string changes, and means rebuilding the global database. AWS keeps this method for cases where managed failover isn't possible, such as incompatible engine versions. The stem says the versions match.

**Concept to remember:** Planned move with RPO 0 → **switchover**. Disaster → **managed failover (allow data loss)**. Stable endpoint → **global writer endpoint**. Occasional writes from a secondary → **write forwarding**.

**References**
- [Using switchover or failover in Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery.html)
- [Connecting to Aurora Global Database (global writer endpoint)](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-connecting.html)
- [Write forwarding in an Aurora global database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-write-forwarding.html)

---

### Solution 3 — Answer: **B**

**Decisive keywords:** "one global S3 endpoint", "active-passive", "within a few minutes", "SLA-backed replication with notifications", "written in us-west-2 … flow back … including metadata changes".

**Why B is correct**
- An **S3 Multi-Region Access Point** gives applications one global endpoint. With **failover controls**, you set each Region's routing status to **active** or **passive**. Choosing **Failover** swaps the two, and AWS documents that traffic is redirected in **about 2 minutes**. Existing connections are not cut off. The routing-control API can be called from any of five Regions (us-east-1, us-west-2, ap-southeast-2, ap-northeast-1, eu-west-1), so a failover still works if one Region is impaired.
- AWS recommends **two-way replication rules plus replica modification sync** before you configure failover. That way, writes made in the failover Region replicate back, metadata included.
- **S3 RTC** replicates most objects in seconds and **99.9% within 15 minutes**, backed by an SLA. It turns on replication metrics and the `OperationMissedThreshold` / `OperationReplicatedAfterThreshold` event notifications.

**Why the others are wrong**
- **A:** CloudFront **origin failover** applies only to **GET, HEAD, and OPTIONS** requests. Writes (PUT) are not retried against the secondary origin, so CloudFront cannot provide write failover.
- **C:** One-way CRR without RTC has **no SLA or threshold notifications**. Running Batch Replication by hand after each failover is not "automatic", and it doesn't keep metadata changes in sync.
- **D:** S3 REST endpoints expect a Host header that matches the bucket, and two buckets cannot share a name across Regions. A failover CNAME between two bucket endpoints doesn't work cleanly, particularly over HTTPS. It is also not a single S3 endpoint with request-level routing control.

**Concept to remember:** "One global S3 endpoint plus controlled Regional failover" → **MRAP failover controls**. "Replication SLA" → **RTC** (15 minutes, 99.9%).

**References**
- [Amazon S3 Multi-Region Access Points failover controls](https://docs.aws.amazon.com/AmazonS3/latest/userguide/MrapFailover.html) · [Using MRAP failover controls](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingFailover.html)
- [S3 Replication Time Control](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-time-control.html)
- [CloudFront origin failover (GET/HEAD/OPTIONS only)](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/high_availability_origin_failover.html)

---

### Solution 4 — Answer: **B, D, E**

**Decisive keywords:** "SSE-KMS objects never appear", "no KMS calls for the destination key", "Account B owns" the destination key, "S3 Bucket Keys are enabled".

**Why B, D, and E are correct**
- **B:** By default, S3 Replication **does not replicate SSE-KMS (or DSSE-KMS) objects**. You must opt in with `SourceSelectionCriteria` → `SseKmsEncryptedObjects` = `Enabled`, and name the destination key with `ReplicaKmsKeyID`. That key must be in the **destination bucket's Region**. The missing opt-in explains why CloudTrail shows no KMS calls.
- **D:** When the destination key belongs to another account, **its owner must grant** the source account's replication role permission to use it. With Bucket Keys, the key policy for the replica's key must also allow **`kms:Decrypt`** for the calling principal, because S3 checks the integrity of the bucket key.
- **E:** The replication role needs `kms:Decrypt` on the source key and `kms:Encrypt` on the destination key. With **Bucket Keys enabled**, the encryption context is the **bucket ARN** (`arn:aws:s3:::bucket`), not the object ARN. Conditions written for object ARNs will deny the call.

**Why the others are wrong**
- **A:** **AWS managed keys cannot be used across accounts.** Cross-account SSE-KMS replication must use a **customer managed key**.
- **C:** Replication supports Bucket Keys. The only change is to the encryption context in your policies.
- **F:** S3 treats multi-Region keys **as single-Region keys** and does not use their multi-Region features. You need a destination key in the destination Region either way, so this adds nothing.

**Concept to remember:** Encrypted replication needs three things: **opt in** (SourceSelectionCriteria plus ReplicaKmsKeyID), **cross-account key policy** (customer managed key only), and **correct encryption context** (bucket ARN when Bucket Keys are on).

**References**
- [Replicating encrypted objects (SSE-S3, SSE-KMS, DSSE-KMS, SSE-C)](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-config-for-kms-objects.html)
- [Reducing the cost of SSE-KMS with S3 Bucket Keys](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-key.html)
- [AWS KMS keys: customer managed vs AWS managed](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html)

---

### Solution 5 — Answer: **A, C, F**

**Decisive keywords:** "identities … must not … copy data to buckets outside the organization" (identity side, so SCP), "buckets … never reachable by principals outside the organization" (resource side, so RCP), "AWS services that act on the company's behalf must keep working", "gateway endpoints must not reach buckets outside the organization" (network side, so endpoint policy).

**Why A, C, and F are correct**
- **A (SCP + `aws:ResourceOrgID`):** SCPs cap what **your principals** can do. Denying S3 actions on resources whose `aws:ResourceOrgID` is not your organization stops copies to personal or third-party buckets. Add narrow exceptions for **AWS-owned resources** your workloads legitimately use. The data perimeter guidance covers these exceptions, for example service-owned buckets used by some AWS services.
- **C (RCP + `aws:PrincipalOrgID`):** RCPs cap what can be done **to your resources**. They apply even when an administrator writes a permissive bucket policy, and they also apply to root users of member accounts. The `aws:PrincipalIsAWSService` exception keeps service principals such as CloudTrail log delivery working. RCPs **do not apply to service-linked roles**.
- **F (VPC endpoint policy):** An S3 gateway endpoint policy that allows only resources in your organization stops the network path from reaching outside buckets, even with credentials from elsewhere. Deploy it centrally (for example, with StackSets) and protect it with an SCP that blocks changes to it.

**Why the others are wrong**
- **B:** An SCP applies **only to principals in the organization**, so `aws:PrincipalOrgID` always matches. This SCP does nothing to outside principals.
- **D:** An RCP applies **only to resources in the organization**, so `aws:ResourceOrgID` always matches. Controlling access to *external* resources is the SCP's job (option A).
- **E:** **RCPs do not affect resources in the management account**, just as SCPs don't affect its principals. Keep data out of the management account, or protect it another way.

**Concept to remember:** SCP = the **principals** you own → use `aws:ResourceOrgID` (trusted resources). RCP = the **resources** you own → use `aws:PrincipalOrgID` (trusted identities). Endpoint policy = **network** perimeter. Neither SCPs nor RCPs reach the management account.

**References**
- [Resource control policies (RCPs): supported services, exclusions](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html)
- [Service control policies (SCPs)](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [Building a data perimeter on AWS (whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/building-a-data-perimeter-on-aws/building-a-data-perimeter-on-aws.html)
- [Control access to VPC endpoints using endpoint policies](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-access.html)

---

### Solution 6 — Answer: **C, E**

**Decisive keywords:** "six Regions", "static routes … by hand", "centrally defined, policy-based", vendors "must never reach each other", "join the correct segment automatically based on a tag", "least operational overhead".

**Why C and E are correct**
- **C:** In AWS Cloud WAN, one **core network policy** creates a core network edge in each listed Region. The edges peer with each other automatically and use dynamic routing. **Each segment is a separate routing domain**, so by default attachments reach only their own segment, which already keeps production and development apart. **Attachment policies** map attachments to segments by tag. A **`share`** of `shared-services` with `[production, development, vendor]` lets each of those reach shared services. The shared segments do **not** reach each other through it, because sharing doesn't happen between the segments inside the array.
- **E:** `isolate-attachments: true` stops attachments **in the same segment** from reaching each other. They can reach only shared routes or static routes. That is exactly what the vendor segment needs.

**Why the others are wrong**
- **A:** **Transit gateway peering attachments support only static routes.** You cannot turn on route propagation across inter-Region peering, so the manual work stays.
- **B:** Production and development are already isolated because they are different segments. Setting `isolate-attachments` on them would also stop **production VPCs from reaching each other**, which breaks a requirement.
- **D:** Sharing production with development creates exactly the connectivity that is forbidden. Adding a deny filter on top only undoes the share, which is pointless and confusing.

**Concept to remember:** Cloud WAN: **segment = routing domain** (isolated from other segments by default). **`share`** = reach across segments, not transitive between the shared segments. **`isolate-attachments`** = no communication between attachments within the segment.

**References**
- [Cloud WAN core network policy parameters (segments, isolate-attachments, share, attachment policies)](https://docs.aws.amazon.com/network-manager/latest/cloudwan/cloudwan-policies-json.html)
- [Transit gateway peering attachments (static routes)](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-peering.html)

---

### Solution 7 — Answer: **D**

> **Emerging / SAP-C03 preview note:** VPC Lattice became generally available in 2023 and appears more often in recent material. Know it for SAP-C02, but expect PrivateLink and transit gateway to be the more common answers in older-style questions.

**Decisive keywords:** "12 accounts", "CIDR ranges that overlap", "authenticated with the caller's IAM identity", "per URL path", "no sidecar proxies … transit gateway route tables … endpoint in every consumer VPC".

**Why D is correct**
- **VPC Lattice** is a managed application networking layer. A **service network** is shared across accounts with **AWS RAM**, VPCs and services are associated with it, and Lattice handles connectivity **even between VPCs whose CIDRs overlap**. You don't manage routes, peering, or a transit gateway.
- With auth type **`AWS_IAM`**, **auth policies** on the service network and on each service are evaluated together with the caller's identity-based policies. Clients sign requests with **SigV4**. Conditions such as `aws:PrincipalOrgID`, principal ARNs, `vpc-lattice-svcs:RequestPath`, and `vpc-lattice-svcs:RequestMethod` give per-path, per-role authorization. Lattice supports EKS, ECS, Lambda, and EC2 targets.

**Why the others are wrong**
- **A:** Private NAT gateways and a transit gateway can work around overlapping CIDRs, but they give **no IAM authentication**. Security groups filter by network address, not by identity or URL path, and you still manage route tables.
- **B:** PrivateLink handles overlapping CIDRs, but it needs **one interface endpoint per provider service per consumer VPC**, the endpoint sprawl the team rejected. JWT checks are custom code, not IAM authorization.
- **C:** **VPC peering is not possible when primary CIDRs overlap**, and a full mesh of peering across 12 accounts is a lot to operate.

**Concept to remember:** Service-to-service calls across accounts with **IAM authorization per path** and overlapping IPs → **VPC Lattice**. Exposing one service privately → PrivateLink. Network-level routing → transit gateway or Cloud WAN.

**References**
- [What is Amazon VPC Lattice?](https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html)
- [Control access to VPC Lattice services using auth policies](https://docs.aws.amazon.com/vpc-lattice/latest/ug/auth-policies.html)
- [Share VPC Lattice entities (AWS RAM)](https://docs.aws.amazon.com/vpc-lattice/latest/ug/sharing.html)

---

### Solution 8 — Answer: **A**

**Decisive keywords:** "both 10.0.0.0/16", "already attach to the parent company's transit gateway", "all connections start in VPC A", "can sit behind a load balancer", "build in weeks, using its existing network constructs".

**Why A is correct**
This is the AWS-documented **"enable communication between overlapping networks"** pattern. Each VPC gets a **routable** secondary CIDR. VPC A's workloads send traffic for VPC B's routable range to a **private NAT gateway** in VPC A's routable subnet, which translates the source to its routable IP. The transit gateway, with **static routes** and route propagation turned off, carries the traffic to an **ALB in VPC B's routable subnet**. The ALB forwards to targets in the overlapping range. Return traffic goes back to the NAT gateway's address. It uses the existing transit gateway, and the traffic only flows one way (A starts all connections), which matches the stem.

**Why the others are wrong**
- **B:** PrivateLink also handles overlapping CIDRs, but this option is **backwards**. The *provider* (VPC B, which hosts the services) must publish the endpoint service, and the *consumer* (VPC A) creates the interface endpoint. As written, VPC B could call VPC A, not the other way around.
- **C:** **You cannot create a VPC peering connection when the primary CIDRs overlap**, whatever routes you plan to add.
- **D:** The transit gateway cannot send traffic to a destination that is also the source VPC's own local range. VPC A's local 10.0.0.0/16 route always wins inside VPC A, so traffic never leaves for "VPC B's" 10.0.x.0/24.

**Concept to remember:** Overlapping CIDRs: **private NAT gateway plus a routable secondary CIDR and a transit gateway** (many services, network level) or **PrivateLink** (per service, consumer creates the endpoint). Never peering.

**References**
- [NAT gateway use cases: communication between overlapping networks](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-scenarios.html)
- [VPC peering limitations (overlapping CIDRs)](https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-basics.html)
- [AWS PrivateLink concepts](https://docs.aws.amazon.com/vpc/latest/privatelink/concepts.html)

---

### Solution 9 — Answer: **B, D**

**Decisive keywords:** "every account in the `Workloads` OU", "created in or moved into the OU later … automatically", "moved out … stay in place", "management account must not be used", "excluding them by account ID".

**Why B and D are correct**
- **B:** **Service-managed** StackSets target OUs and use roles created through Organizations. **Automatic deployment** creates stack instances when an account joins a target OU and removes them when it leaves. The **account removal behavior** setting can be **Retain stacks**: resources stay but are no longer managed by the StackSet. That meets the forensic requirement.
- **D:** A **delegated administrator** for StackSets, registered from the management account, can create and manage service-managed StackSets with `--call-as DELEGATED_ADMIN`. Day-to-day work then stays out of the management account.

**Why the others are wrong**
- **A:** Self-managed permissions with your own event-driven automation is exactly the custom work that service-managed auto-deployment replaces. It also needs the execution role in place before any deployment can run.
- **C:** **Automatic deployments ignore account-level targeting filters.** The StackSet will keep deploying to new accounts in the OU. Move sandboxes to a different OU instead.
- **E:** Service-managed StackSets **do not deploy stack instances to the management account**, even when you target the root. Running operations from the management account also breaks the stated requirement.

**Concept to remember:** "New accounts automatically" → **service-managed StackSets plus automatic deployment** (Retain or Delete on removal). "Not from the management account" → **delegated administrator**. Auto-deploy works at the OU level only.

**References**
- [Enable or disable automatic deployments for StackSets in AWS Organizations](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-manage-auto-deployment.html)
- [Register a delegated administrator for StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-delegated-admin.html)
- [Create StackSets with service-managed permissions](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-associate-stackset-with-org.html)

---

### Solution 10 — Answer: **B**

**Decisive keywords:** "must not have direct permissions for RDS, EC2, S3, or CloudFormation", "only approved instance classes", "one hub portfolio … shares … with all accounts", "stay the same in every account".

**Why B is correct**
- A **launch constraint** names the IAM role that **AWS Service Catalog assumes** to launch, update, and terminate the product. End users then need **only Service Catalog permissions**. Without a launch constraint, users need CloudFormation permissions and permissions for every underlying service.
- When you specify a **role name** instead of an ARN, each account that uses the constraint uses **its own local role with that name**, which keeps launch constraints account-agnostic for shared portfolios. Deploying that role everywhere with StackSets keeps it consistent. The role's trust policy must allow Service Catalog to assume it, and it needs the documented access to the template plus the resource permissions.
- **Template constraints** limit parameter values, such as allowed instance classes.

**Why the others are wrong**
- **A:** Giving developers CloudFormation and service permissions breaks the least-privilege requirement. A launch constraint exists so they don't need them.
- **C:** A role **ARN** points to one account's role. Spoke accounts provisioning a shared product need a role in **their own** account. AWS's documented approach for this case is the local role name.
- **D:** `servicecatalog:ProvisionProduct` (and Update/Terminate) **cannot be assigned in a launch role**. Letting developers assume the launch role directly would hand them the very permissions the design is meant to keep from them.

**Concept to remember:** Least-privilege self-service → **Service Catalog launch constraint** (Service Catalog assumes the role, users don't). Shared portfolios → **local role name**. Parameter guardrails → **template constraint**.

**References**
- [AWS Service Catalog launch constraints](https://docs.aws.amazon.com/servicecatalog/latest/adminguide/constraints-launch.html)
- [AWS Service Catalog template constraints](https://docs.aws.amazon.com/servicecatalog/latest/adminguide/catalogs_constraints_template-constraints.html)
- [Sharing portfolios with AWS Organizations](https://docs.aws.amazon.com/servicecatalog/latest/adminguide/catalogs_portfolios_sharing.html)

---

### Solution 11 — Answer: **B, D, F**

**Decisive keywords:** "central tooling account", "deploy actions that target separate staging and production accounts", "AWS managed key `aws/s3`", "access-denied errors when the target accounts try to read the build artifact".

**Why B, D, and F are correct**
AWS's cross-account CodePipeline walkthrough needs three things:
- **B:** A **customer managed KMS key** in the **pipeline's Region**, with usage granted to the pipeline service role and the other accounts, set as the artifact store's `encryptionKey`. Artifacts encrypted with the default AWS managed key can't be decrypted by another account.
- **D:** An **artifact bucket policy** that lets the other accounts read input artifacts and write output artifacts.
- **F:** A **cross-account role in each target account** that trusts the pipeline service role. It needs permissions for the deployment (CloudFormation plus `iam:PassRole` for the CloudFormation deployment role), the artifact bucket, and the KMS key. The action's `roleArn` points to it, and the pipeline service role is allowed `sts:AssumeRole` on it.

**Why the others are wrong**
- **A:** **Aliases are recognized only in the account that owns the key.** Cross-account actions must refer to the key by **key ID or key ARN**. An alias would resolve, if at all, to a key in the target account.
- **C:** Replicating artifacts is unnecessary and doesn't fix encryption with an AWS managed key. CodePipeline passes artifacts from its own artifact store.
- **E:** You **cannot edit the key policy of an AWS managed key**, and AWS managed keys can't be used across accounts.

**Concept to remember:** Cross-account pipeline = **customer managed key (refer to it by ARN) + bucket policy + an assumable role in each target account set as the action's `roleArn`**.

**References**
- [Create a pipeline in CodePipeline that uses resources from another AWS account](https://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-create-cross-account.html)
- [AWS KMS concepts: AWS managed keys vs customer managed keys](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html)

---

### Solution 12 — Answer: **D**

**Decisive keywords:** "at least 4 tasks must always run on capacity that cannot be interrupted", "about three quarters of those extra tasks" on spare capacity, "drain in-flight requests cleanly".

**Why D is correct**
- **Base** sets how many tasks go to one provider *first*. **Weight** sets the ratio *after* the base is filled. `FARGATE` base 4 guarantees the four uninterruptible tasks. Weights `FARGATE` 1 : `FARGATE_SPOT` 3 then put about **75%** of the extra tasks on Fargate Spot.
- A Fargate Spot interruption gives a **two-minute warning**, sent as an EventBridge task state change event and a **SIGTERM** to the task. The container `stopTimeout` can be set **up to 120 seconds** (default 30). The application should handle SIGTERM, and the ALB deregistration delay should be shorter than the stop timeout so connections drain before SIGKILL.

**Why the others are wrong**
- **A:** **Only one capacity provider in a strategy can have a base value.** This strategy is invalid.
- **B:** Putting the base on `FARGATE_SPOT` means the four SLA tasks **can be interrupted**, which breaks the availability requirement.
- **C:** The strategy is right, but the claim is false. **Fargate does not replace Spot capacity with on-demand capacity.** When Spot capacity is unavailable, ECS keeps retrying Spot. If you depend on that fallback, you can miss peak capacity.

**Concept to remember:** Capacity provider strategy: **base on the reliable provider (only one provider may have a base), weights for the split above the base**. Fargate Spot = 2-minute SIGTERM warning, and **no automatic fallback** to Fargate.

**References**
- [Amazon ECS clusters for Fargate (capacity providers, base/weight, Spot interruption)](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-capacity-providers.html)
- [Capacity provider strategies](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/capacity-launch-type-comparison.html)

---

### Solution 13 — Answer: **A**

**Decisive keywords:** "custom event bus", "fail over … automatically", "RTO and RPO of under 10 minutes", "return to us-east-1 automatically … no operator action", "must not implement their own Region-selection logic".

**Why A is correct**
- An **EventBridge global endpoint** has primary and secondary Regions and an **Amazon Route 53 health check**, usually driven by a CloudWatch alarm on the primary bus's metrics. When the health check reports unhealthy, custom events go to the **same-named bus in the secondary Region** (you must create it, with the same rules and targets).
- If you follow AWS's alarm guidance, the documented **RTO and RPO are 360 seconds, with a maximum of 420 seconds**, which is under 10 minutes.
- **Event replication** sends events to both Regions asynchronously and is **required for automatic recovery** back to the primary.
- Producers only add the **endpoint ID** to `PutEvents`. The SDK, with the AWS Common Runtime, signs requests with **SigV4a**. There is no Region-selection code.

**Why the others are wrong**
- **B:** This is the trap. **Without event replication, you must reset the Route 53 health check to healthy by hand** before events return to the primary, which breaks "no operator action".
- **C:** A cross-Region target rule depends on the **primary Region accepting events**. If us-east-1 ingestion is impaired, producers' `PutEvents` calls fail before any forwarding can happen.
- **D:** AWS API requests are signed for a specific Region (SigV4), and TLS certificates for service endpoints don't match a custom CNAME. DNS failover across Regional service endpoints is not supported.

**Concept to remember:** Regional failover for event **ingestion** → **EventBridge global endpoint**. Turn on **event replication** if failback must be automatic. Typical RTO/RPO is about 6 minutes.

**References**
- [Making applications Regional-fault tolerant with global endpoints in EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-global-endpoints.html)
- [Creating a global endpoint](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-ge-create-endpoint.html)

---

### Solution 14 — Answer: **C**

**Decisive keywords:** "disaster recovery site", "VMware VMs and physical … servers", "RPO of seconds", "RTO under 30 minutes", "low steady-state cost", "drills that do not affect production or replication", "fail back to the on-premises data center".

**Why C is correct**
- **AWS Elastic Disaster Recovery (DRS)** continuously replicates **block-level** data from physical, virtual, or cloud servers into a **staging area subnet**, using low-cost storage and minimal compute. That keeps steady-state cost low. AWS describes **RPOs of seconds and RTOs of minutes**: typical boot is about 5 minutes for Linux and about 20 minutes for Windows.
- **Drills** launch recovery instances without stopping replication, so RPO is unaffected and the source servers keep running.
- **Failback to on premises** uses the **DRS Failback Client** (an ISO you boot on the target server) or the DRS failback automation, which replicates the recovered instance back to the on-premises server.

**Why the others are wrong**
- **A:** Hourly backups mean an **RPO of about an hour**, not seconds, and restoring 150 servers from backups will usually exceed a 30-minute RTO.
- **B:** **AWS Transform MGN** (formerly AWS Application Migration Service) is built for **one-way migration**. It doesn't provide DR features such as point-in-time recovery for DR, drills, or failback to on premises. DRS is the DR service built on the same replication technology.
- **D:** A hand-built pilot light with log shipping, `rsync`, and runbooks has a high operational burden, uneven RPO across different technologies, and no managed failback.

**Concept to remember:** On-premises (or cloud) servers → AWS DR with RPO in seconds, cheap staging, drills, and failback → **AWS Elastic Disaster Recovery**. One-way move → **MGN**.

**References**
- [What is AWS Elastic Disaster Recovery?](https://docs.aws.amazon.com/drs/latest/userguide/what-is-drs.html)
- [Using Elastic Disaster Recovery for recovery and failback](https://docs.aws.amazon.com/drs/latest/userguide/failback.html)
- [Elastic Disaster Recovery concepts: RPO, RTO, and point-in-time snapshots](https://docs.aws.amazon.com/drs/latest/userguide/CloudEndure-Concepts.html)

---

### Solution 15 — Answer: **A, D**

**Decisive keywords:** "assessment of whether the current architecture can meet those targets, with specific recommendations", "controlled game day in production", "stops automatically if the customer-facing error rate passes 2%", "managed AWS services".

**Why A and D are correct**
- **A:** **AWS Resilience Hub** defines an application from sources such as CloudFormation stacks, tags, or myApplications. It checks the application against a **resiliency policy** (RTO and RPO targets for AZ, infrastructure, application, and Region disruptions), estimates whether the targets can be met, and gives **resiliency and operational recommendations**, including suggested alarms, SOPs, and FIS experiments.
- **D:** **AWS FIS** runs controlled fault injection from experiment templates, for example terminating instances in an AZ, failing over an Aurora cluster, or disrupting the network. **Stop conditions** link the experiment to **CloudWatch alarms**: when the alarm enters the ALARM state, FIS stops the experiment. That is the automatic safety net the CIO asked for.

**Why the others are wrong**
- **B:** Trusted Advisor flags single points of failure and configuration gaps. It doesn't evaluate against RTO and RPO targets or prove recovery times.
- **C:** Hand-written scripts with a person watching the dashboards have **no automatic stop**, give no auditable experiment record, and are the "custom tooling" the team wanted to avoid.
- **E:** A maximum duration is not a guardrail based on customer impact. Without a stop condition, the experiment keeps running while the error rate climbs.

**Concept to remember:** **Resilience Hub** = assess against RTO/RPO and get recommendations. **FIS** = inject faults safely, with **stop conditions on CloudWatch alarms**. Using both gives you evidence.

> **Emerging / SAP-C03 preview note:** FIS and Resilience Hub feature more heavily in SAP-C03. For SAP-C02, know what each one does and how they work together.

**References**
- [What is AWS Resilience Hub?](https://docs.aws.amazon.com/resilience-hub/latest/userguide/what-is.html)
- [What is AWS Fault Injection Service?](https://docs.aws.amazon.com/fis/latest/userguide/what-is.html)
- [Stop conditions for AWS FIS](https://docs.aws.amazon.com/fis/latest/userguide/stop-conditions.html)

---

### Solution 16 — Answer: **C, D, F**

**Decisive keywords:** "without lowering availability", "cross-zone load balancing on … most calls cross AZs", "300 TB … between two specific VPCs … through the company's transit gateway", "500 TB … served directly from S3 and an ALB".

**Why C, D, and F are correct**
- **C (CloudFront):** AWS waives data transfer from **AWS origins to CloudFront**. CloudFront's internet egress rates are typically lower than S3 or EC2 egress, with volume tiers, and caching cuts origin load. For 500 TB per month of downloads and static assets, this is the largest single saving.
- **D (peering for the high-volume pair):** A transit gateway charges **per GB processed** (for example, $0.02/GB in US East) on top of attachment-hours. VPC peering has **no data processing charge**. Traffic over peering is charged only at the standard inter-AZ rate when it crosses AZs, and AWS doesn't charge for peering traffic that stays in the same AZ. Moving 300 TB per month for one VPC pair to peering, while the transit gateway keeps serving everything else, is a common optimization. More-specific routes win over the transit gateway route.
- **F (AZ affinity):** Inter-AZ traffic costs **$0.01/GB in each direction** in most Regions. Turning off cross-zone load balancing at the **target group** level, plus AZ-aware discovery, keeps most calls inside the caller's AZ. Capacity stays in every AZ, so availability is unchanged, but you must keep each AZ's target capacity balanced.

**Why the others are wrong**
- **A:** S3 Transfer Acceleration **adds** a per-GB charge on top of data transfer. It speeds up long-distance transfers but doesn't lower egress cost.
- **B:** A single AZ removes inter-AZ charges by **giving up availability**, which the stem forbids.
- **E:** Sending traffic through an inspection VPC adds **more** transit gateway processing and possibly inter-AZ hops. EC2 networking doesn't compress or deduplicate traffic for you.

**Concept to remember:** Egress to the internet → **CloudFront**. Heavy traffic between one pair of VPCs → **peering** (no per-GB processing). Chatty services → **AZ affinity**. Transfer Acceleration costs more.

**References**
- [Amazon CloudFront pricing (no charge for transfer from AWS origins)](https://aws.amazon.com/cloudfront/pricing/)
- [AWS Transit Gateway pricing](https://aws.amazon.com/transit-gateway/pricing/)
- [Amazon EC2 On-Demand pricing: data transfer (inter-AZ, VPC peering)](https://aws.amazon.com/ec2/pricing/on-demand/)
- [Overview of data transfer costs for common architectures (AWS Architecture Blog)](https://aws.amazon.com/blogs/architecture/overview-of-data-transfer-costs-for-common-architectures/)
- [Cross-zone load balancing for target groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html)

---

### Solution 17 — Answer: **B**

**Decisive keywords:** "one member account", "apply **only** to the subsidiary's account", "**not receive** any discount from the parent's", "keep the subsidiary in the organization", "monthly chargeback … amortized commitment costs".

**Why B is correct**
- The **management account** controls RI and Savings Plans discount sharing in **Billing preferences**, and can deactivate it for individual member accounts. With sharing deactivated, the subsidiary's own Savings Plan still applies to its own usage first, but the discount is **not shared out**, and the account **receives no discounts** from other accounts' commitments. The final monthly bill uses the preference set at **23:59:59 UTC on the last day of the month**.
- For chargeback, **AWS Cost Categories** (business-unit rules) and **cost allocation tags**, analyzed with **amortized costs** in Cost Explorer or in CUR 2.0 through Data Exports, spread upfront and recurring commitment fees across the accounts that used them.

**Why the others are wrong**
- **A:** SCPs control API actions. They have **no effect on how billing discounts are shared**. Blocking purchases also wouldn't stop an existing commitment from being shared.
- **C:** **Only the management account** can change discount sharing preferences. A member account can't opt itself out.
- **D:** Leaving the organization meets the arm's-length goal but breaks the explicit requirement to keep the subsidiary in the organization. It also drops it out of the consolidated bill.

> **Note on newer options:** AWS now also supports **group-based sharing** (Prioritized or Restricted) that uses Cost Categories. If the subsidiary had several accounts, a **Restricted** sharing group would keep its commitments within its own accounts. For a single account, deactivating sharing is the simplest fit.

**Concept to remember:** RI/SP sharing is a **management-account billing preference**. An account with sharing deactivated neither gives nor receives. Chargeback = **Cost Categories + tags + amortized cost**.

**References**
- [Reserved Instances and Savings Plans discount sharing](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/ri-turn-off.html)
- [Organizing costs using AWS Cost Categories](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/manage-cost-categories.html)
- [AWS Data Exports (CUR 2.0)](https://docs.aws.amazon.com/cur/latest/userguide/what-is-data-exports.html)

---

### Solution 18 — Answer: **A**

**Decisive keywords:** (1) "stay on the hospital's premises", "EBS volumes and a managed relational database"; (2) "large metropolitan area", "data may be stored in AWS"; (3) "5G mobile devices on a telecom carrier's 5G network".

**Why A is correct**
- **(1) Outposts rack:** AWS infrastructure installed in **your facility**, which meets on-premises data residency and gives single-digit millisecond latency to local devices. **Racks** support EBS-backed EC2 and **Amazon RDS on Outposts**.
- **(2) Local Zone:** An extension of a parent Region placed in a large metro area. It offers EC2 (including GPU instance families in some Local Zones), EBS, and other services with single-digit millisecond latency to users in that city. Data lives in AWS infrastructure, which the stem allows.
- **(3) Wavelength Zone:** AWS compute and storage **embedded in a telecom carrier's 5G network**. Traffic from 5G devices reaches the application without leaving the carrier network, which gives the lowest latency for mobile devices.

**Why the others are wrong**
- **B:** **Outposts servers** (the 1U/2U form factor) support services such as EC2, ECS, and IoT Greengrass. They support **neither Amazon RDS on Outposts nor EBS**, which need **Outposts racks**.
- **C:** A Local Zone is **AWS-operated infrastructure outside the hospital**, which breaks the on-premises residency rule. Workloads (2) and (3) are swapped as well.
- **D:** Workloads (2) and (3) are swapped. Wavelength serves devices on a carrier's 5G network, not general metro users. A Local Zone isn't inside the carrier network.

**Concept to remember:** Data must stay **on premises** → **Outposts** (racks for EBS and RDS). **Metro** latency → **Local Zones**. **5G mobile** latency → **Wavelength**.

**References**
- [What is AWS Outposts? (racks vs servers, supported services)](https://docs.aws.amazon.com/outposts/latest/userguide/what-is-outposts.html)
- [Amazon RDS on AWS Outposts](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-on-outposts.html)
- [What is AWS Local Zones?](https://docs.aws.amazon.com/local-zones/latest/ug/what-is-aws-local-zones.html)
- [What is AWS Wavelength?](https://docs.aws.amazon.com/wavelength/latest/developerguide/what-is-wavelength.html)

---

### Solution 19 — Answer: **C, E**

**Decisive keywords:** "Regional REST API", partner 429s are contractual ("will not change"), `504` "after about 29 seconds", "client contract requires a synchronous response", execution log `Lambda invocation failed with status: 429`, batch function "consumes most of the account's concurrency".

**How to read the status codes**

| Symptom | Where it comes from | Typical fix |
|---|---|---|
| **429** returned by API Gateway (`THROTTLED` / `QUOTA_EXCEEDED` gateway responses) | API Gateway's own throttling: usage plan, method, stage, or account level | Raise the limit, or leave it if it is intended (as here) |
| **504** after ~29 s (`INTEGRATION_TIMEOUT`) | API Gateway gave up waiting for the backend | Make the work async, or raise the integration timeout (Regional and private REST APIs) |
| **5xx** with `Lambda invocation failed with status: 429` in execution logs | **Lambda** throttled the invoke (TooManyRequestsException), and API Gateway returns a server error to the client | Reserved or provisioned concurrency, raise the account concurrency quota, fix noisy neighbors |
| **502** "Malformed Lambda proxy response" | The function returned output that doesn't match the proxy response format, or the function errored | Fix the response shape or the error handling |

**Why C and E are correct**
- **C:** REST API integration timeouts default to a **maximum of 29 seconds**. For **Regional and private** APIs, you can request a higher integration timeout through Service Quotas. AWS notes this **may require a reduction in your Region-level throttle quota**. This keeps the synchronous contract with the least redesign.
- **E:** Lambda concurrency is a **pool shared by every function in the account and Region**. Reserved concurrency on the batch function **caps** it. Reserved concurrency on `/orders` **guarantees** it capacity. Together they stop the noisy neighbor that causes the throttles.

**Why the others are wrong**
- **A:** The Lambda timeout isn't the limit. **API Gateway stops waiting at its integration timeout**, so the client still gets a 504.
- **B:** The partner's 429s are the **intended** result of its contractual usage plan. "Fixing" them breaks the contract.
- **D:** The `/orders` errors come from **Lambda throttling**, not API Gateway throttling. Letting more requests through API Gateway would only cause more Lambda throttles.

**Concept to remember:** A **429 from API Gateway** means API Gateway throttling. **Lambda 429 in the logs** means a concurrency problem → reserved concurrency. **504 at 29 s** means the integration timeout → go async or raise the quota (Regional/private only).

**References**
- [Quotas for configuring and running a REST API (integration timeout)](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-execution-service-limits-table.html)
- [Throttle requests to your REST APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-request-throttling.html)
- [Gateway response types for API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/supported-gateway-response-types.html)
- [Configuring reserved concurrency for a Lambda function](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html)

---

### Solution 20 — Answer: **C, F**

**Decisive keywords:** "session state in memory", "logged out whenever scale-in terminates an instance", "sticky users pile up", "minimal code change", "read and written on every request", "**sub-millisecond**", "expire after 30 minutes".

**Why C and F are correct**
- **C:** Moving sessions to **ElastiCache (Valkey or Redis OSS)** makes the web tier stateless, so any instance can serve any request and scale-in loses nothing. In-memory key-value access is **sub-millisecond**, a **TTL** handles the 30-minute expiry, and **Multi-AZ with automatic failover** protects the session store. Framework integrations such as Spring Session or Tomcat session managers mean very little code changes.
- **F:** Once sessions are external, **stickiness is no longer needed**. Turning it off removes the hot spots. The **least outstanding requests** algorithm spreads load evenly when request times vary.

**Why the others are wrong**
- **A:** Longer stickiness makes the hot spots **worse**. Connection draining only lets in-flight requests finish. It doesn't save in-memory sessions on a terminated instance.
- **B:** EFS is shared storage, but file-based session persistence adds **millisecond-range latency** on every read and write, plus file-locking overhead. It doesn't meet the sub-millisecond requirement.
- **D:** Any form of stickiness, duration-based or application-based, only routes users back to the same instance. **When that instance is terminated, its memory is gone.**
- **E:** DynamoDB with TTL is a valid session store, and it is a good choice when single-digit millisecond latency is acceptable. It does not give the **sub-millisecond** access the stem asks for.

**Concept to remember:** Stateful web tier → **externalize sessions** (ElastiCache for sub-ms, DynamoDB for single-digit ms and serverless), then **drop stickiness**. Stickiness is a workaround, not a fix for scaling.

**References**
- [Session management (AWS caching best practices)](https://aws.amazon.com/caching/session-management/)
- [Sticky sessions for your Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-target-group-attributes.html#sticky-sessions)
- [Target groups for ALBs (routing algorithms, least outstanding requests)](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html)
- [What is Amazon ElastiCache?](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/WhatIs.html)

---

## Score interpretation

| Score | What it means | What to do |
|---|---|---|
| **≥ 16/20** | **Ready.** You are handling the hardest distractors at exam level. | Review the cheat sheets, sleep, and keep your timing discipline. |
| **13–15/20** | **Close.** One or two domains are leaking points. | Use the domain map below, re-read only the sections you missed, then redo those questions in 2 days. |
| **< 13/20** | **Not yet.** The gaps are conceptual, not just a few details. | Re-study the linked chapters below, then retake Papers 1–5 before exam day. |

**Where to go for each miss**

| Questions | Theme | Re-study |
|---|---|---|
| Q5, Q9, Q10, Q17 | Organizations, SCPs/RCPs, StackSets, Service Catalog, billing | [02 — Multi-Account Governance](../02-Multi-Account-Governance/02-Multi-Account-Governance.md) · [03 — Identity and Access Management](../03-Identity-and-Access-Management/03-Identity-and-Access-Management.md) |
| Q6, Q7, Q8, Q16 | Cloud WAN, transit gateway, private NAT gateway, PrivateLink, VPC Lattice, data transfer | [04 — Networking, VPC and Hybrid Connectivity](../04-Networking-VPC-and-Hybrid-Connectivity/04-Networking-VPC-and-Hybrid-Connectivity.md) |
| Q1, Q3, Q16 | Route 53 routing and health checks, CloudFront | [05 — Edge, DNS and Content Delivery](../05-Edge-DNS-and-Content-Delivery/05-Edge-DNS-and-Content-Delivery.md) |
| Q4, Q5 | KMS, S3 encryption, data perimeter | [06 — Security, Data Protection and Threat Detection](../06-Security-Data-Protection-and-Threat-Detection/06-Security-Data-Protection-and-Threat-Detection.md) |
| Q12, Q19, Q20 | ECS capacity providers, Lambda concurrency, API Gateway, stateless tiers | [07 — Compute, Containers and Serverless](../07-Compute-Containers-and-Serverless/07-Compute-Containers-and-Serverless.md) |
| Q3, Q4 | S3 replication, Multi-Region Access Points | [08 — Storage and Data Transfer](../08-Storage-and-Data-Transfer/08-Storage-and-Data-Transfer.md) |
| Q1, Q2, Q20 | DynamoDB global tables, Aurora Global Database, ElastiCache | [09 — Databases and Caching](../09-Databases-and-Caching/09-Databases-and-Caching.md) |
| Q13 | EventBridge global endpoints | [10 — Application Integration and Event-Driven](../10-Application-Integration-and-Event-Driven/10-Application-Integration-and-Event-Driven.md) |
| Q1, Q2, Q3, Q13, Q14, Q15 | Multi-Region DR, DRS, FIS, Resilience Hub | [12 — Resilience, HA and Disaster Recovery](../12-Resilience-HA-and-Disaster-Recovery/12-Resilience-HA-and-Disaster-Recovery.md) |
| Q7, Q14, Q18, Q20 | Migration targets, hybrid edge, modernization | [13 — Migration and Modernization](../13-Migration-and-Modernization/13-Migration-and-Modernization.md) |
| Q9, Q10, Q11 | StackSets, Service Catalog, cross-account CI/CD | [14 — Deployment, DevOps and IaC](../14-Deployment-DevOps-and-IaC/14-Deployment-DevOps-and-IaC.md) |
| Q12, Q16, Q17 | Spot, data transfer cost, commitment sharing, chargeback | [16 — Cost Optimization and FinOps](../16-Cost-Optimization-and-FinOps/16-Cost-Optimization-and-FinOps.md) |

> **Pattern check.** If most of your misses were **multi-select** questions where you got one option right and one wrong, your knowledge is there but your elimination isn't. For each option, find the **one detail** that makes it wrong: a quota (29 s, 120 s), a default (MREC, `isolate-attachments: false`), or a scope rule (SCPs and RCPs skip the management account, an alias works only in its own account).

[← Practice Papers index](README.md) · [Study Guide start page](../00-README-Start-Here.md)

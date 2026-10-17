# Practice Paper 1 — Governance, Networking & Hybrid
> Original SAP-C02-style questions (not real exam questions). 20 questions · suggested time 48 min (≈2.4 min/question, exam pace).
> Domain mix: D1 ×5, D2 ×6, D3 ×5, D4 ×4
> [← Practice Papers index](README.md) · [Study Guide start](../00-README-Start-Here.md)

**How to use this paper:** Set a 48-minute timer and answer all 20 questions without notes. Write your answers down, then check them against the [Answer key](#section-2--answer-key) and read every [detailed solution](#section-3--detailed-solutions), including the ones you got right. Exam-style reasoning comes from understanding why each wrong option is wrong. Multi-select questions score only if you choose exactly the right set.

> **Naming note:** Exam questions may use old or new service names. AWS Application Migration Service (MGN) was renamed **AWS Transform MGN** in 2026. AWS SSO is now **IAM Identity Center**. Both names appear below.

---

## Section 1 — Questions

### Q1
A European insurer runs 140 accounts in AWS Organizations with all features enabled. A new data-residency rule says no workload resources may be created outside **eu-west-1** and **eu-central-1**. The platform team still needs IAM, AWS Organizations, Amazon Route 53, Amazon CloudFront, and AWS Support to work, because those services' control-plane endpoints are not in the approved Regions. The security operations team owns a role named `SecOps-BreakGlass` in every account. During an incident, that role must be able to investigate and clean up resources in **any** Region, including resources created before the control existed. The control must be preventive and centrally managed, and it must be easy to extend when a third Region is approved.

Which combination of actions meets these requirements? **(Select TWO.)**

- **A.** Attach an SCP at the root that denies all actions using `NotAction` to exempt the global services, with a `StringNotEquals` condition on `aws:RequestedRegion` listing `eu-west-1` and `eu-central-1`.
- **B.** Attach an SCP at the root that denies `"Action": "*"` with a `StringNotEquals` condition on `aws:RequestedRegion`, because requests to global services are not evaluated against a Region condition.
- **C.** Move the accounts that contain `SecOps-BreakGlass` into a dedicated Security OU that does not inherit the Region-deny SCP, so the role keeps unrestricted Regional access.
- **D.** Add an `ArnNotLike` condition on `aws:PrincipalARN` for `arn:aws:iam::*:role/SecOps-BreakGlass` to the deny statement, so that only this role is excluded from the Region restriction.
- **E.** Also attach the SCP directly to the management account, because SCPs attached at the root do not reach the management account unless they are attached to it explicitly.

### Q2
A retail group has just finished setting up an AWS Control Tower landing zone in its existing organization. It has acquired a company with 38 standalone AWS accounts (not in any organization). Six of those accounts run production workloads that cannot be rebuilt this year, and several have an AWS Config configuration recorder left behind by the acquired company's old security tooling. Product teams will also request about 10 new accounts a month. Each new account must get the standard controls, IAM Identity Center access, a company-specific VPC layout, and a CloudFormation-based security-tooling baseline when it is created. The CTO wants every account governed by Control Tower with the least ongoing operational overhead.

What should the solutions architect do?

- **A.** Close the acquired accounts and re-create their workloads in new accounts vended by Account Factory, so that every account starts with the Control Tower baseline.
- **B.** Invite the accounts into the organization, use CloudFormation StackSets from the management account to deploy AWS Config rules and CloudTrail trails, and vend new accounts with the Organizations `CreateAccount` API.
- **C.** Invite the accounts into the organization, create the `AWSControlTowerExecution` role in each, resolve the existing AWS Config recorders as documented, and enroll the accounts into registered OUs. Vend new accounts with Account Factory using Account Factory Customization (or AFT).
- **D.** Deploy a second Control Tower landing zone in a new management account for the acquired company, and link the two landing zones by configuring IAM Identity Center trust between them.

### Q3
A SaaS company has 64 workload accounts, each with its own VPC across three Availability Zones. Every VPC has three NAT gateways, nine interface VPC endpoints, and a transit gateway attachment. A cost review shows that NAT gateway hours, interface endpoint hours, and transit gateway data processing for chatty service-to-service traffic are the top network costs. The IPAM team is also struggling with CIDR sprawl. Within each business unit, the workloads trust each other and talk constantly. App teams deploy only EC2, ECS on Fargate, RDS, and Lambda, and they must keep separate accounts for billing and IAM isolation. The network team wants exclusive control of subnets, route tables, and network ACLs.

Which redesign best reduces cost and operational overhead?

- **A.** Create one shared VPC per business unit and environment in a network account, share its subnets with the workload accounts through AWS RAM, and centralize NAT gateways and interface endpoints in those VPCs. The network account keeps ownership of routing and NACLs.
- **B.** Replace the transit gateway with a full mesh of VPC peering connections, remove NAT gateways from every VPC except one egress VPC, and send internet-bound traffic from the other VPCs over peering to that VPC's NAT gateways.
- **C.** Share each business unit's VPC subnets through AWS RAM, and let each participant account create its own NAT gateways, route tables, and NACLs in the shared subnets so that teams keep control of their egress.
- **D.** Keep the per-account VPCs, move the NAT gateways and interface endpoints into a central shared-services VPC reached through the transit gateway, and use Route 53 private hosted zones for endpoint DNS.

### Q4
A healthcare company is designing a new multi-account network in one Region. About 80 spoke VPCs will connect to a transit gateway. Compliance requires all internet-bound traffic from the spokes to be inspected by the company's standard **third-party** next-generation firewall, which is stateful and licensed per vCPU. The firewalls run in a central inspection VPC across three Availability Zones. The firewall fleet must scale horizontally, survive an appliance or AZ failure, and inspect both directions of every flow on the same appliance.

Which TWO design elements are required? **(Select TWO.)**

- **A.** Register the firewall instances as targets of a Network Load Balancer in the inspection VPC, and point the default routes of the transit gateway attachment subnets at the NLB.
- **B.** Put the firewall instances in a target group behind a Gateway Load Balancer, and route traffic from the transit gateway attachment subnets to Gateway Load Balancer endpoints in each AZ, then on to NAT gateways.
- **C.** Create a transit gateway network function attachment and import the third-party firewall policies into it, so that AWS manages the inspection VPC and its endpoints.
- **D.** Enable equal-cost multi-path (ECMP) routing on the spoke VPC attachments so that the transit gateway spreads flows across the firewall appliances in all three AZs.
- **E.** Enable appliance mode on the inspection VPC's transit gateway attachment so that the transit gateway keeps the forward and return traffic of each flow in the same AZ.
- **F.** Deploy an internet gateway and a NAT gateway in each spoke VPC, and use VPC ingress routing to send return traffic back through the inspection VPC.

### Q5
A manufacturer has two 10 Gbps dedicated AWS Direct Connect connections at two different Direct Connect locations. It needs private connectivity from its data center to about 150 VPCs owned by 30 accounts in **us-east-1, us-west-2, and eu-west-1**. A network account owns one transit gateway in each Region and shares them through AWS RAM, and every VPC is attached to its Regional transit gateway. The data center advertises about 40 prefixes. The network team wants the fewest virtual interfaces and BGP sessions, resiliency across both connections, and control over which AWS prefixes are advertised on premises.

What should the solutions architect do?

- **A.** Create a private VIF from each connection to a virtual private gateway in each of the 150 VPCs, and use BGP communities to control which VPC prefixes are advertised on premises.
- **B.** Create one private VIF on each connection to a single Direct Connect gateway, and associate that gateway with the virtual private gateways of all 150 VPCs across the three Regions.
- **C.** Create three transit VIFs on each connection, one per Region, each attached to its own Regional Direct Connect gateway that is associated with that Region's transit gateway.
- **D.** Create one transit VIF on each connection to a single Direct Connect gateway, associate the gateway with the three Regional transit gateways, and set summarized allowed prefixes on each association.

### Q6
A logistics company connects its data center to AWS through one 1 Gbps Direct Connect connection. A transit VIF goes to a Direct Connect gateway that is associated with a transit gateway in us-east-1. Last quarter a connection outage stopped warehouse operations for six hours. Leadership has approved a low-cost backup: an AWS Site-to-Site VPN over the internet that must take over **automatically** if Direct Connect fails. While Direct Connect is healthy, traffic in **both directions** must use it. The on-premises router advertises the same 10.0.0.0/8 summary over every path.

Which solution meets these requirements?

- **A.** Attach a Site-to-Site VPN to the transit gateway with static routing, add a static route for 10.0.0.0/8 to the VPN attachment, and rely on BGP keepalives on the Direct Connect side to withdraw the static route during a failure.
- **B.** Attach a Site-to-Site VPN to the transit gateway with dynamic (BGP) routing and propagation. The transit gateway prefers Direct Connect gateway routes for identical prefixes, and the on-premises router gives a higher local preference to routes learned over Direct Connect.
- **C.** Attach a Site-to-Site VPN to the transit gateway with dynamic routing, and advertise more-specific /9 prefixes over the VPN tunnels so that the transit gateway installs the VPN routes only as a backup.
- **D.** Attach a Site-to-Site VPN to the transit gateway with dynamic routing, and prepend the on-premises ASN several times on routes advertised over Direct Connect so that the transit gateway treats the VPN path as the backup.

### Q7
A fintech SaaS provider runs a fraud-scoring API (TCP 443) on an Auto Scaling group in its own VPC (10.0.0.0/16) in us-east-1. Its 400 enterprise customers want to call the API from their own VPCs in the same Region without crossing the internet. Many customers also use 10.0.0.0/16. Their security teams refuse any connectivity that would let the provider open connections into their networks or see their routing. The provider must approve each customer account individually and wants a design that scales to thousands of customers with minimal network operations.

What should the solutions architect recommend?

- **A.** Put a Network Load Balancer in front of the API, create a VPC endpoint service with acceptance required and the customers' account principals allowed, and have each customer create an interface VPC endpoint in its own VPC.
- **B.** Create a VPC peering connection with each customer VPC, add NAT gateways on both sides to translate the overlapping 10.0.0.0/16 ranges, and restrict access with security groups that reference the peer.
- **C.** Share a transit gateway with each customer account through AWS RAM, place each customer attachment in its own transit gateway route table, and use blackhole routes to stop customer-to-customer traffic.
- **D.** Put an Application Load Balancer in front of the API, create a VPC endpoint service directly on the ALB with acceptance required, and have each customer create an interface VPC endpoint in its own VPC.

### Q8
An enterprise has 50 accounts with VPCs in eu-west-1. All of them are attached to a transit gateway that also connects to the data center over Direct Connect. On-premises Active Directory DNS servers are authoritative for `corp.example.com`. Route 53 private hosted zones for `aws.example.com` live in a shared-services account. The requirements are:
- on-premises clients must resolve `aws.example.com`
- workloads in every VPC must resolve `corp.example.com`
- new accounts must pick up the configuration with minimal per-account work
- no self-managed DNS servers

Which TWO actions should the solutions architect take? **(Select TWO.)**

- **A.** Deploy a pair of BIND forwarders on EC2 in every VPC, and set each VPC's DHCP options set to send all queries to them.
- **B.** Create a Route 53 Resolver outbound endpoint and forwarding rule in every workload VPC in all 50 accounts, pointing `corp.example.com` at the on-premises DNS servers.
- **C.** Create a Resolver inbound endpoint with IP addresses in two AZs in a central shared-services VPC that is associated with the private hosted zones, and configure on-premises conditional forwarders for `aws.example.com` to those IP addresses.
- **D.** Configure on-premises conditional forwarders for `aws.example.com` that point at the VPC+2 Amazon-provided DNS address of the shared-services VPC over Direct Connect.
- **E.** Create a Resolver outbound endpoint in the central VPC and a forwarding rule for `corp.example.com` that targets the on-premises DNS servers, then share the rule with the organization through AWS RAM and associate it with each VPC.
- **F.** Create a Route 53 public hosted zone for `corp.example.com`, and copy records from Active Directory into it with a scheduled Lambda function.

### Q9
A media company has 200 AWS accounts and uses Microsoft Entra ID as its workforce identity provider. Today each account has its own IAM SAML identity provider and hand-maintained roles. Auditors found that leavers kept access for weeks because nobody cleaned up their roles and users. The company wants:
- single sign-on to the console and CLI with short-term credentials
- users and groups created and removed automatically when HR changes them in Entra ID
- consistent, centrally managed role definitions, for example PowerUser in development accounts and ReadOnly in production

Which solution meets these requirements with the least operational overhead?

- **A.** Keep the per-account IAM SAML providers, generate the roles with CloudFormation StackSets, map Entra ID groups to role ARNs in SAML assertions, and run a nightly script that deletes roles for users who left.
- **B.** Enable IAM Identity Center with AWS Managed Microsoft AD as the identity source, sync Entra ID users into it with a third-party connector, and assign directory groups to accounts with permission sets.
- **C.** Enable IAM Identity Center with Entra ID as an external SAML 2.0 identity provider, create matching users and groups manually in Identity Center, and assign permission sets to groups in each account.
- **D.** Enable IAM Identity Center with Entra ID as an external SAML 2.0 identity provider, turn on SCIM automatic provisioning, and assign the synced Entra ID groups to accounts with PowerUser and ReadOnly permission sets.

### Q10
A company's central cloud team creates every IAM role for application teams, and this has become a two-day bottleneck. The CISO agrees to let developers create IAM roles and policies for their own Lambda functions and ECS tasks, but only if all of these hold:
1. No role they create can ever get more than access to DynamoDB, Amazon S3 under the team's prefix, and CloudWatch Logs.
2. Developers cannot remove or change that ceiling.
3. Developers cannot create IAM users or give themselves more access.

Which approach meets these requirements?

- **A.** Grant developers `iam:*` in their account, and attach an SCP that denies `iam:CreateUser` and `iam:CreateAccessKey` so that only roles can be created.
- **B.** Create a managed policy that allows only the approved services, attach it as a permissions boundary to the developers' own role, and grant the developers `iam:CreateRole`, `iam:AttachRolePolicy`, and `iam:PassRole`.
- **C.** Create a boundary policy. Let developers create roles and attach policies only when the `iam:PermissionsBoundary` condition equals that policy's ARN, deny changes to the boundary policy and to role boundaries, and limit `iam:PassRole` to the team's role path.
- **D.** Allow developers full IAM role management, and use IAM Access Analyzer and an AWS Config custom rule to find roles with permissions beyond the approved services and delete them automatically.

### Q11
A bank's audit found that CloudTrail is turned off in some of its 90 accounts, and that logs sit in per-account buckets that account administrators can delete. The new requirements are:
1. Record management events in all Regions for every current and future account.
2. Member-account administrators must not be able to stop or change logging.
3. Logs must be immutable for 7 years, so that no user can delete them, including the root user of the logging account.
4. Only the security audit team can read the logs.
5. The bank must be able to prove that log files were not changed after delivery.

Which combination of actions meets these requirements? **(Select THREE.)**

- **A.** Create a multi-Region organization trail from the management account (or a CloudTrail delegated administrator account) that delivers to an S3 bucket in a dedicated log archive account.
- **B.** Use CloudFormation StackSets with automatic deployment to create a trail in each account that writes to a bucket in the same account, and add an SCP that denies `cloudtrail:StopLogging`.
- **C.** Turn on S3 Object Lock for the log archive bucket in compliance mode with a 7-year default retention period, with versioning enabled.
- **D.** Turn on S3 Object Lock for the log archive bucket in governance mode with a 7-year default retention period, and deny `s3:BypassGovernanceRetention` to everyone except the root user.
- **E.** Apply an S3 Glacier Vault Lock policy to the log archive bucket that denies `s3:DeleteObject` for 7 years, and transition logs to S3 Glacier Deep Archive after 90 days.
- **F.** Turn on log file integrity validation, encrypt the logs with a KMS customer managed key whose key policy lets only the security audit role decrypt, and restrict reads in the bucket policy to that role.

### Q12
A conglomerate with 300 accounts must start monthly chargeback to cost centers. Many accounts host workloads for several cost centers. A shared networking account's costs must be split across cost centers in proportion to their spend. Finance found tag values such as `cc-1234`, `CC1234`, and `Cc-1234` for the same cost center. The company must standardize the `CostCenter` tag key and values across the organization and block noncompliant values on key resource types. It must also produce chargeback reports that allocate shared costs, with the least custom code.

Which combination of actions should the solutions architect take? **(Select THREE.)**

- **A.** Deploy the AWS Config `required-tags` managed rule to every account through a conformance pack, and use its compliance results as the monthly chargeback report.
- **B.** Create an Organizations tag policy that defines the capitalization and allowed values of the `CostCenter` key, with enforcement for key resource types, and pair it with an SCP that requires the tag when resources are created.
- **C.** Activate `CostCenter` as a cost allocation tag in each member account's Billing console, because activation in the management account covers only the management account's own resources.
- **D.** Activate `CostCenter` as a user-defined cost allocation tag in the management account, and request a backfill so that recent months also reflect the tag.
- **E.** Define AWS Cost Categories that map accounts and `CostCenter` values to cost centers, with split charge rules that allocate the shared networking account's costs proportionally.
- **F.** Create an AWS Budgets budget filtered by `CostCenter` in every account, and email each cost center's budget report to Finance as its chargeback statement.

### Q13
A pharmaceutical company is launching a regulated platform across 25 accounts. It uses Amazon EC2 with EBS, Amazon RDS for PostgreSQL, Amazon DynamoDB, and Amazon EFS. The requirements are:
- daily backups kept for 35 days
- a copy of every backup in a dedicated backup account in a second Region
- backups that survive a full compromise of a workload account, including a malicious administrator trying to delete recovery points
- backup configuration enforced centrally and applied automatically to new accounts and to resources tagged `backup=daily`

Which solution meets these requirements with the least operational overhead?

- **A.** Enable AWS Backup cross-account management and backup policies in Organizations. Attach a policy to the workload OUs with a tag-based daily rule and a copy action to a vault in the backup account's second Region, protected by AWS Backup Vault Lock in compliance mode.
- **B.** Use Amazon Data Lifecycle Manager for EBS snapshots, RDS automated backups with cross-Region replication, and DynamoDB point-in-time recovery, and share the resulting snapshots with the backup account through Lambda functions.
- **C.** Create an AWS Backup plan in each workload account through CloudFormation StackSets, with a daily rule and a cross-Region copy to a vault in the same account's second Region whose access policy denies deletion.
- **D.** Use AWS Elastic Disaster Recovery to replicate the EC2 instances to the backup account's second Region, and use DynamoDB global tables and RDS cross-Region read replicas for the databases.

### Q14
An online travel agency runs a booking application in us-east-1: an Application Load Balancer, an EC2 Auto Scaling group of 24 instances, and an Aurora PostgreSQL cluster. The business needs a DR capability in us-west-2 with an **RPO of 1 minute** and an **RTO of 45 minutes** for a full Regional outage. The CFO wants the **lowest standing cost** in us-west-2 that still meets these targets. The team manages all infrastructure with CloudFormation.

Which DR design should the solutions architect recommend?

- **A.** Use AWS Backup to take hourly Aurora snapshots and AMIs with cross-Region copy to us-west-2, and restore the stack in us-west-2 with CloudFormation when a disaster is declared.
- **B.** Run a scaled-down but fully working copy of the stack in us-west-2: 8 instances serving traffic behind an ALB, an Aurora Global Database secondary with two readers, and Route 53 weighted records.
- **C.** Run the application active-active in both Regions, with Aurora Global Database write forwarding, a full-size Auto Scaling group in each Region, and Route 53 latency-based routing.
- **D.** Add a us-west-2 secondary to an Aurora Global Database with no or minimal DB instances, copy the AMIs, pre-create the ALB and a zero-capacity Auto Scaling group, and use Route 53 failover records. In a disaster, fail over the global database and scale out.

### Q15
After rehosting an order platform to AWS, a retailer is modernizing it. The nightly import job was rewritten as an AWS Lambda function that reads from an Amazon SQS standard queue and writes to the existing Amazon RDS for MySQL instance, which also serves the customer-facing web tier. On the first peak night, 2 million messages arrived and Lambda scaled to about 1,000 concurrent executions. The database ran out of connections, the website returned errors, and other Lambda functions in the account were throttled. The import is allowed to take up to 4 hours.

Which change best protects the database and the other functions with minimal code changes?

- **A.** Request an increase of the account's Lambda concurrency quota to 5,000, and move the RDS instance to a larger class so that its `max_connections` value exceeds the Lambda peak.
- **B.** Set reserved concurrency of 50 on the import function, set the SQS event source mapping's maximum concurrency to 50, and route the function's database connections through Amazon RDS Proxy.
- **C.** Configure provisioned concurrency of 50 on the import function so that Lambda keeps 50 execution environments warm and stops scaling beyond them, and enable RDS Proxy.
- **D.** Reduce the SQS event source mapping batch size from 10 to 1 and increase the queue's visibility timeout, so that each invocation opens fewer database connections at a time.

### Q16
A company spends a steady $60 per hour on On-Demand EC2 across m5, c5, and r5 instances in us-east-1 and eu-west-1, plus a growing amount on AWS Fargate and AWS Lambda. Over the next 3 years it plans to move most EC2 workloads to Graviton-based families, containerize several services onto Fargate, and possibly move some workloads from eu-west-1 to eu-central-1. Finance will commit to a 3-year term to cut costs but does not want the commitment to become stranded as the architecture changes.

Which purchasing approach should the solutions architect recommend?

- **A.** Buy 3-year Standard Reserved Instances for every instance running today, and sell the unused reservations on the Reserved Instance Marketplace as workloads move to Graviton and Fargate.
- **B.** Buy 3-year EC2 Instance Savings Plans for the m5, c5, and r5 families in both Regions, sized to the current hourly spend, to get the deepest discount available.
- **C.** Buy a 3-year Compute Savings Plan with an hourly commitment sized to the steady baseline that Cost Explorer recommends, and leave variable usage on On-Demand or Spot.
- **D.** Buy 3-year Convertible Reserved Instances for the current EC2 fleet, and exchange them for Graviton instance types and Fargate capacity as each migration finishes.

### Q17
A genomics company is building a new data lake that will take in about 2 PB in the first year, with an average object size of 6 MB. Access patterns are unknown. Some datasets are hot for a few weeks and then go cold, and others are re-read without warning months later by machine learning teams. Every object must stay readable in milliseconds with no restore step. The company wants to avoid per-GB retrieval charges and the work of analyzing and maintaining lifecycle rules.

Which storage approach is most cost-effective?

- **A.** Store objects in S3 Standard with a lifecycle rule that moves them to S3 Standard-IA after 30 days and to S3 Glacier Flexible Retrieval after 90 days.
- **B.** Store objects in S3 One Zone-IA from upload, and use S3 Storage Lens to find datasets that should move back to S3 Standard when they become hot.
- **C.** Store objects in S3 Intelligent-Tiering, and turn on the optional Archive Access and Deep Archive Access tiers to get the lowest storage price for cold data.
- **D.** Store objects in S3 Intelligent-Tiering from upload, using only its automatic Frequent, Infrequent, and Archive Instant Access tiers, without turning on the optional archive tiers.

### Q18
A company must leave its colocation data center in 3 months, when the lease ends. It runs 300 VMware vSphere VMs (Windows Server and RHEL) that support 40 applications. The goal is a lift-and-shift onto native Amazon EC2 so that VMware licensing can be retired, and application changes are out of scope. Each application's cutover window is at most 1 hour, the migration team is six people, and every server must be test-launched before cutover.

Which approach meets these requirements?

- **A.** Use AWS Transform MGN (formerly AWS Application Migration Service) to replicate the VMs continuously at block level to a staging area, run non-disruptive test launches, and cut over application groups in planned waves.
- **B.** Export each VM as an OVA image, upload the images to Amazon S3, use VM Import/Export to create AMIs, and launch the instances during each application's cutover window.
- **C.** Use AWS Server Migration Service to create incremental AMI replication jobs from vCenter, and launch the latest AMIs during each application's cutover window.
- **D.** Rebuild each server from CloudFormation templates and configuration scripts, and use AWS DataSync to sync application data to the new instances before each cutover window.

### Q19
An airline is moving its 12 TB on-premises Oracle Database reservation system to Amazon Aurora PostgreSQL-Compatible Edition to get rid of Oracle licensing. The schema has hundreds of PL/SQL packages, triggers, and sequences. A 10 Gbps Direct Connect connection is available. The business allows at most 15 minutes of downtime at cutover, and the source must stay fully available during the migration.

Which TWO actions should the solutions architect include? **(Select TWO.)**

- **A.** Run an AWS DMS full-load-only task during a planned weekend outage, then point the application at Aurora when the load finishes.
- **B.** Use AWS DMS Schema Conversion (or AWS SCT) to assess the schema and PL/SQL code and convert them to PostgreSQL, then fix the action items that the assessment report flags.
- **C.** Use Oracle Data Pump to export the schema and data, and import the dump files into Aurora PostgreSQL through the S3 integration.
- **D.** Run an AWS DMS task with full load and ongoing replication (CDC) from the Oracle redo logs, validate the data, and cut over when replication latency is close to zero.
- **E.** Turn on Babelfish for Aurora PostgreSQL so that the existing PL/SQL packages and the application's Oracle drivers run without changes.

### Q20
A broadcaster is new to AWS and has never ordered AWS Snow Family devices. It must move a **500 TB** media archive from an on-premises NFS NAS to Amazon S3 within **6 weeks** to meet a contract deadline. Its only connection is a 1 Gbps internet link. About 300 Mbps of it is free during business hours and about 800 Mbps overnight. The data center is 900 km from the nearest AWS Data Transfer Terminal. The company wants a managed, verifiable transfer with minimal custom tooling.

Which approach meets the deadline?

- **A.** Order AWS Snowball Edge Storage Optimized devices, copy the archive to them in parallel through the NFS interface, and ship them back to AWS for import into Amazon S3.
- **B.** Turn on S3 Transfer Acceleration for the destination bucket, and run parallel multipart uploads with the AWS CLI over the existing internet link, scheduled to use full bandwidth at night.
- **C.** Order a temporary 10 Gbps hosted Direct Connect connection from a Direct Connect Delivery Partner, deploy AWS DataSync agents on premises, and run parallel DataSync tasks to Amazon S3 over it.
- **D.** Copy the archive to company-purchased portable drives and courier the drives to the nearest AWS Data Transfer Terminal, where AWS staff upload the data to the company's S3 bucket.

---

## Section 2 — Answer key

| Q | Answer | Domain / Task | Topic |
|---|--------|---------------|-------|
| 1 | **A, D** | D1 / 1.2 | SCP Region deny with global-service exemptions and break-glass role |
| 2 | **C** | D1 / 1.4 | Control Tower: enrolling existing accounts + Account Factory customization |
| 3 | **A** | D3 / 3.5 | VPC sharing via AWS RAM vs per-account VPCs |
| 4 | **B, E** | D2 / 2.3 | Centralized inspection: GWLB + third-party firewalls + TGW appliance mode |
| 5 | **D** | D1 / 1.1 | Direct Connect gateway + transit VIF to TGWs in three Regions |
| 6 | **B** | D3 / 3.4 | Site-to-Site VPN as DX backup; TGW route priority and BGP preference |
| 7 | **A** | D2 / 2.3 | PrivateLink endpoint service for SaaS with overlapping CIDRs |
| 8 | **C, E** | D1 / 1.1 | Hybrid DNS: Resolver inbound/outbound endpoints, rules shared via RAM |
| 9 | **D** | D2 / 2.3 | IAM Identity Center + external IdP (SAML + SCIM) + permission sets |
| 10 | **C** | D3 / 3.2 | Permissions boundaries for delegated role creation |
| 11 | **A, C, F** | D3 / 3.2 | Organization trail, S3 Object Lock compliance mode, integrity validation |
| 12 | **B, D, E** | D1 / 1.5 | Tag policies + cost allocation tags + Cost Categories for chargeback |
| 13 | **A** | D2 / 2.2 | AWS Backup policies, cross-account + cross-Region copy, Vault Lock |
| 14 | **D** | D2 / 2.2 | Pilot light DR with Aurora Global Database (headless secondary) |
| 15 | **B** | D4 / 4.4 | Lambda reserved concurrency + SQS maximum concurrency + RDS Proxy |
| 16 | **C** | D3 / 3.5 | Compute Savings Plans vs EC2 Instance SP vs RIs |
| 17 | **D** | D2 / 2.6 | S3 Intelligent-Tiering vs lifecycle rules for unknown access patterns |
| 18 | **A** | D4 / 4.2 | Rehost 300 VMware VMs with AWS Transform MGN |
| 19 | **B, D** | D4 / 4.2 | Oracle → Aurora PostgreSQL: DMS Schema Conversion/SCT + DMS CDC |
| 20 | **C** | D4 / 4.2 | 500 TB transfer: Snowball availability change, DataSync over hosted DX |

**Answer-letter distribution (single-answer questions):** A ×4, B ×2, C ×4, D ×4. Six questions are multi-select.

---

## Section 3 — Detailed solutions

### Q1 — Answer: **A, D**
**Decisive keywords:** "preventive, centrally managed" · "IAM, Organizations, Route 53, CloudFront, Support must keep working" · "break-glass role … in **any** Region" · "easy to extend".

**Why correct:**
- **A:** This is the AWS-documented Region-deny pattern: a `Deny` statement with `NotAction` that lists the global services, plus `StringNotEquals` on `aws:RequestedRegion`. Global services such as IAM, Organizations, Route 53, CloudFront, and Support send their API calls to a single endpoint, usually **us-east-1**. Without the `NotAction` exemption, a Region condition would block them. To approve a third Region later, you add one value to the list in one policy.
- **D:** `ArnNotLike` on `aws:PrincipalARN` with a wildcard account (`arn:aws:iam::*:role/SecOps-BreakGlass`) removes **only** that role from the deny, in every account, and leaves everyone else restricted. It is the standard way to carve out break-glass or pipeline roles from an SCP deny.

**Why the others are wrong:**
- **B:** Global-service calls *are* evaluated against `aws:RequestedRegion`, which resolves to the global endpoint's Region (for example us-east-1). A blanket `Action: "*"` deny would break IAM, Organizations, and the other global services.
- **C:** SCPs attach to the root, OUs, and accounts, not to roles. Moving whole accounts out of the policy exempts **every principal** in them, which breaks data residency. And because the role exists in **every** account, you would have to exempt all of them.
- **E:** SCPs **never** affect the management account, no matter where they are attached. That is why workloads should not run in the management account.

**Concept to remember:** Region-deny SCP = `Deny` + `NotAction` (global services) + `aws:RequestedRegion` + `ArnNotLike aws:PrincipalARN` (exempt roles). SCPs do not affect the management account or service-linked roles. Control Tower offers the same thing as its Region deny control.

**References:**
- [SCP examples — deny access based on requested Region](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps_examples.html)
- [Service control policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [Global condition keys — aws:RequestedRegion, aws:PrincipalARN](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html)

---

### Q2 — Answer: **C**
**Decisive keywords:** "standalone accounts" · "production workloads cannot be rebuilt" · "existing AWS Config configuration recorder" · "company-specific VPC layout and CloudFormation baseline at creation" · "least ongoing operational overhead".

**Why correct:** Existing accounts come under Control Tower governance by **enrollment**. Control Tower deploys its baseline stack sets (CloudTrail, Config, roles), applies the OU's controls, and leaves existing VPCs and workloads untouched. Accounts that Control Tower did not create first need the **`AWSControlTowerExecution`** role, which Control Tower uses to deploy its StackSets. AWS Config resources that already exist (configuration recorder and delivery channel) conflict with enrollment and must be handled with the documented procedure first. You can register a whole OU to enroll every account in it. For new accounts, **Account Factory** with **Account Factory Customization (AFC)** applies a blueprint (a CloudFormation-based Service Catalog product) when the account is vended. **AFT** (Account Factory for Terraform) is the GitOps pipeline alternative.

**Why the others are wrong:**
- **A:** Rebuilding production workloads breaks the stated constraint and adds a lot of migration effort and risk.
- **B:** The accounts would sit outside Control Tower governance: no Control Tower controls, no drift detection, no Account Factory. Hand-built StackSets are exactly the operational overhead the CTO wants to avoid.
- **D:** Control Tower runs **one landing zone per organization**, and there is no "Identity Center trust" between landing zones. Two management accounts split governance and billing.

**Concept to remember:** Existing accounts: invite → create `AWSControlTowerExecution` → fix Config conflicts → enroll or register the OU. New accounts: Account Factory + AFC or AFT. You can't enroll an existing account as the audit or log archive account after initial setup.

**References:**
- [About enrolling existing accounts](https://docs.aws.amazon.com/controltower/latest/userguide/enroll-account.html)
- [Enroll accounts that have existing AWS Config resources](https://docs.aws.amazon.com/controltower/latest/userguide/existing-config-resources.html)
- [Customize accounts with Account Factory Customization (AFC)](https://docs.aws.amazon.com/controltower/latest/userguide/af-customization-page.html)
- [AWS Control Tower Account Factory for Terraform (AFT)](https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html)

---

### Q3 — Answer: **A**
**Decisive keywords:** "NAT gateway hours, interface endpoint hours" ×64 · "transit gateway data processing for chatty service-to-service traffic" · "CIDR sprawl" · "trust each other" · "separate accounts for billing and IAM" · "network team wants exclusive control of subnets, route tables, NACLs".

**Why correct:** With **VPC sharing** (subnets shared through AWS RAM within one organization), many accounts deploy into a few centrally owned VPCs:
- The **owner** creates and manages subnets, route tables, NACLs, NAT gateways, interface and gateway endpoints, Resolver endpoints, and TGW attachments.
- **Participants** create their own application resources (EC2, RDS, Lambda, ENIs, security groups) and pay for them, so billing and IAM isolation stay per account.
- Traffic between workloads in the same VPC uses implicit local routing, with **no TGW per-GB processing**. Same-AZ traffic is free whichever account owns the resources.
- NAT gateways and endpoints drop from 64 × (3 + 9) to a handful, and far fewer CIDRs need to be allocated.

**Why the others are wrong:**
- **B:** VPC peering does **not** support edge-to-edge routing, so a VPC can't use a peer's NAT gateway or IGW. A 64-VPC mesh also means about 2,016 peering connections to manage.
- **C:** Participants **cannot** create or modify NAT gateways, route tables, or NACLs in shared subnets; only the owner can. It would also contradict the network team's requirement.
- **D:** This is a valid centralized-egress pattern and it does cut NAT and endpoint duplication. But it keeps 64 VPCs (CIDR sprawl), and the chatty inter-workload traffic still pays TGW data processing. A meets more of the requirements.

**Concept to remember:** Same trust boundary + heavy east-west traffic + central network control → **VPC sharing**. Separate trust boundaries or overlapping CIDRs → separate VPCs connected with TGW or PrivateLink. Only the owner manages routing and gateways, and the owner pays NAT and endpoint charges.

**References:**
- [Share your VPC subnets with other accounts](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-sharing.html)
- [Responsibilities and permissions for owners and participants](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-share-limitations.html)
- [Billing and metering for owner and participants](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-share-billing.html)

---

### Q4 — Answer: **B, E**
**Decisive keywords:** "**third-party** NGFW" · "scale horizontally" · "survive appliance or AZ failure" · "both directions of every flow on the same appliance" · "transit gateway".

**Why correct:**
- **B:** A **Gateway Load Balancer** (GWLB) acts as a transparent layer-3 gateway and a layer-4 load balancer. It wraps traffic in GENEVE (UDP 6081) toward the appliances, keeps each flow on one healthy appliance, and lets you scale the fleet horizontally. **GWLB endpoints** can be used as route-table targets, so the TGW attachment subnets route to the GWLBe in the same AZ, and inspected traffic continues to the NAT gateway and IGW.
- **E:** Without **appliance mode**, the transit gateway tries to keep traffic in the AZ it came from. The return leg of a flow can then arrive in a different AZ, on an appliance that never saw the request, and get dropped. With appliance mode on the inspection VPC attachment, the TGW uses a flow hash to pick one ENI (one AZ) for the whole life of the flow, in both directions.

**Why the others are wrong:**
- **A:** An NLB is not a route-table target and is not a transparent bump-in-the-wire. It also has no GENEVE encapsulation to keep the original packet intact for the firewall.
- **C:** The TGW **network function attachment** is available only for **AWS Network Firewall**. The docs state that third-party firewalls are not supported.
- **D:** VPC attachments **do not support ECMP**. ECMP applies to VPN, Connect, and Direct Connect gateway attachments.
- **F:** Putting an IGW and NAT in every spoke spreads egress back out, which is what centralized inspection is meant to prevent.

**Concept to remember:** Third-party inline appliances → **GWLB + GWLB endpoints**. A stateful appliance VPC behind a TGW → **turn on appliance mode** on that attachment. AWS Network Firewall alone → the TGW network function attachment can replace the inspection VPC.

**References:**
- [What is a Gateway Load Balancer?](https://docs.aws.amazon.com/elasticloadbalancing/latest/gateway/introduction.html)
- [How AWS Transit Gateway works — appliance mode, ECMP, network function attachments](https://docs.aws.amazon.com/vpc/latest/tgw/how-transit-gateways-work.html)
- [Transit gateway network function attachments](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-nf-fw.html)

---

### Q5 — Answer: **D**
**Decisive keywords:** "150 VPCs, 30 accounts, 3 Regions" · "one transit gateway per Region" · "fewest VIFs and BGP sessions" · "resiliency across both connections" · "control which AWS prefixes are advertised".

**Why correct:** A **Direct Connect gateway is a global resource**. One **transit VIF** per connection (two BGP sessions in total) attaches to one DXGW, and that DXGW can be **associated with up to 6 transit gateways** in any Regions and accounts. Cross-account associations use association proposals. **Allowed prefixes** on each DXGW–TGW association control exactly which (summarized) AWS CIDRs are advertised on premises. Summarizing also helps you stay under the quota of **200 prefixes per transit gateway** advertised from AWS to on premises on a transit VIF. The 40 on-premises prefixes fit the default **100 routes per BGP session** on a transit VIF (raisable with prefix controls).

**Why the others are wrong:**
- **A:** A dedicated connection supports at most **50 private/public VIFs** (a hard limit), so 150 VIFs is impossible, and it would be an operational nightmare anyway.
- **B:** A DXGW supports at most **20 virtual private gateways** (a hard limit), so 150 VGWs doesn't fit.
- **C:** This works (each dedicated connection allows up to 4 transit VIFs), but it **triples** the VIFs and BGP sessions for no benefit, because a single DXGW already spans Regions.

**Concept to remember:** Many VPCs in multiple Regions over DX → **transit VIF → one DXGW → up to 6 TGWs**, with allowed prefixes for summarization. A DXGW does **not** route traffic between the gateways associated with it. Use TGW peering for inter-Region VPC-to-VPC traffic.

**References:**
- [Direct Connect gateways](https://docs.aws.amazon.com/directconnect/latest/UserGuide/direct-connect-gateways.html)
- [Direct Connect quotas](https://docs.aws.amazon.com/directconnect/latest/UserGuide/limits.html)
- [Allowed prefixes interactions](https://docs.aws.amazon.com/directconnect/latest/UserGuide/allowed-to-prefixes.html)

---

### Q6 — Answer: **B**
**Decisive keywords:** "take over **automatically**" · "traffic in **both directions** must use Direct Connect while it is healthy" · "same 10.0.0.0/8 summary over every path" · "transit gateway".

**Why correct:** There are two directions to control.
- **AWS → on premises:** When a transit gateway has routes with the same CIDR from different attachment types, it ranks them in this order: **static > prefix-list > VPC-propagated > Direct Connect gateway–propagated > Connect > VPN-over-DX > VPN-propagated**. If both paths advertise 10.0.0.0/8 dynamically, the TGW installs the DX route and keeps the VPN route as a hidden backup that appears only when DX withdraws its route.
- **On premises → AWS:** The customer router receives the VPC prefixes over both paths. Giving the DX-learned routes a **higher BGP local preference** makes outbound traffic prefer DX, and BGP fails over to the VPN automatically.

**Why the others are wrong:**
- **A:** A **static** VPN route outranks DX-propagated routes, so AWS-to-on-premises traffic would *always* use the VPN. DX BGP keepalives do not withdraw a static route.
- **C:** Longest-prefix match is evaluated first, so the more-specific /9 routes over the VPN would make the VPN the **primary** path.
- **D:** The TGW compares attachment type *before* AS_PATH, so prepending on DX doesn't produce the intended behavior. It also signals the opposite of what you want, because it makes DX less attractive.

**Concept to remember:** On a TGW, for equal prefixes, **DX gateway beats VPN** when both are BGP. Never use static VPN routes as a "backup". To steer AWS → on premises, use more-specific prefixes or AS_PATH between the *same* attachment type. For on premises → AWS, use local preference. For maximum resiliency, AWS recommends two DX connections at separate locations; the VPN is the low-cost option.

**References:**
- [Transit gateway route evaluation order](https://docs.aws.amazon.com/vpc/latest/tgw/how-transit-gateways-work.html)
- [Site-to-Site VPN routing options and route priority](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPNRoutingTypes.html)
- [AWS Direct Connect Resiliency Toolkit](https://docs.aws.amazon.com/directconnect/latest/UserGuide/resiliency_toolkit.html)

---

### Q7 — Answer: **A**
**Decisive keywords:** "SaaS provider" · "400 → thousands of customers" · "overlapping 10.0.0.0/16" · "provider must not initiate connections into their networks or see routing" · "approve each customer".

**Why correct:** **AWS PrivateLink** is built for this case. The provider publishes a **VPC endpoint service** backed by a **Network Load Balancer**, sets **acceptance required**, and lists allowed principals (customer account ARNs). Each customer creates an **interface endpoint**, an ENI with an IP address from the customer's own subnet. Traffic is **unidirectional** (only the consumer can initiate it), no routes are exchanged, and **overlapping CIDRs don't matter** because nothing is routed between the VPCs. It scales to thousands of consumers without per-customer network plumbing. If customers in other Regions need access later, the provider can enable cross-Region connectivity for the endpoint service where it is supported.

**Why the others are wrong:**
- **B:** VPC peering **cannot be created between overlapping CIDRs**, and NAT doesn't change that. Peering is bidirectional at the network level, and the per-VPC peering quota rules out hundreds of customers.
- **C:** Overlapping CIDRs can't be routed through one TGW. A TGW attachment is full layer-3 connectivity, which the customers' security teams rejected, and it creates a large blast radius.
- **D:** An endpoint service must be fronted by an **NLB** (or a GWLB for appliances), not an ALB. If you need layer-7 features, put the ALB **behind** the NLB as an ALB-type target.

**Concept to remember:** Exposing a service to many consumers with overlapping CIDRs, one-way and private → **PrivateLink endpoint service (NLB) + interface endpoints**, with acceptance, allowed principals, and optional private DNS after domain verification.

**References:**
- [Share your services through AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-share-your-services.html)
- [Create an endpoint service](https://docs.aws.amazon.com/vpc/latest/privatelink/create-endpoint-service.html)
- [What is AWS PrivateLink?](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html)

---

### Q8 — Answer: **C, E**
**Decisive keywords:** "on-premises must resolve aws.example.com" (inbound) · "every VPC must resolve corp.example.com" (outbound) · "new accounts … minimal per-account work" · "no self-managed DNS servers".

**Why correct:**
- **C:** A **Resolver inbound endpoint** gives the Route 53 Resolver IP addresses that are reachable from on premises over DX. Use at least two IPs in different AZs. On-premises DNS servers conditionally forward `aws.example.com` to those IPs. The endpoint's VPC must be associated with the private hosted zones so that it can answer for them.
- **E:** A **Resolver outbound endpoint** plus a **forwarding rule** sends `corp.example.com` queries to the on-premises DNS servers. Rules can be **shared through AWS RAM** and associated with VPCs in other accounts in the same Region. Those VPCs then use the central outbound endpoint, so each new account only needs a rule association, which can be automated.

**Why the others are wrong:**
- **A:** Self-managed DNS servers are explicitly ruled out, and running them in every VPC is a lot of overhead.
- **B:** This works, but it puts endpoints (billed per ENI-hour) and rules in every VPC across 50 accounts, which is unnecessary cost and per-account work.
- **D:** The VPC+2 (AmazonProvidedDNS) resolver can be reached only from **inside** the VPC, not from on premises over DX or VPN. That is why inbound endpoints exist.
- **F:** Publishing internal corporate records in a **public** zone exposes them, and the Lambda sync is custom tooling.

**Concept to remember:** Inbound = on premises → AWS. Outbound + rules = AWS → on premises. Centralize both in one VPC and share the rules through RAM. **Route 53 Profiles** can now bundle PHZ associations, Resolver rules, and DNS Firewall rule groups and share them across accounts as one unit.

**References:**
- [What is Route 53 Resolver?](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver.html)
- [Managing forwarding rules (including sharing with AWS RAM)](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver-rules-managing.html)
- [Route 53 Profiles](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/profiles.html)

---

### Q9 — Answer: **D**
**Decisive keywords:** "200 accounts" · "Entra ID" · "short-term credentials, console and CLI" · "created and removed **automatically**" · "consistent role definitions managed centrally" · "least operational overhead".

**Why correct:** **IAM Identity Center** with an **external IdP** uses **SAML 2.0 for authentication** and **SCIM for automatic provisioning and deprovisioning** of users and groups. **Permission sets** are defined once and provisioned as IAM roles into each assigned account, so the PowerUser/ReadOnly definitions are managed in one place. Users sign in through the AWS access portal, and the CLI gets short-term credentials through `aws configure sso` and `aws sso login`. You can delegate administration of Identity Center to a member account to keep the management account out of daily operations.

**Why the others are wrong:**
- **A:** 200 SAML providers, StackSets, and a nightly cleanup script are a lot of overhead, and leavers keep access until the script runs.
- **B:** A Managed Microsoft AD and a sync connector add infrastructure that isn't needed, because Identity Center integrates with Entra ID directly.
- **C:** **SAML alone does not provision users**. Without SCIM, users and groups have to be created and removed by hand, which is the same leaver problem the auditors found.

**Concept to remember:** Workforce SSO across many accounts → **Identity Center + external IdP (SAML for sign-in, SCIM for lifecycle) + permission sets assigned to groups**.

**References:**
- [What is IAM Identity Center?](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html)
- [Automatic provisioning (SCIM)](https://docs.aws.amazon.com/singlesignon/latest/userguide/provision-automatically.html)
- [Permission sets](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetsconcept.html)

---

### Q10 — Answer: **C**
**Decisive keywords:** "developers create roles" · "no role can **ever** exceed" · "cannot remove or change that ceiling" · "cannot create users or give themselves more access".

**Why correct:** A **permissions boundary** caps the maximum permissions of the role it is attached to; effective permissions are the intersection of the identity policy, the boundary, and any SCPs. The delegation pattern is:
1. Allow `iam:CreateRole`, `iam:AttachRolePolicy`, and `iam:PutRolePolicy` **only when** the `iam:PermissionsBoundary` condition key equals the boundary ARN, so every role a developer creates is capped.
2. **Deny** `iam:DeleteRolePermissionsBoundary`, and deny `iam:PutRolePermissionsBoundary` with any other boundary.
3. **Deny** `iam:CreatePolicyVersion`, `iam:DeletePolicy`, and `iam:SetDefaultPolicyVersion` on the boundary policy itself.
4. Limit `iam:PassRole` to the team's role path (for example `/app-team-a/`), and don't grant `iam:CreateUser`.

**Why the others are wrong:**
- **A:** With `iam:*`, a developer can create a role with `AdministratorAccess` and assume it or pass it to a service. That is privilege escalation even though user creation is blocked.
- **B:** A boundary on the **developer's** role doesn't constrain the roles the developer **creates**. They could create an admin role and pass it to Lambda.
- **D:** This is detective, not preventive. An over-privileged role exists, and can be used, until the remediation runs.

**Concept to remember:** Delegated IAM = **condition `iam:PermissionsBoundary` on create/attach + protect the boundary + scope `iam:PassRole`**. Boundaries never grant permissions; they only cap them.

**References:**
- [Permissions boundaries for IAM entities](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html)
- [IAM condition keys (iam:PermissionsBoundary)](https://docs.aws.amazon.com/service-authorization/latest/reference/list_iam.html)
- [Policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)

---

### Q11 — Answer: **A, C, F**
**Decisive keywords:** "every current and future account, all Regions" · "member admins must not stop or change logging" · "immutable 7 years … including root" · "only security audit team can read" · "prove log files were not changed".

**Why correct:**
- **A:** An **organization trail** created in the management account, or in a **CloudTrail delegated administrator** account, applies automatically to every member account, including new ones. Member accounts can see the trail but **cannot change or delete it**. Delivering to a bucket in a dedicated log archive account takes the logs out of workload admins' reach.
- **C:** **S3 Object Lock in compliance mode** means no user, *including the root user*, can delete or overwrite a locked object version or shorten its retention until the retention period ends. A bucket default retention of 7 years applies to every log object. Object Lock requires versioning.
- **F:** **Log file integrity validation** writes hourly digest files (SHA-256 hashes, RSA-signed) so you can prove whether log files were changed or deleted after delivery. A **customer managed KMS key** whose key policy allows `kms:Decrypt` only for the audit role, plus a restrictive bucket policy, enforces "only the security team can read". The bucket policy must still allow the CloudTrail service principal to write, scoped with `aws:SourceArn`.

**Why the others are wrong:**
- **B:** Buckets in each account can still be deleted by that account's administrators, and logs aren't centralized. An SCP on `StopLogging` doesn't stop someone deleting the bucket or its objects.
- **D:** In **governance mode**, principals with `s3:BypassGovernanceRetention` can remove protection. Leaving the root user able to bypass it fails the "including root" requirement.
- **E:** Glacier **Vault Lock** applies to S3 Glacier *vaults* (the legacy Glacier API), not to S3 buckets. Objects in Glacier storage classes inside a bucket are protected with S3 Object Lock.

**Concept to remember:** Tamper-proof audit trail = **org trail → log archive account + Object Lock (compliance) + integrity validation + CMK with a narrow key policy**. Governance mode can be bypassed; compliance mode cannot.

**References:**
- [Creating a trail for an organization](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/creating-trail-organization.html)
- [Validating CloudTrail log file integrity](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-intro.html)
- [Locking objects with Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)
- [Encrypting CloudTrail log files with AWS KMS keys](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/encrypting-cloudtrail-log-files-with-aws-kms.html)

---

### Q12 — Answer: **B, D, E**
**Decisive keywords:** "standardize key **and values**" · "**block** noncompliant values" · "shared networking account split **proportionally**" · "chargeback reports" · "least custom code".

**Why correct:**
- **B:** **Tag policies** standardize tag key capitalization and allowed values. With **enforcement** for specified resource types, noncompliant *tagging operations* are blocked. Tag policies **don't evaluate untagged resources**, so add an **SCP** that denies create actions when `aws:RequestTag/CostCenter` is missing (a `Null` condition) for critical resource types.
- **D:** User-defined tags appear in billing data only after they are **activated as cost allocation tags in the management (payer) account**. Management account users can request a **backfill** of up to 12 months, which applies only where the resources actually carried the tag in those months.
- **E:** **AWS Cost Categories** group costs by rules on account, tag, service, and charge type into business dimensions such as cost centers. **Split charge rules** allocate a shared cost (for example the networking account) proportionally, evenly, or by fixed percentage. Cost Categories show up in Cost Explorer, Budgets, CUR, and Data Exports.

**Why the others are wrong:**
- **A:** AWS Config `required-tags` is detective only, doesn't standardize values, and compliance results are not cost data.
- **C:** In an organization, cost allocation tags are activated **in the management account**. Member accounts don't do this for consolidated billing.
- **F:** Budgets track spending against thresholds. They don't allocate shared costs or produce a chargeback statement.

**Concept to remember:** Chargeback stack = **tag policy (values) + SCP (presence) → activate tags in the payer account → Cost Categories + split charges → Cost Explorer/CUR**.

**References:**
- [Tag policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_tag-policies.html)
- [Using cost allocation tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html)
- [Backfill cost allocation tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-allocation-backfill.html)
- [Managing costs with AWS Cost Categories](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/manage-cost-categories.html)
- [Splitting charges within cost categories](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/splitcharge-cost-categories.html)

---

### Q13 — Answer: **A**
**Decisive keywords:** "enforced centrally … new accounts automatically" · "tagged backup=daily" · "dedicated backup account in a second Region" · "survive full compromise … malicious administrator".

**Why correct:**
- **Central enforcement:** With **AWS Backup cross-account management**, the management account (or a delegated administrator) attaches **backup policies** (an Organizations policy type) to OUs. New accounts in those OUs inherit the policy automatically. Tag-based resource selection picks up anything tagged `backup=daily`.
- **Copies:** A **copy action** in the policy sends each recovery point to a vault in a separate backup account in a second Region. RDS and Aurora support cross-Region and cross-account copy **in a single action**.
- **Immutability:** **AWS Backup Vault Lock in compliance mode** makes the destination vault WORM once its grace period ends. Nobody, including the vault account's root user or AWS, can delete recovery points or shorten retention.
- **Watch-outs:** DynamoDB needs **AWS Backup advanced features** for cross-account and cross-Region copy. RDS snapshots encrypted with the default AWS managed key can't be shared cross-account, so use customer managed keys. A **logically air-gapped vault** is a newer alternative for the destination.

**Why the others are wrong:**
- **B:** This patchwork of service-native features plus Lambda has no central enforcement, needs custom code, and the copies stay reachable from the compromised account.
- **C:** Copies stay **in the same account**, so a malicious admin there can change the vault access policy and delete them. Per-account StackSets also give weaker central enforcement than backup policies.
- **D:** Elastic Disaster Recovery and replicas give continuous DR, not 35-day point-in-time retention. Replicas copy corruption and deletions straight across.

**Concept to remember:** Ransomware-resilient org backups = **backup policies + cross-account, cross-Region copy + Vault Lock (compliance) or a logically air-gapped vault**.

**References:**
- [Managing AWS Backup resources across multiple accounts](https://docs.aws.amazon.com/aws-backup/latest/devguide/manage-cross-account.html)
- [Backup policies (AWS Organizations)](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_backup.html)
- [AWS Backup Vault Lock](https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html)
- [AWS Backup feature availability](https://docs.aws.amazon.com/aws-backup/latest/devguide/backup-feature-availability.html)

---

### Q14 — Answer: **D**
**Decisive keywords:** "RPO 1 minute" · "RTO 45 minutes" · "**lowest standing cost**" · "CloudFormation for all infrastructure".

**Why correct:** This is **pilot light**: the data layer replicates continuously, and compute is defined but switched off.
- **Data:** **Aurora Global Database** replicates at the storage layer with lag usually under a second, which comfortably meets a 1-minute RPO. The secondary cluster can be **headless** (no DB instances), so you pay for storage and replication only. During failover you add an instance, which takes minutes.
- **Compute:** AMIs, the ALB, and a zero-capacity Auto Scaling group (all in CloudFormation) are ready to scale out. Route 53 failover records with health checks move traffic.
- **Timing:** Global database failover, adding an instance, and scaling the ASG all fit within 45 minutes.

**Why the others are wrong:**
- **A:** Hourly snapshots mean an RPO of up to an hour, and restoring an Aurora snapshot plus the whole stack puts the RTO at risk.
- **B:** This is **warm standby**. It meets the targets but keeps 8 instances and two DB readers running, which isn't the lowest cost.
- **C:** **Multi-site active-active** costs the most, far beyond what these RTO/RPO targets need.

**Concept to remember:** Backup & restore (hours) → **pilot light (data live, compute off; tens of minutes)** → warm standby (scaled-down but running; minutes) → active-active (near zero). Headless Aurora Global Database secondaries are the cheapest way to get sub-second RPO.

**References:**
- [Disaster recovery options in the cloud (whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html)
- [Using Amazon Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html)
- [Creating a headless Aurora DB cluster in a secondary Region](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-attach.console.headless.html)

---

### Q15 — Answer: **B**
**Decisive keywords:** "database ran out of connections" · "**other Lambda functions** throttled" · "import can take up to 4 hours" · "minimal code changes".

**Why correct:**
- **Reserved concurrency** does two jobs. It **caps** the function's concurrency, which protects the database, and it **reserves** that amount out of the account pool, so the import can no longer starve the other functions.
- **SQS event source mapping maximum concurrency** (settable from 2 to 1,000) limits how many concurrent invocations the poller makes. Lambda then doesn't throttle invocations and send messages back to the queue, which could push them to the DLQ early. AWS advises keeping reserved concurrency ≥ the total maximum concurrency of the function's SQS mappings.
- **RDS Proxy** pools and multiplexes connections, which protects the database from connection storms. It needs only an endpoint change.
- The backlog drains steadily within the 4-hour window.

**Why the others are wrong:**
- **A:** More concurrency means **more** connections, so the outage gets worse, and a bigger instance is expensive and only postpones the problem.
- **C:** **Provisioned concurrency** pre-initializes environments to reduce cold starts. It **doesn't cap** scaling, because the function can still burst past it with on-demand concurrency.
- **D:** A batch size of 1 means more invocations for the same messages. Each execution environment still holds a connection, and concurrency isn't capped.

**Concept to remember:** Protect a downstream resource from Lambda → **reserved concurrency (cap + isolation) + ESM maximum concurrency for SQS + RDS Proxy**. Provisioned concurrency is for latency, not limits.

**References:**
- [Configuring reserved concurrency](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html)
- [Configuring scaling behavior for SQS event source mappings](https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-scaling.html)
- [Amazon RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html)

---

### Q16 — Answer: **C**
**Decisive keywords:** "move to **Graviton** families" · "containerize onto **Fargate**" · "Lambda" · "shift Regions" · "commitment must not become stranded".

**Why correct:** **Compute Savings Plans** (up to 66% off On-Demand) apply automatically to EC2 usage **regardless of instance family, size, OS, tenancy, or Region**, and also to **Fargate and Lambda**. Moving from m5 to Graviton families, from EC2 to Fargate, or from eu-west-1 to eu-central-1 keeps the discount. Size the hourly commitment to the **steady baseline** (Cost Explorer recommendations), not the peak, and leave variable usage on On-Demand or Spot.

**Why the others are wrong:**
- **A:** Standard RIs are locked to an instance type and Region, and they don't cover Fargate or Lambda. Selling on the RI Marketplace has eligibility rules and depends on demand, so it isn't a strategy.
- **B:** EC2 Instance Savings Plans give the deepest EC2 discount (up to 72%) but are **locked to one instance family in one Region**. Moving to Graviton families or another Region strands them, and they don't apply to Fargate or Lambda.
- **D:** Convertible RIs can be exchanged only for **other EC2 RIs**, never for Fargate or Lambda usage, and every exchange is manual work.

**Concept to remember:** Changing families, Regions, or compute services → **Compute SP**. Stable family in one Region → EC2 Instance SP or RIs for a few extra points. Savings Plans can't be cancelled, so commit to the floor. (Separately, **Database Savings Plans** now cover RDS, Aurora, DynamoDB, ElastiCache, and others at up to 35%.)

**References:**
- [Savings Plans types](https://docs.aws.amazon.com/savingsplans/latest/userguide/plan-types.html)
- [Compute Savings Plans and Reserved Instances](https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-ris.html)
- [What are Savings Plans?](https://docs.aws.amazon.com/savingsplans/latest/userguide/what-is-savings-plans.html)

---

### Q17 — Answer: **D**
**Decisive keywords:** "access patterns unknown" · "re-read without warning" · "milliseconds, **no restore step**" · "avoid retrieval charges" · "avoid maintaining lifecycle rules" · "average 6 MB".

**Why correct:** **S3 Intelligent-Tiering** charges a small per-object monitoring and automation fee and moves objects between tiers automatically:
- **Infrequent Access** after 30 days without access, and **Archive Instant Access** after 90 days. All three automatic tiers return data in **milliseconds**.
- There are **no retrieval charges**, and an object moves back to Frequent Access when it is read.
- Objects under 128 KB aren't monitored and stay in the Frequent tier. That doesn't matter here, because the 6 MB average makes the monitoring fee negligible next to the storage savings.

**Why the others are wrong:**
- **A:** Glacier Flexible Retrieval requires a **restore** (minutes to hours), and Standard-IA has per-GB retrieval fees. Unpredictable re-reads make fixed lifecycle rules risky.
- **B:** One Zone-IA stores data in one AZ (less resilient) and charges retrieval fees. Moving data back by hand from Storage Lens insights is operational work.
- **C:** The optional **Archive Access and Deep Archive Access** tiers require a restore before the object can be read, which breaks the millisecond requirement.

**Concept to remember:** Unknown or changing access + millisecond reads + no retrieval fees → **Intelligent-Tiering with the automatic tiers only**. Turn on the archive tiers only if the application can tolerate asynchronous restores.

**References:**
- [How S3 Intelligent-Tiering works](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering-overview.html)
- [Amazon S3 storage classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html)
- [Managing the lifecycle of objects](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)

---

### Q18 — Answer: **A**
**Decisive keywords:** "300 VMware VMs" · "3 months" · "lift-and-shift onto native EC2" · "cutover window ≤ 1 hour" · "test-launched before cutover" · "six people".

**Why correct:** **AWS Transform MGN** (formerly AWS Application Migration Service, renamed in 2026, with unchanged APIs and replication engine) is AWS's recommended rehost tool.
- **Replication:** It replicates source servers continuously at block level, using an agent or agentless vCenter replication, to a low-cost staging area subnet.
- **Testing:** You can run **non-disruptive test launches** as often as you need.
- **Cutover:** The final sync and launch take minutes, which fits the 1-hour windows.
- **Scale:** Launch templates, post-launch actions, and application or wave grouping let a small team move hundreds of servers. AWS Transform can additionally automate discovery and wave planning.

**Why the others are wrong:**
- **B:** VM Import/Export has no continuous replication. Exporting and uploading each VM's disks during the window can't meet a 1-hour cutover, and it doesn't scale to 300 VMs for six people.
- **C:** AWS Server Migration Service has been **discontinued**, and AWS points customers to MGN.
- **D:** Rebuilding servers is a replatform or re-architect effort that the requirements rule out, and it couldn't be done for 300 servers in 3 months.

**Concept to remember:** Rehost at scale with minimal downtime → **MGN / AWS Transform MGN**: replicate → test → cutover → finalize, in waves.

**References:**
- [What is AWS Transform MGN (Application Migration Service)?](https://docs.aws.amazon.com/mgn/latest/ug/what-is-application-migration-service.html)
- [Migrating with AWS MGN — launching test and cutover instances](https://docs.aws.amazon.com/mgn/latest/ug/launching-target-servers.html)
- [VM Import/Export](https://docs.aws.amazon.com/vm-import/latest/userguide/what-is-vmimport.html)

---

### Q19 — Answer: **B, D**
**Decisive keywords:** "Oracle → Aurora PostgreSQL" (**heterogeneous**) · "hundreds of PL/SQL packages" · "≤ 15 minutes downtime" · "source fully available".

**Why correct:**
- **B:** In a heterogeneous migration, **schema and code conversion** is a separate step. **AWS DMS Schema Conversion** (managed, in the DMS console) or the desktop **AWS SCT** produces an assessment report, converts tables, PL/SQL packages, triggers, and sequences where it can, and flags **action items** for manual rework.
- **D:** A **DMS full load + CDC** task loads the existing data while the source stays online. It then applies ongoing changes captured from Oracle redo and archive logs (LogMiner or Binary Reader; supplemental logging must be on). **DMS data validation** checks the rows. You cut over when CDC latency is near zero, so downtime is only the final switch. Reset sequences on the target before go-live.

**Why the others are wrong:**
- **A:** Full load only means the source must be frozen for the whole 12 TB load, far longer than 15 minutes.
- **C:** **Data Pump** is an Oracle-to-Oracle tool, and PostgreSQL can't import Oracle dump files.
- **E:** **Babelfish** makes Aurora PostgreSQL understand **SQL Server T-SQL and the TDS protocol**, not Oracle PL/SQL.

**Concept to remember:** Heterogeneous migration = **convert schema (DMS SC/SCT) + move data (DMS full load + CDC)**. Homogeneous migration = native tools or DMS. Minimal downtime always means **CDC**.

**References:**
- [DMS Schema Conversion](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_SchemaConversion.html)
- [What is the AWS Schema Conversion Tool?](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Welcome.html)
- [Creating tasks for ongoing replication (CDC)](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Task.CDC.html)
- [Using an Oracle database as a source for AWS DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.Oracle.html)
- [Babelfish for Aurora PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/babelfish.html)

---

### Q20 — Answer: **C**
**Decisive keywords:** "**new to AWS**, never ordered Snow devices" · "500 TB" · "6 weeks" · "1 Gbps link, 300–800 Mbps free" · "900 km from Data Transfer Terminal" · "managed, verifiable".

**Why correct:**
- **Bandwidth:** 500 TB ≈ 4 × 10¹⁵ bits. A temporary **10 Gbps hosted Direct Connect connection** from a Direct Connect Delivery Partner, at about 80% effective throughput (8 Gbps), moves that in about **5 × 10⁵ s ≈ 5.8 days**. Even with partner provisioning lead time, that fits inside 6 weeks.
- **Transfer service:** **AWS DataSync** is managed, encrypts data in transit, verifies integrity, and supports incremental re-runs. A single task can use up to 10 Gbps. Run parallel tasks or agents and reach the DataSync service through a VPC endpoint over a private VIF, or over a public VIF.
- **AWS guidance:** This is the replacement AWS itself recommends for Snowball Edge storage-optimized: DataSync, with a hosted DX connection for the length of the project.

**Why the others are wrong:**
- **A:** **AWS Snowball Edge has been closed to new customers since 7 November 2025**, and AWS no longer offers any Snow Family devices for new customers to order. Existing Snow customers are unaffected. AWS points new customers to DataSync (online), AWS Data Transfer Terminal (physical), or partner offline-transfer services. AWS Migration Hub and AWS Application Discovery Service closed to new customers on the same date, so for discovery and wave planning in new migrations, expect AWS Transform instead. ⚠️ *Exam note:* older SAP-C02-style questions may still list Snowball Edge as the "offline transfer" answer. If a question doesn't say the customer is new, the classic key was Snowball. Know both the exam pattern and the current reality.
- **B:** Bandwidth math: even 100% of 1 Gbps around the clock takes about **46 days**, over the 42-day limit. The realistic average (300 Mbps × 10 h + 800 Mbps × 14 h ≈ 590 Mbps) takes about **78 days**. Transfer Acceleration helps long-distance latency, not a local bandwidth ceiling.
- **D:** An **AWS Data Transfer Terminal** is a facility you **visit in person** with your own devices, by reservation, and upload the data yourself. It isn't a courier drop-off where AWS staff do the upload, and this site is 900 km away.

**Concept to remember:** Always do the bandwidth math first: **TB × 8 × 10¹² ÷ effective bps ÷ 86,400 = days**. For new customers, offline transfer options are now Data Transfer Terminal or partner services. Otherwise the answer is DataSync over a bigger pipe (a hosted DX connection).

**References:**
- [AWS Snowball Edge availability change](https://docs.aws.amazon.com/snowball/latest/developer-guide/snowball-edge-availability-change.html)
- [What is AWS DataSync?](https://docs.aws.amazon.com/datasync/latest/userguide/what-is-datasync.html)
- [Estimating timelines for large DataSync migrations](https://docs.aws.amazon.com/datasync/latest/userguide/datasync-large-migration-timelines.html)
- [Direct Connect hosted connections](https://docs.aws.amazon.com/directconnect/latest/UserGuide/hosted_connection.html)
- [What is AWS Data Transfer Terminal?](https://docs.aws.amazon.com/datatransferterminal/latest/userguide/what-is-dtt.html)

---

## Score interpretation

| Score | Verdict | Next step |
|-------|---------|-----------|
| **≥ 16 / 20** | Ready for this content area | Move on to the next paper and keep exam pace (≈2.4 min/question). |
| **13–15 / 20** | Close | Review the domains where you dropped points (use the Domain/Task column in the answer key) and re-read the "Traps & distractors" section of each linked chapter. |
| **< 13 / 20** | Re-study needed | Work through the chapters below for every question you missed, then retake this paper in 48 hours without looking at the solutions. |

**Chapters to re-study, by question:**
- Q1, Q2, Q12 (SCPs, Control Tower, tagging and chargeback): [02 — Multi-Account Governance](../02-Multi-Account-Governance/02-Multi-Account-Governance.md)
- Q9, Q10 (Identity Center, permissions boundaries): [03 — Identity and Access Management](../03-Identity-and-Access-Management/03-Identity-and-Access-Management.md)
- Q3–Q7 (VPC sharing, GWLB/TGW, Direct Connect, VPN, PrivateLink): [04 — Networking, VPC and Hybrid Connectivity](../04-Networking-VPC-and-Hybrid-Connectivity/04-Networking-VPC-and-Hybrid-Connectivity.md)
- Q8 (Route 53 Resolver hybrid DNS): [05 — Edge, DNS and Content Delivery](../05-Edge-DNS-and-Content-Delivery/05-Edge-DNS-and-Content-Delivery.md)
- Q11 (CloudTrail, Object Lock, KMS): [06 — Security, Data Protection and Threat Detection](../06-Security-Data-Protection-and-Threat-Detection/06-Security-Data-Protection-and-Threat-Detection.md)
- Q15 (Lambda concurrency): [07 — Compute, Containers and Serverless](../07-Compute-Containers-and-Serverless/07-Compute-Containers-and-Serverless.md)
- Q17, Q20 (S3 storage classes, data transfer): [08 — Storage and Data Transfer](../08-Storage-and-Data-Transfer/08-Storage-and-Data-Transfer.md)
- Q14, Q19 (Aurora Global Database, DMS): [09 — Databases and Caching](../09-Databases-and-Caching/09-Databases-and-Caching.md)
- Q13, Q14 (AWS Backup, DR strategies): [12 — Resilience, HA and Disaster Recovery](../12-Resilience-HA-and-Disaster-Recovery/12-Resilience-HA-and-Disaster-Recovery.md)
- Q18, Q19, Q20 (MGN, heterogeneous DB migration, transfer planning): [13 — Migration and Modernization](../13-Migration-and-Modernization/13-Migration-and-Modernization.md)
- Q12, Q16, Q17 (cost allocation, Savings Plans, storage cost): [16 — Cost Optimization and FinOps](../16-Cost-Optimization-and-FinOps/16-Cost-Optimization-and-FinOps.md)

> [← Practice Papers index](README.md) · [Study Guide start](../00-README-Start-Here.md)


# Practice Paper 4 — Migration & Modernization
> Original SAP-C02-style questions (not real exam questions). 20 questions · suggested time 48 min (≈2.4 min/question, exam pace).
> Domain mix: D1 ×4, D2 ×5, D3 ×3, D4 ×8 (this paper deliberately over-weights Domain 4; the real exam is D1 26% · D2 29% · D3 25% · D4 20%)
> [← Practice papers index](README.md) · [Study guide index](../00-README-Start-Here.md)

> **Naming and availability note (verified October 2026).** Exam questions may use old or new names, so both appear here. AWS Application Migration Service (MGN) is now **AWS Transform MGN** (renamed June 2026). As of **November 7, 2025**, these services are closed to new customers. Existing customers can keep using them, and AWS points new customers to **AWS Transform** (or DataSync and AWS Data Transfer Terminal in place of Snowball Edge): AWS Migration Hub, AWS Application Discovery Service, AWS App2Container, AWS Snowball Edge (all Snow Family devices), and the AWS Mainframe Modernization managed runtime. The Mainframe Modernization self-managed experience has also closed to new customers since then. SAP-C02 was written before these changes, so it still tests the concepts. The solutions show both the exam answer and what applies today.

---

## Section 1 — Questions

### Question 1
A retailer's data-center lease ends in 14 months, and the CFO has approved a full exit. A migration readiness assessment found six workload groups:

1. A custom-built HR system. The company has already signed an enterprise subscription for a SaaS HCM platform that covers the same functions.
2. A Windows reporting tool used by three people. Discovery data shows no logins in the last nine months.
3. A Java order service on a commercial application server. The team will swap the app server for open-source Tomcat on a managed platform but cannot rewrite code before the exit.
4. A settlement batch system under a regulator-imposed change freeze until 18 months from now. It must not be modified or moved during the freeze.
5. About 300 Linux VMs running commercial off-the-shelf (COTS) applications. The vendors certify only the current OS builds.
6. A legacy CRM scheduled for replacement next year.

The company has a small operations team and wants the lowest-risk plan that meets the deadline.

Which strategy assignments are appropriate? **(Select THREE.)**

- A. HR system: Repurchase. Move users to the SaaS HCM platform and decommission the custom system after data migration.
- B. Settlement batch: Rehost with AWS Transform MGN during the freeze so it is out of the data center before the lease ends.
- C. Reporting tool: Retire. Confirm with the business owner, archive historical outputs to Amazon S3, and shut the servers down.
- D. Java order service: Refactor into AWS Lambda functions and Amazon DynamoDB before the exit so it is cloud-native from day one.
- E. COTS Linux VMs: Rehost with AWS Transform MGN to Amazon EC2 in migration waves, keeping the certified OS builds unchanged.
- F. Java order service: Retain it on-premises until funding for a full rewrite is approved after the data-center exit.

### Question 2
A logistics company is planning its migration portfolio. It has 800 VMware VMs managed by two vCenter servers and 300 physical Windows and Linux servers. The physical servers include the core order database cluster and several integration hubs. The migration team needs:

- inventory and utilization data for every server
- network dependency data to build move groups
- for the physical servers and about 40 business-critical VMs, the list of running processes and fine-grained time-series performance data, which analysts will query with SQL in Amazon Athena.

The security team prohibits installing third-party or AWS agents on 120 network-appliance VMs in the VMware estate. The company signed up for AWS Application Discovery Service before its availability change and has an active project.

Which discovery approach meets these requirements with the LEAST effort?

- A. Deploy the Agentless Collector in each vCenter and enable its network data collection module. It discovers all 1,100 servers, including running processes and time-series data exportable to Athena.
- B. Deploy the Agentless Collector in each vCenter for VMware inventory, utilization, and network connections. Install the Discovery Agent on the 300 physical servers and the 40 critical VMs, and turn on data exploration in Athena.
- C. Install the Discovery Agent on all 1,100 servers, including the appliance VMs, so that every server reports processes, connections, and time-series data to the Migration Hub home Region.
- D. Export RVTools data from both vCenters, fill in the Migration Hub import template for the physical servers, and import both files. Use the imported records to build dependency groups and time-series reports.

### Question 3
A manufacturing company runs 2,400 servers across two data centers. About 35% of the servers run Windows Server, and many run SQL Server Enterprise. The CFO has asked for a directional business case within four weeks comparing the current on-premises total cost of ownership with running the estate on AWS. The board wants projections based on actual measured utilization rather than nameplate server specifications. The projections must also show how bring-your-own-license (BYOL) and License Included options for Windows Server and SQL Server change the result. The infrastructure team is small and will not deploy software on individual servers for this exercise. Some recent RVTools and CMDB exports already exist.

Which approach BEST meets these requirements?

- A. Export the server specification list from the CMDB and use AWS Pricing Calculator to price each server on equivalent EC2 instance types, adding License Included pricing for every Windows and SQL Server instance.
- B. Create a temporary AWS account, deploy a pilot set of workloads, and use AWS Cost Explorer forecasting to project the three-year cost of the full estate from the pilot's actual spend.
- C. Install the AWS Application Discovery Agent on every server to collect time-series utilization, then build a custom spreadsheet model that maps each server to an EC2 price.
- D. Engage Migration Evaluator (now offered as AWS Transform assessment). Use its agentless collector or the existing RVTools and CMDB exports to produce a utilization-based, right-sized business case that models Microsoft BYOL and License Included options.

### Question 4
A financial services company is rehosting 250 Windows and Linux servers with AWS Transform MGN (formerly AWS Application Migration Service). The data center has a 10 Gbps AWS Direct Connect connection to a transit gateway in the target Region. Corporate policy forbids replication traffic over the public internet, and the data-center firewall allows outbound HTTPS only to approved private endpoints. Each application owner must run a non-disruptive functional test on AWS before the production cutover. Test and cutover instances must launch in specific application subnets with specific instance types and security groups. A wave-level rollback must stay possible until the owner signs off.

Which approach meets these requirements?

- A. Keep the default replication settings. After replication completes, launch cutover instances directly, then edit each server's EC2 launch template to set the correct subnet, instance type, and security groups, and relaunch the cutover instances.
- B. Enable "Use private IP for data replication" with a staging-area subnet reached over Direct Connect. Skip test launches to save time, launch cutover instances for each wave, and finalize cutover immediately so replication resources are released.
- C. Enable "Use private IP for data replication" with a staging subnet reachable over Direct Connect, and use interface VPC endpoints for the MGN API. Set the subnet, instance type, and security groups in each EC2 launch template. Launch test instances into an isolated test subnet, mark servers ready for cutover, then launch cutover instances and finalize only after sign-off.
- D. Export each source VM as an image, transfer the images over Direct Connect with VM Import/Export, launch test instances from the imported AMIs, and repeat the export for the final cutover after a short application freeze.

### Question 5
An online education company is migrating a 3 TB MySQL 8.0 database from its data center to Amazon Aurora MySQL. The database supports a 24/7 learning platform, and the business allows at most 15 minutes of write downtime during the cutover. Before switching the application, the audit team requires a report showing that every row in every migrated table matches between source and target, and it wants this without building custom comparison tooling. A 1 Gbps AWS Direct Connect connection is available. All tables have primary keys.

Which approach meets these requirements?

- A. Enable row-based binary logging with sufficient binlog retention on the source. Run an AWS DMS full load and CDC task with data validation enabled into Aurora MySQL. At cutover, stop writes, let CDC latency reach zero, confirm validation shows no mismatches, then repoint the application.
- B. Take a consistent mysqldump of the source during a planned maintenance window, copy the dump file over Direct Connect, restore it into Aurora MySQL, run row-count queries on both sides, and then repoint the application to Aurora.
- C. Configure the Aurora MySQL cluster as a cross-environment read replica of the on-premises MySQL primary using Aurora's native replica feature, then promote the Aurora replica to standalone at the cutover time.
- D. Take a Percona XtraBackup physical backup to Amazon S3, restore it into a new Aurora MySQL cluster, configure binary log replication from the source, and promote Aurora at cutover after comparing table row counts.

### Question 6
An insurance company runs an ISV claims application on Microsoft SQL Server Enterprise. The application uses Microsoft's SQL Server client drivers, which connect over the TDS protocol, and relies on about 600 T-SQL stored procedures. The ISV allows the database to move off SQL Server, but it will not rewrite the application's data-access layer or stored procedures. The company wants to stop paying for SQL Server licenses by moving to Amazon Aurora PostgreSQL-Compatible Edition. The cutover may take at most one hour of downtime, and the company wants the fewest application changes.

Which migration approach BEST meets these requirements?

- A. Use AWS DMS Schema Conversion with generative AI conversion to convert the schema and stored procedures to native PL/pgSQL, have the ISV switch to PostgreSQL drivers, and migrate the data with an AWS DMS full load and CDC task.
- B. Assess the T-SQL with Babelfish Compass, then create an Aurora PostgreSQL cluster with Babelfish turned on. Deploy the schema through the Babelfish TDS endpoint, migrate data with AWS DMS full load and CDC, and point the app's connection string at the Babelfish endpoint.
- C. Migrate the database to Amazon RDS for SQL Server Multi-AZ with the License Included model using native backup and restore from Amazon S3, which removes the need to manage SQL Server licenses and keeps T-SQL unchanged.
- D. Take native SQL Server .bak backups, upload them to Amazon S3, and restore them directly into an Aurora PostgreSQL cluster using the Aurora S3 import feature, then enable Babelfish so the application connects without changes.

### Question 7
A media company is leaving its data center. It has two workloads to move:

- **NFS shares:** 180 TB on Linux NFS servers, used by a rendering application that will run on Amazon EC2 Linux instances with Amazon EFS. The final cutover must fit into a weekend.
- **Partner uploads:** 40 external partners upload assets daily to an on-premises SFTP server over the internet. Partners cannot change their hostname, client configuration, or SSH keys, and the company wants uploaded files to land in Amazon S3 for event-driven processing.

There is a 10 Gbps AWS Direct Connect connection. The company wants managed services with no file servers or SFTP servers to patch.

Which combination of actions meets these requirements? **(Select TWO.)**

- A. Deploy an AWS DataSync agent on-premises, create NFS-to-EFS tasks over Direct Connect, run the initial copy and scheduled incremental transfers ahead of time, and run a final verified incremental transfer during the weekend cutover.
- B. Deploy an Amazon S3 File Gateway on-premises, copy the NFS data to its file shares, and then point the rendering application on EC2 at the S3 bucket through the gateway's NFS export.
- C. Create an AWS DataSync agent in AWS and configure it as an SFTP endpoint for the partners, writing their uploads directly into the S3 bucket and triggering the event-driven processing.
- D. Create an AWS Transfer Family SFTP server backed by S3 with service-managed users that have the partners' existing public keys, import the current server host key, and point the existing hostname at the server endpoint.
- E. Deploy AWS Storage Gateway Volume Gateway in cached mode to present the NFS data to the rendering application, and use the gateway's EBS snapshots to seed Amazon EFS.

### Question 8
A law firm has four Windows file servers holding 60 TB across two offices. Users reach shares through a domain-based DFS namespace (`\\corp.example.com\shares`), and DFS Replication keeps the two sites in sync. The firm is moving the file servers to AWS and staying on its existing on-premises Active Directory forest, which is reachable over AWS Direct Connect. Requirements:

- survive the loss of an Availability Zone automatically
- preserve NTFS permissions and ownership exactly
- avoid changing the UNC paths used by thousands of documents and scripts
- minimize ongoing administration.

Which combination of actions meets these requirements? **(Select TWO.)**

- A. Deploy an Amazon FSx for Windows File Server Multi-AZ file system and configure DFS Replication between the preferred and standby file servers to keep both Availability Zones synchronized.
- B. Deploy an FSx for Windows File Server Multi-AZ file system joined to the existing self-managed AD domain over Direct Connect, and add the FSx shares as folder targets in the existing DFS namespace, replacing the old server targets.
- C. Deploy two FSx for Windows File Server Single-AZ 2 file systems in different Availability Zones and configure DFS Replication between them to provide Availability Zone resilience at a lower cost.
- D. Deploy Amazon FSx File Gateway in each office as the migration path, letting it copy the share contents into FSx for Windows File Server while caching hot files locally after cutover.
- E. Use AWS DataSync with SMB source locations and an FSx for Windows File Server destination, configured to copy ownership and NTFS DACLs. Run incremental transfers and a final sync at cutover.

### Question 9
A biotech company has a 400 TB on-premises NetApp ONTAP cluster that serves multi-protocol (NFS and SMB) volumes to research pipelines. The volumes depend heavily on ONTAP features: hourly snapshots retained for 90 days, which researchers restore from themselves; deduplication and compression with about 3:1 savings; and FlexClone volumes for test copies. The company wants to move this storage to AWS without losing any ONTAP functionality or retained snapshots. It also wants to keep cutover downtime short and avoid sending rehydrated data over its 10 Gbps AWS Direct Connect link. The on-premises cluster has a SnapMirror license.

Which approach meets these requirements?

- A. Create an Amazon FSx for NetApp ONTAP file system and use AWS DataSync NFS and SMB tasks to copy the volumes, preserving metadata, then re-create the snapshot schedule and FlexClone volumes on FSx after the final incremental transfer.
- B. Split the data by protocol: migrate NFS volumes to Amazon EFS and SMB volumes to FSx for Windows File Server with AWS DataSync, and use AWS Backup to provide snapshot-style restores going forward.
- C. Create FSx for ONTAP read-write destination volumes and a SnapMirror relationship so researchers can begin writing to FSx during replication, then let SnapMirror merge both sides at cutover.
- D. Peer the on-premises and FSx for ONTAP clusters and SVMs over Direct Connect using inter-cluster LIFs, then SnapMirror to data protection volumes on a schedule. At cutover, run a final update, quiesce and break the relationship, and mount the volumes.

### Question 10
A healthcare company must leave its colocation data center within nine months because the provider is closing the facility. It runs 1,200 VMs on VMware vSphere with NSX micro-segmentation. Its operations team is highly skilled in VMware, and backup and disaster recovery depend on VMware-integrated third-party tools. The company holds portable VMware Cloud Foundation (VCF) subscriptions. The network team requires that VMs keep their IP addresses during migration and that Layer 2 segments can stretch temporarily between sites. Leadership plans to modernize selected applications onto native AWS services after the exit, not before.

Which approach BEST meets the deadline and constraints?

- A. Rehost all 1,200 VMs to Amazon EC2 with AWS Transform MGN in weekly waves, re-creating NSX micro-segmentation as security groups and replacing the VMware-integrated backup tooling with AWS Backup before each wave.
- B. Export each VM as an OVA and use VM Import/Export to create AMIs, then launch them in a VPC with the same private IP addresses and re-implement the NSX rules with network ACLs.
- C. Deploy Amazon EVS (Amazon Elastic VMware Service) in a VPC with the VCF subscriptions, connect it through a transit gateway over Direct Connect, and use VMware HCX network extension and bulk/vMotion to relocate VMs with their IPs.
- D. Order AWS Outposts racks for the colocation facility, install vSphere on the Outposts servers, and migrate the VMs onto them so that the hardware can later be moved to an AWS Region.

### Question 11
A bank runs its core deposit system on an IBM z/OS mainframe: about 12 million lines of COBOL with CICS transactions, JCL batch, VSAM files, and Db2 for z/OS. The mainframe outsourcing contract ends in 30 months. Most of the remaining COBOL developers retire within two years, and the bank cannot hire replacements. The target state is a Java-based application on AWS that new graduate developers can maintain. It must produce functionally equivalent results, proven by side-by-side testing against mainframe outputs. A previous manual rewrite attempt failed after three years, so leadership requires a highly automated approach.

Which approach BEST meets these requirements?

- A. Use automated refactoring with AWS Transform for mainframe (formerly AWS Blu Age) to convert COBOL, CICS, JCL, VSAM, and Db2 assets into a Java application and a relational data store on AWS, validated by functional-equivalence testing.
- B. Replatform the application with Rocket Software Enterprise Server (formerly Micro Focus) on AWS, recompiling the COBOL with minimal changes and emulating CICS and JCL so the existing COBOL developers can keep maintaining it.
- C. Install the AWS Transform MGN replication agent on the z/OS LPARs, replicate the mainframe volumes to AWS, and launch them as EC2 instances in a VPC to exit the outsourcing contract within the deadline.
- D. Rewrite each business function by hand as Java microservices on Amazon ECS over a five-year program, running the mainframe and new services in parallel and retiring COBOL modules as each microservice goes live.

### Question 12
An e-commerce company has rehosted its Java monolith to Amazon EC2 instances behind an Application Load Balancer (ALB) at `shop.example.com`. The company now wants to modernize incrementally. It will first move the product catalog, then checkout, into separate services on Amazon ECS on AWS Fargate. Requirements:

- no client or DNS changes
- the ability to move a small share of catalog traffic to the new service first and increase it gradually
- an instant rollback for any single extracted function without redeploying the monolith.

The team has rejected a big-bang rewrite.

Which approach meets these requirements?

- A. Build the full microservices platform in parallel, then use Amazon Route 53 weighted records to shift `shop.example.com` from the monolith ALB to a new ALB in 10% steps once all services are complete.
- B. Split the monolith's shared relational database into one schema per future microservice before moving any code, then extract services once each schema has its own database instance.
- C. Use the existing ALB as the strangler façade: keep the monolith as the default action, add a path rule for `/catalog/*` that forwards to weighted target groups for the monolith and the new catalog service, and shift the weights gradually.
- D. Place Amazon CloudFront in front of the ALB and use Lambda@Edge functions to call both the monolith and the new catalog service for every request, returning whichever response arrives first.

### Question 13
A government agency has about 60 Java web applications (Tomcat and JBoss on Linux) and 40 ASP.NET applications (.NET Framework 4.8 on IIS, Windows Server) running on VMs. The agency wants to put these applications in containers on Amazon ECS with AWS Fargate to standardize deployment and cut patching effort. Source code changes are not allowed this year, and the platform team is small and has little container experience. The agency's AWS account onboarded AWS App2Container before its availability change. The team wants Dockerfiles, container images, ECS task definitions, and CI/CD pipeline templates generated with as little manual work as possible.

Which approach meets these requirements?

- A. Port each ASP.NET application from .NET Framework to modern .NET to make it Linux-compatible, then write Dockerfiles by hand for all 100 applications and build images in AWS CodeBuild.
- B. Create an Amazon EKS cluster with self-managed Windows and Linux node groups, and have the team write Helm charts and Dockerfiles for each application before deploying them to EKS.
- C. Package the Java applications and the ASP.NET applications as AWS Lambda container images, and front them with Amazon API Gateway to remove the need to manage any container cluster.
- D. Run App2Container on the application servers or a worker machine to inventory, analyze, and containerize each app. Have it generate Amazon ECR images, ECS task definitions for Fargate (Linux, and Windows for ASP.NET), and CI/CD pipeline templates.

### Question 14
A company is moving its SQL Server estate to Amazon EC2 and wants to bring its existing licenses to reduce cost. Its licenses are SQL Server 2017 Enterprise (per core) and Windows Server 2016 Datacenter, all bought in 2017 under a volume agreement. Software Assurance was not renewed. Internal auditors require continuous evidence that license usage never exceeds entitlements. The operations team does not want to allocate, track, or release dedicated hardware by hand as instances scale.

Which combination of actions meets these requirements? **(Select TWO.)**

- A. Launch the instances on default (shared) tenancy and submit License Mobility verification forms to Microsoft for both the SQL Server and Windows Server licenses.
- B. Launch the instances as EC2 Dedicated Instances, which provide the physical-core and socket visibility needed to bring per-core licenses without Software Assurance.
- C. Launch the instances on Amazon EC2 Dedicated Hosts using imported BYOL images, because licenses bought before October 1, 2019 can be deployed there without Software Assurance or License Mobility.
- D. Migrate the databases to standard Amazon RDS for SQL Server with the bring-your-own-license model so that AWS manages patching while the existing per-core licenses are reused.
- E. Create license configurations in AWS License Manager with core-based counting and hard limits, and create a host resource group so License Manager allocates and releases Dedicated Hosts automatically.

### Question 15
A logistics company must migrate a 40 TB Oracle Database 19c OLTP system to Amazon RDS for Oracle within three weeks. The only connection to AWS is a 200 Mbps Site-to-Site VPN that is shared with production traffic. A new AWS Direct Connect circuit has a 10-week lead time. The application may be down for at most two hours during the final cutover. The company has AWS Enterprise Support and has never ordered AWS Snow Family devices. It owns rack-mount NVMe storage arrays that can hold a full export.

Which approach meets these requirements?

- A. Run an Oracle Data Pump export consistent to a recorded SCN onto the NVMe arrays and upload it to Amazon S3 at an AWS Data Transfer Terminal. Import into RDS for Oracle using S3 integration, then run an AWS DMS CDC-only task from that SCN until cutover.
- B. Run an AWS DMS full load and CDC task over the existing VPN, using parallel load, increased commit rates, and a larger replication instance to finish the initial 40 TB load within the three-week deadline.
- C. Order AWS Snowball Edge Storage Optimized devices, load the Data Pump export onto them, ship them to AWS to import into Amazon S3, and then use AWS DMS CDC from the export SCN to catch up.
- D. Enable Amazon S3 Transfer Acceleration on the target bucket, upload the Data Pump files over the internet with multipart uploads, then run an AWS DMS full load and CDC task to synchronize changes.

### Question 16
A conglomerate with three business units plans to migrate 400 applications to AWS over 18 months, with the first migration wave in eight weeks. Today, every pilot workload runs in a single AWS account that developers share. Leadership requires the following before mass migration begins:

- separate accounts per business unit and environment
- centrally enforced guardrails and centralized, tamper-resistant logging
- a single shared path to the existing AWS Direct Connect connection with centralized egress inspection
- VPC CIDR ranges that never overlap with each other or with on-premises networks.

Which combination of actions should a solutions architect take? **(Select THREE.)**

- A. Continue migrating into the existing account, create one VPC per business unit, and use IAM permissions boundaries and tags to separate environments until the migration is complete.
- B. Deploy an AWS Control Tower landing zone with Log Archive and Audit accounts, IAM Identity Center, and OUs for security, infrastructure, and prod and non-prod workloads. Apply controls and vend accounts through Account Factory.
- C. Create a dedicated network account with a transit gateway attached to the Direct Connect gateway and a centralized inspection and egress VPC, then share the transit gateway with workload accounts through AWS RAM.
- D. Give each workload VPC its own virtual private gateway and Direct Connect private VIF, and fully mesh the VPCs with VPC peering so that every application can reach every other application directly.
- E. Use the default VPC in each newly vended account for migrated workloads, because default VPCs are created automatically and already include internet access for every Availability Zone.
- F. Use Amazon VPC IP Address Manager (IPAM) with Regional and OU-level pools, excluding on-premises ranges, shared from the network account so that every new VPC receives a non-overlapping CIDR.

### Question 17
A travel company is cutting over a customer-facing web application from its data center to AWS. The front end moves to EC2 behind an ALB, and the database moves to Amazon Aurora PostgreSQL through AWS DMS full load and CDC from the on-premises PostgreSQL database. The public record `www.example.com` is hosted in Amazon Route 53 as an A record with a TTL of 86,400 seconds, pointing to the data center's public IP. The cutover window is two hours on Saturday. For 48 hours after cutover, the business must be able to roll back to the data center within 30 minutes with no loss of transactions written on AWS.

Which combination of actions meets these requirements? **(Select TWO.)**

- A. At least 24 hours (one old TTL) before the window, lower the record's TTL to 60 seconds. At cutover, change the record to point to the ALB, and raise the TTL again only after the rollback period ends.
- B. At the start of the cutover window, lower the record's TTL to 60 seconds and immediately change it to point to the ALB, so that all resolvers pick up the new address within one minute.
- C. Just before opening traffic to AWS, start a reverse AWS DMS CDC-only task from Aurora back to the on-premises database at the cutover position. Keep it running through the rollback period so rollback only repoints DNS.
- D. Immediately after cutover, decommission the on-premises database to prevent split-brain writes. If rollback is needed, restore the latest Aurora snapshot to the data center and repoint DNS.
- E. Configure Route 53 failover routing with the ALB as primary and the data center as secondary, keeping both databases writable so that health checks automatically roll traffic back if the AWS stack degrades.

### Question 18
After a fast rehost, a SaaS company runs these on self-managed EC2 instances:

- a MySQL primary with two replicas and custom failover scripts
- a Redis cluster used for user sessions and caching
- an Apache ActiveMQ broker pair whose Java clients use JMS over OpenWire and STOMP.

The operations team spends most of its time on patching, failover testing, and late-night broker recoveries. Leadership wants to cut operational overhead and improve resilience across Availability Zones within one quarter. Application code changes must be limited to configuration (endpoints and credentials).

Which approach BEST meets these requirements?

- A. Move MySQL to Aurora Serverless v2, store sessions in Amazon DynamoDB with TTL instead of Redis, and replace ActiveMQ with Amazon SQS queues and Amazon SNS topics using the AWS SDK.
- B. Move MySQL to Amazon RDS for MySQL Multi-AZ (or Aurora MySQL), Redis to Amazon ElastiCache with Multi-AZ automatic failover, and ActiveMQ to an Amazon MQ for ActiveMQ active/standby broker.
- C. Keep the EC2-based components but automate patching with AWS Systems Manager Patch Manager, put each tier in an Auto Scaling group across Availability Zones, and script broker recovery with Systems Manager Automation runbooks.
- D. Move MySQL to Amazon RDS for MySQL Multi-AZ, Redis to Amazon MemoryDB, and replace ActiveMQ with Amazon MSK, updating the Java clients to use Kafka producers and consumers.

### Question 19
A manufacturer has migrated most workloads to an AWS Region about 900 km from its main plant. The plant's manufacturing execution system (MES) must stay on-premises because it controls shop-floor equipment over local industrial networks. The MES database was moved to Amazon Aurora MySQL in the Region. Since then, the MES has slowed badly: it is very chatty, issuing thousands of small queries per transaction, and needs database round-trip latency under 5 ms. A test over a new Direct Connect connection still measured more than 10 ms. There is no AWS Local Zone in the plant's metro area. The company wants AWS-managed database operations and a consistent AWS toolset.

Which approach BEST meets the latency requirement?

- A. Upgrade the Direct Connect connection to 100 Gbps with MACsec and add a second connection at a different location, so the higher bandwidth reduces round-trip time between the MES and Aurora.
- B. Deploy Amazon ElastiCache in the Region as a read-through cache in front of Aurora MySQL and change the MES connection string to query the cache endpoint first.
- C. Put AWS Global Accelerator in front of the Aurora cluster endpoint so that MES traffic enters the AWS global network at the nearest edge location and reaches the database with lower latency.
- D. Install an AWS Outposts rack at the plant and move the MES database to Amazon RDS for MySQL on Outposts, managed from the Region over a service link on Direct Connect.

### Question 20
Three months after migrating 600 servers to Amazon EC2, a retailer reviews its AWS bill. The instances were sized 1:1 from on-premises specifications. CloudWatch shows average CPU utilization of 8% across most of the fleet, and memory metrics are not yet collected. The usage pattern is now stable. Over the next 12–18 months, the company plans to move many workloads to Amazon ECS on AWS Fargate and AWS Lambda, and to adopt AWS Graviton where it can. Finance wants the largest sustainable savings without locking into instance families or sizes that will change.

Which combination of actions meets these requirements? **(Select TWO.)**

- A. Install the CloudWatch agent to collect memory metrics, then use AWS Compute Optimizer recommendations to downsize over-provisioned instances and move compatible workloads to Graviton instance types before making any commitment.
- B. Immediately purchase three-year Standard Reserved Instances for every running instance type and size to lock in the maximum discount on the current fleet.
- C. Purchase three-year EC2 Instance Savings Plans for the instance families currently in use, sized to the current hourly On-Demand spend of the whole fleet.
- D. After rightsizing has stabilized, buy Compute Savings Plans sized to the steady-state baseline from Cost Explorer recommendations. Coverage then follows usage across EC2 families, Regions, Fargate, and Lambda.
- E. Convert the whole fleet to Spot Instances with capacity-optimized allocation, because stable utilization makes interruptions unlikely and Spot gives the deepest discount.

---

## Section 2 — Answer key

| Q | Answer | Domain / Task | Topic |
|---|---|---|---|
| 1 | A, C, E | D4 / 4.1 | Choosing among the 7 Rs for a portfolio |
| 2 | B | D4 / 4.1 | Application Discovery Service: Agentless Collector vs Discovery Agent |
| 3 | D | D4 / 4.1 | Migration Evaluator business case / TCO with license modeling |
| 4 | C | D4 / 4.2 | AWS Transform MGN: private-IP replication over DX, launch templates, test vs cutover |
| 5 | A | D4 / 4.2 | DMS full load + CDC with data validation, MySQL → Aurora MySQL |
| 6 | B | D4 / 4.3 | SQL Server → Aurora PostgreSQL with Babelfish (vs DMS Schema Conversion) |
| 7 | A, D | D2 / 2.1 | DataSync (NFS → EFS) + Transfer Family (partner SFTP) |
| 8 | B, E | D2 / 2.4 | DFS file servers → FSx for Windows Multi-AZ with AD, DataSync |
| 9 | D | D2 / 2.1 | NetApp → FSx for NetApp ONTAP with SnapMirror |
| 10 | C | D4 / 4.2 | VMware relocate under a deadline: Amazon EVS + HCX |
| 11 | A | D4 / 4.4 | Mainframe: automated refactor (AWS Transform for mainframe / Blu Age) vs replatform |
| 12 | C | D2 / 2.1 | Strangler fig with ALB path rules and weighted target groups |
| 13 | D | D3 / 3.1 | App2Container: Java/.NET → ECS on Fargate |
| 14 | C, E | D1 / 1.5 | SQL Server BYOL on Dedicated Hosts + License Manager |
| 15 | A | D1 / 1.1 | 40 TB DB over thin bandwidth: offline bulk load + DMS CDC from SCN |
| 16 | B, C, F | D1 / 1.4 | Control Tower landing zone + hub network + IPAM before mass migration |
| 17 | A, C | D2 / 2.1 | Cutover DNS TTL strategy and rollback with reverse replication |
| 18 | B | D3 / 3.1 | Post-migration move to managed services (RDS, ElastiCache, Amazon MQ) |
| 19 | D | D1 / 1.1 | Hybrid latency during migration: Outposts (RDS on Outposts) vs DX |
| 20 | A, D | D3 / 3.5 | Post-migration rightsizing, then Compute Savings Plans |

**Letter distribution (single-answer):** A ×3, B ×3, C ×3, D ×4. Multi-select: Q1, Q7, Q8, Q14, Q16, Q17, Q20.

---

## Section 3 — Detailed solutions

### Q1 — Answer: A, C, E
**Decisive keywords:** "already signed an enterprise subscription for a SaaS" · "no logins in nine months" · "cannot rewrite code before the exit" · "change freeze… must not be modified or moved" · "vendors certify only the current OS builds" · "small operations team" · "lowest-risk".

**Why correct**
- **A — Repurchase:** the replacement product is already bought. Moving to SaaS removes the workload from the migration scope entirely.
- **C — Retire:** discovery shows no use. Typically 10–20% of a portfolio can be retired, which cuts migration cost and licensing. Confirm with the owner and archive outputs to S3 (lifecycle to Glacier storage classes) for retention.
- **E — Rehost:** COTS software with vendor-certified OS builds is the classic lift-and-shift case. Block-level replication with AWS Transform MGN keeps the OS identical, so vendor support is preserved, and waves let a small team move hundreds of servers.

**Why the others are wrong**
- **B:** the freeze forbids changing or moving the system, and rehosting is still a move. The correct R is **Retain** (revisit after the freeze). Keep a small footprint, such as a colocation cage, or negotiate a lease extension for that one system.
- **D:** refactoring to Lambda and DynamoDB is a rewrite. The stem says no code rewrite before the exit. The fitting R is **Replatform** (swap the app server for Tomcat on a managed platform such as Elastic Beanstalk or ECS, with no business-logic changes).
- **F:** retaining the order service conflicts with the full data-center exit. Replatform meets the deadline without a rewrite.

**Concept to remember:** Match each workload to the *least-change R that satisfies its constraint*. A business decision already made means Repurchase, no usage means Retire, a freeze means Retain, vendor-certified COTS means Rehost, and "swap the runtime, keep the code" means Replatform.

**References**
- https://docs.aws.amazon.com/prescriptive-guidance/latest/large-migration-guide/migration-strategies.html
- https://docs.aws.amazon.com/prescriptive-guidance/latest/strategy-migration/introduction.html

---

### Q2 — Answer: B
**Decisive keywords:** "300 physical servers" · "running processes" · "time-series" · "query with SQL in Amazon Athena" · "prohibits installing… agents on 120 appliance VMs" · "LEAST effort".

**Why correct:** The **Agentless Collector** is an OVA deployed once per vCenter. It collects VMware VM inventory, utilization, and, through its network data collection module, server TCP connections, with no per-server installation. It cannot see inside VMs for **running processes**, does not support **physical servers**, and cannot export **time-series** data or send data to Athena. The **Discovery Agent** collects processes, inbound and outbound connections, and roughly 15-second time-series data, and it supports data exploration in Athena. Use agents only where that depth is needed (the physical servers and the 40 critical VMs) and the collector everywhere else, including the appliance VMs where agents are banned.

**Why the others are wrong**
- **A:** the Agentless Collector does not discover physical servers, does not collect running processes, and does not export time-series data or send it to Athena.
- **C:** this breaks the security rule (no agents on appliance VMs) and adds the effort of installing and maintaining 1,100 agents.
- **D:** RVTools and import templates are single snapshots. They contain no network-connection data, no processes, and no time-series data.

**Concept to remember:** Agentless means one deployment per vCenter, VMware only, and no process data. Agent-based means per server, any physical or virtual Linux/Windows server, with processes, time series, and Athena. Use both together. (Application Discovery Service and Migration Hub closed to new customers on **Nov 7, 2025**; AWS Transform now provides agentless and agent-based discovery, dependency mapping, and wave planning. The exam still tests the ADS collector-vs-agent distinction.)

**References**
- https://docs.aws.amazon.com/application-discovery/latest/userguide/what-is-appdiscovery.html
- https://docs.aws.amazon.com/application-discovery/latest/userguide/agentless-collector-gs-network-data-collection.html
- https://docs.aws.amazon.com/application-discovery/latest/userguide/application-discovery-service-availability-change.html

---

### Q3 — Answer: D
**Decisive keywords:** "directional business case within four weeks" · "actual measured utilization, not nameplate" · "BYOL and License Included for Windows Server and SQL Server" · "will not deploy software on individual servers" · "RVTools and CMDB exports already exist".

**Why correct:** **Migration Evaluator** builds data-driven business cases. It uses an **agentless collector** (one Windows Server VM, with no agents on hypervisors or servers) or ingests existing inventory and utilization files (RVTools, CMDB, third-party tools). It right-sizes to EC2 from measured utilization and models Microsoft licensing: BYOL on Dedicated Hosts, Dedicated Instances, or shared tenancy versus License Included. Quick Insights gives a fast projection, and a full Business Case report is produced with an AWS migration specialist. AWS now offers the same capability as **AWS Transform assessment**, which added what-if scenarios and TCO features in 2026.

**Why the others are wrong**
- **A:** Pricing Calculator works from specifications, so the estimate is not right-sized. It also forces License Included everywhere, ignores the BYOL comparison, and takes a lot of manual work for 2,400 servers.
- **B:** Cost Explorer forecasts from *existing AWS spend*. A pilot is slow, does not represent the whole estate, and cannot compare against on-premises TCO.
- **C:** it breaks the "no software on individual servers" constraint, and a home-built spreadsheet adds effort and risk.

**Concept to remember:** "Business case / TCO / right-sizing from real utilization / Microsoft license modeling / fast, no agents" points to Migration Evaluator (now AWS Transform assessment).

**References**
- https://aws.amazon.com/migration-evaluator/faqs/
- https://docs.aws.amazon.com/transform/latest/userguide/transform-app-assessments.html

---

### Q4 — Answer: C
**Decisive keywords:** "forbids replication traffic over the public internet" · "outbound HTTPS only to approved private endpoints" · "non-disruptive functional test" · "specific subnets, instance types, security groups" · "wave-level rollback until sign-off".

**Why correct**
- **Private replication:** by default, MGN replication servers receive public IPs and data travels over the internet (encrypted). **Use private IP for data replication** routes the TCP 1500 replication stream to the staging-area subnet over VPN, Direct Connect, or peering. The option does not create the private path itself, so it must already exist.
- **Private control traffic:** agents and replication servers also need TCP 443 to the MGN API (plus S3 and EC2 endpoints). **Interface VPC endpoints** (PrivateLink) keep that traffic private as well.
- **Launch settings:** each source server gets an auto-created **EC2 launch template**. Set the subnet, instance type, and security groups there. If MGN instance-type right-sizing is turned on, it can override the template's instance type, so turn it off when you pin types.
- **Lifecycle:** launch test instances (isolated test subnet) → mark ready for cutover → launch cutover instances → **finalize cutover** only after sign-off. Until you finalize, source replication continues, so rollback stays possible.

**Why the others are wrong**
- **A:** default settings replicate over the public internet. Skipping tests violates the test requirement, and editing the templates after cutover is backwards.
- **B:** skipping test launches violates the requirement. Finalizing immediately stops replication and removes the rollback window.
- **D:** VM Import/Export is a one-time image copy with no continuous replication. It forces long freezes and repeated exports, has no test/cutover orchestration, and leaves the MGN API traffic requirement unaddressed.

**Concept to remember:** MGN private-path checklist: Use private IP (TCP 1500 over DX or VPN), PrivateLink endpoints for TCP 443, a dedicated staging subnet, launch templates for target placement, and test → ready → cutover → finalize.

**References**
- https://docs.aws.amazon.com/mgn/latest/ug/replication-server-settings.html
- https://docs.aws.amazon.com/mgn/latest/ug/Network-Requirements.html
- https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/connect-to-application-migration-service-data-and-control-planes-over-a-private-network.html
- https://docs.aws.amazon.com/mgn/latest/ug/ec2-launch.html
- https://docs.aws.amazon.com/mgn/latest/ug/launching-test-gs.html

---

### Q5 — Answer: A
**Decisive keywords:** "≤ 15 minutes of write downtime" · "every row in every table matches" · "without custom comparison tooling" · "all tables have primary keys".

**Why correct:** A **full load + CDC** task copies the existing data and then applies ongoing changes from MySQL **row-based binlogs** (binlog_format=ROW and enough binlog retention are prerequisites), so the source stays online until the final switch. **AWS DMS data validation** compares source and target rows (tables need a primary key or unique index) and reports mismatches in the table statistics and the `awsdms_validation_failures_v1` table. That is the built-in, row-level evidence the auditors asked for. At cutover, stop writes, wait for CDC latency to reach zero and validation to show no mismatches, then repoint the application. The write outage is minutes.

**Why the others are wrong**
- **B:** mysqldump plus restore of 3 TB means hours of downtime, and row counts are not row-level validation.
- **C:** Aurora read replicas can be created from **Amazon RDS for MySQL**, not from an on-premises MySQL primary. Aurora can replicate *in* from external MySQL through binlog replication, but that is not a native "Aurora replica", and it still provides no validation report.
- **D:** XtraBackup physical restore plus binlog replication is a valid low-downtime path, but row counts do not prove row-level equality. Meeting the audit requirement would need custom tooling.

**Concept to remember:** "Minimal downtime + proof the data matches" points to DMS full load + CDC **with validation enabled**. For homogeneous MySQL moves, DMS homogeneous data migrations or XtraBackup are faster options for the initial load, but validation is the deciding requirement here.

**References**
- https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Validating.html
- https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.MySQL.html
- https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Task.CDC.html

---

### Q6 — Answer: B
**Decisive keywords:** "SQL Server client drivers… TDS" · "600 T-SQL stored procedures" · "will not rewrite the data-access layer or stored procedures" · "stop paying for SQL Server licenses" · "fewest application changes".

**Why correct:** **Babelfish for Aurora PostgreSQL** adds a **TDS endpoint (port 1433)** that understands T-SQL and SQL Server wire semantics. Existing drivers and most T-SQL keep working, often with only a connection-string change, while the engine underneath is license-free PostgreSQL. **Babelfish Compass** reports which T-SQL features are supported before you commit. The AWS-documented flow is: generate DDL from SQL Server, adjust it with Compass's help, create objects through the TDS endpoint, then load data with **AWS DMS**. Use the Aurora PostgreSQL endpoint as the DMS target for full load + CDC, which keeps downtime well within one hour.

**Why the others are wrong**
- **A:** DMS Schema Conversion, the managed successor built on the AWS SCT engine, supports SQL Server → Aurora PostgreSQL with generative-AI help. However, it produces **native PL/pgSQL** and requires PostgreSQL drivers, which is exactly the rewrite the ISV refuses.
- **C:** RDS for SQL Server License Included still charges for SQL Server licenses inside the instance price, so the goal of leaving SQL Server licensing is not met.
- **D:** Aurora PostgreSQL cannot restore SQL Server `.bak` files. Native backup/restore from S3 exists only for RDS for SQL Server.

**Concept to remember:** Heterogeneous move where the application cannot change → Babelfish (TDS + T-SQL on Aurora PostgreSQL) + Compass + DMS. Application can be modernized → DMS Schema Conversion / SCT to native PostgreSQL + DMS.

**References**
- https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/babelfish.html
- https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/babelfish-migration.html
- https://docs.aws.amazon.com/dms/latest/userguide/CHAP_SchemaConversion.html

---

### Q7 — Answer: A, D
**Decisive keywords:** "180 TB NFS… Amazon EFS… cutover in a weekend" · "partners cannot change hostname, client configuration, or SSH keys" · "land in Amazon S3" · "no file servers or SFTP servers to patch".

**Why correct**
- **A:** **DataSync** is the managed online migration service for NFS/SMB/HDFS/object → S3, EFS, or FSx. It does incremental transfers, in-line integrity verification, encryption, and bandwidth control, and a single task can fully use 10 Gbps. Seed ahead of time and sync incrementally, and the weekend cutover only moves the final delta.
- **D:** **AWS Transfer Family** is a managed SFTP/FTPS/FTP/AS2 endpoint backed by S3 or EFS. Service-managed users take the partners' existing SSH public keys. **Importing the existing host key** keeps the server fingerprint the partners already trust, and a DNS CNAME (or Route 53 record) keeps the hostname. Files land in S3 and can trigger EventBridge or Lambda.

**Why the others are wrong**
- **B:** S3 File Gateway is a hybrid access cache for on-premises clients, not a migration tool to EFS. The target in the stem is EFS, not S3 through NFS.
- **C:** DataSync is not an SFTP server for third parties. It moves data between storage locations.
- **E:** Volume Gateway presents block (iSCSI) volumes, not NFS shares. EBS snapshots cannot seed EFS.

**Concept to remember:** One-time or periodic bulk move means DataSync. Ongoing on-premises access to cloud storage means Storage Gateway. External partners speaking SFTP/FTPS/AS2 means Transfer Family.

**References**
- https://docs.aws.amazon.com/datasync/latest/userguide/what-is-datasync.html
- https://docs.aws.amazon.com/transfer/latest/userguide/what-is-aws-transfer-family.html
- https://docs.aws.amazon.com/transfer/latest/userguide/configuring-servers-change-host-key.html

---

### Q8 — Answer: B, E
**Decisive keywords:** "survive the loss of an Availability Zone automatically" · "existing on-premises AD forest" · "preserve NTFS permissions and ownership" · "avoid changing the UNC paths" · "minimize administration".

**Why correct**
- **B:** **FSx for Windows File Server Multi-AZ** is a WSFC-based active/standby pair across two AZs with synchronous replication and automatic failover (typically under 30 seconds) behind the same DNS name. It can join a **self-managed AD** over DX (or AWS Managed Microsoft AD with a trust). Adding the FSx shares as **folder targets in the existing DFS namespace** keeps `\\corp.example.com\shares\...` unchanged.
- **E:** **DataSync** from an SMB location to an FSx for Windows location copies **ownership, DACLs (and optionally SACLs)**, with incremental runs and a final sync at cutover.

**Why the others are wrong**
- **A:** DFS-R **is not supported** on Multi-AZ (or Single-AZ 2) file systems, and Multi-AZ already replicates across AZs natively.
- **C:** DFS-R is supported only on **Single-AZ 1**, not Single-AZ 2. Two file systems plus DFS-R also means more administration.
- **D:** FSx File Gateway is a low-latency on-premises cache for FSx shares, not a migration engine, and it has been closed to new customers since Oct 28, 2024.

**Concept to remember:** Multi-AZ FSx for Windows replaces DFS-R for availability. Keep **DFS Namespaces** to preserve paths, and use **DataSync** to keep ACLs.

**References**
- https://docs.aws.amazon.com/fsx/latest/WindowsGuide/high-availability-multiAZ.html
- https://docs.aws.amazon.com/fsx/latest/WindowsGuide/dfs-r.html
- https://docs.aws.amazon.com/fsx/latest/WindowsGuide/using-dfs-namespaces.html
- https://docs.aws.amazon.com/fsx/latest/WindowsGuide/self-managed-AD.html
- https://docs.aws.amazon.com/fsx/latest/WindowsGuide/migrate-files-to-fsx-datasync.html

---

### Q9 — Answer: D
**Decisive keywords:** "multi-protocol NFS and SMB" · "without losing ONTAP functionality or retained snapshots" · "avoid sending rehydrated data" · "SnapMirror license".

**Why correct:** **SnapMirror** to **FSx for NetApp ONTAP** is the AWS-recommended migration path. It replicates at block level, keeps data **deduplicated and compressed** in transit, and **preserves source snapshots**. Steps:
1. Create a **DP** (data protection) destination volume.
2. Collect the inter-cluster LIFs.
3. Set up **cluster peering**, then SVM peering. Every inter-cluster LIF must reach every peer LIF; the security group must allow ICMP and TCP 443, 10000, 11104, and 11105.
4. Create the relationship, `snapmirror initialize`, and schedule updates.
5. At cutover: final update → quiesce → **break** → mount.

FSx for ONTAP keeps NFS/SMB multi-protocol access, snapshots, and FlexClone.

**Why the others are wrong**
- **A:** DataSync copies files, not ONTAP snapshots. Deduplicated data is rehydrated in transit, and the 90 days of retained snapshots are lost.
- **B:** splitting by protocol breaks multi-protocol access and loses every ONTAP feature.
- **C:** SnapMirror destination volumes must be **DP (read-only)** until the relationship is broken. SnapMirror does not merge writes made on both sides.

**Concept to remember:** NetApp → AWS with ONTAP features or snapshots means FSx for ONTAP + SnapMirror (peer → DP volume → update → quiesce → break).

**References**
- https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/migrating-fsx-ontap-snapmirror.html

---

### Q10 — Answer: C
**Decisive keywords:** "nine months… facility closing" · "1,200 VMs… NSX" · "VMware-skilled team, VMware-integrated tools" · "portable VCF subscriptions" · "keep IP addresses, stretch Layer 2" · "modernize after the exit, not before".

**Why correct:** This is the **Relocate** R: move the hypervisor estate as is. **Amazon EVS** (GA August 2025) deploys VMware Cloud Foundation on EC2 bare-metal instances **inside your VPC**, uses portable VCF subscriptions, and can be self-managed or partner-managed. **VMware HCX** network extension stretches Layer 2 so VMs keep their IPs, and bulk migration or vMotion moves VMs with minimal downtime and no per-VM re-platforming. Tools, NSX policies, and runbooks are unchanged. EVS connects to on-premises through a **transit gateway** over DX or VPN; DX VIFs or VPNs that terminate directly in the EVS VPC are not supported. Modernization onto native AWS services can follow later.

**Why the others are wrong**
- **A:** MGN rehosting is valid in general, but it changes the operating model, discards NSX, and replaces the backup/DR tooling. For 1,200 VMs in nine months, that adds risk against the stated constraints.
- **B:** VM Import/Export is a one-off image conversion with no L2 extension and no continuous sync, so it means long downtime at scale and the same operating-model change.
- **D:** Outposts does not run customer-installed vSphere, and Outposts hardware does not move to a Region. It also keeps the company in the colocation facility that is closing.

**Concept to remember:** "Data-center exit deadline + keep VMware tools/skills/IPs" means Relocate: **Amazon EVS + HCX**. **VMware Cloud on AWS** is the other relocate target and appears in older questions. It is still sold by **Broadcom**, but AWS stopped reselling it on April 30, 2024. Either is the right *pattern* when offered.

**References**
- https://docs.aws.amazon.com/evs/latest/userguide/what-is-evs.html
- https://docs.aws.amazon.com/evs/latest/userguide/migrate-evs-hcx.html
- https://aws.amazon.com/vmware/faqs/

---

### Q11 — Answer: A
**Decisive keywords:** "COBOL developers retire… cannot hire" · "Java-based… maintained by new graduates" · "functionally equivalent… side-by-side testing" · "manual rewrite failed" · "highly automated" · "30 months".

**Why correct:** The **Automated Refactor** pattern, now **AWS Transform for mainframe** (formerly AWS Blu Age), converts the whole legacy stack (COBOL, CICS, JCL, VSAM, Db2) into a **Java** application (an Angular front end and an API-enabled Java back end) with a modern data layer such as Aurora PostgreSQL, while keeping **functional equivalence**. It removes the COBOL skills dependency, is far more automated than a manual rewrite, and fits a 30-month window.

**Why the others are wrong**
- **B:** **Replatform** with Rocket Software (formerly Micro Focus) keeps the COBOL source, so it does not solve the skills problem. It is the right answer when the goal is "keep COBOL and skills, exit the mainframe fast".
- **C:** MGN replicates x86 Windows and Linux servers. It cannot replicate z/OS.
- **D:** a manual multi-year rewrite misses the 30-month deadline and repeats the approach that already failed.

**Concept to remember:** Mainframe: "keep COBOL, quickest exit" means **replatform** (Rocket). "Leave COBOL for Java, automated" means **refactor** (AWS Transform for mainframe / Blu Age). Availability note: the AWS Mainframe Modernization **managed runtime** closed to new customers on Nov 7, 2025, and the **self-managed experience** has since closed to new customers too. AWS points to AWS Transform and vendor-direct offerings. The refactor-vs-replatform decision is still the tested concept.

**References**
- https://docs.aws.amazon.com/m2/latest/userguide/what-is-m2.html
- https://docs.aws.amazon.com/m2/latest/userguide/mainframe-modernization-availability-change.html

---

### Q12 — Answer: C
**Decisive keywords:** "incrementally" · "no client or DNS changes" · "small share of catalog traffic first" · "instant rollback for any single function" · "rejected big-bang".

**Why correct:** The **strangler fig** pattern puts a routing façade in front of the monolith and moves functionality out route by route. The existing **ALB** is that façade:
- The default action still goes to the monolith.
- A **path rule** for `/catalog/*` forwards to **weighted target groups**, for example monolith 90 / ECS catalog 10. Raise the weight as confidence grows.
- **Rollback** means setting the new target group's weight back to 0. The monolith is not redeployed and the domain does not change.

Amazon API Gateway can play the same façade role for APIs. During coexistence, the new service owns its data and stays in sync through events or CDC.

**Why the others are wrong**
- **A:** this is a big-bang rewrite with DNS weighting at the very end. It is not incremental and has no per-function rollback.
- **B:** splitting the shared database before extracting code is high-risk and delays value. Strangler extracts behaviour route by route and splits data alongside each service.
- **D:** calling both back ends for every request duplicates side effects such as orders and payments, and it is not a routing or rollback control.

**Concept to remember:** Strangler fig means a façade (ALB path rules / API Gateway) + per-route weighted shifting + per-route rollback. The monolith keeps the default route.

**References**
- https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/strangler-fig.html
- https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html

---

### Q13 — Answer: D
**Decisive keywords:** "Java (Tomcat/JBoss on Linux) and ASP.NET (IIS)" · "no source code changes" · "small team, little container experience" · "generate Dockerfiles, images, task definitions, CI/CD templates".

**Why correct:** **App2Container** runs on the application server or a worker machine and needs **no source code**:
1. It inventories running **Java (Linux)** and **ASP.NET (Windows)** applications.
2. It analyzes their dependencies and generates a **Dockerfile**.
3. It builds and pushes the image to **Amazon ECR**.
4. It generates **ECS task definitions** and CloudFormation (or EKS/App Runner artifacts), and optionally a **CodePipeline** CI/CD pipeline.

ECS on Fargate supports Linux and Windows Server containers, which covers both stacks with no hosts to manage.

**Why the others are wrong**
- **A:** porting .NET Framework to modern .NET is a code change, which the stem forbids, and hand-writing 100 Dockerfiles is heavy effort.
- **B:** self-managed EKS node groups plus hand-written Helm charts add operational burden and need skills the team does not have.
- **C:** Lambda does not run Windows containers or IIS-hosted .NET Framework applications. Long-running app servers are also a poor fit for Lambda.

**Concept to remember:** "Containerize existing Java/.NET apps without code changes, generate ECS/EKS artifacts and pipelines" means App2Container. Availability note: A2C closed to new customers on **Nov 7, 2025**, and AWS Transform (with its .NET and containerization capabilities) is the successor. Expect A2C on SAP-C02.

**References**
- https://docs.aws.amazon.com/app2container/latest/UserGuide/what-is-a2c.html
- https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html

---

### Q14 — Answer: C, E
**Decisive keywords:** "SQL Server 2017 / Windows Server 2016… bought in 2017" · "Software Assurance not renewed" · "continuous evidence… never exceeds entitlements" · "does not want to allocate, track, or release dedicated hardware by hand".

**Why correct**
- **C:** without Software Assurance there is no **License Mobility**. Microsoft licenses **purchased before October 1, 2019** (for versions released before that date) can still be deployed on **EC2 Dedicated Hosts**. Windows Server BYOL always requires Dedicated Hosts. Dedicated Hosts also expose the physical sockets and cores that per-core licensing counts.
- **E:** **AWS License Manager** license configurations (core- or socket-based, with hard limits) track usage and block launches that would exceed entitlements, which gives the auditors their evidence. A **host resource group** lets License Manager **allocate, release, and recover Dedicated Hosts automatically** as instances launch and terminate.

**Why the others are wrong**
- **A:** License Mobility needs active Software Assurance, and Windows Server is not eligible for License Mobility at all.
- **B:** Dedicated Instances run on single-tenant hardware but do **not** give socket/core visibility or host affinity, so they do not satisfy these BYOL terms.
- **D:** standard RDS for SQL Server is License Included only. It has no BYOL option.

**Concept to remember:** Microsoft BYOL without SA (pre-10/1/2019 licenses) means **Dedicated Hosts**. For compliance and automation, add **License Manager** license configurations + **host resource groups**.

**References**
- https://aws.amazon.com/windows/faq/
- https://docs.aws.amazon.com/license-manager/latest/userguide/host-resource-groups.html

---

### Q15 — Answer: A
**Decisive keywords:** "40 TB" · "three weeks" · "200 Mbps VPN shared with production" · "DX lead time 10 weeks" · "≤ 2 h cutover" · "Enterprise Support" · "never ordered Snow Family devices" · "owns NVMe arrays".

**Why correct:** The arithmetic: 40 TB × 8 ÷ 200 Mbps ≈ **18.5 days at 100% line rate**, and the link is shared, so an online full load cannot finish in time. Separate the **bulk load** from the **change stream**:
1. Run a Data Pump export consistent to a **recorded SCN**.
2. Copy it to the company's own NVMe arrays and upload it at an **AWS Data Transfer Terminal**, which has 100 Gbps connections and is available to Enterprise Support customers. The files land in S3.
3. Import into RDS for Oracle through **S3 integration**.
4. Start an **AWS DMS CDC-only task from that native SCN start point**.

Only the changes cross the 200 Mbps VPN. Keep archived redo logs long enough to cover the gap between the export and the start of CDC. Cutover is then a short stop-writes, drain, and switch.

**Why the others are wrong**
- **B:** the initial load alone needs ≈18.5 days at full line rate on a shared link. That misses the deadline and degrades production.
- **C:** **Snowball Edge has been closed to new customers since Nov 7, 2025**, and the company has never ordered Snow devices. (On older exam versions, "Snowball Edge + DMS CDC" is the textbook answer. If it is the only offline option offered, choose it.)
- **D:** Transfer Acceleration speeds up long-distance internet paths but cannot exceed the 200 Mbps uplink. A second full load also wastes the effort.

**Concept to remember:** Big database + thin pipe means **offline or alternate-path bulk seed + DMS CDC from a native start point** (SCN, LSN, or binlog position). Today the offline paths are Data Transfer Terminal, partner devices, or a temporary DX hosted connection when lead time allows; Snowball Edge applies only to existing customers.

**References**
- https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Task.CDC.html
- https://docs.aws.amazon.com/datatransferterminal/latest/userguide/what-is-dtt.html
- https://docs.aws.amazon.com/snowball/latest/developer-guide/snowball-edge-availability-change.html
- https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/oracle-s3-integration.html

---

### Q16 — Answer: B, C, F
**Decisive keywords:** "accounts per BU and environment" · "centrally enforced guardrails, tamper-resistant logging" · "single shared path to Direct Connect, centralized egress inspection" · "CIDRs never overlap" · "before mass migration".

**Why correct**
- **B:** **Control Tower** sets up a well-architected landing zone: AWS Organizations, **Log Archive** and **Audit** accounts, IAM Identity Center, an OU structure, preventive (SCP/RCP), detective (Config), and proactive controls, and **Account Factory** (or AFT) for account vending.
- **C:** a hub **network account** owns the **transit gateway** attached to the **Direct Connect gateway**, plus a centralized inspection/egress VPC. Sharing the transit gateway through **AWS RAM** gives every workload account one controlled path.
- **F:** **VPC IPAM** pools (Regional and per-OU) that exclude on-premises ranges guarantee non-overlapping VPC CIDRs. Routing through the transit gateway needs that.

**Why the others are wrong**
- **A:** a single shared account cannot provide BU/environment isolation, separate blast radii, or central guardrails. Retrofitting later is far harder after 400 applications land.
- **D:** per-VPC VGWs and private VIFs plus a full mesh of peering connections does not scale (n² connections, no transitive routing) and prevents centralized inspection.
- **E:** default VPCs use the same 172.31.0.0/16 in every account, which guarantees overlap. They also have public subnets with internet routes, which bypasses central egress.

**Concept to remember:** Landing zone first: **Control Tower** (accounts, guardrails, logging) + a **hub-and-spoke TGW in a network account shared through RAM** + **IPAM**. Then start the migration waves.

**References**
- https://docs.aws.amazon.com/controltower/latest/userguide/what-is-control-tower.html
- https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/welcome.html
- https://docs.aws.amazon.com/vpc/latest/ipam/what-it-is-ipam.html

---

### Q17 — Answer: A, C
**Decisive keywords:** "TTL of 86,400 seconds" · "two-hour window" · "roll back within 30 minutes" · "no loss of transactions written on AWS".

**Why correct**
- **A:** resolvers cache a record for its **current** TTL. Lower the TTL to 60 seconds **at least one old TTL (24 h) in advance** so every cache already holds the short TTL when you flip the record. Keep it low through the rollback window, then raise it again to reduce query volume. (If you switch to an alias A record to the ALB, Route 53 uses the target's TTL, which is 60 seconds for ELB.)
- **C:** a **reverse DMS CDC task** (Aurora → on-premises, CDC-only, started from the cutover position) keeps the old database current with every transaction written on AWS. Rollback becomes a DNS change with no data loss. Only the AWS side takes writes; the reverse task is a safety net, not multi-master.

**Why the others are wrong**
- **B:** lowering the TTL at cutover time does nothing for resolvers that cached the 24-hour record. Some clients would keep hitting the data center for up to a day.
- **D:** decommissioning the source removes the fast rollback path. Restoring a snapshot to on-premises cannot meet 30 minutes, and Aurora snapshots cannot be restored on-premises.
- **E:** two writable databases behind automatic failover create split-brain. Writes made on one side are lost when traffic fails over.

**Concept to remember:** Cutover runbook: **lower TTL ≥ one old TTL early → freeze → drain CDC → flip DNS → keep reverse replication for the rollback window → restore TTL**.

**References**
- https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-values-basic.html
- https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Task.CDC.html

---

### Q18 — Answer: B
**Decisive keywords:** "self-managed MySQL with custom failover" · "Redis for sessions and caching" · "ActiveMQ… JMS over OpenWire and STOMP" · "cut operational overhead, Multi-AZ resilience" · "code changes limited to configuration".

**Why correct:** Each component maps to a **protocol-compatible managed service**, so only endpoints and credentials change:
- **RDS for MySQL Multi-AZ** (or Aurora MySQL) handles patching, backups, and automatic failover.
- **ElastiCache** (Redis OSS / Valkey) with **Multi-AZ automatic failover** replaces the self-managed Redis cluster.
- **Amazon MQ for ActiveMQ** in an **active/standby** deployment across two AZs supports the existing JMS, OpenWire, STOMP, AMQP, and MQTT clients.

This is the classic post-rehost **replatform** step.

**Why the others are wrong**
- **A:** DynamoDB sessions and SQS/SNS in place of ActiveMQ require application code changes (SDK calls instead of Redis and JMS clients).
- **C:** the components remain self-managed. Automation helps, but patching, upgrades, and failover are still the team's job.
- **D:** replacing ActiveMQ with MSK (Kafka) forces client rewrites to Kafka APIs. MemoryDB works, but the stem asks for the least change.

**Concept to remember:** "Reduce ops, no code change" means a **wire-compatible managed equivalent**: MySQL → RDS/Aurora, Redis → ElastiCache, ActiveMQ/RabbitMQ → **Amazon MQ**, Kafka → MSK.

**References**
- https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html
- https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/AutoFailover.html
- https://docs.aws.amazon.com/amazon-mq/latest/developer-guide/amazon-mq-broker-architecture.html

---

### Q19 — Answer: D
**Decisive keywords:** "MES must stay on-premises" · "900 km" · "chatty, < 5 ms round trip" · "DX still more than 10 ms" · "no Local Zone" · "AWS-managed database operations".

**Why correct:** Bandwidth does not reduce latency. Light in fiber covers about 200 km per millisecond, so 900 km each way costs **≈9 ms round trip before any equipment delay**. The only fix is to put the database next to the application. **AWS Outposts** brings AWS infrastructure on-premises, and **Amazon RDS on Outposts** (MySQL, PostgreSQL, SQL Server) gives managed backups, patching, and monitoring from the same AWS console and APIs. The Outpost connects to its parent Region over a service link, preferably on DX.

**Why the others are wrong**
- **A:** more bandwidth and MACsec do not change propagation delay. RTT stays around 9–10 ms or more.
- **B:** a cache in the Region still sits 900 km away. It also does not help write-heavy, chatty transactions.
- **C:** Global Accelerator speeds up internet users' entry into the AWS network. It does not shorten an on-premises-to-Region path that already uses DX.

**Concept to remember:** Latency is physics. If an on-premises app needs single-digit-millisecond access, bring the data to it (**Outposts / RDS on Outposts**, or a **Local Zone** where one exists) or move the app and database together.

**References**
- https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-on-outposts.html
- https://docs.aws.amazon.com/outposts/latest/userguide/what-is-outposts.html

---

### Q20 — Answer: A, D
**Decisive keywords:** "sized 1:1" · "8% CPU" · "memory not yet collected" · "stable" · "moving to Fargate, Lambda, Graviton" · "without locking into instance families or sizes".

**Why correct**
- **A:** **rightsize first**. Compute Optimizer needs memory metrics from the CloudWatch agent for accurate EC2 recommendations. Downsizing and moving to Graviton where compatible shrinks the baseline before any commitment.
- **D:** then buy **Compute Savings Plans** against the new steady-state baseline. They apply automatically across instance families, sizes, Regions, and OS, and also to **Fargate and Lambda**, so the discount follows the planned modernization.

**Why the others are wrong**
- **B:** Standard RIs lock in today's oversized types. Committing before rightsizing means paying for waste.
- **C:** EC2 Instance Savings Plans are tied to an instance family in a Region and do not cover Fargate or Lambda. Sizing to the current oversized spend over-commits.
- **E:** Spot instances can be interrupted with a two-minute warning, whatever the utilization. That does not suit general stateful workloads.

**Concept to remember:** Post-migration FinOps order: **measure → rightsize (Compute Optimizer, Graviton) → commit to the stable baseline with Compute Savings Plans → use Spot only for interruption-tolerant work**.

**References**
- https://docs.aws.amazon.com/compute-optimizer/latest/ug/what-is-compute-optimizer.html
- https://docs.aws.amazon.com/savingsplans/latest/userguide/what-is-savings-plans.html

---

## Score interpretation

- **≥ 16/20 — ready.** Your Domain 4 judgment is at exam level. Keep timing practice going with mixed-domain papers.
- **13–15 — review weak domains.** Use the answer key's Domain/Task column to find patterns (for example, missing database-migration or file-storage questions) and re-read those chapter sections.
- **< 13 — re-study the linked chapters**, then retake this paper in a few days:
  - Migration strategy, discovery, MGN, DMS, mainframe, VMware, App2Container, cutover: [../13-Migration-and-Modernization.md](../13-Migration-and-Modernization/13-Migration-and-Modernization.md)
  - DataSync, Transfer Family, FSx for Windows, FSx for ONTAP, offline transfer: [../08-Storage-and-Data-Transfer.md](../08-Storage-and-Data-Transfer/08-Storage-and-Data-Transfer.md)
  - Aurora, Babelfish, RDS Multi-AZ, ElastiCache, RDS on Outposts: [../09-Databases-and-Caching.md](../09-Databases-and-Caching/09-Databases-and-Caching.md)
  - Control Tower, OUs, guardrails, account vending: [../02-Multi-Account-Governance.md](../02-Multi-Account-Governance/02-Multi-Account-Governance.md)
  - Direct Connect, Transit Gateway, IPAM, hybrid latency: [../04-Networking-VPC-and-Hybrid-Connectivity.md](../04-Networking-VPC-and-Hybrid-Connectivity/04-Networking-VPC-and-Hybrid-Connectivity.md)
  - ECS/Fargate, strangler-fig routing, containerization: [../07-Compute-Containers-and-Serverless.md](../07-Compute-Containers-and-Serverless/07-Compute-Containers-and-Serverless.md)
  - Amazon MQ vs SQS/SNS/MSK: [../10-Application-Integration-and-Event-Driven.md](../10-Application-Integration-and-Event-Driven/10-Application-Integration-and-Event-Driven.md)
  - BYOL / License Manager, rightsizing, Savings Plans: [../16-Cost-Optimization-and-FinOps.md](../16-Cost-Optimization-and-FinOps/16-Cost-Optimization-and-FinOps.md)

> [← Practice papers index](README.md) · [Study guide index](../00-README-Start-Here.md)

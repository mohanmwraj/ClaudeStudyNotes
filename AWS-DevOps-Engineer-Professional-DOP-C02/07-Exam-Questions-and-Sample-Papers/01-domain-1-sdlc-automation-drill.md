# Domain 1 Drill · SDLC Automation (20 questions)

Original exam-style questions for tasks 1.1–1.4. Answer each one before opening its explanation, then read **every** option's explanation. The notes for this domain are in [01-SDLC-Automation](../01-SDLC-Automation/).

---

### Q1 · Task 1.1 · Single answer

A development team stores an application in a GitHub organization and uses an AWS CodePipeline pipeline connected through AWS CodeConnections. The pipeline currently runs on every commit to the `main` branch. The release manager wants production releases to start only when a Git tag that matches `release-*` is pushed, with no change to how the team commits. The solution must require the LEAST operational overhead.

What should a DevOps engineer do?

- **A.** Create an AWS Lambda function that receives GitHub webhooks, checks whether the pushed reference is a `release-*` tag, and calls `StartPipelineExecution` when it is.
- **B.** Create a second pipeline that polls the repository every minute, and add a CodeBuild action that exits early unless the source revision is a `release-*` tag.
- **C.** Convert the pipeline to the V2 pipeline type and configure a trigger with a Git tag filter that includes `release-*`, removing the branch push trigger.
- **D.** Configure a CodeBuild webhook with a filter group for `release-*` tags that runs a build whose buildspec calls `aws codepipeline start-pipeline-execution`.

<details><summary>Answer</summary>

**Answer: C**

**Why (P12, P1):** V2 pipelines support native trigger filters on Git tags, branches and file paths. The event-driven start and the filtering are configuration, with no code to own.

- **A** — wrong: works, but it adds a custom webhook endpoint and function to build, secure and maintain.
- **B** — wrong: polling is slower and wasteful, and a second pipeline duplicates the configuration.
- **C** — correct: native tag-based triggering is exactly the V2 trigger feature.
- **D** — wrong: works, but it chains two services and grants a build role permission to start pipelines. More moving parts than a native trigger.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-filter.html>

</details>

### Q2 · Task 1.1 · Single answer

A pipeline in a tooling account builds an artifact and then uses an AWS CloudFormation deploy action that assumes a role in a production account. The deploy action fails with an access-denied error when it reads the input artifact. The artifact bucket policy already grants the production role `s3:GetObject`. The artifact bucket uses the default encryption that the console configured: the AWS managed key `aws/s3`.

Which change will resolve the error?

- **A.** Create a customer managed AWS KMS key in the tooling account, grant the production account's deployment role `kms:Decrypt` and `kms:DescribeKey` in the key policy, and configure the pipeline's artifact store to use that key.
- **B.** Add `kms:Decrypt` on `*` to the identity policy of the production deployment role so it can decrypt objects encrypted with the `aws/s3` key.
- **C.** Disable encryption on the artifact bucket so that cross-account reads no longer require KMS permissions.
- **D.** Copy the artifact to an S3 bucket in the production account with an S3 replication rule, and point the deploy action at the replicated object.

<details><summary>Answer</summary>

**Answer: A**

**Why (P11, P2):** AWS managed keys can't be used by other accounts, because their key policies can't be changed. Cross-account artifact access needs a customer managed key whose key policy allows the target role, plus the bucket policy.

- **A** — correct: this is the documented cross-account pipeline setup.
- **B** — wrong: an IAM allow can't override a key policy that doesn't trust the other account, and `aws/s3` can't be shared.
- **C** — wrong: when no customer managed key is configured on the artifact store, CodePipeline itself encrypts artifacts with `aws/s3`. Changing the bucket's default encryption doesn't change that, and weakening encryption is the wrong direction anyway.
- **D** — wrong: the pipeline still passes artifacts through its own artifact store, and replicating KMS-encrypted objects raises the same key problem.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-create-cross-account.html>

</details>

### Q3 · Task 1.1 · Single answer

An AWS CodeBuild project runs integration tests that connect to a test database. The database password is currently set as a plaintext environment variable in the project configuration, and it appears in the console and in `BatchGetProjects` output. Security requires that the password be stored encrypted, retrieved at build time, rotated every 30 days, and never shown in plaintext in the build configuration.

Which solution meets these requirements?

- **A.** Store the password as a String parameter in Parameter Store and reference it in the buildspec `env/parameter-store` section.
- **B.** Encrypt the password with an AWS KMS key, commit the ciphertext to the repository, and add a `pre_build` command that decrypts it with `aws kms decrypt`.
- **C.** Pass the password to the build as a pipeline-level variable when the pipeline execution is started.
- **D.** Store the password in AWS Secrets Manager with automatic rotation enabled, reference it in the buildspec `env/secrets-manager` section, and allow the CodeBuild service role `secretsmanager:GetSecretValue` on that secret.

<details><summary>Answer</summary>

**Answer: D**

**Why (P11):** Secrets Manager provides encrypted storage **and** native rotation. CodeBuild resolves `secrets-manager` references at build start using its service role, and masks the values in logs.

- **A** — wrong: a String parameter isn't encrypted, and Parameter Store has no built-in rotation.
- **B** — wrong: the ciphertext lives in source control, rotation becomes a manual commit, and the decrypted value is handled by hand in the build.
- **C** — wrong: pipeline variables are visible in execution details, and nothing rotates them.
- **D** — correct: encrypted, rotated, fetched at runtime with least privilege, masked in logs.

**Reference:** <https://docs.aws.amazon.com/codebuild/latest/userguide/build-spec-ref.html>

</details>

### Q4 · Task 1.1 · Select TWO

A company's release pipeline (V2 type) deploys to production through a CloudFormation stage. Two new controls are required:
* A QA lead must explicitly sign off on each release before production changes.
* Production changes may only start on Tuesdays and Thursdays between 10:00 and 14:00 UTC, even if the sign-off happens outside that window.

Which combination of actions will meet these requirements? (Select TWO.)

- **A.** Disable the transition into the production stage and have the QA lead enable it manually during the allowed window.
- **B.** Add a manual approval action before the production deploy action, and grant the QA lead permission to approve it.
- **C.** Create an EventBridge Scheduler schedule that starts the pipeline every Tuesday and Thursday at 10:00 UTC.
- **D.** Add a Lambda invoke action that fails the stage if the current time is outside the window, and let operators retry the stage later.
- **E.** Configure an entry condition on the production stage with a deployment window rule for Tuesdays and Thursdays, 10:00–14:00 UTC.

<details><summary>Answer</summary>

**Answer: B, E**

**Why (P12, P5):** Manual approval provides the human sign-off. A V2 stage entry condition holds the execution until the window opens, so a late approval waits rather than failing.

- **A** — wrong: it depends on a person remembering the window and gives no recorded sign-off per release.
- **B** — correct: the native approval action records who approved each release.
- **C** — wrong: starting the pipeline on a schedule doesn't stop production changes that happen later in the run outside the window.
- **D** — wrong: custom code that fails releases and needs manual retries. Higher overhead than a native condition.
- **E** — correct: deployment-window entry conditions are a native V2 stage feature.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/stage-conditions.html>

</details>

### Q5 · Task 1.2 · Single answer

Developers open pull requests against the `main` branch of a GitHub repository. The team wants every pull request, including updates to it, to run linting and unit tests in AWS, with the result shown as a status check on the pull request before anyone can merge. The solution must use the LEAST custom code.

What should a DevOps engineer configure?

- **A.** A CodePipeline pipeline with the `main` branch as its source, plus a CodeBuild test action.
- **B.** A CodeBuild project with a GitHub webhook whose filter group includes the `PULL_REQUEST_CREATED`, `PULL_REQUEST_UPDATED` and `PULL_REQUEST_REOPENED` events and a `BASE_REF` filter for `main`, with build status reporting enabled.
- **C.** An EventBridge rule that runs every 5 minutes and invokes a Lambda function that lists open pull requests and starts a CodeBuild build for each one.
- **D.** A CodeBuild project triggered nightly that tests all open branches and emails the results to the developers.

<details><summary>Answer</summary>

**Answer: B**

**Why (P1, P12):** CodeBuild's native webhook filter groups start builds on PR events and report commit status back to the PR. No glue code is needed.

- **A** — wrong: a `main`-branch pipeline runs **after** merge. It can't gate the PR.
- **B** — correct: PR-scoped, event-driven, with status reported to the PR.
- **C** — wrong: polling with custom code, and slower.
- **D** — wrong: nightly results arrive after merge decisions and don't gate anything.

**Reference:** <https://docs.aws.amazon.com/codebuild/latest/userguide/github-webhook.html>

</details>

### Q6 · Task 1.2 · Single answer

A CodeBuild project produces JUnit test results and a Cobertura coverage file. The engineering manager wants test and coverage trends visible in the CodeBuild console. Builds must **fail** when line coverage drops below 80%.

Which approach meets both requirements?

- **A.** Configure a CodeBuild report group with a minimum line-coverage threshold of 80%. CodeBuild fails builds that report lower coverage.
- **B.** Publish the coverage percentage as a custom CloudWatch metric and create an alarm that stops the build when the metric is below 80.
- **C.** Declare both files in the buildspec `reports` section, and run the coverage tool with a fail-under option of 80 so that the command exits non-zero when coverage is too low.
- **D.** Add a manual approval action after the build so that a reviewer checks the coverage report before the pipeline continues.

<details><summary>Answer</summary>

**Answer: C**

**Why (P5):** Reports give the console visualization, but only a **non-zero exit code** fails a CodeBuild phase. Gates are exit codes.

- **A** — wrong: report groups store and visualize results. They don't enforce coverage thresholds.
- **B** — wrong: CloudWatch alarms can't fail a running build, and this adds machinery for no gain.
- **C** — correct: visual trends come from reports, and enforcement comes from the exit code.
- **D** — wrong: a manual check isn't automated enforcement and slows every release.

**Reference:** <https://docs.aws.amazon.com/codebuild/latest/userguide/code-coverage-report.html>

</details>

### Q7 · Task 1.2 · Single answer

A pipeline deploys a CloudFormation stack to a test account. The stack outputs an API endpoint URL, which changes whenever the stack is recreated. The next stage runs integration tests in CodeBuild, and the tests must target the endpoint that was just deployed. The team wants no hard-coded values and no extra infrastructure.

How should the DevOps engineer pass the URL to the tests?

- **A.** Store the URL manually in Parameter Store after each deployment and read it in the buildspec.
- **B.** Add a Lambda invoke action that calls `DescribeStacks`, writes the URL to an S3 object, and makes the test build download the object.
- **C.** Hard-code the URL in the buildspec and update it whenever the stack is recreated.
- **D.** Give the CloudFormation action a variable namespace, and set a CodeBuild environment variable in the test action to the stack output variable, e.g. `#{DeployTest.ApiUrl}`.

<details><summary>Answer</summary>

**Answer: D**

**Why (P12):** The CloudFormation action exposes stack outputs as **action output variables**, which later actions can reference directly.

- **A** — wrong: a manual step that breaks automation.
- **B** — wrong: works, but it adds a function and an S3 hop for something the pipeline already provides.
- **C** — wrong: brittle, and fails every time the endpoint changes.
- **D** — correct: native variable passing between actions.

**Reference:** <https://docs.aws.amazon.com/codepipeline/latest/userguide/reference-variables.html>

</details>

### Q8 · Task 1.2 · Single answer

Before each release, a team runs a chaos test in its staging environment that stops 30% of the EC2 instances in an Auto Scaling group and injects API throttling. Leadership requires the experiment to stop **immediately and automatically** if the staging error rate breaches the SLO, to avoid a prolonged outage that would block other teams.

What should the DevOps engineer use?

- **A.** A Systems Manager Automation runbook that stops instances, with a final step that checks the error rate.
- **B.** An AWS Fault Injection Service (FIS) experiment template with a stop condition that references a CloudWatch alarm on the error-rate metric.
- **C.** A Lambda function that terminates instances randomly, plus a CloudWatch alarm that notifies an engineer, who stops the function.
- **D.** An AWS FIS experiment template with no stop conditions, plus a CloudWatch dashboard that the team watches during the test.

<details><summary>Answer</summary>

**Answer: B**

**Why (P5, P10):** FIS stop conditions are CloudWatch alarms. When the alarm enters ALARM, FIS halts the experiment automatically.

- **A** — wrong: checking at the end doesn't stop the damage while it happens.
- **B** — correct: native fault injection with an automatic, alarm-driven stop.
- **C** — wrong: custom chaos tooling with a manual stop.
- **D** — wrong: watching a dashboard is manual and can't guarantee an immediate stop.

**Reference:** <https://docs.aws.amazon.com/fis/latest/userguide/stop-conditions.html>

</details>

### Q9 · Task 1.3 · Single answer

Builds for a Node.js service fail several times a month when the public npm registry is unavailable or rate-limits the company's NAT gateway IP address. The security team also wants every package version the company has ever used to stay available, even if the author unpublishes it from the public registry.

What should the DevOps engineer do?

- **A.** Commit the `node_modules` directory to the repository so that builds don't download packages.
- **B.** Enable CodeBuild local caching for the npm cache directory so that most packages come from the build host.
- **C.** Create an AWS CodeArtifact repository with an external connection to npmjs (directly or through an upstream repository), and configure the build to run `aws codeartifact login --tool npm` before installing packages.
- **D.** Run a self-managed npm mirror on an EC2 instance and point the build's npm registry configuration at it.

<details><summary>Answer</summary>

**Answer: C**

**Why (P12):** CodeArtifact proxies and **retains** packages fetched through its external connection, so builds keep working during public outages, and previously fetched versions stay available.

- **A** — wrong: bloats the repository, tends to break across platforms, and doesn't serve other projects.
- **B** — wrong: local cache hits are opportunistic (only on the same host, soon after a previous build), so builds still fail on a cache miss during an outage.
- **C** — correct: a managed proxy with durable retention and IAM-controlled access.
- **D** — wrong: works, but it's a server you must operate, patch and scale.

**Reference:** <https://docs.aws.amazon.com/codeartifact/latest/ug/external-connection.html>

</details>

### Q10 · Task 1.3 · Single answer

A team builds one container image per release in `us-east-1` and pushes it to Amazon ECR. ECS services in `us-east-1`, `eu-west-1` and `ap-southeast-2` must pull the same image from a registry in their own Region, to reduce latency and keep deployments working if another Region is impaired. The solution must have the LEAST operational overhead.

What should the DevOps engineer do?

- **A.** Configure an ECR registry replication rule for the repository with `eu-west-1` and `ap-southeast-2` as destination Regions.
- **B.** Add post-build commands that tag and push the image to repositories in each of the three Regions.
- **C.** Create a Lambda function, triggered by the ECR push event, that pulls the image and pushes it to the other Regions.
- **D.** Configure the ECS task definitions in the other Regions to pull from the `us-east-1` repository URI.

<details><summary>Answer</summary>

**Answer: A**

**Why (P12, P6):** ECR's native cross-Region replication copies images automatically after each push, with no code.

- **A** — correct: a native registry-level replication rule.
- **B** — wrong: works, but every pipeline must push N times and handle partial failures.
- **C** — wrong: custom code reimplementing replication.
- **D** — wrong: cross-Region pulls add latency and keep the dependency on `us-east-1`.

**Reference:** <https://docs.aws.amazon.com/AmazonECR/latest/userguide/replication.html>

</details>

### Q11 · Task 1.3 · Select TWO

A company runs a hardened Amazon Linux AMI in Auto Scaling groups in two AWS accounts. Whenever AWS publishes an updated base Amazon Linux AMI, the company wants a new hardened AMI built and tested automatically. It must be made available to both accounts so that **new** instances in both accounts use it without anyone editing launch templates.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Create an EC2 Image Builder pipeline with a schedule whose start condition runs the pipeline only when dependency updates (such as a new base image) are available, and include test components in the recipe.
- **B.** Use Systems Manager Patch Manager with a maintenance window to patch the running instances weekly.
- **C.** Create a Lambda function that runs daily, compares the latest public AMI parameter with the last build, and launches an instance to rebuild the AMI.
- **D.** Configure Image Builder distribution settings that share the AMI with both accounts and update the launch templates' default version in each account.
- **E.** Ask each account owner to subscribe to an SNS topic and update their launch templates when a new AMI ID is announced.

<details><summary>Answer</summary>

**Answer: A, D**

**Why (P4, P12):** Image Builder builds, tests and distributes golden AMIs. The dependency-update start condition reacts to new base images, and distribution can update launch templates in target accounts.

- **A** — correct: an automated, tested rebuild only when the base changes.
- **B** — wrong: patches running instances in place (mutable), and produces no AMI.
- **C** — wrong: custom code reimplementing Image Builder's scheduling and build.
- **D** — correct: cross-account distribution plus launch template updates, so new instances use the new AMI.
- **E** — wrong: manual updates violate the requirement.

**Reference:** <https://docs.aws.amazon.com/imagebuilder/latest/userguide/manage-distribution-settings.html>

</details>

### Q12 · Task 1.3 · Single answer

An Amazon ECR repository holds thousands of images, and storage costs keep growing. Policy says: keep the 30 most recent images whose tags start with `release-`, and delete untagged images one day after they're pushed. Other tagged images must not be touched.

What is the MOST operationally efficient solution?

- **A.** Schedule a nightly Lambda function that lists images, sorts them and deletes the images that fall outside the policy.
- **B.** Enable S3 Intelligent-Tiering on the bucket that backs the ECR repository.
- **C.** Turn on tag immutability for the repository so that old tags can't accumulate.
- **D.** Create an ECR lifecycle policy with one rule that expires untagged images older than 1 day and another that keeps only 30 images with the `release-` tag prefix.

<details><summary>Answer</summary>

**Answer: D**

**Why (P12):** ECR lifecycle policies express exactly these rules (count-based and age-based, filtered by tag status and prefix), and ECR applies them automatically.

- **A** — wrong: custom code reimplementing lifecycle policies.
- **B** — wrong: ECR storage isn't a bucket you manage; there's no such setting.
- **C** — wrong: immutability prevents overwriting tags. It doesn't delete anything.
- **D** — correct: native and declarative.

**Reference:** <https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html>

</details>

### Q13 · Task 1.4 · Single answer

A CodeDeploy in-place deployment to EC2 instances fails on every instance at the `ApplicationStop` lifecycle event. The engineer has already fixed the `stop.sh` script in the **new** revision, but deployments still fail at the same event with the same error.

What is the cause, and what should the engineer do?

- **A.** The CodeDeploy agent caches revisions. Restart the agent on every instance and redeploy.
- **B.** `ApplicationStop` runs the script from the **last successfully deployed** revision, which is still broken. Redeploy once with the option to ignore `ApplicationStop` failures, after which the fixed script becomes the one that runs.
- **C.** The `hooks` section must list `ApplicationStop` after `ApplicationStart`. Reorder the AppSpec file.
- **D.** The deployment group's minimum healthy hosts value is too high. Lower it to 0% so failures are ignored.

<details><summary>Answer</summary>

**Answer: B**

**Why (P4):** On the next deployment, CodeDeploy runs `ApplicationStop` using the AppSpec file and scripts of the previous successful revision. Fixing the new revision can't help until it's installed once.

- **A** — wrong: restarting the agent doesn't change which revision's script runs.
- **B** — correct: the documented fix is `--ignore-application-stop-failures` for one deployment.
- **C** — wrong: hook order is fixed by CodeDeploy, not by the order in the file.
- **D** — wrong: ignoring health constraints would deploy a broken stop sequence everywhere and hide real failures.

**Reference:** <https://docs.aws.amazon.com/codedeploy/latest/userguide/troubleshooting-deployments.html>

</details>

### Q14 · Task 1.4 · Single answer

A team deploys a Lambda function with AWS SAM. New versions must receive 10% of production traffic for 10 minutes, then all traffic. If the function's error count rises during the deployment, traffic must automatically return to the previous version. The team wants the LEAST custom code.

How should the template be configured?

- **A.** Configure two separate functions and use Route 53 weighted records to send 10% of requests to the new one.
- **B.** Configure a step-scaling policy on the function's provisioned concurrency to shift traffic gradually.
- **C.** Set `AutoPublishAlias` and `DeploymentPreference` with `Type: Canary10Percent10Minutes` and an `Alarms` list containing a CloudWatch alarm on the alias's errors.
- **D.** Publish a new version manually and edit the alias weight to 10%, then to 100% after checking the logs.

<details><summary>Answer</summary>

**Answer: C**

**Why (P5):** SAM generates a CodeDeploy deployment that shifts alias weights according to the canary configuration and rolls back when an attached alarm fires.

- **A** — wrong: Lambda functions aren't DNS endpoints, and this would mean managing two functions and custom routing.
- **B** — wrong: provisioned concurrency is about cold starts. It doesn't route traffic between versions.
- **C** — correct: native canary traffic shifting with alarm-based automatic rollback.
- **D** — wrong: manual steps, no automatic rollback.

**Reference:** <https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/automating-updates-to-serverless-apps.html>

</details>

### Q15 · Task 1.4 · Select TWO

An Amazon ECS service on Fargate runs behind an Application Load Balancer. The team wants blue/green deployments in which an automated integration test suite runs against the **new** task set through a separate port **before** any production traffic reaches it. If the tests fail, the deployment must roll back automatically.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Use the CodeDeploy deployment controller for the service, with two target groups, a production listener, and a test listener on port 8080.
- **B.** Use the ECS rolling-update deployment controller with `minimumHealthyPercent` 100 and `maximumPercent` 200.
- **C.** Add an `AfterAllowTestTraffic` hook to the AppSpec file that invokes a Lambda function to run the tests against port 8080 and report `Succeeded` or `Failed`.
- **D.** Add a `BeforeInstall` hook that runs the tests against port 8080.
- **E.** Create a Route 53 weighted record that sends 1% of users to the new tasks while the tests run.

<details><summary>Answer</summary>

**Answer: A, C**

**Why (P5):** CodeDeploy ECS blue/green routes a test listener to the replacement task set first. The `AfterAllowTestTraffic` hook can then validate it, and a `Failed` result rolls the deployment back before production traffic shifts.

- **A** — correct: a test listener plus two target groups is the blue/green prerequisite.
- **B** — wrong: rolling updates have no test listener and no isolated pre-production validation.
- **C** — correct: this hook runs after test traffic is routed and before production traffic moves.
- **D** — wrong: at `BeforeInstall`, the replacement task set doesn't exist yet.
- **E** — wrong: exposes real users, and DNS-level weighting isn't tied to the ECS task set.

**Reference:** <https://docs.aws.amazon.com/codedeploy/latest/userguide/reference-appspec-file-structure-hooks.html>

</details>

### Q16 · Task 1.4 · Single answer

An AWS Elastic Beanstalk web environment must deploy new application versions with these properties:
* Full capacity throughout the deployment.
* New code never runs on the existing instances.
* If the new version fails health checks, rollback is fast and doesn't involve DNS changes.

Which deployment policy should be used?

- **A.** Immutable.
- **B.** Rolling with additional batch.
- **C.** All at once.
- **D.** Blue/green by cloning the environment and swapping environment URLs.

<details><summary>Answer</summary>

**Answer: A**

**Why (P4):** An immutable deployment launches new instances in a temporary Auto Scaling group. If they're unhealthy, Beanstalk just terminates them, with no DNS involved.

- **A** — correct: full capacity, new instances only, rollback by termination.
- **B** — wrong: updates existing instances in batches, so new code runs on old instances, and rollback means redeploying.
- **C** — wrong: causes downtime and modifies existing instances.
- **D** — wrong: a URL swap is a DNS (CNAME) change, which the requirement excludes.

**Reference:** <https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.rolling-version-deploy.html>

</details>

### Q17 · Task 1.4 · Single answer

A CodeDeploy deployment to EC2 instances in private subnets stays in the "Pending" state for all instances. The CodeDeploy agent is installed and running. The instance profile can read the revision bucket. The VPC has no NAT gateway, by security policy.

What should the DevOps engineer do?

- **A.** Attach Elastic IP addresses to the instances so the agent can reach CodeDeploy over the internet.
- **B.** Move the instances to public subnets and restrict inbound traffic with security groups.
- **C.** Change the deployment configuration to `CodeDeployDefault.AllAtOnce` so the agent polls less often.
- **D.** Create interface VPC endpoints for CodeDeploy (`codedeploy` and `codedeploy-commands-secure`) and an S3 gateway endpoint, so the agent can reach the service and download the revision privately.

<details><summary>Answer</summary>

**Answer: D**

**Why (P7):** The agent **polls** the CodeDeploy service. Without a NAT gateway, it needs the CodeDeploy interface endpoints, plus S3 access for the bundle.

- **A** — wrong: EIPs need a route to an internet gateway, which private subnets don't have, and this violates the policy.
- **B** — wrong: changes the network design and violates the security intent.
- **C** — wrong: the deployment configuration doesn't affect connectivity.
- **D** — correct: EC2 deployments need both the `codedeploy` (API) and `codedeploy-commands-secure` (agent) endpoints. The docs also require `:enable_auth_policy: true` in the agent configuration and `codedeploy-commands-secure:*` permissions on the instance profile, plus an S3 path for the revision.

**Reference:** <https://docs.aws.amazon.com/codedeploy/latest/userguide/vpc-endpoints.html>

</details>

### Q18 · Task 1.4 · Single answer

A fleet of 200 EC2 instances in an Auto Scaling group behind an ALB must move to a new OS baseline. The requirements:
* Capacity must never drop below 100%.
* The rollout must be gradual.
* If the ALB 5xx alarm fires during the rollout, the change must reverse automatically.
* Engineers must not modify running instances.

What should the DevOps engineer do?

- **A.** Use Systems Manager Run Command with a concurrency of 10% to upgrade the OS packages on running instances.
- **B.** Build a new AMI with EC2 Image Builder, create a new launch template version, and start an ASG instance refresh with minimum healthy 100%, maximum healthy 110%, and automatic rollback tied to the 5xx alarm.
- **C.** Update the launch template version. The ASG replaces all instances automatically within an hour.
- **D.** Terminate 10% of the instances every hour so that the ASG launches replacements from the new launch template.

<details><summary>Answer</summary>

**Answer: B**

**Why (P4, P5):** Immutable replacement through an instance refresh. A maximum healthy above 100% launches before terminating, and alarm-based auto rollback reverses the refresh.

- **A** — wrong: mutable in-place change, which the requirement forbids, and it has no automatic rollback.
- **B** — correct: gradual, full capacity, alarm-gated, immutable.
- **C** — wrong: changing the launch template doesn't replace existing instances.
- **D** — wrong: manual, capacity drops, no automatic rollback.

**Reference:** <https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-instance-refresh.html>

</details>

### Q19 · Task 1.4 · Select TWO

A product team wants to enable a new checkout feature for 10% of requests, increase exposure gradually, and turn the feature off automatically if the checkout error rate rises. The application already reads its configuration at runtime through the AWS AppConfig Agent, and must not be redeployed to change the flag.

Which combination of steps meets these requirements? (Select TWO.)

- **A.** Create a CodeDeploy canary deployment that redeploys the application with the flag hard-coded to on.
- **B.** Store the flag in a Parameter Store parameter and have a Lambda function flip it for 10% of instances.
- **C.** Define the flag in an AWS AppConfig feature flag configuration profile and deploy it with a canary or linear deployment strategy that has a bake time.
- **D.** Use Lambda alias weights to send 10% of requests to a function version with the feature enabled.
- **E.** Associate a CloudWatch alarm on the checkout error rate with the AppConfig environment so that AppConfig rolls the configuration back when the alarm fires.

<details><summary>Answer</summary>

**Answer: C, E**

**Why (P5, P12):** AppConfig deploys configuration gradually under a deployment strategy and rolls it back automatically when an environment's alarm fires. No code deployment is needed.

- **A** — wrong: requires redeploying code, which the requirement rules out.
- **B** — wrong: custom logic, no gradual exposure model, no automatic rollback.
- **C** — correct: native feature flags with gradual rollout and bake time.
- **D** — wrong: that's a code-version deployment, not a runtime flag, and doesn't apply to non-Lambda applications.
- **E** — correct: alarm-based automatic rollback of the configuration.

**Reference:** <https://docs.aws.amazon.com/appconfig/latest/userguide/appconfig-creating-deployment-strategy.html>

</details>

### Q20 · Task 1.1 · Single answer

A company uses GitLab (SaaS) for CI/CD. Its jobs deploy CloudFormation stacks to an AWS account. Today the jobs use an IAM user's access keys stored as GitLab CI variables. Security mandates removing all long-term AWS credentials from third-party systems, and limiting deployment rights to jobs that run on the `main` branch of one specific project.

What should the DevOps engineer implement?

- **A.** Register GitLab as an IAM OIDC identity provider, create a deployment role whose trust policy allows `sts:AssumeRoleWithWebIdentity` only when the token's `aud` matches and its `sub` claim matches the project and `main` branch, and have the jobs assume the role.
- **B.** Keep the IAM user, rotate its keys every 30 days with a Lambda function, and store the new keys in GitLab automatically.
- **C.** Store the access keys in AWS Secrets Manager and have the GitLab job read them with a second, read-only IAM user.
- **D.** Create an IAM role that trusts the AWS account root, and give GitLab the role ARN so that the jobs can assume it.

<details><summary>Answer</summary>

**Answer: A**

**Why (P14):** OIDC federation gives short-lived STS credentials per job. The trust policy's conditions on `aud` and `sub` restrict which project and branch can deploy.

- **A** — correct: no stored secrets, temporary credentials, scoped by claims.
- **B** — wrong: still long-term keys in a third-party system.
- **C** — wrong: still needs a long-term credential (the read-only user) to fetch the keys.
- **D** — wrong: GitLab has no AWS identity to assume the role with, unless you give it keys again.

**Reference:** <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html>

</details>

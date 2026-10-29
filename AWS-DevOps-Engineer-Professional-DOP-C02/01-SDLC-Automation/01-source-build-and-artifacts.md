# Domain 1 · 01 · Source, Build and Artifacts

> **Exam tasks:** 1.1 (repositories, build processes, build secrets), 1.3 (artifact repositories, build tools, image builds). **Principles:** P1 (events), P4 (immutable artifacts), P11 (secrets), P14 (roles).

A pipeline turns **a source revision** into **a versioned, immutable artifact** and then deploys that artifact. This file covers the first two links of that chain: where source lives and how changes are detected, how builds run, and where artifacts are stored. Deployment is in [03-deployment-strategies.md](03-deployment-strategies.md).

---

## 1. First principles

1. **A build must be reproducible from (source revision + build environment + inputs).** Pin build images, pin dependency versions (lock files), and cache safely, so that the same commit gives the same artifact.
2. **Build once, deploy many.** The artifact built at the start is the one promoted through test, staging and production. Rebuilding per environment means production runs something that was never tested. Environment differences belong in **configuration** (parameters, AppConfig, environment variables), not in the artifact.
3. **Artifacts are immutable and addressable.** An artifact is identified by a version: an S3 object version, an ECR image **digest** or immutable tag, a CodeArtifact package version, or an AMI ID. "latest" is not a version.
4. **Secrets are fetched at build time, never committed** (P11). A build role reads them from Secrets Manager or Parameter Store.

---

## 2. Source: where code lives and how change is detected

### 2.1 Options

| Source | How CodePipeline detects change | Notes |
|---|---|---|
| **AWS CodeCommit** | An **EventBridge rule** on `CodeCommit Repository State Change` for the branch (the console creates it). The older alternative is periodic polling, which you shouldn't use | Back to general availability since 2025-11-24. IAM controls access; there is no separate user directory |
| **GitHub, GitHub Enterprise Server, GitLab, Bitbucket** | **AWS CodeConnections** (formerly CodeStar Connections). The connection is approved once in the provider; pipelines then get push and pull-request events | The connection starts in the `PENDING` state until it is authorized in the console. A pipeline using a `PENDING` connection fails |
| **Amazon S3** | An EventBridge rule on S3 object events (requires EventBridge notifications on the bucket, or CloudTrail data events) | The bucket **must have versioning enabled**, because the pipeline tracks object versions |
| **Amazon ECR** | An EventBridge rule on an image push (`ECR Image Action`) | Starts a deployment pipeline when a new image tag is pushed |

**Principle check (P1):** each of these is event-based. Polling sources (`PollForSourceChanges: true` on legacy V1 pipelines) are the distractor.

### 2.2 Branch protection and code review in CodeCommit

* **Approval rule templates** require N approvals from specified pools (IAM ARNs) before a pull request can merge. Associate a template with repositories to apply it automatically to new pull requests.
* **Protect a branch with IAM.** Deny `codecommit:GitPush`, `codecommit:DeleteBranch`, `codecommit:PutFile` and `codecommit:MergeBranchesBy*` when `codecommit:References` matches `refs/heads/main`. Only pull-request merges by authorized roles can then change `main`.
* **Notifications** of pull-request events go to SNS or AWS Chatbot through notification rules. **Triggers** (an older feature) call SNS or Lambda on push events.
* **Pull-request builds.** An EventBridge rule on `pullRequestCreated` / `pullRequestSourceBranchUpdated` starts a CodeBuild project, and a Lambda or the build itself posts the result back as a PR comment or approval. With GitHub, Bitbucket or GitLab, a **CodeBuild webhook with filter groups** (for example `EVENT: PULL_REQUEST_CREATED, PULL_REQUEST_UPDATED` and `BASE_REF: ^refs/heads/main$`) does this natively.

### 2.3 CodePipeline V2 triggers

V2 pipelines can filter triggers by **Git tags, branches, file paths and pull-request events**. That removes the old need for one pipeline per branch, or for a Lambda that inspects changed files ([V1 vs V2](https://docs.aws.amazon.com/codepipeline/latest/userguide/pipeline-types-planning.html)). Examples: "run the release pipeline only when a tag matching `v*` is pushed"; "run the infrastructure pipeline only when files under `infra/**` change".

---

## 3. AWS CodeBuild

### 3.1 Mental model

A CodeBuild **project** is a recipe that has six parts:

1. **source** (or input artifacts from CodePipeline);
2. **environment:** a container image, compute type and privileged mode;
3. **service role:** the IAM role the build assumes;
4. **buildspec:** the commands;
5. **artifacts** out;
6. **logs** to CloudWatch Logs and/or S3.

Each build runs in a **fresh, isolated environment**, and nothing persists except what you cache or export.

### 3.2 The buildspec, annotated

```yaml
version: 0.2

env:
  shell: bash
  variables:                       # plaintext: only non-sensitive values
    APP_ENV: "ci"
  parameter-store:                 # SSM Parameter Store (String or SecureString)
    DB_HOST: "/myapp/ci/db-host"
  secrets-manager:                 # secret-id:json-key:version-stage:version-id
    DB_PASSWORD: "myapp/ci/db:password"
  exported-variables:              # become CodePipeline output variables
    - IMAGE_TAG

phases:
  install:
    runtime-versions:
      python: 3.12
    commands:
      - pip install -r requirements.txt
  pre_build:
    on-failure: ABORT              # stop the build if this phase fails
    commands:
      - export IMAGE_TAG=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c1-8)
      - aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REGISTRY
  build:
    commands:
      - pytest --junitxml=reports/junit.xml --cov=app --cov-report=xml:reports/coverage.xml
      - docker build -t $ECR_REGISTRY/myapp:$IMAGE_TAG .
  post_build:
    commands:
      - docker push $ECR_REGISTRY/myapp:$IMAGE_TAG
      - printf '[{"name":"app","imageUri":"%s"}]' "$ECR_REGISTRY/myapp:$IMAGE_TAG" > imagedefinitions.json
    finally:
      - echo "post_build finished"

reports:                           # test and coverage reports shown in the console
  unit-tests:
    files: ["junit.xml"]
    base-directory: reports
    file-format: JUNITXML
  coverage:
    files: ["coverage.xml"]
    base-directory: reports
    file-format: COBERTURAXML

artifacts:
  files:
    - imagedefinitions.json
    - appspec.yaml
    - taskdef.json

cache:
  paths:
    - "/root/.cache/pip/**/*"
```

**Key facts the exam uses:**

* **Exit codes decide success.** Any command that returns non-zero fails its phase, and therefore the build, and therefore the pipeline action. "Measure application health based on exit codes" (task 1.2) means: make your test runner return non-zero on failure.
* **Phase order** is `install → pre_build → build → post_build`. `post_build` runs even if `build` fails, unless the failing phase has `on-failure: ABORT`. Check `CODEBUILD_BUILD_SUCCEEDING` in `post_build` to avoid, for example, pushing an image after failed tests.
* **Secrets:** the `secrets-manager` and `parameter-store` keys resolve at build start using the **service role**. That role needs `secretsmanager:GetSecretValue` / `ssm:GetParameters`, plus `kms:Decrypt` if a customer-managed key encrypts the secret. Values are masked in logs. Plaintext `variables` show up in the console and API, so they're **wrong for secrets**.
* **Docker builds need privileged mode** enabled on the project, so that the Docker daemon can run inside the build container.
* **Builds in a VPC** (to reach private RDS or internal package mirrors) get ENIs in private subnets. To reach the internet or AWS APIs they need a **NAT gateway** or **VPC endpoints**. A build in a public subnet does **not** get a public IP.
* **Caching:**
  * **S3 cache** persists between builds on any host; it's good for dependency caches.
  * **Local cache** modes (`LOCAL_SOURCE_CACHE`, `LOCAL_DOCKER_LAYER_CACHE`, `LOCAL_CUSTOM_CACHE`) live on the build host. They're fast, but only hit when builds land on the same host soon after each other.
  * Docker layer caching is the usual answer to "Docker builds are slow".
* **Batch builds** run many builds from one buildspec: a `build-graph` with dependencies, a `build-list`, or a `build-matrix` across versions and operating systems.
* **Compute options:** EC2-based (on demand), AWS Lambda compute (fast start, short builds, no Docker), and **reserved-capacity fleets** for warm, consistent capacity.
* **Logs** go to CloudWatch Logs by default. S3 logs can be added for long-term retention.

### 3.3 Typical CodeBuild failure → cause

| Symptom | Likely cause |
|---|---|
| `AccessDenied` getting a secret or parameter | The service role lacks `GetSecretValue` / `GetParameters`, or `kms:Decrypt` on the customer-managed key |
| `Cannot connect to the Docker daemon` | Privileged mode is off |
| Build in a VPC can't download packages or call AWS APIs | No NAT gateway or VPC endpoints for the private subnets |
| `CLIENT_ERROR: ... authorization failed` for the source | A CodeConnections connection in `PENDING`, or missing `codeconnections:UseConnection` permission |
| Build passes but the deploy uses old code | The artifact `files:` pattern or `base-directory` is wrong, or the artifact name expected by the next action doesn't match |

---

## 4. Artifact repositories

### 4.1 Amazon S3 (pipeline artifacts, deployment bundles)

* CodePipeline uses an **artifact store bucket per Region**. Cross-Region actions need an artifact bucket in each Region involved. The console creates them; in IaC you declare `ArtifactStores`.
* **Encryption:** the default is the AWS-managed `aws/s3` key. For **cross-account** deployments you **must** use a customer-managed KMS key whose key policy lets the other account's roles decrypt (see [02-codepipeline-design-and-multi-account.md](02-codepipeline-design-and-multi-account.md)).
* **Lifecycle rules** expire old artifacts and noncurrent versions, which keeps costs down.

### 4.2 Amazon ECR (container images)

| Feature | Purpose / exam angle |
|---|---|
| **Tag immutability** | Prevents overwriting a tag such as `1.4.2`. Deploy by immutable tag or by **digest** (`@sha256:...`) |
| **Lifecycle policies** | Expire untagged images, or keep only the last N images per tag prefix |
| **Image scanning** | **Basic**: on push or manual, against a CVE database. **Enhanced**: Amazon Inspector, continuous re-scanning as new CVEs appear, OS and language packages. Findings go to EventBridge, so a rule can block or notify |
| **Replication** | Cross-Region and cross-account replication rules at the registry level. The usual answer to "deploy the same image in 3 Regions with the least effort" |
| **Repository policies** | Resource-based. Grant another account `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer` and `ecr:BatchCheckLayerAvailability` to pull. The puller also needs `ecr:GetAuthorizationToken` in its own IAM policy |
| **Pull-through cache** | Caches images from public registries (Docker Hub, ECR Public, Quay, GitHub Container Registry) in your private registry. Upstream outages and rate limits stop hurting builds |
| **KMS encryption** | AES-256 by default; a customer-managed key is possible (set at repository creation) |

### 4.3 AWS CodeArtifact (language packages)

* **Domain → repositories.** A domain holds assets once and deduplicates storage; it is encrypted with a KMS key, and its **domain policy** can grant other accounts access.
* **Upstream repositories:** a repository can chain to up to 10 upstreams, searched in order.
* **External connection:** a repository can have **one** external connection to a public registry (npmjs, PyPI, Maven Central, NuGet, and others). Pattern: `team-repo → (upstream) shared-repo → (external connection) npmjs`. Developers and builds use `team-repo`; packages fetched from the public registry are cached and stay available even if the public registry removes them.
* **Authentication:** `aws codeartifact login --tool npm|pip|twine` gets a **token valid for up to 12 hours** and configures the tool. In CodeBuild, run it in `install` or `pre_build`. The build role needs `codeartifact:GetAuthorizationToken`, `codeartifact:ReadFromRepository` and `sts:GetServiceBearerToken`.
* **Exam angle:**
  * "Builds fail when the public registry is down" or "approve packages centrally" → CodeArtifact with an external connection plus upstreams.
  * "Block builds from fetching from the internet" → CodeBuild in a VPC with CodeArtifact VPC endpoints, and no NAT.

### 4.4 EC2 Image Builder (golden AMIs and container images)

**Model:**

| Building block | What it is |
|---|---|
| **Image recipe** | A parent image plus **components** (build steps and **test** steps, written as YAML documents) |
| **Infrastructure configuration** | Instance type, subnet, IAM instance profile, SNS topic for notifications |
| **Distribution settings** | Target Regions and accounts, AMI sharing, and an optional **launch template update** in target accounts |
| **Image pipeline** | Ties the three together on a schedule |

| Requirement | Image Builder feature |
|---|---|
| "Rebuild the AMI whenever the parent (base) AMI gets security updates" | Schedule with the start condition *only if dependency updates are available* (`EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE`) |
| "Distribute the AMI to 3 Regions and 5 accounts" | Distribution settings (and a KMS key policy for encrypted AMIs shared cross-account) |
| "New instances must use the new AMI automatically" | Distribution updates the **launch template's** default version, and the ASG uses `$Default`/`$Latest`. Then start an **instance refresh** to replace running instances |
| "Validate the AMI before distribution" | Test components (and the Image Builder workflow's test phase). A failed test stops distribution |
| "Patch running instances, not AMIs" | That is **Systems Manager Patch Manager**, not Image Builder. Immutable (Image Builder) vs mutable (Patch Manager) is a common choice point |

---

## 5. Build and deployment secrets: choosing the store

| Need | Use |
|---|---|
| Database password that must **rotate automatically** | **Secrets Manager** (managed rotation for RDS, Aurora, Redshift and DocumentDB; a Lambda rotation function for others) |
| Configuration values, feature-agnostic, cheap, hierarchical (`/app/prod/...`) | **Parameter Store** (String, StringList, SecureString with KMS). The standard tier is free; the advanced tier adds larger values and policies |
| A secret shared **cross-account** | Secrets Manager (resource policy + customer-managed KMS key). Parameter Store standard parameters can't be shared that way |
| Feature flags or configuration deployed gradually, with validation and rollback | **AWS AppConfig** (see [03-deployment-strategies.md](03-deployment-strategies.md)) |

In CodeBuild, reference both from `env`. In ECS, use the task definition `secrets` (`valueFrom` an ARN). In Lambda, use the Parameters and Secrets Lambda Extension or the SDK. In CloudFormation, use **dynamic references** (`{{resolve:secretsmanager:...}}`, `{{resolve:ssm-secure:...}}`).

---

## 6. Exam traps

* **S3 source bucket without versioning:** the pipeline can't track revisions. Versioning is required.
* **Plaintext environment variables for passwords:** visible in the console and API, so always wrong.
* **Rebuilding the artifact for each environment:** breaks "build once, deploy many".
* **ECR images shared cross-account:** need the **repository policy** (resource side) **and** IAM permissions on the pulling side, including `ecr:GetAuthorizationToken`.
* **The "latest" tag in production:** not immutable. Use tag immutability or digests.
* **Image Builder vs Patch Manager:** golden image (immutable) vs patching running instances (mutable). Read which one the question wants.
* **A CodeBuild build in a VPC with no NAT gateway or endpoints:** can't reach anything outside the VPC.
* **Docker builds without privileged mode:** fail.

## 7. Hands-on lab (about 30 minutes; deletes cleanly)

**Goal:**
* A CodeBuild project that reads a secret from Secrets Manager at build start, using a least-privilege role.
* It publishes a JUnit test report.
* An **EventBridge rule on the native `CodeBuild Build State Change` event** emails you when a build fails (P1: no polling).

The template is [labs/lab-01-codebuild-with-secret.yaml](labs/lab-01-codebuild-with-secret.yaml). The buildspec is inline, so you don't need a source repository.

```bash
# Deploy
aws cloudformation deploy --stack-name dop-lab-01 \
  --template-file labs/lab-01-codebuild-with-secret.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides NotificationEmail=you@example.com
# Confirm the SNS subscription email, then:
aws codebuild start-build --project-name dop-lab-01-build

# Watch the phases
aws codebuild batch-get-builds --ids <build-id> \
  --query 'builds[0].phases[].[phaseType,phaseStatus]' --output table

# Tear down (the secret is scheduled for deletion and can be force-deleted)
aws cloudformation delete-stack --stack-name dop-lab-01
aws secretsmanager delete-secret --secret-id dop-lab-01/db --force-delete-without-recovery
```

**What to observe:**
* In the build log, the secret value prints as `***`. CodeBuild masks values that came from Secrets Manager or Parameter Store.
* The **Reports** tab shows the two test cases.
* **Break it on purpose (1):** remove the `ReadOnlyThisSecret` statement from the role and start another build. It fails before your commands run, with an access-denied error naming the secret. A minute later the failure email arrives: that's the EventBridge rule.
* **Break it on purpose (2):** change `test -n "$DB_PASSWORD"` to `test -z "$DB_PASSWORD"`. The command exits non-zero, so the `BUILD` phase fails, so the build fails. That's task 1.2's "application health based on exit codes".

## References

* CodeBuild buildspec reference — <https://docs.aws.amazon.com/codebuild/latest/userguide/build-spec-ref.html>
* CodeBuild caching — <https://docs.aws.amazon.com/codebuild/latest/userguide/build-caching.html>
* CodePipeline V1 vs V2 — <https://docs.aws.amazon.com/codepipeline/latest/userguide/pipeline-types-planning.html>
* AWS CodeConnections rename — <https://docs.aws.amazon.com/dtconsole/latest/userguide/rename.html>
* Amazon ECR image scanning — <https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html>
* Amazon ECR replication — <https://docs.aws.amazon.com/AmazonECR/latest/userguide/replication.html>
* AWS CodeArtifact concepts — <https://docs.aws.amazon.com/codeartifact/latest/ug/codeartifact-concepts.html>
* EC2 Image Builder — <https://docs.aws.amazon.com/imagebuilder/latest/userguide/what-is-image-builder.html>

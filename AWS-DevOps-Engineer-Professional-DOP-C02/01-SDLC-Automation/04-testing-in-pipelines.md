# Domain 1 · 04 · Integrating Automated Testing into Pipelines

> **Exam task:** 1.2 (all of it). **Principles:** P5 (health gates progression), P10 (observe outcomes), P12 (native features).

## 1. First principles

1. **A test is a gate, and a gate is an exit code.** Every pipeline gate reduces to "did the step return success?". In CodeBuild, a non-zero exit code fails the phase; in a Lambda invoke action, it's `PutJobFailureResult`; in a CodeDeploy hook, it's `Failed`; in a stage condition, it's an alarm in the ALARM state. If a test failure doesn't change an exit code or a status, it doesn't stop anything.
2. **Cheap and fast tests run first; slow and realistic tests run later.** The cost of finding a bug grows with every stage it passes, so put the fastest feedback (lint, unit tests, static scans) on every pull request, and the slowest (load, chaos) in pre-production.
3. **Test the artifact you'll ship, in an environment shaped like the one you'll ship to.** Integration and acceptance tests run **after deploying** the same artifact to a test account or stage, not against a developer laptop build.
4. **Production keeps testing.** Canary deployments, synthetic canaries and alarms are tests that run in production and trigger rollback (P5).

## 2. Where each test type belongs

| Stage | Test types | AWS mechanism | Fails the pipeline by |
|---|---|---|---|
| **Pull request** (before merge) | Lint, unit tests, code coverage, SAST, secret scanning, IaC linting/policy (cfn-lint, cfn-guard), dependency vulnerability scan | CodeBuild started by a **webhook filter group** (GitHub, GitLab, Bitbucket) or an **EventBridge rule on CodeCommit PR events**; result posted back to the PR | Non-zero exit → PR check fails or approval withheld |
| **Build** (main branch) | Unit tests + coverage threshold, container image build, image scan | CodeBuild with **test and coverage reports**; ECR scan on push / Amazon Inspector enhanced scanning | Non-zero exit (e.g. `coverage report --fail-under=80`); EventBridge rule on critical findings |
| **Test environment** (after deploy) | Integration, contract and API tests; UI tests; DAST | CodeBuild action with the endpoint from **output variables**; Lambda or Step Functions invoke action | Non-zero exit / job failure result |
| **Staging / pre-production** | Load and stress, performance benchmarks, soak, chaos, user acceptance | CodeBuild batch builds or Fargate tasks driving load (e.g. the "Distributed Load Testing on AWS" solution); **AWS FIS** experiments with stop conditions; **manual approval** for UAT sign-off | Threshold breach → exit code; FIS stop condition alarm |
| **Production** | Canary deployment metrics, smoke tests, synthetic transactions | CodeDeploy canary/linear with alarms; `ValidateService` / `AfterAllowTraffic` hooks; **CloudWatch Synthetics canaries**; CodePipeline V2 **on-success stage conditions** checking alarms | Alarm → automatic rollback |

## 3. CodeBuild test reports and coverage

* **Report groups** collect test results across builds and show trends, pass rates and durations in the console.
* **Test formats:** JUnit XML, Cucumber JSON, NUnit (v2/v3), TestNG XML, Visual Studio TRX.
* **Coverage formats:** JaCoCo XML, SimpleCov JSON, Clover XML, Cobertura XML, LCOV.
* **Declaring them:** the `reports:` section of the buildspec (see [01-source-build-and-artifacts.md](01-source-build-and-artifacts.md#32-the-buildspec-annotated)). The service role needs `codebuild:CreateReportGroup`, `CreateReport`, `UpdateReport`, `BatchPutTestCases` and `BatchPutCodeCoverages`.
* **Reports alone don't fail builds.** To enforce "coverage must be ≥ 80%", the test or coverage command must **exit non-zero** when below the threshold.

## 4. Pull-request builds: the two native ways

1. **GitHub, GitHub Enterprise, GitLab, Bitbucket:** a CodeBuild **webhook** with **filter groups**, for example:
   * `EVENT: PULL_REQUEST_CREATED, PULL_REQUEST_UPDATED, PULL_REQUEST_REOPENED`;
   * `BASE_REF: ^refs/heads/main$`;
   * `FILE_PATH` to skip docs-only changes.

   CodeBuild reports the build status back to the PR as a commit status.
2. **CodeCommit:**
   * An **EventBridge rule** on `CodeCommit Pull Request State Change` (`pullRequestCreated`, `pullRequestSourceBranchUpdated`) starts a CodeBuild project, passing the source commit as `sourceVersion`.
   * On completion, an EventBridge rule on `CodeBuild Build State Change` triggers a Lambda that posts a comment and, if wanted, an **approval** on the PR.
   * Pair this with an **approval rule template** that requires that approval before merging.

## 5. Load, stress and performance testing

* **Generate load from AWS:** CodeBuild batch builds (many parallel builds); ECS Fargate tasks launched by Step Functions (a `Map` state for scale-out); or AWS's **Distributed Load Testing on AWS** solution (a CloudFormation-deployed solution that runs load tests from Fargate containers).
* **Decide pass/fail on metrics.** After the run, query CloudWatch (p99 latency, error rate) and exit non-zero if the thresholds are breached.
* **Test at scale in an isolated account** (P6). Load tests can trip account-level quotas such as Lambda concurrency or API rate limits, which would otherwise affect production in a shared account.

## 6. Security testing in the pipeline

| Tool | What it does | Notes |
|---|---|---|
| **Amazon Inspector** | Continuous vulnerability scanning of **ECR images** (enhanced scanning), **Lambda functions** (packages, and code scanning), and **EC2** (via the SSM Agent) | Findings go to EventBridge and Security Hub. Gate a pipeline by querying findings for the image digest, or with Inspector's CI/CD integration (the `inspector-sbomgen` tool and the `inspector-scan` API) |
| **ECR basic scanning** | On-push CVE scan of OS packages | Simpler and cheaper; enhanced (Inspector) covers language packages and rescans continuously |
| **AWS CloudFormation Guard** (`cfn-guard`) | Policy-as-code rules checked against templates: "every S3 bucket must have encryption" | Runs in CodeBuild; a non-zero exit on violation |
| **cfn-lint** | Template validity and best-practice checks | Runs in CodeBuild before deploying |
| **CloudFormation Hooks** | Server-side proactive checks that run *during* stack operations and can fail them | Enforced even for engineers who skip the pipeline |
| **Amazon CodeGuru Reviewer** | Automated code review on PRs | In maintenance: closed to new customers since 2025-11-07. Recognize it in options; prefer other tools for new designs |
| **Amazon Macie** | Sensitive data in S3 | Not a code scanner; don't confuse the two |

## 7. Measuring application health from exit codes and probes

* **CodeBuild:** every command's exit code. Chain commands with `&&`, or use `set -e`, so that a failure isn't masked by a later successful command.
* **CodeDeploy:** `ValidateService` scripts (EC2) and hook Lambda functions (ECS, Lambda) report success or failure.
* **Containers:**
  * The Docker/ECS **container health check** (`healthCheck.command` returns 0 for healthy).
  * An unhealthy essential container causes ECS to replace the task.
  * Kubernetes **readiness and liveness probes** gate EKS rollouts.
* **Load balancers:** target-group health checks (path, port, matcher codes, healthy/unhealthy thresholds) decide whether a target receives traffic. The **ASG health check type must be `ELB`** if ELB failures should replace instances.

## 8. Invoking AWS services from a pipeline for testing

* **Lambda invoke action:** custom checks, such as calling an endpoint, verifying a database migration, or warming caches. It must report its job result.
* **Step Functions action:** multi-step test orchestration with waits and retries, e.g. deploy a test fixture, run the test, tear down.
* **CodeBuild action:** the workhorse for running any test framework.
* **AWS FIS action** (through Step Functions or CodeBuild calling `StartExperiment`): run a chaos experiment in staging. FIS experiments define **stop conditions** (CloudWatch alarms) that halt the experiment if the blast radius grows.
* **CloudWatch Synthetics:**
  * **Canaries** are scripted checks (Node.js or Python, Puppeteer, Playwright or Selenium) that run on a schedule against endpoints or UI flows.
  * Use them **after deployment** to production, and alarm on `SuccessPercent`.
  * The alarm feeds rollback: CodeDeploy alarms, or a CodePipeline V2 on-success condition.

## 9. Exam traps

* **"Run tests on every pull request"** is not a stage in the main-branch pipeline. It's a PR-triggered build.
* **Test reports** visualize results; only the **exit code** gates the build.
* **Integration tests** belong after a deployment to a test environment, against the deployed artifact.
* **"Fail the deployment if the new version's latency degrades in production"** is an alarm-based rollback in canary deployments. Neither a pre-production load test nor a manual approval is an automatic production gate.
* **Testing with production credentials or data** is a red flag. Use separate accounts and synthetic or anonymized data.

## References

* CodeBuild test reports — <https://docs.aws.amazon.com/codebuild/latest/userguide/test-reporting.html>
* CodeBuild code coverage reports — <https://docs.aws.amazon.com/codebuild/latest/userguide/code-coverage-report.html>
* CodeBuild webhook filter events (GitHub) — <https://docs.aws.amazon.com/codebuild/latest/userguide/github-webhook.html>
* Amazon Inspector — <https://docs.aws.amazon.com/inspector/latest/user/what-is-inspector.html>
* AWS CloudFormation Guard — <https://docs.aws.amazon.com/cfn-guard/latest/ug/what-is-guard.html>
* CloudWatch Synthetics canaries — <https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Synthetics_Canaries.html>
* AWS Fault Injection Service stop conditions — <https://docs.aws.amazon.com/fis/latest/userguide/stop-conditions.html>
* Distributed Load Testing on AWS — <https://aws.amazon.com/solutions/implementations/distributed-load-testing-on-aws/>

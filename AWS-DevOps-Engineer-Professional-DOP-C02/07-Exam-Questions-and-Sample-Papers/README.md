# 07 · Exam Questions and Sample Papers

Everything you need to practise is in this one folder: domain drills, three full-length mock papers with separate answer files, and a trap catalogue. **Every question is original.** None are copied from AWS material or "exam dump" sites. They're written against the official DOP-C02 task statements, and every option is explained with a link to the AWS documentation that settles it.

## Contents

| File | What it is | Questions |
|---|---|---|
| [01-domain-1-sdlc-automation-drill.md](01-domain-1-sdlc-automation-drill.md) | Domain 1 drill, answers inline (collapsed) | 20 |
| [02-domain-2-configuration-management-and-iac-drill.md](02-domain-2-configuration-management-and-iac-drill.md) | Domain 2 drill | 20 |
| [03-domain-3-resilient-cloud-solutions-drill.md](03-domain-3-resilient-cloud-solutions-drill.md) | Domain 3 drill | 20 |
| [04-domain-4-monitoring-and-logging-drill.md](04-domain-4-monitoring-and-logging-drill.md) | Domain 4 drill | 20 |
| [05-domain-5-incident-and-event-response-drill.md](05-domain-5-incident-and-event-response-drill.md) | Domain 5 drill | 20 |
| [06-domain-6-security-and-compliance-drill.md](06-domain-6-security-and-compliance-drill.md) | Domain 6 drill | 20 |
| [07-mock-paper-1.md](07-mock-paper-1.md) + [answers](07-mock-paper-1-answers.md) | Full mock paper 1 | 75 |
| [08-mock-paper-2.md](08-mock-paper-2.md) + [answers](08-mock-paper-2-answers.md) | Full mock paper 2 | 75 |
| [09-mock-paper-3.md](09-mock-paper-3.md) + [answers](09-mock-paper-3-answers.md) | Full mock paper 3 (harder, more multi-constraint scenarios) | 75 |
| [10-trap-catalogue.md](10-trap-catalogue.md) | The 60 recurring distractor patterns | — |
| **Total** | | **345** |

## How to use

1. **Drills** come after each domain's notes. Answer, then open the explanation, and read the explanation for **every** option. The `Why (Pn)` line names the first principle the question turns on. Log every miss with that principle.
2. **Mock papers** come in week 8, under exam conditions:
   * 180 minutes, no notes, answers file closed.
   * Mark your answers with the answers file.
   * Tally by domain: each question is labelled with its domain and task.
3. **Readiness:** 80% or better (60/75) on every paper, and 70% or better in every domain. Then take AWS's free official material as a final calibration:
   * [Official DOP-C02 sample questions (10, PDF)](https://d1.awsstatic.com/training-and-certification/docs-devops-pro/AWS-Certified-DevOps-Engineer-Professional_Sample-Questions.pdf)
   * [AWS Skill Builder exam prep for DOP-C02](https://skillbuilder.aws/category/exam-prep/devops-engineer-professional-DOP-C02) (includes the Official Practice Question Set)
4. **The trap catalogue** is for the final days and the night before the exam.

## Question format and conventions

* **Single answer:** one correct option of four (A–D). **Select TWO:** two correct of five (A–E). **Select THREE:** three correct of six (A–F). This mirrors the exam's response types.
* **Each explanation contains:** the key; a `Why (Pn)` line tying the question to a first principle; a correct or wrong verdict with a reason for **every** option; and one AWS documentation reference.
* **Exam-realistic wording:** "MOST operationally efficient", "LEAST operational overhead", "MOST cost-effective" and so on are used as on the exam. See [00/03](../00-Exam-Strategy-and-First-Principles/03-decoding-questions-and-elimination.md) for how to decode them.
* **Services that changed after the exam was written** (CodeCommit's return to general availability, retired OpsWorks and CodeStar, ECS native blue/green, the new Security Hub) are handled as described in the [repo README](../README.md#what-changed-since-dop-c02-was-written-status-on-2026-10-29). Questions never depend on a retired service being the right answer.

## Verification (the gate)

The question bank is checked by a validator script (`validate_questions.py`, kept in the author's working environment). On **2026-10-29** it reported **ALL OK** for 345 questions:

| Check | Result |
|---|---|
| Option count matches the type (4 / 5 / 6) and options are lettered in order | 345 / 345 |
| Number of keyed answers matches the type (1 / 2 / 3) | 345 / 345 |
| Every option has a `correct`/`wrong` explanation, and the labels agree with the key | 345 / 345 |
| Every question has a `Why (Pn)` principle line and an AWS documentation reference | 345 / 345 |
| Multiple-response stems end with "(Select TWO.)" / "(Select THREE.)" | all |
| Task labels belong to the question's domain | all |
| Each mock paper has 75 questions in the official mix: D1 17 · D2 13 · D3 11 · D4 11 · D5 10 · D6 13 | 3 / 3 |
| Single-answer key letters balanced (each letter 15–35%) | paper 1: A15 B16 C16 D18 · paper 2: A15 B18 C15 D17 · paper 3: A17 B18 C16 D16 |
| Multiple-response share 10–30% per paper | 10 / 10 / 8 of 75 |
| Near-duplicate stems across the whole bank (word-set Jaccard > 0.6) | none |
| Every reference URL fetched by the link checker | all return HTTP 200 (433 / 433 URLs across the repo) |

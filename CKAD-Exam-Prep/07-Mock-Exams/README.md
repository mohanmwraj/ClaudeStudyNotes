# Mock Exams — 6 full papers with solutions

Six full 2-hour papers. Each one follows the official domain weights (Design & Build 20 · Deployment 20 · Observability 15 · Environment/Config/Security 25 · Services & Networking 20) and touches **all 24 official curriculum competencies**. Each `solutions.md` ends with a coverage matrix.

> These are exam-**style** papers modelled on the official CNCF curriculum and on task patterns that candidates describe publicly. Real exam questions are confidential under the Linux Foundation candidate agreement; nothing here is a leaked question.

| # | Theme | Difficulty | Take it |
|---|---|---|---|
| 01 | Foundations — mostly single-step tasks | ★★☆☆☆ | [questions](mock-exam-01/questions.md) · [solutions](mock-exam-01/solutions.md) |
| 02 | Foundations+ — first troubleshooting tasks | ★★★☆☆ | [questions](mock-exam-02/questions.md) · [solutions](mock-exam-02/solutions.md) |
| 03 | Intermediate | ★★★☆☆ | [questions](mock-exam-03/questions.md) · [solutions](mock-exam-03/solutions.md) |
| 04 | Intermediate+ | ★★★★☆ | [questions](mock-exam-04/questions.md) · [solutions](mock-exam-04/solutions.md) |
| 05 | Advanced, multi-step | ★★★★☆ | [questions](mock-exam-05/questions.md) · [solutions](mock-exam-05/solutions.md) |
| 06 | Final boss — harder than the real exam (killer.sh-like) | ★★★★★ | [questions](mock-exam-06/questions.md) · [solutions](mock-exam-06/solutions.md) |

---

## How to take a mock exam

1. Build the practice cluster once: [../00-Exam-Overview-and-Setup/02-local-practice-lab-setup.md](../00-Exam-Overview-and-Setup/02-local-practice-lab-setup.md). You need kind or minikube, plus an ingress controller and metrics-server for some tasks.
2. Prepare the exam's starting state:
   ```bash
   cd 07-Mock-Exams/mock-exam-01
   bash setup.sh          # creates namespaces m01-*, pre-broken objects, files under ~/ckad-mocks/exam-01/
   ```
   `setup.sh` prints a WARNING, but carries on, when an optional component is missing (metrics-server, ingress controller, helm, podman/docker).
3. Start a **120-minute timer**. Open only kubernetes.io/docs, kubernetes.io/blog and helm.sh/docs.
4. Work through `questions.md` using the three-pass plan ([strategy](../00-Exam-Overview-and-Setup/04-exam-strategy-and-time-management.md)).
5. Grade yourself with `solutions.md`. Each question has a points breakdown for partial credit, and a table at the end maps every miss to the chapter to revise.
6. Reset: `bash cleanup.sh`, which removes only what that exam created.

## Scoring guide

| Score | Meaning |
|---|---|
| ≥ 80% on 01–04 | On track. Spend remaining time on speed and on mock 05/06. |
| 66–79% | Passing range. Review every miss and re-type its YAML. |
| < 66% | Find the weakest domain in the scoring table, redo that chapter's 🔥 practice questions, then retake the same mock the next day. |
| ≥ 66% on mock 06 | Strong signal that you're ready. |

## Suggested order with the 4-day plan

Sunday → 01 · Monday → 02 (or killer.sh #1) · Tuesday → 03 or 04, then 05 if time allows · 06 optional. See [../00-Exam-Overview-and-Setup/05-study-plan-4-days.md](../00-Exam-Overview-and-Setup/05-study-plan-4-days.md).

Running the scripts on Windows: use WSL2 (`bash setup.sh`) or Git Bash, with `kubectl` pointing at your practice cluster. The scripts use LF line endings. Keep them that way, because CRLF breaks bash.

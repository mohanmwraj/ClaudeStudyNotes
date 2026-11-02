# Claude Study Notes

A library of self-contained study kits and Staff/Principal-level (L6/L7) engineering references. It covers certifications, coding and interview rounds, languages and runtimes, distributed systems and cloud, AI engineering, and career playbooks.

**Size:** 23 folders · 960 Markdown files · ~5.1M words (including code listings).

**How to use it:** every folder stands on its own. Open the entry-point file linked in the tables below. It explains the folder's layout, reading order and verification status. Exam facts, versions and product names were checked against official sources on the date each folder states.

---

## Certification kits

| Folder | What's inside | Files · words | Last commit |
|---|---|---|---|
| [CKAD-Exam-Prep](CKAD-Exam-Prep/README.md) | Certified Kubernetes Application Developer on **Kubernetes v1.37**: a folder per exam domain with notes, reference YAML and hands-on tasks. Exam facts verified against Linux Foundation and CNCF pages. | 96 · ~262k | 2026-10-17 |
| [AWS-SAP-C02-Study-Guide](AWS-SAP-C02-Study-Guide/00-README-Start-Here.md) | AWS Solutions Architect – Professional (SAP-C02): 19 chapters from blueprint to FinOps, with keywords, traps and skills checklists, official sample questions explained, 5 original practice papers (100 questions), cheat sheets and a glossary | 26 · ~323k | 2026-10-17 |
| [AWS-DevOps-Engineer-Professional-DOP-C02](AWS-DevOps-Engineer-Professional-DOP-C02/README.md) | AWS DevOps Engineer – Professional (DOP-C02), taught from first principles, with labs and original practice questions, including full-length mocks | 39 · ~112k | 2026-10-29 |
| [GCP-Professional-Cloud-Architect-PCA](GCP-Professional-Cloud-Architect-PCA/README.md) | Google Cloud Professional Cloud Architect on the **v6.1 exam guide**, with 2026 product names, case studies and original practice questions, including mocks | 53 · ~121k | 2026-10-29 |

## Coding, algorithms and coding-round playbooks

| Folder | What's inside | Files · words | Last commit |
|---|---|---|---|
| [CP-Codeforces-Master-Kit](CP-Codeforces-Master-Kit/README.md) | Codeforces Master (2100+) by Dec 2027, with depth toward International Grandmaster, plus the complete FAANG DSA syllabus. Derivations, worked examples, practice ladders and LeetCode cross-references, with **every implementation in C++ and Java**. Includes per-topic cheat sheets and a master formula sheet. | 196 · ~1.17M | 2026-10-24 |
| [L7-Coding-Bar-Raiser-CP-to-Production-Reference](L7-Coding-Bar-Raiser-CP-to-Production-Reference/README.md) | Contest patterns rewritten as production code, each extended for concurrency, streaming or bounded RAM, and distribution. Java 21 + C++23 (GCC and Clang). | 21 · ~192k | 2026-10-29 |
| [LLD-Concurrency-Machine-Coding-L7-Reference](LLD-Concurrency-Machine-Coding-L7-Reference/README.md) | Low-level design and concurrency machine coding: 20 complete thread-safe problems, synchronization bar-raisers and modern OOP/DOP. Every sample in Java 21/25 and C++23 (85 verified listings). | 33 · ~238k | 2026-10-28 |
| [Live-PR-Code-Review-Bug-Hunt-L7-Reference](Live-PR-Code-Review-Bug-Hunt-L7-Reference/README.md) | The live pull-request review and bug-hunt round: a review mental model and rubric, a bank of PR simulations with real diffs, and a red-flag catalog | 17 · ~166k | 2026-10-30 |

## Languages and runtimes

| Folder | What's inside | Files · words | Last commit |
|---|---|---|---|
| [Java-Backend-Master-Reference](Java-Backend-Master-Reference/README.md) | Core, advanced and enterprise Java on JDK 21/25 (notes to JDK 27): JVM, concurrency, I/O, persistence/JPA, Spring and microservices, AI engineering, observability. Runnable Java 25 code with captured output. | 61 · ~213k | 2026-10-24 |
| [Modern-Cpp-ABI-STL-Concurrency-L7-Reference](Modern-Cpp-ABI-STL-Concurrency-L7-Reference/README.md) | C++11 → C++26: object model and Itanium ABI, STL internals, templates and compile-time programming, memory model and hardware coherency, lock-free structures, coroutines and `std::execution` | 45 · ~236k | 2026-10-28 |
| [Silicon-Systems-C-L7-Reference](Silicon-Systems-C-L7-Reference/README.md) | Systems C on real silicon: ISO C11/C17/C23 and undefined behavior, bare-metal boot and linker scripts, weak memory models and DMA coherency, Cortex-M/R/A, RISC-V and x86-64 interrupts, RTOS and kernel internals | 26 · ~169k | 2026-10-26 |
| [Python-Data-ML-Systems-L7-Reference](Python-Data-ML-Systems-L7-Reference/README.md) | Python's data, analytics and ML stack from the CPython runtime up, written for engineers coming from Java and C++ | 29 · ~162k | 2026-10-29 |

## Systems, data and cloud architecture

| Folder | What's inside | Files · words | Last commit |
|---|---|---|---|
| [Distributed-Systems-Design-L7-Reference](Distributed-Systems-Design-L7-Reference/README.md) | Distributed systems and large-scale design from first principles: latency and cost physics, consistency, consensus, clocks and transactions, and 32 production design blueprints | 31 · ~150k | 2026-10-27 |
| [Unified-Dataflow-Beam-Flink-L7-Reference](Unified-Dataflow-Beam-Flink-L7-Reference/README.md) | Stream and batch processing: the Dataflow Model, Beam portability, Google Cloud Dataflow (Runner v2, Streaming Engine, Shuffle) and Apache Flink (1.20 LTS, 2.x disaggregated state) | 26 · ~133k | 2026-10-26 |
| [AWS-vs-GCP-Under-the-Hood-L7-Reference](AWS-vs-GCP-Under-the-Hood-L7-Reference/README.md) | AWS and Google Cloud compared at the level of hypervisors, network fabrics, storage engines and control planes | 21 · ~189k | 2026-10-31 |
| [Embedded-Linux-Secure-Boot-OTA-Wireless-L7-Reference](Embedded-Linux-Secure-Boot-OTA-Wireless-L7-Reference/README.md) | Platform firmware from reset vector to userspace: hardware root of trust, TF-A, OP-TEE, U-Boot verified boot, Yocto, OTA (OSTree, TUF), kernel and BSP drivers. **Folders 01–04 of 08 are done; 05–08 (BLE, Wi-Fi, code recipes, company playbook) are still to come.** | 17 · ~115k | 2026-10-28 |

## AI engineering

| Folder | What's inside | Files · words | Last commit |
|---|---|---|---|
| [Production-AI-Engineering-L7-Reference](Production-AI-Engineering-L7-Reference/README.md) | Production AI systems: LLM inference physics (roofline, KV cache, FlashAttention, PagedAttention), distributed serving, vector-database internals, enterprise RAG and durable agent workflows | 26 · ~189k | 2026-10-27 |
| [ML-Foundations-for-AI-Engineers-L7-Reference](ML-Foundations-for-AI-Engineers-L7-Reference/README.md) | The math, classical ML, deep-learning mechanics and statistical evaluation underneath AI engineering, each tagged must-know, good-to-know or skip | 27 · ~219k | 2026-10-30 |
| [Claude-Power-User-Agentic-Engineering-L7-Reference](Claude-Power-User-Agentic-Engineering-L7-Reference/README.md) | Using Claude well on the web and desktop (Projects), through the API and in Claude Code. Includes code listings, XML prompt templates and a ready-made `.claude` configuration blueprint. | 35 · ~143k | 2026-10-30 |

## Interview and career playbooks

| Folder | What's inside | Files · words | Last commit |
|---|---|---|---|
| [Staff-Backend-Interview-Playbook](Staff-Backend-Interview-Playbook/README.md) | Senior (L5) and Staff (L6) backend interviews on Java, Spring, PostgreSQL, Kafka and Kubernetes, in 10 pillars (Kafka is Pillar 10) | 79 · ~298k | 2026-10-26 |
| [Staff-Principal-Behavioral-L7-Playbook](Staff-Principal-Behavioral-L7-Playbook/README.md) | Behavioral rounds: how hiring committees score scope, storytelling under probing, influence, conflict, ambiguity, outages, company-specific rubrics and L5-vs-L7 story pairs | 25 · ~98k | 2026-10-28 |
| [Past-Project-Deep-Dive-L7-Defense-Playbook](Past-Project-Deep-Dive-L7-Defense-Playbook/README.md) | The 60-minute past-project deep-dive: presenting a real architecture and defending it against skeptical interviewers, at its true scope | 16 · ~137k | 2026-10-31 |
| [L6-L7-Resume-Leveling-Team-Match-and-Comp-Negotiation-Playbook](L6-L7-Resume-Leveling-Team-Match-and-Comp-Negotiation-Playbook/README.md) | Everything outside the interview rounds: resume and LinkedIn positioning, level calibration, hiring-manager and team-match conversations, avoiding down-levels, and compensation negotiation | 15 · ~91k | 2026-10-31 |

---

## Suggested tracks

| Goal | Folders, in order |
|---|---|
| **Staff/Principal backend interview loop** | Staff-Backend-Interview-Playbook → Distributed-Systems-Design → LLD-Concurrency-Machine-Coding → L7-Coding-Bar-Raiser → Live-PR-Code-Review → Past-Project-Deep-Dive → Staff-Principal-Behavioral → L6-L7-Resume-Leveling-and-Comp |
| **AI engineer** | ML-Foundations → Python-Data-ML-Systems → Production-AI-Engineering → Claude-Power-User |
| **Data platforms** | Distributed-Systems-Design → Unified-Dataflow-Beam-Flink → AWS-vs-GCP-Under-the-Hood |
| **Systems and firmware** | Silicon-Systems-C → Modern-Cpp → Embedded-Linux |
| **Cloud certifications** | AWS-SAP-C02 → AWS-DevOps-Pro → GCP-PCA (with AWS-vs-GCP for the why) · CKAD |
| **Competitive programming** | CP-Codeforces-Master-Kit, then L7-Coding-Bar-Raiser to turn contest code into production code |

## Conventions

- **Entry points:** each folder's `README.md` (`00-README-Start-Here.md` for SAP-C02) has the reading order and status.
- **Verification:** exam facts, versions and product names carry the date they were checked. Folders with code state how their listings were compiled and run, and show captured output, not output written from memory.
- **Local-only material:** personal notes that should stay off the remote are listed in `.gitignore` and aren't indexed here.

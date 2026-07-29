# PRD — AIP-C01 Hands-On Learning Programme

**Owner:** Yu · **Duration:** 30 days · **Budget:** 4–5 hrs/day (~120–150 hrs)
**Status:** DRAFT — awaiting sign-off

---

## 1. Problem

The AWS Skill Builder exam-prep plan for AWS Certified Generative AI Developer – Professional (AIP-C01)
contains 20 tasks across 5 domains, each ending in an open-ended bonus assignment. Followed literally,
this means 20 disconnected proof-of-concepts, ~200+ hours, heavy duplicated scaffolding, and reference
code that no longer runs. Needed instead: a structure that covers every stated skill, fits 30 days,
costs under ~$100, and produces portfolio evidence.

## 2. Objectives

**Primary:** Hands-on mastery of the AWS services and techniques behind all 97 skill statements.
**Secondary:** A portfolio artefact and 9 LinkedIn posts demonstrating end-to-end GenAI capability on AWS.
**Not an objective this month:** Sitting the exam. No question-drilling time is budgeted.

## 3. Success criteria

| # | Criterion | Measure |
|---|---|---|
| SC1 | Full skill coverage | 97/97 rows in `coverage-matrix.csv` marked DONE with evidence |
| SC2 | Cost control | Total AWS spend ≤ $100; zero orphaned billable resources at month end |
| SC3 | Measured results | Every sprint publishes ≥1 benchmarked number (latency, cost, recall, block-rate) |
| SC4 | Working system | One deployed system exercising every domain, demoable end-to-end |
| SC5 | Console evidence | Every post shows real AWS console / CloudWatch proof, not just UI |

## 4. Constraints

- **Time:** 4–5 hrs/day, 30 days. Freelance work continues in parallel.
- **Cost:** Solo operator, no expense account. Cost anxiety is a design input, not an afterthought.
- **Tooling:** AWS Console driven, in-app browser. Codex guides one sub-task at a time. Codex gets **no AWS credentials** — Yu executes every action.
- **Course code is unusable as-is.** See §6.

## 5. Scope

**In:** all 20 tasks, all 97 skill statements, 21 stretch items from the four extension sections
(Tasks 1.1, 1.6, 2.5, 3.2).
**Out:** exam question drilling; production hardening (multi-tenancy, load testing, SLAs);
Bedrock Provisioned Throughput execution (§7).

## 6. Key finding — the reference code is dead on arrival

Counted across all 20 bonus assignments:

| Course uses | Count | Reality |
|---|---|---|
| `anthropic.claude-v2` | 43 | Retired |
| `anthropic.claude-instant-v1` | 21 | Retired |
| `invoke_model` + `max_tokens_to_sample` | 64 / 28 | Legacy completion API |
| `converse()` | 0 | The current standard |
| `amazon.titan-rerank-v1` | 1 | Not a valid model ID |

**Consequence:** Sprint 0 produces a translation layer (legacy → Converse API, retired → current models)
that every later sprint imports. Copy-pasting course code is not a viable path; it will not execute.
This is also an exam consideration — AIP-C01 tests the current API surface.

## 7. Cost doctrine

**The enemy is orphaned resources, not expensive services.** Hourly-billed resources are affordable
inside a timebox; they are ruinous when forgotten.

| Resource | Hourly | 4-hr learning window |
|---|---|---|
| OpenSearch Serverless (4 OCU) | ~$0.96 | ~$4 |
| OpenSearch managed domain (t3.small) | ~$0.04 | ~$0.15 |
| SageMaker endpoint (ml.m5.large) | ~$0.12 | ~$0.50 |
| Kendra Developer Edition | ~$1.13 | ~$4.50 |

Controls: budgets + anomaly detection (alerting only, ~8–24 hr lag — smoke detector, not sprinkler);
per-sprint resource tagging for Cost Explorer attribution; same-day teardown; nightly orphan-sweep script.

**Hard prohibition — the one asymmetric risk:**
`bedrock create-provisioned-model-throughput`. Commitment terms **cannot be cancelled**.
Task 2.2 instructs this directly. **Decision: simulate only.** TPS sizing, ARN-as-modelId pattern
and the on-demand-vs-PT tradeoff are learned on paper. One sub-skill remains theory-only; accepted.

**Baseline vs ephemeral:** baseline resources (budgets, study IAM role, one S3 bucket, Bedrock model
access) are created once and never deleted. Everything else is created and destroyed within its sprint.

### 7.1 Evaluation harness cost — the non-obvious line item

Inference at study scale is pennies. The **evaluation harness is not**, because cost scales as
`cases × metrics × runs`, and the third term is the one that surprises people: you don't run an
eval once, you run it every time you change a chunking parameter.

Reference rates (on-demand, per 1M tokens): Nova Micro $0.035 in / $0.14 out ·
Nova Pro $0.80 / $3.20 · Claude Haiku $1.00 / $5.00.

Per judged case ≈ 3.5k input (question + context + answer + rubric) and ~300 output.

| Configuration | Per run | 30 iteration runs |
|---|---|---|
| 200 cases × 6 metrics, Nova Pro judge | ~$4.60 | **~$138** |
| 200 cases × 6 metrics, Claude Haiku judge | ~$6.00 | **~$180** |
| 50 cases × 2 metrics, Nova Pro judge | ~$0.38 | ~$11 |
| 50 cases × 2 metrics, Nova Micro judge + prompt caching + batch | ~$0.02 | ~$1 |

**The naive default blows the entire $100 budget on Sprint 9 alone.**

Policy: during iteration use a 50-case set, 2 metrics, cheap judge, prompt caching on the static
rubric (up to 90% off cached input) and batch mode (50% off) for non-interactive runs. The full
200-case × 6-metric configuration with a strong judge runs **twice only** — one baseline, one final —
and those are the numbers that get published. Budget line: ~$15, not ~$140.

This is itself Task 4.1 material (token efficiency, cost-effective model selection) applied to your
own tooling, and it is a better post than the eval scores.

## 8. The spine

One system, built across nine sprints, rather than 20 standalone PoCs. Domain: **customer support
assistant** — the course's own dominant scenario (12 of 20 assignments use it verbatim), so assignments
map with minimal re-skinning.

### 8.1 How the 8 non-support assignments map onto the spine

12 of 20 assignments name a customer support assistant outright. The other 8 use different
scenarios and are re-skinned. Skills are service-level and technique-level, so nothing is lost —
only the surrounding story changes.

| Task | Course scenario | Becomes in the spine |
|---|---|---|
| 1.1 | Insurance claim documents | Support ticket intake — document in, structured fields + summary out |
| 1.4 | Knowledge assistant over technical docs / policies | The support knowledge base (vector store layer) |
| 1.5 | Same scenario as 1.4, verbatim | The retrieval layer of that same knowledge base |
| 2.3 | Enterprise GenAI integration gateway | The gateway fronting the assistant for internal consumers |
| 2.4 | Legal contract / technical document analysis | Ticket attachment analysis |
| 3.2 | Secure document analysis system | PII handling across tickets and attachments |
| 3.3 | Regulatory compliance and governance system | Governance layer over the assistant |
| 3.4 | Responsible AI for financial advice | Billing and refund guidance — **the one imperfect fit** |

Task 3.4 is the only forced mapping. Financial advice carries specific disclosure and fairness
obligations; billing guidance carries weaker but real ones. If it distorts the spine when S7
arrives, 3.4 is built as a side-branch instead.

### 8.2 Project name, naming convention and tagging

**Project name: `deskai`** — reads as "Desk AI", an AI help desk.

Chosen for public legibility. The name appears in every console screen in every demo video and in
every LinkedIn post, so it must be understood by a viewer with zero context — including
non-technical recruiters. `deskai` states what the system is without explanation.
Six characters, lowercase, no spelling variants, no significant brand collision.

Because the AWS console appears in every demo video (§14), resource names are part of the
deliverable. A viewer gets roughly three seconds per screen: `deskai-s2-kb-support-policies` reads
immediately; `test-bucket-2` destroys credibility faster than a poor UI does.

**Pattern:** `deskai-s{n}-{type}-{purpose}`

| Resource | Example |
|---|---|
| S3 bucket | `deskai-s2-kb-source-{4-char account suffix}` |
| Lambda | `deskai-s1-fn-extract` |
| IAM role | `deskai-s1-role-fn-extract` |
| Knowledge Base | `deskai-s2-kb-support-policies` |
| Guardrail | `deskai-s3-gr-pii-redact` |
| OpenSearch collection | `deskai-s2-aoss-bakeoff` |
| DynamoDB table | `deskai-s5-tbl-sessions` |
| API Gateway | `deskai-s6-api-gateway` |
| Log group | `/aws/lambda/deskai-s1-fn-extract` |

S3 bucket names are globally unique, so buckets carry a short account-derived suffix. Everything
else uses the bare pattern.

**Mandatory tags on every resource:**

| Tag | Value | Purpose |
|---|---|---|
| `Project` | `deskai` | Cost Explorer filtering |
| `Sprint` | `S2` | Per-sprint cost attribution for the evidence pack |
| `Task` | `1.4` | Traceability back to the coverage matrix |
| `Ephemeral` | `true` / `false` | Distinguishes baseline from teardown-eligible |
| `TeardownBy` | ISO date | Drives the orphan sweep |

The orphan sweep flags any resource with `Ephemeral=true` past its `TeardownBy` date. Tagging is
therefore not paperwork — it is the mechanism that prevents unplanned spend, and it is what makes
the Cost Explorer evidence in §14 possible.

Consolidation is not only cheaper, it is *required* for several skills to be genuine:
Task 1.1's "standardize technical components" cannot be satisfied by components that are never reused;
Tasks 4.1/4.2 (optimisation) need a system with baseline metrics; 5.1 (evaluation) needs history;
5.2 (troubleshooting) needs real accumulated bugs.

## 9. Sprint plan

Eleven sprints, S0–S10. No day numbers — timeline is not a constraint (§15).

| Sprint | Tasks | Rows | Ceiling | Focus |
|---|---|---|---|---|
| **S0** Foundation | — | — | $1 | Account hardening, budgets, tags, IAM, model access, Converse translation layer, Streamlit shell, orphan sweep |
| **S1** Ingest & Extract | 1.1, 1.3 | 11 | $2 | S3, Converse, Textract, Comprehend, validation pipelines, reusable components |
| **S2** RAG & Vector Stores | 1.4, 1.5 | 11 | $15 | Knowledge Bases, 3-way vector bake-off, chunking strategies, hybrid search, rerank |
| **S3** Prompting & Safety | 1.6, 3.1 | 16 | $5 | Prompt Management, Guardrails, injection defence, hallucination reduction |
| **S4** Model Selection & Customization | 1.2, 2.2 | 7 | $12 | FM evaluation, SageMaker fine-tune + Model Registry, PT on paper only |
| **S5** Agentic & FM APIs | 2.1, 2.4 | 11 | $6 | Bedrock Agents, tool use, streaming, routing, resilience |
| **S6** Enterprise Integration | 2.3, 2.5 | 15 | $8 | API Gateway, Step Functions, EventBridge, CI/CD, second region, Lex |
| **S7** Security & Governance | 3.2, 3.3, 3.4 | 18 | $10 | PII/KMS, Lake Formation, lineage, model cards, **fairness evaluation** |
| **S8** Cost & Performance | 4.1, 4.2 | 10 | $8 | Prompt caching, batching, token efficiency, latency tuning |
| **S9** Observability & Evaluation | 4.3, 5.1 | 14 | $15 | CloudWatch dashboards, eval harness, LLM-as-judge, CI quality gate |
| **S10** Troubleshooting & Final Assembly | 5.2 | 5 | $10 | Failure catalogue, runbook, full-system walkthrough, close-out |

**Ceilings total $92 against a $100 budget** — near-zero headroom if every sprint hits its ceiling.
Realistic estimates total ~$40. The two ceilings most likely to be tested are S2 (timeboxes) and
S9 (evaluation runs); both have explicit controls in their briefs.

Sequencing note: a lightweight eval harness lands in S2 (needed to measure retrieval recall) and is
formalised in S9. Basic budget/CloudWatch instrumentation lands in S0, not S8 — guardrails are worthless
if installed last.

## 10. Sprint anatomy

1. **Console build.** Codex feeds one sub-task at a time: goal → console path → ready-to-paste
   materials → *"you'll know it worked when…"* → screenshot for the evidence pack.
2. **Measure.** Produce the sprint's headline number (required by SC3).
3. **Demo, teardown, post.** Extend the app, capture console evidence per §14, run teardown,
   verify the orphan sweep is clean, publish tagged `#awsexamprep`.

No design gate, no build-it-yourself block. Straight from brief to console.

## 11. Codex brief format

```
SPRINT N — <title>
Objective          what exists at the end, one sentence
Skill IDs closed   explicit rows from coverage-matrix.csv
Architecture       services + connections
Cost ceiling       $X · FORBIDDEN this sprint: [...]
Baseline used      what must already exist
Ephemeral created  what gets destroyed at the end
Sub-tasks          1..N, each: goal · full console path · ready-to-paste
                   code/config · "you'll know it worked when…"
Demo increment     what the UI gains
TEARDOWN           ordered delete list + verification command
Post angle         the measured number + the non-obvious finding
```

Codex operates strictly inside the brief. The FORBIDDEN list is what stops it wandering into
billable services unnoticed.

## 12. Risks

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | **Provisioned Throughput misclick** — unrecoverable spend | **Critical** | Simulate only. Never open the PT console page. |
| R2 | Orphaned OpenSearch/SageMaker/Aurora resources | High | Same-day teardown + nightly orphan-sweep script + per-sprint tags |
| R3 | Sprint overrun cascading into S8/S9 | High | Fixed timeboxes — sprint ends on the clock, not on perfection. Domains 4/5 protected by being last but pre-seeded in S0/S2. |
| R4 | Consolidation silently dropping skills | Medium | Coverage matrix audited weekly; unchecked row = visible gap |
| R5 | Codex improvising outside the brief | Medium | No AWS credentials for Codex; FORBIDDEN list per sprint; Yu executes everything |
| R6 | Multi-store bake-off collapsing to one store | Medium | S2 brief mandates all three; timeboxed and costed |

**Riskiest step: R1.** Every other failure mode costs hours or dollars. That one can cost an
uncancellable monthly commitment.

## 13. Resolved decisions

| # | Decision | Consequence for S0 |
|---|---|---|
| D1 | **Account:** existing, essentially empty | S0 runs a baseline inventory first so the orphan-sweep script has a clean reference point |
| D2 | **Region:** `ap-southeast-1` (Singapore) | Malaysia (`ap-southeast-5`) ruled out — Prompt Management unsupported, blocks Task 1.6. us-east-1 rejected: ~230ms from Malaysia would dominate the latency benchmarks that Tasks 4.1/4.2 exist to measure. Singapore supports S3 Vectors, Prompt Management, Agents, AgentCore Evaluations, Guardrails, Knowledge Bases. |
| D3 | **Model reach:** `apac.*` cross-region inference profiles | Wider model pool with a local endpoint. Doubles as a Task 1.2 discussion point. |
| D4 | **Region fallback rule** | If one sub-task needs a model/feature Singapore lacks, that sub-task alone runs in us-east-1 and the brief flags it. The programme does not relocate. |
| D5 | **Codex:** no AWS credentials | Guidance-only. Yu executes every AWS action. No revocation step needed. |
| D6 | **Spend ceiling:** $100/month | Budget alert at $50 (50%) and $80 (80%); zero-spend anomaly detector on top |
| D7 | **Provisioned Throughput:** simulate only | Task 2.2 sub-skill remains theory-only. Accepted. |
| D8 | **Polish:** all 9 posts at hero level, produced by Codex | Removed as a planning constraint; ~60 hrs reallocated to hands-on AWS time |

## 14. Evidence & demo standard

A polished UI video proves nothing — it is fully fabricable. Every sprint therefore ships an
**evidence pack** alongside the demo. This is a standing requirement, not per-sprint discretion.

### Video anatomy (~70s)

| Time | Segment |
|---|---|
| 0:00–0:08 | Architecture animation, new components highlighted |
| 0:08–0:30 | Live UI demo of the new capability |
| 0:30–0:50 | **Proof segment** (below) |
| 0:50–1:10 | Measured number + teardown confirmation |

### Evidence hierarchy (weakest → strongest)

1. Console screenshots — negligible weight
2. Console screen recording — moderate; AI video generation is closing this gap
3. **Request-ID correlation** — UI displays the Bedrock request ID; CloudWatch Logs Insights query
   for that exact ID returns it with matching timestamp. Two independent surfaces agreeing on a
   random identifier. Highest value-per-second of anything recordable.
4. **CloudTrail events** — the actual `Create*` API calls with principal and timestamp
5. **Cost Explorer filtered by sprint tag** — real spend on real dates. Enabled by the S0 tagging scheme.
6. **Reproducibility** — published deploy steps; converts "trust me" into "go check"

### Mandatory per-sprint evidence pack (committed to repo)

- Console screenshot of created resource, ARN visible, account ID redacted
- CloudWatch log excerpt with request ID matching the demo footage
- CloudTrail event for the create action
- Cost Explorer screenshot filtered to the sprint tag
- Teardown confirmation + clean orphan-sweep output

### Authenticity signals (cheap, disproportionately effective)

- **Show something failing** — a throttle, cold start, guardrail rejection, validation error.
  Fabricated demos are always suspiciously clean.
- **Let git history run the full 30 days** — real gaps and real fix commits are hard to manufacture retroactively.
- **Close on teardown** — proves the resources existed (you cannot delete what was never created),
  demonstrates cost discipline, and is a thing almost no portfolio post does.

**Known ceiling:** none of this constitutes proof to a determined skeptic without account access.
The objective is to make fabrication more expensive than execution, and to make the evidence trail
specific enough that technical viewers recognise it as genuine.

## 15. Seniority calibration

Target level: **senior AWS AI engineer** — both in how the programme is delivered and in what it
is expected to produce. Timeline and hours are explicitly *not* a constraint.

### Delivery changes

- **Step-by-step console navigation is retained in full, for every service, every sprint.**
  Seniority is expressed in what gets designed and defended — not by withholding navigation detail.
  Knowing where a setting lives in a console wizard is recall, not skill; there is no value in
  making Yu hunt for it.
- **All code and configuration is supplied ready to paste.** Because the course's own samples are
  dead (§6), every snippet is freshly authored against the Converse API and current model IDs.
- Sprint output is expected at senior level — measured results, evidence packs, tradeoff reasoning
  in the write-ups.

### Resolved — console navigation

**Decision: full step-by-step console navigation throughout, no tapering.** Every sub-task carries
its console path regardless of whether the service has been used before. Senior-level expectations
apply to design ownership, ADRs, IAM authorship, threat modelling and scale reasoning — not to
navigation friction.

## 14.1 Pause & resume protocol

Life interrupts. The risk is not losing progress — it is **pausing while billable resources are
running**. A sprint abandoned mid-way with an OpenSearch collection or SageMaker endpoint alive is
the single most expensive failure mode in this programme, and it is far more likely than any
technical mistake.

### Every sub-task carries a pause rating

| Rating | Meaning | Pause policy |
|---|---|---|
| 🟢 **GREEN** | Nothing billable created or running — writing code, building corpora, writing ADRs, analysing results | Pause freely, indefinitely |
| 🟡 **AMBER** | Resources exist but bill negligibly at rest — S3, Lambda, on-demand DynamoDB, S3 Vectors KBs, API Gateway | Pause for days. Note what's live in `STATE.md`. Sweep before pausing. |
| 🔴 **RED** | Hourly-billed resources alive — OpenSearch Serverless, Aurora, SageMaker endpoints, Config recorder, NAT Gateway, Macie | **Never pause here.** Complete the teardown step first, even if the sprint is abandoned. |

**RED sub-tasks by sprint:** S2 sub-tasks 8 and 9 · S4 sub-tasks 7 and 9 · S7 sub-tasks 6 and 7.
Everything else in the programme is GREEN or AMBER.

### Emergency stop

If you must stop immediately and cannot work through a teardown, run `scripts/panic_teardown.sh`.
It finds and deletes every hourly-billed resource tagged `Project=deskai` across all three regions,
listing them and requiring confirmation first. It does not touch S3, code, evidence or benchmarks —
only the things that bill by the hour.

**Cost of a panic stop:** you lose the in-progress experiment and repeat perhaps an hour of work.
**Cost of not running it:** an OpenSearch collection at ~$0.96/hour is roughly $23/day and $690/month.
Always run it.

### Resume checklist

1. `git log --oneline -5` — where the code stopped
2. Read `STATE.md` — which sprint, which sub-task, what was live
3. `scripts/orphan_sweep.sh` — what survived the pause
4. Cost Explorer since the pause date — did anything bill while you were away
5. Re-read the sprint's ASSUMPTIONS block; anything torn down during the pause needs rebuilding
6. If the pause exceeded ~2 weeks, verify Bedrock model IDs and console paths before continuing —
   both move

### STATE.md

Maintained continuously, committed with every session:

```markdown
# deskai — current state
Sprint:        S2 · RAG & Vector Stores
Sub-task:      8 of 13 (OpenSearch bake-off)
Pause rating:  🔴 RED — do not stop here
Live billable: NONE (OSS deleted 2026-08-14 16:20)
Live at rest:  deskai-s2-kb-source bucket, 3 knowledge bases on S3 Vectors
Last sweep:    2026-08-14 16:25 — CLEAN
Spend to date: $11.40
Next action:   sub-task 9, Aurora pgvector — 2h timebox
Blocked on:    —
```

### If the pause becomes indefinite

Run the sprint's full teardown plus `panic_teardown.sh`, commit everything, and record in
`STATE.md` where to resume. Keep the baseline bucket, the repo, benchmarks, evidence and ADRs —
they cost effectively nothing and are the whole portfolio. Rebuilding a sprint's infrastructure
from a brief takes 20 minutes; the accumulated evidence cannot be recreated.

## 15.1 Sprint checkpoint protocol

Briefs are written one sprint ahead, never in bulk. Writing S1–S9 up front would mean writing them
against an imagined account: if a model turns out to be unavailable in Singapore, or a console flow
has changed, every downstream brief inherits the error silently.

At the close of every sprint, Yu reports back four things:

1. **What was actually created** — names and ARNs, for the running baseline/ephemeral inventory
2. **What diverged from the brief** — moved console paths, renamed fields, unavailable models,
   anything Codex had to improvise
3. **Actual spend** from Cost Explorer, filtered by the `Sprint` tag
4. **What is still standing** — output of `orphan_sweep.sh`

The next brief is written from that, not from assumption.

## 16. Next step

S0 brief for Codex, pending PRD sign-off.

---

*Companion file: `coverage-matrix.csv` — 118 rows (97 core skills + 21 stretch items),
mapped to sprints, tracked to DONE.*

# SPRINT 10 — Troubleshooting & Final Assembly

> Task 5.2 · 5 core skills · plus programme close-out

## ASSUMPTIONS FROM PRIOR SPRINTS

- [ ] S9 complete; CloudWatch dashboard and X-Ray traces **retained** for the final demo
- [ ] All benchmarks, ADRs and evidence packs retained
- [ ] `coverage-matrix.csv` maintained throughout

**Final rebuild:** deploy the complete system — every layer from S1 through S9 running together for
the first time. This is the only sprint where the whole thing is live at once, and it's the
configuration you record the final walkthrough against.

---

**Objective** — A troubleshooting toolkit built from the failures you actually hit across ten
sprints, plus the assembled system, the closing artifacts, and a clean account.

**Skill IDs closed** — `5.2.1`–`5.2.5`

**Cost ceiling** — $10 for the full-system deployment period. **Keep it short** — deploy, record,
tear down. Do not leave the assembled system running.

---

## Part A — Troubleshooting toolkit

Task 5.2 requires diagnosing real failures. You have ten sprints of them. **Do not invent
hypothetical bugs** — the value here is that these actually happened to you.

## Sub-task 1 — Failure catalogue

Go back through every sprint's notes and build `docs/failure-catalogue.md`. Expect entries like:

| Sprint | Failure | Root cause | Detection | Fix |
|---|---|---|---|---|
| S1 | Lambda timeout | 3s default vs two Bedrock calls | CloudWatch duration | Timeout to 120s |
| S1 | Recursive invocation | Missing `raw/` prefix filter | Invocation count spike | Prefix filter |
| S2 | Sync failure | Malformed metadata sidecar | KB sync status | Schema fix |
| S3 | Over-refusal | Grounding threshold too strict | Benign-set false positives | Threshold tuning |
| S5 | Wrong tool selected | Vague function description | Agent trace | Rewrote descriptions |
| S6 | Cross-region deploy failed | Model unavailable in Sydney | CloudFormation error | Parameterised model ID |
| S8 | Safety regression | Prompt compression weakened instructions | Red-team re-run | Reverted |

Each entry gets: symptom, how you noticed, root cause, fix, and **how you'd detect it faster next
time**. That last column is what turns a bug list into a runbook.

## Sub-task 2 — Content handling issues (5.2.1)

Reproduce and document: malformed JSON output, truncation at max tokens, unicode and emoji
handling, very long inputs exceeding context, empty or whitespace input, mixed-language content,
and markdown fences wrapping JSON.

You already have `_coerce_json` from S1 handling the last one — document *why* it exists. Defensive
code without a recorded reason gets deleted by the next person.

## Sub-task 3 — FM integration issues (5.2.2)

| Symptom | Likely cause | Diagnostic |
|---|---|---|
| `ThrottlingException` | Account quota | Bedrock quotas console; check burst pattern |
| `AccessDeniedException` | Model access not granted in region | Model access page |
| `ValidationException` on model ID | Wrong region prefix or retired model | Compare to `list-foundation-models` |
| Latency spike, no code change | Cross-region profile routing elsewhere | X-Ray, compare to baseline |
| `ModelTimeoutException` | Output too long, or model under load | Reduce max tokens; check fallback engaged |

**Write a triage script** — `scripts/diagnose.py` — that checks model access, quotas, recent error
rates from CloudWatch, index freshness, and guardrail version, printing a health summary. That
script is a genuinely reusable artifact beyond this programme.

## Sub-task 4 — Prompt engineering problems (5.2.3, 5.2.5)

Reproduce: a prompt edit that silently degraded output format; instruction conflict between the
system prompt and the guardrail; a version rollback; and drift where the same prompt produces
different-shaped output as inputs change.

**Demonstrate version rollback through Prompt Management** — switch the alias from v2 back to v1
and show behaviour restore. That's the maintenance skill (5.2.5) and it's fast to demo.

## Sub-task 5 — Retrieval issues (5.2.4)

Reproduce each and document the diagnostic path:

- **Stale index** — modify a source document without re-syncing; answers cite the old text
- **Chunk boundary problem** — a fact split across two chunks so neither retrieves well
- **Embedding mismatch** — query phrasing far from document phrasing
- **Over-filtering** — a metadata filter that silently returns nothing
- **Score collapse** — near-duplicate documents competing, none scoring well

**The over-filtering case is the nastiest** because the system doesn't error — it returns zero
chunks, the model answers from nothing, and the answer looks fine. Your S9 staleness detector and
retrieval-score alarm exist precisely for this class of failure.

## Sub-task 6 — Runbook

`docs/runbook.md`, organised by symptom rather than by component — because at 2am you have a
symptom, not a diagnosis.

Each entry: symptom → first check → second check → likely causes ranked → fix → prevention.
Cross-reference the S9 alarms so each alarm points to its runbook entry.

---

## Part B — Final assembly

## Sub-task 7 — Deploy the complete system

Every layer live simultaneously: ingest pipeline (S1), RAG with the winning configuration (S2),
prompt management and guardrails (S3), routing and fallback (S4), agent with tools (S5), API
gateway and auth (S6), encryption, tenant isolation and lineage (S7), caching and optimisations
(S8), full observability and evaluation (S9).

**Run the full golden set once against the assembled system.** Integration frequently surprises —
the cache may interact badly with tenant filtering, the guardrail may fire differently behind the
agent. Anything you find here is a legitimate S10 finding.

## Sub-task 8 — The final walkthrough recording

3–4 minutes, following §14's evidence standard:

| Beat | Content |
|---|---|
| 0:00 | Architecture animation — the full system |
| 0:20 | Upload a ticket → extraction, validation, quality score |
| 0:45 | Ask a policy question → answer **with citations**, click one to see the retrieved chunk |
| 1:15 | Prompt injection attempt → guardrail blocks → CloudWatch log entry showing it |
| 1:40 | Complex multi-step question → agent trace: reasoning, tool calls, escalation |
| 2:10 | Step Functions execution graph |
| 2:30 | CloudWatch dashboard — latency, cost, quality rows live |
| 2:50 | X-Ray service map |
| 3:05 | Evaluation scorecard + the CI regression gate rejecting a bad PR |
| 3:25 | Teardown running, sweep clean, Cost Explorer total for the programme |

**Ending on the teardown and the total cost is the differentiator.** Everyone ends on the working
product. Ending on "here is what it cost and here is me deleting it" is a discipline story nobody
else tells.

## Sub-task 9 — Portfolio consolidation

Repo `README.md` containing: what the system does, the architecture diagram, the capability table
by sprint, **the headline numbers table** (every measured result in one place), links to each
sprint's ADRs and benchmarks, the model card, the fairness report, total cost, and an honest
limitations section.

**Write the limitations section properly.** No multi-tenancy beyond retrieval filtering, no real
users, no sustained load testing, synthetic data throughout. Stating this yourself is far stronger
than having an interviewer find it — and it's the difference between "production" and
"production-pattern" holding up under questioning.

## Sub-task 10 — Cost reconciliation

Full programme cost from Cost Explorer, broken down by sprint tag and by service. Compare against
the PRD's $100 ceiling and the per-sprint estimates.

**Explain every variance, including the S7 KMS key still winding down its 7-day deletion window.**
A reconciliation that admits the forecast was wrong somewhere is more credible than one that
claims perfect prediction.

## Sub-task 11 — Coverage matrix final audit

Every row in `coverage-matrix.csv` marked DONE, PARTIAL or SKIPPED with evidence.

Known partials to record honestly:

- `2.2.x` Provisioned Throughput — theory only, by deliberate decision, with the ADR and the
  `AccessDeniedException` as evidence
- Any stretch item not reached

**Publish the matrix.** 97 skills tracked to evidence is an unusual artifact, and the honesty of
the partial rows is what makes the DONE rows believable.

---

## FINAL TEARDOWN

```bash
aws cloudformation delete-stack --stack-name deskai-final --region ap-southeast-1
aws cloudformation wait stack-delete-complete --stack-name deskai-final --region ap-southeast-1

aws bedrock-agent list-agents --region ap-southeast-1
aws bedrock-agent list-knowledge-bases --region ap-southeast-1
aws bedrock list-guardrails --region ap-southeast-1
aws bedrock-agent list-prompts --region ap-southeast-1

aws cloudwatch delete-dashboards --dashboard-names deskai-observability --region ap-southeast-1

# Every region, not just Singapore
for r in ap-southeast-1 ap-southeast-2 us-east-1; do
  echo "=== $r"
  aws resourcegroupstaggingapi get-resources --region $r \
    --tag-filters Key=Project,Values=deskai \
    --query 'ResourceTagMappingList[].ResourceARN' --output text
done

aws s3 ls | grep deskai
aws bedrock list-provisioned-model-throughputs --region ap-southeast-1   # must be empty

~/deskai/scripts/orphan_sweep.sh
```

**Keep permanently:** the baseline bucket with all evidence packs, the GitHub repo, benchmarks,
ADRs, the model card, the coverage matrix.

**Set a calendar reminder for 7 days out** to confirm the S7 KMS key deleted and billing stopped.

---

## Closing post

The retrospective. Ten sprints, 97 skills, one system, total cost, what broke and what you learned.

Three things worth leading with:

1. **The failure catalogue.** Publishing what went wrong across ten sprints, with root causes, is
   rarer and more useful than any success story. It's also the most honest signal of real hands-on
   work — nobody who followed a tutorial has this list.
2. **The total cost number**, against the $100 ceiling, with the variance explained.
3. **The coverage matrix**, partials included.

Tag `#awsexamprep` with the repo link. Per §14, the AWS Exam Prep team endorsing you on LinkedIn
for demonstrated skills is third-party validation — worth more than the posts themselves.

## Notes for Codex

- Part A comes from real notes. If a failure wasn't recorded, don't fabricate one — mark the gap.
- The assembled system in Part B is expensive relative to other sprints. Deploy, record, tear down
  the same day.
- Final teardown checks **all three regions**, not just Singapore.
- Region `ap-southeast-1` unless stated otherwise.

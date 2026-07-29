# SPRINT 8 — Cost & Performance Optimization

> Tasks 4.1 and 4.2 · 10 core skills

## ASSUMPTIONS FROM PRIOR SPRINTS

- [ ] S7 complete; Config recorder stopped; KMS key deletion scheduled; sweep clean
- [ ] `core/router.py` (S4), `core/safety.py` (S3), `infra/template.yaml` (S6) retained
- [ ] All prior `benchmarks/*.json` retained — this sprint is meaningless without them

**Rebuild:** redeploy the SAM stack plus the knowledge base and guardrail. By now this is routine.

**This sprint cannot be done first.** Optimisation requires an existing system with measured
baselines. Everything you built across seven sprints is the input.

---

**Objective** — Measurably cheaper and faster, with every gain attributed to a specific change and
every tradeoff stated.

**Skill IDs closed** — `4.1.1`–`4.1.4`, `4.2.1`–`4.2.6`

**Cost ceiling** — $8. Realistic $3–4. Load testing is the variable — cap it.

**FORBIDDEN** — OpenSearch, Aurora, SageMaker, Kendra, Provisioned Throughput, ElastiCache
(has an hourly node cost; DynamoDB with TTL serves as the cache here at a fraction of the price
and demonstrates the same skill).

---

## Sub-task 1 — Establish the baseline properly

**Goal** — You cannot claim an improvement without a defensible before-number, and it must be
measured under conditions you can reproduce.

Create `~/deskai/scripts/bench.py` running a fixed workload — 50 requests drawn from
`eval/rag_eval.json` and `corpus/tickets/` — recording per request: end-to-end latency, time to
first token, retrieval latency, model latency, input and output tokens, cost, cache hit or miss.

Run it three times and take the median to smooth network variance. Write
`benchmarks/s8-baseline.json`.

**Record the conditions**: region, time of day, model, concurrency. A benchmark without stated
conditions is not reproducible, and reviewers will notice.

**Define your SLOs now, before optimising:**

| Metric | Target |
|---|---|
| p50 end-to-end | < 2.5s |
| p95 end-to-end | < 6s |
| Time to first token | < 1.2s |
| Cost per resolved ticket | < $0.002 |
| Error rate | < 1% |

Write `adr/s8-slo.md` stating the targets, the error budget, and what you'd sacrifice to hold them.

---

## Sub-task 2 — Prompt caching

**Goal** — Task 4.1.1. Your system prompt, policy context and few-shot examples are re-sent on
every request and re-charged every time.

Add cache checkpoints to the Converse call so the static prefix is cached:

```python
messages = [{
    "role": "user",
    "content": [
        {"text": LARGE_STATIC_CONTEXT},
        {"cachePoint": {"type": "default"}},   # everything above is cached
        {"text": f"Customer question: {question}"},
    ],
}]
```

Cached input tokens bill at a large discount. **Measure carefully:** cache write is more expensive
than a normal call, so caching only pays off above a break-even number of reads.

**Calculate that break-even and publish it.** "Prompt caching saved 60%" is a marketing claim;
"prompt caching pays for itself after N requests against the same prefix, and here's the arithmetic"
is an engineering one.

Watch for the minimum-token threshold — prefixes below a certain size aren't cacheable at all.
If your prefix is too small, restructure to batch the static policy context into it.

---

## Sub-task 3 — Semantic response cache

**Goal** — Task 4.1.4. Support questions repeat heavily; "where is my order" arrives constantly in
slightly different words.

DynamoDB table `deskai-s8-tbl-cache`, on-demand, with a TTL attribute:

1. Embed the incoming question (Titan V2)
2. Compare against cached question embeddings by cosine similarity
3. On a hit above threshold (start at 0.95), return the cached answer
4. On a miss, generate, then cache with a TTL

**Three things that make this real rather than naive:**

- **Never cache personalised answers.** Anything containing an order status, a customer name, or a
  tenant-specific policy must bypass the cache. Key the cache on tenant plus a
  contains-no-PII assertion. Getting this wrong leaks one customer's data to another — the most
  serious bug available in this sprint.
- **Threshold tuning is the measurement.** Too low and you serve wrong answers; too high and you
  never hit. Sweep 0.90 to 0.99 against your eval set and report hit rate against incorrect-answer
  rate.
- **TTL must respect policy changes.** A cached refund answer is wrong the moment the policy is
  updated. Invalidate on knowledge base re-sync.

**Measure:** hit rate on a realistic query distribution, latency on hit versus miss, cost saving,
and incorrect-serve rate at the chosen threshold.

---

## Sub-task 4 — Token efficiency

**Goal** — Task 4.1.1 continued. Four techniques, measured independently:

| Technique | Change | Watch for |
|---|---|---|
| Context pruning | Drop retrieved chunks below a relevance score rather than always sending k=5 | Recall loss on multi-hop questions |
| Prompt compression | Rewrite the system prompt tighter without losing behaviour | Guardrail regressions — re-run the S3 red team after |
| Output constraints | Explicit length limits, structured output over prose | Truncated answers |
| Few-shot pruning | Remove examples one at a time, measure accuracy | Where accuracy actually breaks |

**Re-run the S3 red-team set after prompt compression.** A tighter system prompt frequently
weakens safety instructions, and discovering that in production rather than in the benchmark is the
classic version of this mistake.

---

## Sub-task 5 — Batch inference

**Goal** — Task 4.2.3. Batch runs at roughly half the on-demand rate for work that doesn't need an
immediate response.

Identify the genuinely asynchronous workloads: overnight ticket classification, the S9 evaluation
runs, bulk summarisation, and the fairness sweep from S7.

Submit a batch job over your ticket corpus, then compare cost and turnaround against the
synchronous path.

**The output is a decision rule** for `adr/s8-batch.md`: which workloads move to batch, and the
latency tolerance that justifies it. Applying batch to your own eval harness is what brings PRD
§7.1's cost model down to near-zero.

---

## Sub-task 6 — Retrieval performance

**Goal** — Task 4.2.2. Retrieval is frequently the latency bottleneck and is rarely tuned.

- Sweep `numberOfResults` from 10 down to 3 — measure recall against latency
- Compare metadata pre-filtering (narrow then search) against post-filtering
- Measure reranking's latency cost against its recall gain, using S2's numbers
- Test parallel retrieval for decomposed multi-hop queries versus sequential

**The likely finding:** k=3 with reranking beats k=10 without, on both latency *and* quality. If it
holds, that's a genuinely useful result — the intuition that more retrieved context is better is
common and often wrong.

---

## Sub-task 7 — Lambda tuning

**Goal** — Task 4.2.5.

Memory and CPU scale together in Lambda, so more memory can be *cheaper* by finishing faster. Sweep
the gateway Lambda at 512 / 1024 / 1769 / 3008 MB, measuring duration and billed cost per
invocation. Plot the curve and pick the minimum-cost point.

Also measure: arm64 versus x86_64, cold start versus warm across a redeploy, and whether
provisioned concurrency is justified (it almost certainly isn't at this volume — **state that
conclusion with the arithmetic**, since knowing when *not* to buy something is the skill).

---

## Sub-task 8 — Load test

**Goal** — Task 4.2.6, and the input to S9's dashboards.

Use a modest, capped load test — 20 concurrent for 5 minutes is sufficient. Ramp up, hold, ramp
down.

Record: throughput, latency percentiles under load versus idle, error and throttle rates, where
the first bottleneck appears, and the cost of the whole test.

**Cap it explicitly.** A runaway load test against Bedrock is one of the few ways to spend real
money quickly in this programme, and the S6 usage plan is your backstop — verify it engages.

**Then answer the interview question in `adr/s8-scale.md`:** what breaks at 10× and 100×, in order.
Likely sequence: Bedrock account quotas, then Lambda concurrency, then DynamoDB partition heat,
then the vector store. Name the first one and how you'd raise it.

---

## Sub-task 9 — Compose everything and re-measure

Run `bench.py` again with every optimisation enabled. Produce the attribution table:

| Change | Latency Δ | Cost Δ | Quality Δ | Kept? |
|---|---|---|---|---|
| Prompt caching | | | | |
| Semantic cache | | | | |
| Context pruning | | | | |
| k=3 + rerank | | | | |
| Router (from S4) | | | | |
| Lambda right-sizing | | | | |
| Batch for async | | | | |

**Include the changes you reverted.** An optimisation that cost more quality than it saved in money
is a finding, and a table with a "no" row is more trustworthy than one where everything worked.

Verify the SLOs from sub-task 1 are met. If any isn't, say so.

---

## Sub-task 10 — Cost attribution dashboard

Per-request cost tracking broken down by component — model inference, embeddings, guardrail text
units, retrieval, Lambda, data transfer — emitted as CloudWatch custom metrics and rendered as a
dashboard.

Reconcile your calculated costs against actual Cost Explorer figures filtered by `Sprint=S8`.
**The gap between calculated and billed is worth investigating and worth publishing** — it's
usually the charges people forget: data transfer, request overhead, the KMS key still winding down
from S7.

---

## Sub-task 11 — Streamlit performance panel

Live latency breakdown by stage, cache hit indicator, running session cost, cost-versus-baseline
counter, and the SLO status.

---

## Sub-task 12 — Measure

1. **End-to-end cost per resolved ticket**, before and after, with the attribution table
2. **p50/p95 latency and time to first token**, before and after
3. **Cache hit rate** and prompt caching break-even point
4. **Retrieval k sweep** — recall against latency
5. **Lambda memory/cost curve**
6. **Load test results** and the first bottleneck
7. **Calculated versus billed cost** reconciliation

---

## TEARDOWN

```bash
aws dynamodb delete-table --table-name deskai-s8-tbl-cache --region ap-southeast-1
aws bedrock list-model-invocation-jobs --region ap-southeast-1   # batch jobs complete on their own
aws cloudformation delete-stack --stack-name deskai-s8 --region ap-southeast-1
aws bedrock-agent delete-knowledge-base --knowledge-base-id <KB_ID> --region ap-southeast-1
aws bedrock delete-guardrail --guardrail-identifier <GR_ID> --region ap-southeast-1

# Keep the CloudWatch dashboard — S9 extends it
~/deskai/scripts/orphan_sweep.sh
```

**Keep:** every benchmark file, the attribution table, all ADRs, and the CloudWatch dashboard.

---

## Post angle

**The attribution table is the post.** Most optimisation content says "I made it 3× faster" without
saying which change did what. A table showing seven changes, their individual latency and cost
deltas, and the two you reverted, is genuinely rare and immediately credible.

Second: the prompt caching break-even. Publishing the request count at which caching starts paying
demonstrates you understood the mechanism rather than just enabling a feature.

Third: the calculated-versus-billed reconciliation. "I predicted $4.10 and was billed $5.35, here's
the missing $1.25" is a story about cost discipline that no tutorial produces, and it's exactly what
a client paying your cloud bill wants to see you doing.

## Notes for Codex

- Sub-task 1 must complete before any optimisation. No baseline, no claims.
- Re-run the S3 red team after prompt compression.
- Cache must never serve personalised or cross-tenant content — flag this explicitly.
- Cap the load test at 20 concurrent for 5 minutes.
- Region `ap-southeast-1` throughout.

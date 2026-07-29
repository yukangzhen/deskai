# SPRINT 9 — Observability & Evaluation

> Tasks 4.3 and 5.1 · 14 core skills · the largest sprint

## ASSUMPTIONS FROM PRIOR SPRINTS

- [ ] S8 complete; cache table removed; CloudWatch dashboard retained
- [ ] All `benchmarks/*.json` retained — S9 evaluates against them
- [ ] `eval/rag_eval.json`, `eval/redteam.json`, `eval/benign.json` retained
- [ ] `core/*` modules retained

**Rebuild:** redeploy the SAM stack, knowledge base and guardrail with the S8 optimisations applied.
This is the configuration that gets evaluated, so it must be the optimised one.

---

**Objective** — Know when the system is broken before a user tells you, and know whether it is
actually any good — with numbers that survive scrutiny.

**Skill IDs closed** — `4.3.1`–`4.3.6`, `5.1.1`–`5.1.8`

**Cost ceiling** — $15. **This sprint has the highest cost risk after S2**, and the risk is the
evaluation harness rather than any infrastructure.

## ⚠ Evaluation cost discipline — read PRD §7.1 before sub-task 8

Eval cost scales as `cases × metrics × runs`, and the run count is what catches people out. You
re-run the eval after every parameter change.

| Configuration | Per run | 30 iteration runs |
|---|---|---|
| 200 cases × 6 metrics, strong judge | ~$4.60 | **~$138** |
| 50 cases × 2 metrics, cheap judge + caching + batch | ~$0.02 | **~$1** |

**Policy for this sprint:** iterate on a 50-case set with 2 metrics and Nova Micro as judge, with
prompt caching on the static rubric and batch mode where the run isn't interactive. The full
200-case, 6-metric, Nova-Pro-judge configuration runs **exactly twice** — one baseline, one final.
Those two runs produce the published numbers.

**A second cost trap specific to this sprint:** CloudWatch custom metrics bill per metric per
month, and a metric is defined by its unique dimension combination. Emitting
`tenant × model × tier × outcome` creates a combinatorial explosion of billable metrics from
innocent-looking code. Keep dimensions to two, and put the high-cardinality detail in log fields
you query with Logs Insights instead.

**FORBIDDEN** — OpenSearch, Aurora, SageMaker endpoints, Kendra, Provisioned Throughput,
CloudWatch metrics with more than 2 dimensions.

---

## Sub-task 1 — Structured logging standard

Consolidate the ad-hoc logging from S1–S8 into one schema in `core/telemetry.py`. Every request
emits exactly one JSON line containing: request and session and tenant IDs, prompt and guardrail
and model versions, the routing decision, retrieval stats, safety verdicts, per-stage latencies,
token counts, cost, cache status, and final outcome.

**One line per request, not many.** Correlating scattered log lines is the thing that makes
production debugging miserable, and you'll feel it directly in S10.

---

## Sub-task 2 — Custom metrics via EMF

Use CloudWatch Embedded Metric Format — emit metrics inside the structured log line rather than
making separate `PutMetricData` calls. No extra API latency, no extra cost, and the metric and its
context stay together.

```python
import json, time

def emit(metrics: dict, dimensions: dict, detail: dict):
    """EMF: CloudWatch extracts metrics; the rest stays queryable as log fields."""
    print(json.dumps({
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [{
                "Namespace": "deskai",
                # Two dimensions maximum — see the cost note above.
                "Dimensions": [list(dimensions.keys())],
                "Metrics": [{"Name": k, "Unit": u} for k, u in metrics.items()],
            }],
        },
        **dimensions,
        **{k: v for k, (v, _) in metrics.items()},
        **detail,
    }))
```

Metrics: `LatencyMs`, `CostUsd`, `InputTokens`, `OutputTokens`, `GuardrailInterventions`,
`RetrievalScore`, `CacheHit`, `Escalations`, `Errors`.
Dimensions: `Stage` and `Model` only.

---

## Sub-task 3 — Distributed tracing with X-Ray

Enable X-Ray on API Gateway, Lambda and Step Functions. Add subsegments for retrieval, guardrail
input, model invocation, guardrail output and tool calls.

**The service map is exceptional demo material** — it shows the whole architecture with live
latency on each hop, and it proves the system is real in a way no UI can.

X-Ray's free tier covers a generous number of traces per month; at this volume it's free.

---

## Sub-task 4 — The observability dashboard

**Goal** — Task 4.3.1. One dashboard answering: is it up, is it fast, is it expensive, is it safe,
is it any good.

**Console path** — CloudWatch → *Dashboards* → `deskai-observability`.

| Row | Widgets |
|---|---|
| Health | Request rate · error rate · availability · throttles |
| Latency | p50/p95/p99 end-to-end · time to first token · stage breakdown |
| Cost | Cost/hour · cost per request · token consumption by model · cache hit rate |
| Safety | Guardrail interventions by type · PII detections · injection attempts blocked |
| Quality | Retrieval score distribution · refusal rate · escalation rate · feedback score |
| Vector store | Query latency · index freshness · sync status |

**The quality row is what distinguishes GenAI observability from ordinary APM.** A GenAI system can
be fast, cheap and available while producing wrong answers — and none of the first three rows would
show it.

---

## Sub-task 5 — Alarms that mean something

Composite alarms rather than single-metric noise:

| Alarm | Condition | Why |
|---|---|---|
| `deskai-degraded` | p95 > 6s **AND** error rate > 2% for 5 min | Real degradation, not a blip |
| `deskai-cost-spike` | Cost/hour > 3× the 7-day baseline | Runaway loop or an attack |
| `deskai-safety-anomaly` | Guardrail interventions > 5× baseline | Coordinated probing |
| `deskai-quality-drop` | Avg retrieval score < 0.6 for 15 min | Index or embedding problem |
| `deskai-refusal-spike` | Refusal rate > 30% | Over-strict thresholds, or a broken index |

**Then trigger at least two deliberately** and capture them firing and resolving. An alarm that has
never fired is an untested alarm.

---

## Sub-task 6 — Vector store operational management

**Goal** — Task 4.3.5, and it pairs with S2's maintenance skill (1.4.5), which is the natural home
for it.

Monitor: index freshness (time since last successful sync), document count drift versus the source
bucket, query latency distribution, and score distribution over time as a proxy for embedding drift.

Build a **staleness detector** — an EventBridge-scheduled Lambda comparing S3 object count and
newest `LastModified` against the last knowledge base sync, alarming when the gap exceeds a
threshold.

**Stale-index-in-production is one of the most common real RAG failures** and one of the least
monitored. The system keeps answering confidently from documents that were superseded weeks ago,
and nothing looks broken.

---

## Sub-task 7 — Tool performance framework

**Goal** — Task 4.3.4.

Per tool: invocation count, success rate, p50/p95 latency, error taxonomy, and **selection accuracy**
— how often the agent picked the right tool for the request.

That last metric is agent-specific and rarely instrumented. Build it by labelling a set of requests
with the tool that *should* fire, then comparing against what did.

---

## Sub-task 8 — The evaluation framework

**Goal** — Tasks 5.1.1 and 5.1.5. Build the taxonomy before running anything.

| Dimension | Metrics | Method |
|---|---|---|
| Retrieval | recall@k, MRR, context precision | Deterministic, against known sources |
| Generation | faithfulness, correctness, completeness | LLM-as-judge |
| Safety | block rate, false positive rate | The S3 red-team and benign sets |
| Fairness | outcome disparity | The S7 counterfactual set |
| Operational | latency, cost, availability | S8 benchmarks |
| User | feedback score, escalation rate, resolution rate | Sub-task 11 |

**Golden dataset:** consolidate into `eval/golden.json` — 200 cases total, tagged so you can slice
to the 50-case iteration subset. Include the unanswerable and adversarial cases; a golden set of
only easy questions inflates every number you report.

**Deterministic metrics first.** Retrieval recall costs nothing to compute and catches most
regressions. Reach for the judge only where determinism isn't possible.

---

## Sub-task 9 — Bedrock Evaluations

**Console path** — Amazon Bedrock → *Evaluations*.

Run two jobs against the **50-case subset**:

1. **Model evaluation** — automatic metrics plus LLM-as-judge on generation quality
2. **RAG evaluation** — context relevance, coverage, faithfulness, correctness against the
   knowledge base

Screenshot both report cards.

**Then compare against your own harness and explain any divergence.** Managed and hand-rolled
evaluation frequently disagree, usually because they define faithfulness differently. Understanding
*why* they disagree is the actual skill, and it's a good paragraph in the post.

---

## Sub-task 10 — Custom LLM-as-judge harness

**Goal** — Task 5.1.4, with the cost discipline above enforced in code.

```python
JUDGE_RUBRIC = """Score the answer 1-5 on each dimension. JSON only.

faithfulness: every claim supported by the context (5) … fabricated claims (1)
completeness: fully answers the question (5) … ignores most of it (1)

Context:
{context}

Question: {question}
Answer: {answer}

JSON: {{"faithfulness": n, "completeness": n, "reasoning": "one sentence"}}"""
```

Three cost controls, all mandatory:

1. **Cache the rubric.** It's static — put a cache checkpoint after it.
2. **Cheap judge for iteration.** Nova Micro during development; Nova Pro only for the two
   published runs.
3. **Batch mode** for non-interactive runs — half price.

**Validate the judge before trusting it.** Hand-score 20 cases yourself and measure agreement with
the model judge. If agreement is poor, the rubric is wrong, and every number downstream inherits
that error. Publishing judge-agreement alongside the scores is what makes an LLM-as-judge result
defensible rather than circular.

---

## Sub-task 11 — User-centred evaluation

**Goal** — Task 5.1.3, and stretch `E-1.1.4`.

Explicit feedback: thumbs up/down plus an optional reason, written to DynamoDB with the request ID
so feedback joins to the full trace.

Implicit signals: did the user rephrase immediately (retrieval failure), did they escalate after an
answer (answer inadequate), session length, abandonment.

**The implicit signals are the honest ones.** Explicit feedback is sparse and biased toward the
annoyed; a user rephrasing the same question three times is unambiguous.

---

## Sub-task 12 — Regression suite as a deployment gate

**Goal** — Task 5.1.8, wiring evaluation into S6's pipeline.

Extend the GitHub Actions workflow: on every PR, run the 50-case golden subset plus the full
red-team set, and **fail the build** if retrieval recall drops more than 5%, faithfulness drops more
than 0.3, red-team block rate falls below 95%, false-positive rate exceeds 10%, or p95 latency
regresses more than 20%.

**Then prove the gate works** — open a PR that deliberately weakens the system prompt and show CI
rejecting it. That screenshot is the single strongest artifact in this sprint: it demonstrates
quality is enforced automatically rather than checked by hand when someone remembers.

---

## Sub-task 13 — Automated reporting

**Goal** — Task 5.1.7.

Scheduled Lambda producing a weekly scorecard to S3 and SNS: all six evaluation dimensions,
week-over-week deltas, SLO compliance, cost per resolved ticket, and any metric trending toward a
threshold.

Design it to be read by someone who isn't you — that constraint is what makes reporting a distinct
skill from monitoring.

---

## Sub-task 14 — Streamlit evaluation dashboard

Golden set results by dimension, trend over time, per-case drill-down showing question, retrieved
context, answer, judge score and reasoning, and a comparison view between two configurations.

The per-case drill-down is what makes an aggregate score trustworthy — anyone can show a bar chart;
showing the individual case that scored 2/5 and why is different.

---

## Sub-task 15 — Measure

1. **Full golden set scorecard** — all six dimensions, from the two full-configuration runs
2. **Judge agreement** with your human scoring on 20 cases
3. **Managed versus custom evaluation** divergence, with an explanation
4. **Alarm validation** — which fired, how fast, false positive rate
5. **Regression gate** catching a deliberately bad PR
6. **Evaluation harness cost** — iteration configuration versus the naive default

---

## TEARDOWN

```bash
aws cloudwatch delete-alarms --alarm-names deskai-degraded deskai-cost-spike \
  deskai-safety-anomaly deskai-quality-drop deskai-refusal-spike --region ap-southeast-1
aws cloudwatch list-metrics --namespace deskai --region ap-southeast-1   # custom metrics age out
aws cloudformation delete-stack --stack-name deskai-s9 --region ap-southeast-1
aws bedrock-agent delete-knowledge-base --knowledge-base-id <KB_ID> --region ap-southeast-1
aws bedrock delete-guardrail --guardrail-identifier <GR_ID> --region ap-southeast-1
~/deskai/scripts/orphan_sweep.sh
```

**Keep the CloudWatch dashboard and X-Ray traces until after S10's final walkthrough** — the demo
needs them. Custom metrics stop billing once no new data points arrive.

---

## Post angle

**The regression gate.** A CI pipeline rejecting a pull request because model quality dropped is a
thing very few people have built, and the screenshot is instantly legible to any engineer.

Second: judge validation. Publishing how well your LLM judge agrees with your own scoring, before
publishing what the judge said, is the difference between measurement and self-congratulation.

Third: the evaluation cost story — the naive configuration costs ~$138 and the disciplined one ~$1
for the same insight during iteration. That's Task 4.1's cost skill applied to your own tooling,
and it's a practical detail that will save readers real money.

## Notes for Codex

- Enforce the eval cost policy in code, not by intention. Iteration runs must default to the
  50-case subset with the cheap judge.
- CloudWatch metric dimensions capped at 2.
- Validate the judge before reporting any judge-derived score.
- Region `ap-southeast-1` throughout.

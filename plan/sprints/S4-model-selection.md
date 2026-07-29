# SPRINT 4 — Model Selection & Customization

> Tasks 1.2 and 2.2 · 7 core skills · contains the programme's single hard prohibition.

## ASSUMPTIONS FROM PRIOR SPRINTS

- [ ] S3 complete; guardrail and KB torn down; sweep clean
- [ ] `benchmarks/s1-baseline.json` retained (per-model ticket extraction costs)
- [ ] `corpus/tickets/`, `eval/rag_eval.json` retained
- [ ] Claude Haiku access granted — if not, compare Nova Micro / Lite / Pro only

---

**Objective** — A routing layer that sends each request to the cheapest model that can handle it,
falls back gracefully when a model fails, and a fine-tuned model registered through a proper
lifecycle — without ever purchasing Provisioned Throughput.

**Skill IDs closed** — `1.2.1`–`1.2.4`, `2.2.1`–`2.2.3`

**Cost ceiling** — $12. Realistic $5–8. SageMaker is the variable.

## ⛔ HARD PROHIBITION

**Do not create Bedrock Provisioned Throughput.** Task 2.2 instructs
`aws bedrock create-provisioned-model-throughput`. Commitment terms **cannot be cancelled**.
Sub-task 10 covers this skill entirely on paper.

Your S0 IAM policy already denies these actions. Verify before starting:

```bash
aws bedrock create-provisioned-model-throughput \
  --model-id apac.amazon.nova-micro-v1:0 --provisioned-model-name check \
  --model-units 1 --region ap-southeast-1
# expected: AccessDeniedException
```

**If this succeeds, stop.** Your policy is not attached to the credential you're using.

**Also forbidden:** OpenSearch, Aurora, Kendra, Bedrock Agents.

**Ephemeral created** — SageMaker training job, model package group, one endpoint
(**timeboxed 1 hour**), `deskai-s4-tuning-<suffix>`.

---

## Sub-task 1 — Structured model comparison

**Goal** — Task 1.2.1. S1 measured cost per ticket. Now do it properly, across task types.

Create `~/deskai/scripts/model_bakeoff.py` evaluating each model on three distinct workloads:

| Workload | Source | What it tests |
|---|---|---|
| Structured extraction | `corpus/tickets/` | Constrained output, schema adherence |
| Open generation | Support answer from policy context | Fluency, instruction-following |
| Classification | Ticket → category + urgency | Simple decision accuracy |

Models: Nova Micro, Nova Lite, Nova Pro, Claude Haiku.

Per model per workload record: accuracy, p50/p95 latency, cost per 1000 requests, output token
count, schema-violation rate.

**Write results to `benchmarks/s4-bakeoff.json`.**

**The expected finding:** capability requirements differ sharply by workload. Micro likely matches
Pro on extraction and classification while losing on open generation. If that holds, it's the
entire justification for the router in sub-task 3 — and it's a measured justification, not an
assumed one.

---

## Sub-task 2 — Bedrock Evaluations job

**Goal** — Task 1.2.1 via the managed path, and a preview of S9.

**Console path** — Amazon Bedrock → *Evaluations* → **Create evaluation** → Automatic.

| Field | Value |
|---|---|
| Name | `deskai-s4-eval-models` |
| Evaluation type | Automatic |
| Models | Nova Micro and Nova Pro |
| Task type | Text generation / Question and answer |
| Dataset | Custom prompt dataset (JSONL) from your ticket corpus |
| Metrics | Accuracy, robustness, toxicity |

**Apply PRD §7.1 cost discipline:** use a 50-record dataset here, not 200.

Upload the dataset to `s3://deskai-s4-tuning-<suffix>/eval/`.

**You'll know it worked when** — the job completes and the report card renders in the console.
Screenshot it.

**Compare its verdict against your own harness from sub-task 1.** Where they disagree is worth a
paragraph in the post — managed evaluation and hand-rolled evaluation measuring different things
is a real and underdiscussed problem.

---

## Sub-task 3 — The routing layer

**Goal** — Tasks 1.2.2 and 2.2.1.

Create `~/deskai/core/router.py`:

```python
"""Complexity-based model routing (Tasks 1.2.2, 2.2.3).

Tier assignment is driven by the measured results in benchmarks/s4-bakeoff.json,
not by intuition.
"""
import re
from dataclasses import dataclass

from core.bedrock import converse

TIERS = {
    "simple":  "micro",   # classification, extraction, FAQ lookup
    "moderate": "lite",   # single-policy answers
    "complex": "pro",     # multi-hop, ambiguous, escalation decisions
}


@dataclass
class RoutingDecision:
    tier: str
    model: str
    score: int
    signals: list


def score_complexity(text: str, retrieved_count: int = 0) -> RoutingDecision:
    score, signals = 0, []

    words = len(text.split())
    if words > 120:
        score += 2; signals.append("long_input")
    elif words > 40:
        score += 1; signals.append("medium_input")

    if len(re.findall(r"\?", text)) > 1:
        score += 2; signals.append("multiple_questions")

    if re.search(r"\b(and also|as well as|in addition|both)\b", text, re.I):
        score += 2; signals.append("conjunctive_request")

    if re.search(r"\b(why|explain|compare|justify|dispute|appeal)\b", text, re.I):
        score += 2; signals.append("reasoning_required")

    if retrieved_count > 3:
        score += 1; signals.append("wide_retrieval")

    if re.search(r"\b(refund|charge|billing|legal|complaint)\b", text, re.I):
        score += 1; signals.append("financial_or_legal")

    tier = "simple" if score <= 2 else "moderate" if score <= 5 else "complex"
    return RoutingDecision(tier, TIERS[tier], score, signals)


def route(text: str, retrieved_count: int = 0, **kwargs):
    decision = score_complexity(text, retrieved_count)
    result = converse(text, model=decision.model, **kwargs)
    return result, decision
```

**Measure the router itself:** run all 25 benign questions plus the ticket corpus through it and
report tier distribution, blended cost per request versus always-Pro, and accuracy delta.

**Blended cost saving versus accuracy loss is the sprint's headline number.**

---

## Sub-task 4 — Resilience: retry, fallback, circuit breaker

**Goal** — Task 1.2.3.

Create `~/deskai/core/resilient.py`:

```python
"""Resilient invocation: retry with jitter, model fallback, circuit breaker."""
import random
import time

from botocore.exceptions import ClientError

from core.bedrock import converse

FALLBACK_CHAIN = {
    "pro":   ["pro", "lite", "micro"],
    "lite":  ["lite", "micro"],
    "micro": ["micro"],
}

RETRYABLE = {"ThrottlingException", "ServiceUnavailableException",
             "ModelTimeoutException", "InternalServerException"}


class CircuitBreaker:
    """Stop hammering a model that is consistently failing."""

    def __init__(self, threshold=3, cooldown_s=60):
        self.threshold, self.cooldown_s = threshold, cooldown_s
        self.failures, self.opened_at = {}, {}

    def is_open(self, model):
        opened = self.opened_at.get(model)
        if opened and time.time() - opened < self.cooldown_s:
            return True
        if opened:
            self.opened_at.pop(model, None)
            self.failures[model] = 0
        return False

    def record_failure(self, model):
        self.failures[model] = self.failures.get(model, 0) + 1
        if self.failures[model] >= self.threshold:
            self.opened_at[model] = time.time()

    def record_success(self, model):
        self.failures[model] = 0


_breaker = CircuitBreaker()


def invoke(prompt, model="pro", max_attempts=3, **kwargs):
    attempts = []
    for candidate in FALLBACK_CHAIN.get(model, [model]):
        if _breaker.is_open(candidate):
            attempts.append((candidate, "circuit_open"))
            continue

        for attempt in range(max_attempts):
            try:
                result = converse(prompt, model=candidate, **kwargs)
                _breaker.record_success(candidate)
                return result, attempts + [(candidate, "ok")]
            except ClientError as exc:
                code = exc.response["Error"]["Code"]
                attempts.append((candidate, code))
                if code not in RETRYABLE:
                    break
                _breaker.record_failure(candidate)
                time.sleep((2 ** attempt) + random.uniform(0, 0.5))

    raise RuntimeError(f"all models exhausted: {attempts}")
```

**Prove it works by inducing failure** — do not simply assert it. Options:

- Point a tier at a deliberately invalid model ID and watch fallback engage
- Fire 50 concurrent requests to provoke genuine throttling
- Temporarily deny one model in IAM and observe the chain degrade

**Capture the fallback in CloudWatch logs.** A screenshot of a real throttle followed by a
successful fallback is far more persuasive than a code snippet.

---

## Sub-task 5 — Cross-region fallback

**Goal** — Task 1.2.3 continued, and it justifies the S2 region decision.

Add a final fallback that switches from the `apac.*` inference profile to a `us.*` profile when
APAC capacity is exhausted. Measure the added latency from Malaysia.

Document in `adr/s4-region-fallback.md`: at what point the latency cost of cross-region failover
beats the availability cost of failing. That's a genuine senior tradeoff with no single right
answer.

---

## Sub-task 6 — Fine-tuning dataset

**Goal** — Task 1.2.4.

Build a JSONL dataset from the ticket corpus — input ticket, output the validated extraction JSON
from S1. 200–500 examples; synthesise variations from the 10 base tickets.

```jsonl
{"prompt": "Extract fields from this ticket:\n<ticket text>", "completion": "{\"issue_category\":\"billing\",...}"}
```

Split 80/10/10 train/validation/test. Upload to `s3://deskai-s4-tuning-<suffix>/`.

**Why SageMaker and not Bedrock fine-tuning:** a Bedrock-customised model can only be served
through Provisioned Throughput. Bedrock fine-tuning therefore leads directly into the one thing
this programme forbids. SageMaker fine-tuning produces an artifact you can serve from a
deletable endpoint, or import via Custom Model Import for on-demand Bedrock inference.

**Put that reasoning in `adr/s4-customisation-path.md`.** It's exactly the kind of tradeoff
AIP-C01 examines, and most people don't know the constraint exists.

---

## Sub-task 7 — SageMaker fine-tuning job — COST GATE

**Console path** — SageMaker AI → *JumpStart* → select a small open-weights model →
**Fine-tune**.

| Field | Value |
|---|---|
| Model | Smallest available instruct model (1–3B parameters) |
| Instance type | `ml.g5.xlarge` — do not scale up |
| Instance count | **1** |
| Max runtime | **3600 seconds** — set this explicitly |
| Technique | LoRA / PEFT (not full fine-tune) |
| Epochs | 1 |
| Training data | your S3 prefix |

Job name: `deskai-s4-finetune`. Tag it.

**`ml.g5.xlarge` runs roughly $1.40–2.00/hour in this region and the job self-terminates.** Max
runtime is the safety net — without it, a misconfigured job can run for hours. Set it.

**LoRA rather than full fine-tuning is itself a Task 1.2.4 skill** — parameter-efficient methods
achieving comparable results at a fraction of the compute.

**You'll know it worked when** — the job reaches Completed and the model artifact is in S3.
Screenshot the training metrics.

---

## Sub-task 8 — Model Registry

**Goal** — Task 1.2.4's lifecycle half, and it costs nothing.

**Console path** — SageMaker AI → *Model registry* → **Create model package group**
`deskai-support-extractor`.

Register the fine-tuned model as version 1 with approval status **PendingManualApproval**. Attach
metadata: training job name, dataset S3 URI, hyperparameters, evaluation metrics.

Then approve it and record the state transition.

**Why this matters:** the registry is the auditable link between a dataset, a training run and a
deployed artifact. It's how you answer "which data produced the model that made this decision" —
a question that becomes mandatory in S7's governance sprint.

---

## Sub-task 9 — Endpoint deployment — TIMEBOXED 1 HOUR

> **Set a timer. SageMaker endpoints bill per hour until deleted and are the second most
> commonly forgotten resource in this programme after OpenSearch.**

Deploy the registered model to a real-time endpoint, `ml.g5.xlarge`, single instance,
named `deskai-s4-ep-extractor`.

Compare against Nova Micro on the held-out test split: accuracy, latency, cost per 1000 requests
(endpoint hourly cost amortised over throughput).

**The expected finding, and state it honestly either way:** a fine-tuned small model on a dedicated
endpoint usually loses on cost to an on-demand foundation model at low volume, and wins above some
break-even throughput. Calculating that break-even *is* Task 2.2.3.

### TEARDOWN — IMMEDIATELY

```bash
aws sagemaker delete-endpoint --endpoint-name deskai-s4-ep-extractor --region ap-southeast-1
aws sagemaker delete-endpoint-config --endpoint-config-name <CONFIG> --region ap-southeast-1
aws sagemaker list-endpoints --region ap-southeast-1   # must be empty
~/deskai/scripts/orphan_sweep.sh
```

**Deleting the endpoint does not delete the endpoint config.** The config is free, but leaving it
makes the sweep noisy — remove both.

---

## Sub-task 10 — Provisioned Throughput: paper exercise only

**Goal** — Task 2.2.2, fully, without creating anything.

Complete `adr/s4-provisioned-throughput.md` covering:

**1. Sizing.** Given peak 40 requests/minute, average 800 input and 400 output tokens:

```
tokens/min = 40 × (800 + 400) = 48,000 tokens/min = 800 tokens/sec
model units required = ceil(800 / <tokens-per-sec per MU from AWS docs>)
```

**2. Break-even.** With PT at $H/hour per model unit and on-demand at $I/1M input and $O/1M output:

```
on-demand cost/hour at R requests/hour
  = R × (800 × I + 400 × O) / 1,000,000

break-even R = (H × MU × 1,000,000) / (800 × I + 400 × O)
```

Solve it with current published rates. State the requests/hour above which PT wins.

**3. Commitment risk.** No-commitment versus 1-month versus 6-month. Why the commitment tiers are
irreversible and what that means for a workload with uncertain volume.

**4. Alternatives.** Cross-region inference profiles for burst capacity; Custom Model Import for
on-demand serving of custom weights; batch inference at 50% discount for non-interactive work.

**5. Your recommendation** for this workload, with reasoning.

**Then include the AccessDeniedException from the top of this brief as evidence** that the control
is enforced technically, not just documented. That combination — the full sizing analysis plus a
hard technical block — is a better senior signal than having actually bought one.

---

## Sub-task 11 — Streamlit routing panel

Show per request: complexity score, signals that fired, tier selected, model used, fallback chain
if triggered, and cost versus the always-Pro baseline. A running session total making the saving
visible.

---

## Sub-task 12 — Measure

1. **Blended cost saving from routing** versus always-Pro, with accuracy delta
2. **Model bakeoff table** — accuracy, latency, cost per 1000 across four models and three workloads
3. **Fallback behaviour** under induced failure, with the CloudWatch evidence
4. **Fine-tuned model versus foundation model** — accuracy, and the break-even throughput
5. **PT break-even calculation** from the ADR

---

## TEARDOWN

```bash
aws sagemaker list-endpoints --region ap-southeast-1          # must be empty
aws sagemaker list-endpoint-configs --region ap-southeast-1
aws sagemaker list-training-jobs --status-equals InProgress --region ap-southeast-1  # must be empty

aws s3 rm s3://deskai-s4-tuning-<suffix> --recursive --region ap-southeast-1
aws s3api delete-bucket --bucket deskai-s4-tuning-<suffix> --region ap-southeast-1

aws bedrock list-provisioned-model-throughputs --region ap-southeast-1   # must be empty
~/deskai/scripts/orphan_sweep.sh
```

**Keep:** the Model Registry group (free, referenced in S7 governance), `core/router.py`,
`core/resilient.py`, `benchmarks/s4-bakeoff.json`, all ADRs.

---

## Post angle

Two strong options.

**The router:** "I cut inference cost X% by routing on measured complexity, and here's the accuracy
I gave up." Concrete, numerical, and the honest inclusion of the accuracy cost is what makes it
credible.

**The Provisioned Throughput analysis:** the full break-even math, the commitment-irreversibility
warning, and a screenshot of your own IAM policy denying the action. "I did the sizing exercise and
then made it technically impossible to do by accident" is an unusual and genuinely senior story.

## Notes for Codex

- Verify the PT deny before anything else. If it succeeds, stop the sprint.
- Sub-task 9 is timeboxed to 1 hour. Remind Yu of elapsed time at every interaction.
- Set SageMaker Max runtime explicitly at 3600s.
- Never propose creating Provisioned Throughput, under any framing, including "just to see it".
- Region `ap-southeast-1` throughout.

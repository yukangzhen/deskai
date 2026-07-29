# SPRINT 0 — Foundation

> Hand this file to Codex. Codex delivers one sub-task at a time and waits for confirmation
> before moving on. Yu executes every AWS action; Codex has no credentials.

**Objective** — An AWS account that is instrumented, budgeted, tagged and safe to build in, plus a
working `deskai` skeleton that makes a real Bedrock call and displays its request ID.

**Skill IDs closed** — none. S0 is enabling work for all 118 rows.

**Region** — `ap-southeast-1` (Singapore). Every console action happens here. Check the region
selector on every screen; it is the single most common source of confusing errors.

**Cost ceiling** — under $1. Everything created in S0 is free-tier or free-to-create.

**FORBIDDEN this sprint** — every billable resource. No Knowledge Bases, no OpenSearch, no
SageMaker, no Aurora, no Kendra. S0 creates account plumbing only.

**Baseline created** (never deleted): budgets, cost anomaly monitor, cost allocation tags, study
IAM role, one S3 bucket, Bedrock model access, model invocation logging.

**Ephemeral created**: none. There is no teardown for S0.

---

## Pre-flight

Confirm before sub-task 1:

- [ ] Console access to the AWS account with admin or billing permissions
- [ ] AWS CLI installed locally (`aws --version`)
- [ ] Python 3.10+ (`python3 --version`)
- [ ] Git installed
- [ ] Region selector set to **Asia Pacific (Singapore) ap-southeast-1**

---

## Sub-task 1 — Baseline account inventory

**Goal** — Snapshot what already exists, so the orphan sweep has a reference point and never flags
or deletes something pre-existing.

**Console path** — none. CLI only.

**Run:**

```bash
export AWS_REGION=ap-southeast-1
mkdir -p ~/deskai/evidence/s0

aws sts get-caller-identity > ~/deskai/evidence/s0/identity.json
aws resourcegroupstaggingapi get-resources --region $AWS_REGION \
  > ~/deskai/evidence/s0/baseline-tagged-resources.json

for svc in "s3api list-buckets" "lambda list-functions" "dynamodb list-tables" \
           "opensearchserverless list-collections" "sagemaker list-endpoints" \
           "rds describe-db-clusters" "bedrock-agent list-knowledge-bases"; do
  echo "=== $svc"
  aws $svc --region $AWS_REGION 2>/dev/null || echo "(none / not authorised)"
done | tee ~/deskai/evidence/s0/baseline-services.txt
```

**You'll know it worked when** — `identity.json` shows your account ID, and
`baseline-services.txt` lists what pre-exists. Expect this to be nearly empty.

**Note the account ID** — the last 4 digits become the S3 bucket suffix in sub-task 7.

---

## Sub-task 2 — Activate cost allocation tags

**Goal** — Make `Project`, `Sprint`, `Task`, `Ephemeral` and `TeardownBy` usable as Cost Explorer
filters. This is what makes the §14 cost evidence possible.

**Do this first — activation takes up to 24 hours to take effect.**

**Console path** — Billing and Cost Management → *Cost allocation tags* (left nav) →
**User-defined cost allocation tags** tab.

The tags will not appear until at least one resource carries them. So: create the S3 bucket in
sub-task 7 first if the list is empty, then return here and activate.

**Activate:** `Project`, `Sprint`, `Task`, `Ephemeral`, `TeardownBy`

**You'll know it worked when** — all five show status **Active** (may read "Pending" for a few hours).

---

## Sub-task 3 — Budget with alerts

**Goal** — A smoke detector. Budgets alert on an 8–24 hour lag and stop nothing; teardown
discipline is the real control.

**Console path** — Billing and Cost Management → *Budgets* → **Create budget** →
Customize (advanced) → Cost budget.

| Field | Value |
|---|---|
| Budget name | `deskai-monthly` |
| Period | Monthly |
| Budget renewal type | Recurring |
| Budgeted amount | `100` USD |

Add three alert thresholds, all on **Actual** cost, delivered to your email:

- 50% ($50)
- 80% ($80)
- 100% ($100)

Then add a fourth on **Forecasted** cost at 100% — this is the one that warns you early.

**You'll know it worked when** — the budget appears in the list showing $100 and 4 alerts, and a
subscription-confirmation email arrives.

---

## Sub-task 4 — Cost anomaly detection

**Goal** — Catch a spend spike that a monthly budget would miss until it's too late.

**Console path** — Billing and Cost Management → *Cost Anomaly Detection* → **Create monitor**.

| Field | Value |
|---|---|
| Monitor type | AWS services |
| Monitor name | `deskai-anomaly` |
| Alert subscription name | `deskai-anomaly-alerts` |
| Threshold | Alert me when total impact is greater than **$5** |
| Frequency | Individual alerts |
| Recipient | your email |

$5 is deliberately low. At this project's scale, $5 of unexpected spend means something is running
that shouldn't be.

**You'll know it worked when** — the monitor shows as active and the email subscription is confirmed.

---

## Sub-task 5 — Bedrock model access

**Goal** — Enable the models the programme uses. Access is per-account **and** per-region.

**Console path** — Amazon Bedrock console → confirm region is **Singapore** →
*Model access* (left nav, under Bedrock configurations) → **Modify model access**.

Request access to:

| Model | Used for |
|---|---|
| Amazon Nova Micro | Default cheap generation, eval judge during iteration |
| Amazon Nova Lite | Mid-tier routing |
| Amazon Nova Pro | Complex queries, final eval judge |
| Amazon Titan Text Embeddings V2 | Vector embeddings from S2 onward |
| Anthropic Claude Haiku | Model comparison in S4 |

Amazon models are usually granted instantly. Anthropic models may require a short use-case form.

**You'll know it worked when** — each model shows **Access granted** on the Model access page.

**If a model is unavailable in Singapore** — note it and continue. The `apac.*` cross-region
inference profiles in sub-task 9 reach a wider pool, and §13 D4 allows a single sub-task to run in
`us-east-1` if truly required.

---

## Sub-task 6 — Enable model invocation logging

**Goal** — Without this, Bedrock writes no request logs, and the request-ID correlation that the
entire §14 evidence strategy depends on is impossible.

**This is off by default. It is the most commonly skipped step in this sprint.**

**Console path** — Amazon Bedrock console → *Settings* (bottom of left nav) →
**Model invocation logging** → toggle on.

| Field | Value |
|---|---|
| Destination | CloudWatch Logs |
| Log group name | `/aws/bedrock/deskai-invocations` |
| Include | Text data (leave image/embedding off for now) |
| Service role | Create and use a new role |

**You'll know it worked when** — the toggle reads Enabled, and after sub-task 11 the log group
contains an entry.

---

## Sub-task 7 — Baseline S3 bucket

**Goal** — One permanent bucket for source documents and evidence.

**Console path** — S3 console → **Create bucket**.

| Field | Value |
|---|---|
| Bucket name | `deskai-baseline-<last 4 of account id>` |
| Region | Asia Pacific (Singapore) ap-southeast-1 |
| Block all public access | **Leave ON** |
| Bucket versioning | Enable |
| Encryption | SSE-S3 (default) |

Then **Properties → Tags → Edit** and add:

| Key | Value |
|---|---|
| `Project` | `deskai` |
| `Sprint` | `S0` |
| `Task` | `baseline` |
| `Ephemeral` | `false` |
| `TeardownBy` | `never` |

**You'll know it worked when** — the bucket exists with all five tags visible on the Properties tab.

**Now go back and finish sub-task 2** — the tags will be selectable in the billing console.

---

## Sub-task 8 — Study IAM role with a hard block on Provisioned Throughput

**Goal** — Permissions for the work, plus a technical control that makes risk R1 impossible rather
than merely discouraged.

**Console path** — IAM console → *Policies* → **Create policy** → JSON tab.

Paste, replacing `<ACCOUNT_ID>` and `<SUFFIX>`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockInvoke",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:Converse",
        "bedrock:ConverseStream",
        "bedrock:ListFoundationModels",
        "bedrock:GetFoundationModel",
        "bedrock:ApplyGuardrail"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3Project",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::deskai-*",
        "arn:aws:s3:::deskai-*/*"
      ]
    },
    {
      "Sid": "Observability",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:StartQuery",
        "logs:GetQueryResults",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "cloudwatch:PutMetricData",
        "cloudwatch:GetMetricStatistics"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TaggingAndInventory",
      "Effect": "Allow",
      "Action": [
        "tag:GetResources",
        "tag:TagResources",
        "tag:GetTagKeys"
      ],
      "Resource": "*"
    },
    {
      "Sid": "HardDenyProvisionedThroughput",
      "Effect": "Deny",
      "Action": [
        "bedrock:CreateProvisionedModelThroughput",
        "bedrock:UpdateProvisionedModelThroughput",
        "bedrock:PurchaseProvisionedModelThroughput"
      ],
      "Resource": "*"
    }
  ]
}
```

Name it `deskai-study-policy`.

**The last statement is the most important thing in this sprint.** An explicit `Deny` cannot be
overridden by any `Allow`. Provisioned Throughput — the one unrecoverable spend in the whole
programme (§7, risk R1) — becomes technically impossible on this credential rather than something
you have to remember not to click.

Attach the policy to the IAM identity you'll use locally. If that identity is currently an admin
user, create a dedicated user or role for `deskai` work and use its credentials in the CLI profile.

**You'll know it worked when** —

```bash
aws bedrock create-provisioned-model-throughput \
  --model-id apac.amazon.nova-micro-v1:0 \
  --provisioned-model-name should-fail --model-units 1 \
  --region ap-southeast-1
```

returns **AccessDeniedException**. Save that output to
`~/deskai/evidence/s0/pt-denied.txt` — it's a genuinely good post artifact.

---

## Sub-task 9 — Repo scaffold and Converse translation layer

**Goal** — The module that replaces the course's dead sample code (§6) and captures the request ID,
token counts, latency and cost on every call. Everything in later sprints imports this.

```bash
mkdir -p ~/deskai/{core,app,scripts,evidence,adr,benchmarks}
cd ~/deskai && git init
python3 -m venv .venv && source .venv/bin/activate
pip install boto3 streamlit
pip freeze > requirements.txt
```

Create `~/deskai/core/bedrock.py`:

```python
"""deskai Bedrock client — Converse API.

Replaces the course's invoke_model/claude-v2 samples, which target retired
models and the legacy completion API and will not execute.
"""
import time
from dataclasses import dataclass, asdict

import boto3

REGION = "ap-southeast-1"

# APAC cross-region inference profiles — wider model pool, local endpoint.
MODELS = {
    "micro": "apac.amazon.nova-micro-v1:0",
    "lite":  "apac.amazon.nova-lite-v1:0",
    "pro":   "apac.amazon.nova-pro-v1:0",
}

# USD per 1M tokens (input, output). VERIFY against the Bedrock pricing page
# for ap-southeast-1 — rates differ by region and change over time.
PRICING = {
    "apac.amazon.nova-micro-v1:0": (0.035, 0.14),
    "apac.amazon.nova-lite-v1:0":  (0.060, 0.24),
    "apac.amazon.nova-pro-v1:0":   (0.800, 3.20),
}

_client = boto3.client("bedrock-runtime", region_name=REGION)


@dataclass
class Result:
    text: str
    request_id: str
    model_id: str
    input_tokens: int
    output_tokens: int
    latency_ms: int
    est_cost_usd: float

    def as_dict(self):
        return asdict(self)


def converse(prompt, model="micro", system=None, max_tokens=1000, temperature=0.0):
    """Single-turn Converse call. Returns a Result carrying evidence metadata."""
    model_id = MODELS.get(model, model)

    kwargs = {
        "modelId": model_id,
        "messages": [{"role": "user", "content": [{"text": prompt}]}],
        "inferenceConfig": {"maxTokens": max_tokens, "temperature": temperature},
    }
    if system:
        kwargs["system"] = [{"text": system}]

    started = time.perf_counter()
    response = _client.converse(**kwargs)
    latency_ms = int((time.perf_counter() - started) * 1000)

    usage = response["usage"]
    price_in, price_out = PRICING.get(model_id, (0.0, 0.0))
    cost = (usage["inputTokens"] / 1e6) * price_in + \
           (usage["outputTokens"] / 1e6) * price_out

    return Result(
        text=response["output"]["message"]["content"][0]["text"],
        request_id=response["ResponseMetadata"]["RequestId"],
        model_id=model_id,
        input_tokens=usage["inputTokens"],
        output_tokens=usage["outputTokens"],
        latency_ms=latency_ms,
        est_cost_usd=cost,
    )
```

**You'll know it worked when** —

```bash
cd ~/deskai && source .venv/bin/activate
python -c "from core.bedrock import converse; r = converse('Reply with exactly: ok'); print(r)"
```

prints a `Result` with a non-empty `request_id`.

---

## Sub-task 10 — Streamlit shell with request ID surfaced

**Goal** — The UI skeleton every later sprint extends. The request ID must be visible **from day
one** — retrofitting it later is painful, and the §14 correlation evidence depends on it.

Create `~/deskai/app/main.py`:

```python
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import streamlit as st
from core.bedrock import converse, MODELS

st.set_page_config(page_title="deskai", layout="wide")
st.title("deskai — support assistant")
st.caption("Sprint 0 · foundation")

with st.sidebar:
    model = st.selectbox("Model", list(MODELS.keys()), index=0)
    temperature = st.slider("Temperature", 0.0, 1.0, 0.0, 0.1)

prompt = st.text_area("Ask something", "Summarise what a support ticket triage system does.")

if st.button("Send", type="primary"):
    with st.spinner("Calling Bedrock…"):
        result = converse(prompt, model=model, temperature=temperature)

    st.markdown("### Response")
    st.write(result.text)

    st.markdown("### Trace")
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Latency", f"{result.latency_ms} ms")
    c2.metric("Input tokens", result.input_tokens)
    c3.metric("Output tokens", result.output_tokens)
    c4.metric("Est. cost", f"${result.est_cost_usd:.8f}")

    st.code(result.request_id, language=None)
    st.caption(f"Bedrock request ID · model {result.model_id}")
```

Run with `streamlit run app/main.py`.

**You'll know it worked when** — you get a response, four metric tiles, and a request ID displayed
in a copyable code block.

---

## Sub-task 11 — Prove the request-ID correlation works

**Goal** — Validate the §14 evidence mechanism now, while it's cheap to fix.

1. Send a prompt in the Streamlit app. Copy the request ID.
2. **Console path** — CloudWatch console → *Logs Insights* → select log group
   `/aws/bedrock/deskai-invocations` → set the time range to **Last 30 minutes** → run:

```
fields @timestamp, requestId, modelId, input.inputTokenCount, output.outputTokenCount
| filter requestId = "PASTE_REQUEST_ID_HERE"
| sort @timestamp desc
```

**You'll know it worked when** — exactly one row returns, and its token counts match the metric
tiles in the UI. Screenshot both screens side by side into `~/deskai/evidence/s0/`.

**If nothing returns** — model invocation logging (sub-task 6) is not enabled, or logs are still
propagating. Wait two minutes and retry before changing anything.

---

## Sub-task 12 — Orphan sweep script

**Goal** — The nightly control that actually prevents surprise bills. Tag-based queries miss some
services, so the script checks the expensive ones explicitly.

Create `~/deskai/scripts/orphan_sweep.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
REGION="${AWS_REGION:-ap-southeast-1}"
TODAY=$(date -u +%Y-%m-%d)
FOUND=0

echo "=== deskai orphan sweep · ${TODAY} · ${REGION}"

echo
echo "--- Ephemeral resources past TeardownBy"
aws resourcegroupstaggingapi get-resources --region "$REGION" \
  --tag-filters Key=Project,Values=deskai Key=Ephemeral,Values=true \
  --query 'ResourceTagMappingList[].[ResourceARN, Tags[?Key==`TeardownBy`].Value|[0], Tags[?Key==`Sprint`].Value|[0]]' \
  --output text 2>/dev/null | while read -r arn teardown sprint; do
    [ -z "${arn:-}" ] && continue
    if [[ "$teardown" != "never" && "$teardown" < "$TODAY" ]]; then
      echo "  OVERDUE [$sprint] $arn (due $teardown)"
    fi
  done

echo
echo "--- Big-ticket services (tag-independent)"
for check in \
  "OpenSearch Serverless|opensearchserverless list-collections --query collectionSummaries[].name" \
  "SageMaker endpoints|sagemaker list-endpoints --query Endpoints[].EndpointName" \
  "Aurora/RDS clusters|rds describe-db-clusters --query DBClusters[].DBClusterIdentifier" \
  "Bedrock Knowledge Bases|bedrock-agent list-knowledge-bases --query knowledgeBaseSummaries[].name" \
  "Kendra indexes|kendra list-indices --query IndexConfigurationSummaryItems[].Name" \
; do
  label="${check%%|*}"; cmd="${check#*|}"
  out=$(aws $cmd --region "$REGION" --output text 2>/dev/null)
  if [ -n "$out" ] && [ "$out" != "None" ]; then
    echo "  ALIVE  ${label}: ${out}"
    FOUND=1
  else
    echo "  clean  ${label}"
  fi
done

echo
echo "--- TRIPWIRE: provisioned throughput (must always be empty)"
pt=$(aws bedrock list-provisioned-model-throughputs --region "$REGION" \
     --query 'provisionedModelSummaries[].provisionedModelName' --output text 2>/dev/null)
if [ -n "$pt" ] && [ "$pt" != "None" ]; then
  echo "  *** CRITICAL: PROVISIONED THROUGHPUT EXISTS: $pt ***"
  echo "  *** Delete immediately. This bills hourly. ***"
  FOUND=1
else
  echo "  clean  no provisioned throughput"
fi

echo
[ "$FOUND" -eq 0 ] && echo "SWEEP CLEAN" || echo "SWEEP FOUND LIVE RESOURCES — review above"
```

```bash
chmod +x ~/deskai/scripts/orphan_sweep.sh
~/deskai/scripts/orphan_sweep.sh
```

**You'll know it worked when** — it prints `SWEEP CLEAN` with every big-ticket check reading
`clean`. Run this at the end of every working session from now on.

---

## Sub-task 13 — Commit

```bash
cd ~/deskai
cat > .gitignore <<'EOF'
.venv/
__pycache__/
*.pyc
evidence/**/*.png
.env
EOF
git add -A
git commit -m "S0: foundation — Converse layer, Streamlit shell, orphan sweep, cost controls"
```

Push to a public GitHub repo named `deskai`. Per §14, let the commit history run across the whole
programme — a real timeline with real gaps is hard to fabricate after the fact.

---

## Exit criteria

S0 is done when all of these are true:

- [ ] Budget `deskai-monthly` active with 4 alerts, email confirmed
- [ ] Cost anomaly monitor active at $5 threshold
- [ ] Five cost allocation tags activated (or pending)
- [ ] Bedrock model access granted for the five models
- [ ] Model invocation logging writing to `/aws/bedrock/deskai-invocations`
- [ ] Baseline S3 bucket exists, tagged, public access blocked
- [ ] `deskai-study-policy` attached; PT creation returns **AccessDeniedException**
- [ ] `converse()` returns a Result with a request ID
- [ ] Streamlit app displays response, four metrics and the request ID
- [ ] A request ID from the UI was located in CloudWatch Logs Insights
- [ ] `orphan_sweep.sh` prints `SWEEP CLEAN`
- [ ] Repo committed and pushed

**Evidence pack for S0** — `identity.json`, `baseline-services.txt`, `pt-denied.txt`, budget
screenshot, model access screenshot, and the paired UI/CloudWatch request-ID screenshots.

## Notes for Codex

- Deliver one sub-task at a time. Wait for Yu to confirm before continuing.
- Sub-task 2 depends on sub-task 7 for tags to be selectable — flag that ordering when you reach it.
- If any console path has moved, describe what's on screen and adapt; do not guess silently.
- Region is `ap-southeast-1` for every action. Verify the selector before each console step.
- Do not propose any billable resource in S0.

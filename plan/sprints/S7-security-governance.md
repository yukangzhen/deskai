# SPRINT 7 — Security, Privacy & Governance

> Tasks 3.2, 3.3 and 3.4 · 10 core skills + 8 stretch · contains the sprint's standout item (fairness)

## ASSUMPTIONS FROM PRIOR SPRINTS

- [ ] S6 complete; both CloudFormation stacks deleted; Lex and Cognito removed; sweep clean
- [ ] `infra/template.yaml` retained — this sprint extends it
- [ ] `corpus/policies/`, `corpus/tickets/`, `eval/*` retained
- [ ] SageMaker Model Registry group from S4 retained (referenced in lineage)

**Rebuild:** redeploy the S6 SAM stack — it's one command now, which is the payoff for S6's IaC
work. Then rebuild the knowledge base and guardrail (~20 min, under $1).

---

**Objective** — The assistant with the controls a regulated business would demand: encrypted,
tenant-isolated, PII-aware, fully traceable from answer back to source document, and **tested for
fairness**.

**Skill IDs closed** — `3.2.1`–`3.2.3`, `3.3.1`–`3.3.4`, `3.4.1`–`3.4.3`
Stretch: `E-3.2.1`–`E-3.2.8`

**Cost ceiling** — $10. Realistic $4–6.

**Cost warnings specific to this sprint:**

| Service | Cost model | Control |
|---|---|---|
| KMS customer-managed key | ~$1/month per key + per-request | Create **one** key, delete at teardown (30-day pending window — it stops billing on schedule) |
| AWS Config | Per configuration item recorded **and** per rule evaluation | Record **specific resource types only**, never "all resources". Turn the recorder off at teardown. |
| Macie | Per GB scanned | Optional. If used, scan only the small policy bucket, then disable. |
| Lake Formation | Free — you pay underlying Glue | Glue crawler runs are per-DPU-hour; one short crawl only |

**AWS Config with "record all resources" enabled and forgotten is the sleeper cost of this sprint.**
It's not dramatic like OpenSearch, but it accrues quietly.

**FORBIDDEN** — OpenSearch, Aurora, SageMaker endpoints, Kendra, Provisioned Throughput,
NAT Gateway, GuardDuty (30-day trial then per-GB, unnecessary here).

---

## Sub-task 1 — KMS and encryption at rest

**Console path** — KMS → **Create key** → Symmetric → Encrypt and decrypt.

Alias `alias/deskai-s7`. Key policy grants your study role encrypt/decrypt; nothing else.

Apply to: the policy corpus bucket (SSE-KMS with this key), the DynamoDB tables
(customer-managed key), and the CloudWatch log group holding Bedrock invocation logs.

**Then demonstrate the control actually binds** — remove `kms:Decrypt` from a role and show the
read fail. An encryption setting you've never seen deny anything is a checkbox, not a control.

**You'll know it worked when** — you have a screenshot of an `AccessDeniedException` caused by the
key policy, and a successful read after restoring the permission.

---

## Sub-task 2 — Tenant isolation

**Goal** — Task 3.2.1. Support data is customer data, and the retrieval layer is where isolation
usually leaks.

Tag every policy document's metadata sidecar with a `tenant_id` (use three synthetic tenants).
Then enforce isolation at retrieval:

```python
"retrievalConfiguration": {
    "vectorSearchConfiguration": {
        "numberOfResults": 5,
        "filter": {"equals": {"key": "tenant_id", "value": caller_tenant}}
    }
}
```

**Then attack your own isolation.** Write a test that asks tenant A's session for content that only
exists in tenant B's documents, and assert it isn't returned. Try it through the agent path too,
where the filter must be threaded through session state.

**Document the residual risk in `adr/s7-tenant-isolation.md`:** filter-based isolation in a shared
index is weaker than physically separate indexes. State when you'd move to separate indexes and
what it would cost. That tradeoff is the senior answer; "I added a filter" is not.

---

## Sub-task 3 — PII pipeline

**Goal** — Tasks 3.2.2 and 3.2.3.

Three layers, each doing something the others can't:

1. **Detection at ingest** — Comprehend `detect_pii_entities` on incoming tickets, entity types and
   offsets recorded
2. **Redaction before the model** — replace detected spans with typed placeholders
   (`[EMAIL_1]`, `[PHONE_1]`) rather than deleting them, so the model retains structure
3. **Guardrail PII filter on output** — the backstop from S3, catching anything regenerated

**Reversible tokenisation (stretch E-3.2.6):** store the placeholder→value mapping encrypted with
the KMS key so a human agent can un-redact when legitimately needed, while the model never sees raw
PII. That's meaningfully beyond masking and worth building.

**Measure:** PII detection recall against your `t05-pii-heavy.txt` corpus file plus deliberately
tricky cases — Malaysian phone formats, NRIC-style identifiers, addresses. Comprehend is tuned for
US formats; **where it misses locally-formatted identifiers is a real, interesting finding** and
directly relevant to anyone operating in this region.

---

## Sub-task 4 — Real-time PII monitoring and remediation (stretch E-3.2.3, E-3.2.4)

CloudWatch metric filter on the structured logs, counting PII detections by type. Alarm when the
rate exceeds a threshold. Alarm triggers a Lambda that quarantines the offending object and posts
an SNS notification.

**Then trigger it deliberately** and capture the alarm firing, the quarantine, and the notification.

---

## Sub-task 5 — Data lineage

**Goal** — Task 3.3.2, and the question every auditor asks: *which data produced this answer?*

Every response records a lineage record:

```json
{
  "answer_id": "…",
  "request_id": "…",
  "timestamp": "…",
  "prompt": {"id": "deskai-support-persona", "version": "2"},
  "model": {"id": "apac.amazon.nova-pro-v1:0"},
  "guardrail": {"id": "…", "version": "1", "intervened": false},
  "retrieved": [
    {"uri": "s3://…/refunds.md", "s3_version_id": "…", "chunk_score": 0.83,
     "kb_id": "…", "ingested_at": "…"}
  ],
  "tools_called": ["order_status"],
  "tenant_id": "tenant-a"
}
```

**The `s3_version_id` is the detail that makes this real.** Referencing the document isn't enough —
documents change. Pinning the exact object version means you can reproduce the answer six months
later even after the policy was rewritten.

Store lineage records in S3 with **Object Lock in governance mode**, which prevents deletion within
the retention period. Demonstrate that a delete attempt fails.

---

## Sub-task 6 — Governance controls with Config and CloudTrail

**Console path** — AWS Config → **Set up** → **Record specific resource types only**.

Select only: S3 buckets, IAM roles, IAM policies, Lambda functions, DynamoDB tables, KMS keys.
**Do not select "record all resources."**

Add rules: `s3-bucket-server-side-encryption-enabled`,
`s3-bucket-public-read-prohibited`, `iam-policy-no-statements-with-admin-access`,
`cloud-trail-encryption-enabled`.

**Then break a rule on purpose** — create a bucket without encryption, watch Config mark it
non-compliant, fix it, watch it return to compliant. The compliance-state timeline screenshot is
the artifact.

Write `adr/s7-governance-model.md`: who approves a prompt or guardrail change, how a model version
is promoted, what triggers a review, and how an unauthorised change is detected. Reference the
CloudTrail queries that would surface each.

---

## Sub-task 7 — Lake Formation fine-grained access (stretch E-3.2.1, E-3.2.2)

Register the lineage bucket with Lake Formation, run one Glue crawler over it to create a table,
then grant column-level permissions — an "auditor" role sees all columns; an "analyst" role is
denied the columns containing customer identifiers.

Query through Athena as each role and show the difference.

**Keep the crawler run short** — Glue bills per DPU-hour, and the dataset is tiny.

---

## Sub-task 8 — Transparency in outputs

**Goal** — Task 3.4.1.

Every answer surfaces: the policy documents used with links, a confidence signal derived from
retrieval scores and grounding, an explicit statement of what the system could *not* determine, and
a plain "this is an AI-generated summary; it does not constitute a decision" disclosure.

**The "could not determine" element is the one that matters.** Systems that only report what they
know read as confident; systems that report the boundary of what they know read as trustworthy —
and it's what a regulator would look for.

---

## Sub-task 9 — Fairness evaluation ⭐

**Goal** — Task 3.4.2. This is the strongest item in the sprint and the one most likely to be
hand-waved. It won't be here, because it's directly measurable.

**Method — counterfactual testing.** Take 20 base tickets with identical substantive content, and
generate variants altering only attributes that *should not* affect the outcome:

| Varied attribute | Variants |
|---|---|
| Customer name | Malay, Chinese, Indian, Anglo origin names |
| Language | English, Bahasa Malaysia, Manglish |
| Tone | Polite, neutral, angry |
| Formality | Formal prose vs SMS-style abbreviation |
| Stated gender | Where the ticket mentions it |

That's 20 base × ~12 variants ≈ 240 cases. Run each through the full pipeline and record: refund
eligibility decision, escalation decision, response length, response reading level, sentiment of
the reply, and which tier the router selected.

**Then analyse for disparity:**

```python
# Escalation rate by varied attribute — outcomes should be near-identical
# where only the protected attribute changed.
import pandas as pd
df = pd.read_json("benchmarks/s7-fairness.json")
print(df.groupby("name_origin")["escalated"].mean())
print(df.groupby("language")["refund_eligible"].mean())
print(df.groupby("tone")["response_length"].mean())
```

**What you're looking for, and what each finding means:**

- Different **refund eligibility** by name origin or language → a serious problem, and the headline
- Different **escalation rate** by tone → arguably legitimate; angry customers may warrant
  escalation. Say so, and explain why that's a different category from the above.
- Shorter or lower-quality responses in Bahasa → a real quality gap with a real business cost
- Different **router tier** by formality → cost asymmetry: informal writers get cheaper models and
  potentially worse answers. Subtle, plausible, and nobody looks for it.

**Then mitigate and re-measure.** Options: strip names before the model sees them (reuse the
redaction from sub-task 3), add explicit fairness instruction to the system prompt, normalise the
complexity score across languages.

**Publish the before-and-after disparity numbers, including any you failed to fix.** An honest
fairness report showing a residual gap is far more credible than one claiming a clean result — and
it's the single most distinctive thing you can post from this entire programme.

---

## Sub-task 10 — Model card and compliance reporting (stretch E-3.2.7, E-3.2.8)

Write `docs/model-card.md`: intended use, out-of-scope uses, training and grounding data, models
and versions, evaluation results including the fairness numbers, known limitations, escalation
paths, review cadence and owner.

Then a Lambda on an EventBridge schedule producing a weekly compliance report: Config compliance
state, guardrail intervention counts, PII detection rates, lineage record completeness, and any
fairness metric drift. Write to S3 as markdown.

---

## Sub-task 11 — Streamlit governance panel

Per answer: lineage record, tenant context, PII detections and redactions, guardrail decisions,
confidence, and the transparency disclosures. Plus a compliance tab showing Config state and the
latest fairness summary.

---

## Sub-task 12 — Measure

1. **Fairness disparity** across each varied attribute, before and after mitigation
2. **PII detection recall**, including the local-format gap
3. **Tenant isolation** — cross-tenant leak attempts blocked
4. **Lineage completeness** — percentage of answers fully traceable to pinned document versions
5. **Config compliance timeline** through the deliberate violation and fix

---

## TEARDOWN

```bash
# Config recorder FIRST — it bills while running
aws configservice stop-configuration-recorder --configuration-recorder-name default --region ap-southeast-1
aws configservice delete-configuration-recorder --configuration-recorder-name default --region ap-southeast-1
aws configservice delete-delivery-channel --delivery-channel-name default --region ap-southeast-1

# Macie if enabled
aws macie2 disable-macie --region ap-southeast-1

# Lake Formation / Glue
aws glue delete-crawler --name deskai-s7-crawler --region ap-southeast-1
aws glue delete-database --name deskai_s7_lineage --region ap-southeast-1

# Object Lock buckets need version-level deletion; governance mode may need bypass
aws s3api delete-objects --bucket deskai-s7-lineage-<suffix> \
  --bypass-governance-retention --delete "$(aws s3api list-object-versions \
  --bucket deskai-s7-lineage-<suffix> --output json \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" --region ap-southeast-1

aws cloudformation delete-stack --stack-name deskai-s7 --region ap-southeast-1

# KMS key last — schedule deletion, minimum 7 days
aws kms schedule-key-deletion --key-id <KEY_ID> --pending-window-in-days 7 --region ap-southeast-1

~/deskai/scripts/orphan_sweep.sh
```

**KMS keys cannot be deleted immediately** — 7 days minimum. They continue to bill the ~$1/month
prorated during the window. Schedule it and note it in your cost reconciliation; it's the one
resource in the programme that outlives its teardown.

**Object Lock caveat:** governance mode requires `--bypass-governance-retention` and the
`s3:BypassGovernanceRetention` permission. Compliance mode cannot be bypassed at all — which is why
this brief specifies governance mode.

**Keep:** `benchmarks/s7-fairness.json`, the model card, all ADRs, the compliance report samples.

---

## Post angle

**Lead with fairness.** Almost nobody runs counterfactual fairness testing on a support assistant,
and the finding is inherently interesting whichever way it lands. "I changed only the customer's
name and the escalation rate moved 8 points" is a sentence that stops a scroll — and publishing the
gap you *couldn't* close is what makes it credible rather than promotional.

Second: the PII detection gap on Malaysian identifier formats. Regionally specific, immediately
useful to a local audience, and it demonstrates you tested against your actual context rather than
the documentation's examples.

Third, briefly: lineage with pinned S3 version IDs. Most "explainability" demos cite a document;
citing the exact version that existed at answer time is the difference between a demo and an
auditable system.

## Notes for Codex

- AWS Config: specific resource types only. Never "all resources".
- Config recorder is stopped first at teardown.
- KMS deletion has a 7-day minimum window — flag this so Yu isn't surprised by residual cost.
- Sub-task 9 is the priority item. If time compresses, cut stretch items 7 and 10 first, never 9.
- Region `ap-southeast-1` throughout.

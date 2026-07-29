# deskai — current state

> Codex reads this first every session. Yu updates it last, before stopping.

```
Sprint:         S1 · Ingest & Extract (not started)
Brief:          plan/sprints/S1-ingest-extract.md
Sub-task:       S0 COMPLETE — all exit criteria and the local evidence pack are complete
Pause rating:   🟡 AMBER
Live billable:  none
Live at rest:   deskai-baseline-1969 (S3), /aws/bedrock/deskai-invocations (CloudWatch Logs), deskai-s0-role-bedrock-logging and deskai-study-policy (IAM); permanent baseline
Last sweep:     2026-07-29 — SWEEP CLEAN (`evidence/s0/orphan-sweep.txt`)
Spend to date:  Cost Explorer posting pending; directly measured Bedrock calls total approximately $0.000046
Next action:    Walk through the S1 ASSUMPTIONS block, then begin S1 sub-task 1 after confirmation
Blocked on:     none
```

---

## Programme progress

| | Sprint | Tasks | Ceiling | Status | Spend |
|---|---|---|---|---|---|
| ✓ | S0 Foundation | — | $1 | complete | $0.00 reported; tag posting pending |
| ▢ | S1 Ingest & Extract | 1.1, 1.3 | $2 | | |
| ▢ | S2 RAG & Vector Stores | 1.4, 1.5 | $15 | | |
| ▢ | S3 Prompting & Safety | 1.6, 3.1 | $5 | | |
| ▢ | S4 Model Selection | 1.2, 2.2 | $12 | | |
| ▢ | S5 Agentic & FM APIs | 2.1, 2.4 | $6 | | |
| ▢ | S6 Enterprise Integration | 2.3, 2.5 | $8 | | |
| ▢ | S7 Security & Governance | 3.2, 3.3, 3.4 | $10 | | |
| ▢ | S8 Cost & Performance | 4.1, 4.2 | $8 | | |
| ▢ | S9 Observability & Eval | 4.3, 5.1 | $15 | | |
| ▢ | S10 Troubleshooting & Finale | 5.2 | $10 | | |

**Skills:** 0 / 97 core · 0 / 21 stretch — see `plan/coverage-matrix.csv`
**Budget:** $0.00 of $100

---

## Checkpoint log

Append at the end of each sprint. The next sprint's brief is read against this.

### S0 — complete · 2026-07-29

- **Created:** `deskai-baseline-1969` (S3, ap-southeast-1, permanent baseline; versioning enabled, SSE-S3, public access blocked; user confirmed five required tags); `deskai-monthly` ($100 recurring monthly budget, 50%/80%/100% actual and 100% forecast alerts); `deskai-anomaly` monitor with `deskai-anomaly-alerts` ($5 above expected spend, daily email summary, permanent baseline tags); `/aws/bedrock/deskai-invocations` (CloudWatch Logs, Standard, 30-day retention); `deskai-s0-role-bedrock-logging` (Bedrock service role); `deskai-study-policy` (attached to IAM user, PT create/update explicit deny verified by IAM simulation)
- **Diverged from brief:** Canonical repo is the existing iCloud DeskAI workspace, not `~/deskai`. Baseline inventory found three pre-existing non-deskai S3 buckets; no Lambda functions, DynamoDB tables, OpenSearch Serverless collections, SageMaker endpoints, RDS clusters, or Bedrock Knowledge Bases. Current Cost Anomaly Detection requires SNS for individual alerts; to comply with S0's no-billable-resource rule, configured direct-email daily summaries instead. Bedrock commercial-region access is now automatic rather than manually requested. Claude Haiku updated from legacy Claude 3 Haiku to active Claude Haiku 4.5. Titan Text Embeddings V2 is unavailable for Knowledge Bases in ap-southeast-1 and needs an S2 region/model decision. Bedrock logging now requires the CloudWatch log group to be created before saving the console configuration; the original flow failed validation until the group existed.
- **Models granted in ap-southeast-1:** Nova Micro, Nova Lite, Nova Pro, and Claude Haiku 4.5 available via cross-region inference from Singapore. Titan Text Embeddings V2 unavailable in the Singapore serverless catalog.
- **Measured:** First Nova Micro Converse smoke test: 5 input tokens, 2 output tokens, 761 ms client latency, estimated $0.000000455; response `ok` with non-empty request ID.
- **Measured:** Streamlit Nova Micro call: 10 input tokens, 322 output tokens, 2,348 ms client latency, estimated $0.00004543; UI surfaced request ID `ce320191-15c6-4bec-975b-36e5399aefe3`.
- **Verified:** CloudWatch Logs Insights returned exactly one Bedrock invocation for request ID `ce320191-15c6-4bec-975b-36e5399aefe3`, with token counts matching the Streamlit trace (10 input, 322 output).
- **Standing:** 2026-07-29 orphan sweep clean: no OpenSearch, SageMaker, RDS/Aurora, Bedrock KB/agent, Kendra, NAT gateway, or Bedrock Provisioned Throughput resources found. Kendra returned `SubscriptionRequiredException`, recorded as clean because the service is not subscribed.
- **Spend:** Cost Explorer sprint-tag posting remains pending; the two directly measured Bedrock calls total approximately $0.000046, comfortably below the $1 S0 ceiling.
- **Still standing:** `deskai-baseline-1969`, `/aws/bedrock/deskai-invocations`, `deskai-s0-role-bedrock-logging`, `deskai-study-policy`, `deskai-monthly`, `deskai-anomaly`, and `deskai-anomaly-alerts` are permanent baseline controls. The 2026-07-29 sweep found no hourly-billed resources and no Provisioned Throughput.
- **Repository:** Public `main` branch published at `https://github.com/yukangzhen/deskai`; raw identity evidence and original course materials remain local and ignored, while committed evidence is redacted.
- **Cost allocation tags:** `Project`, `Sprint`, `Task`, `Ephemeral`, and `TeardownBy` confirmed Active on 2026-07-29.
- **Evidence:** Local-only screenshots saved for the $100 budget and four alerts, Amazon Nova model catalog, Claude Haiku 4.5 model catalog, Streamlit response and trace, and the matching CloudWatch request-ID result. PNG files remain ignored under the sprint brief's privacy rule; redacted textual evidence is committed.

---

## Open issues

*Anything unresolved that a future session needs to know.*

---

## Account facts

Fill in during S0 sub-task 1 — every sprint needs these.

```
Account ID (last 4):     1969
Region:                 ap-southeast-1
Bucket suffix:           1969
Models granted:         Nova Micro, Nova Lite, Nova Pro, Claude Haiku 4.5 (cross-region)
Baseline bucket:        deskai-baseline-1969
```

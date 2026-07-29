# SPRINT 6 — Enterprise Integration

> Tasks 2.3 and 2.5 · 11 core skills + 4 stretch

## ASSUMPTIONS FROM PRIOR SPRINTS

- [ ] S5 complete; agent, KB, guardrail, DynamoDB tables torn down; sweep clean
- [ ] Lambda source and seed data retained from S5
- [ ] GitHub repo `deskai` exists and is pushed

**Rebuild:** this sprint puts a production-shaped front end on the assistant, so it needs a working
backend. Sub-task 0 redeploys the S5 order tables and the three action Lambdas — but this time
**from infrastructure-as-code**, not the console. That's deliberate: sub-task 8's CI/CD skill
requires a deployable artifact, and hand-clicked resources can't be deployed twice.

---

**Objective** — The assistant exposed as a governed enterprise API: authenticated, throttled,
event-driven, deployed by pipeline, and running in two regions.

**Skill IDs closed** — `2.3.1`–`2.3.5`, `2.5.1`–`2.5.6`
Stretch: `E-2.5.1` multi-language · `E-2.5.2` sentiment · `E-2.5.3` recommendations ·
`E-2.5.4` Amazon Lex

**Cost ceiling** — $8. Realistic $2–4. API Gateway, EventBridge, SQS and Step Functions are all
fractions of a cent at this volume; the second-region deployment roughly doubles a very small number.

**FORBIDDEN** — OpenSearch, Aurora, SageMaker, Kendra, Provisioned Throughput, NAT Gateway
(~$0.05/hr plus data processing — easy to create accidentally via a VPC wizard, and there is no
reason to need one here).

**Ephemeral created** — API Gateway, Cognito user pool, EventBridge bus, SQS queue + DLQ,
Step Functions state machine, Lambdas, DynamoDB tables, Lex bot, second-region stack.

## Architecture

```
   client / Streamlit / Lex
            │
            ▼
   ┌─────────────────────────────────────────┐
   │  API Gateway  deskai-s6-api-gateway     │
   │   · Cognito authorizer                  │
   │   · usage plan: 10 req/s, 1000/day      │
   │   · request validation                  │
   └───────────────┬─────────────────────────┘
                   │
                   ▼
        deskai-s6-fn-gateway  ──▶ router (S4) ──▶ Bedrock
                   │
                   ├──▶ EventBridge  deskai-s6-bus
                   │        ├──▶ SQS deskai-s6-q-analytics ──▶ DLQ
                   │        └──▶ Step Functions deskai-s6-sfn-resolve
                   │
                   └──▶ DynamoDB (orders, sessions)

   GitHub Actions ──▶ SAM deploy ──▶ ap-southeast-1
                                └──▶ ap-southeast-2   (cross-environment)
```

---

## Sub-task 1 — SAM template for the backend

**Goal** — Task 2.3.5. Everything from here is defined in code so it can be deployed repeatedly and
to more than one region.

Create `~/deskai/infra/template.yaml` — a SAM template defining: the two DynamoDB tables
(on-demand), the three action Lambdas plus the gateway Lambda, the API, the EventBridge bus, the
SQS queue and DLQ, the state machine, and IAM roles scoped per function.

Parameterise the region and stage so the same template deploys twice.

```bash
cd ~/deskai/infra
sam build
sam deploy --guided --stack-name deskai-s6 --region ap-southeast-1 \
  --capabilities CAPABILITY_IAM
```

**Include the Provisioned Throughput deny in every Lambda role in the template.** Defence in depth,
and it means the control survives into anything deployed from this repo.

**You'll know it worked when** — `aws cloudformation describe-stacks --stack-name deskai-s6`
returns CREATE_COMPLETE and the API endpoint URL is in the outputs.

---

## Sub-task 2 — API Gateway with validation and error mapping

**Goal** — Tasks 2.5.1 and 2.3.1.

Define in the template: `POST /v1/ask`, `GET /v1/orders/{order_id}`, `POST /v1/escalations`.

Add a request model with required fields and a length cap on the question, plus gateway responses
mapping 4XX and 5XX to a consistent JSON error envelope:

```json
{"error": {"code": "VALIDATION_FAILED", "message": "…", "request_id": "…"}}
```

**Return the request ID in every response**, success or failure. It ties the client response to
CloudWatch, which is the §14 evidence mechanism and also the only sane way to support an API.

---

## Sub-task 3 — Authentication

**Goal** — Task 2.3.3.

**Console path** — Cognito → **Create user pool**. Name `deskai-s6-pool`. Create an app client
without a secret. Create one test user.

Attach a Cognito authorizer to the API in the template and protect all three routes.

Verify: unauthenticated call returns 401; call with a valid ID token returns 200.

**Capture both responses for the evidence pack.** A screenshot of a 401 is proof the auth layer
exists — which is otherwise invisible in a demo.

---

## Sub-task 4 — Usage plans and throttling

**Goal** — the "gateway" half of Task 2.3.5.

Create a usage plan: rate 10 req/s, burst 20, quota 1000/day. Attach an API key and associate it
with the stage.

**Then prove throttling works** — fire 50 concurrent requests and capture the 429 responses:

```bash
seq 1 50 | xargs -P 20 -I{} curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST "$API_URL/v1/ask" -H "x-api-key: $KEY" \
  -H "Authorization: $TOKEN" -H 'Content-Type: application/json' \
  -d '{"question":"where is my order"}' | sort | uniq -c
```

Expect a mix of 200 and 429. **That count is a headline number** — a rate limit you've never
observed triggering is a rate limit you don't know works.

---

## Sub-task 5 — Event-driven processing

**Goal** — Tasks 2.3.2 and 2.5.3.

The gateway Lambda publishes an event per interaction to `deskai-s6-bus`:

```json
{
  "source": "deskai.assistant",
  "detail-type": "TicketAnswered",
  "detail": {
    "session_id": "…", "request_id": "…", "tier": "moderate",
    "escalated": false, "sentiment": "NEGATIVE", "cost_usd": 0.00021
  }
}
```

Two rules on the bus: one routing everything to `deskai-s6-q-analytics` (SQS, with a DLQ after 3
receives), one routing `escalated: true` events to the Step Functions workflow.

**Then prove the DLQ works** — deploy a consumer that deliberately fails, send events, and show
them landing in the DLQ. A DLQ you've never seen catch anything is decoration.

---

## Sub-task 6 — Step Functions resolution workflow

**Goal** — Task 2.5.5.

State machine `deskai-s6-sfn-resolve`: classify → retrieve context → attempt resolution →
choice (resolved / needs human) → notify → record. Retry with backoff on every task state,
Catch routing to a failure-handling state.

**The visual execution graph is exceptional demo material.** Record both a successful execution and
a failed one that catches correctly — the red path with a graceful recovery communicates
engineering maturity in a way a green path can't.

---

## Sub-task 7 — Multi-language and sentiment (stretch E-2.5.1, E-2.5.2)

Reuse `core/extract.enrich()` from S1 for Comprehend language detection and sentiment. Route
non-English questions to a model prompt instructed to answer in the detected language, and attach
sentiment to the emitted event so angry tickets can be prioritised.

**Test with Bahasa Malaysia.** A locally relevant multi-language demo is more memorable than a
French one, and you can verify the output quality yourself.

---

## Sub-task 8 — CI/CD pipeline

**Goal** — Task 2.3.5, the CI half.

Create `.github/workflows/deploy.yml`:

- On PR: lint, unit tests, `sam validate`, `cfn-lint`
- On merge to main: `sam build`, `sam deploy` to ap-southeast-1
- Manual approval gate before the second region
- Authenticate via **GitHub OIDC with an IAM role** — no long-lived access keys in secrets

**The OIDC detail matters.** Storing AWS access keys in GitHub secrets is the common approach and
the wrong one; short-lived credentials via OIDC is the current practice, and being able to explain
why is a genuine differentiator.

Include a smoke test post-deploy that calls `/v1/ask` and fails the pipeline on a non-200.

**Measure deploy time** from merge to live endpoint.

---

## Sub-task 9 — Cross-region deployment

**Goal** — Task 2.3.4.

Deploy the same template to `ap-southeast-2` (Sydney):

```bash
sam deploy --stack-name deskai-s6-syd --region ap-southeast-2 \
  --parameter-overrides Stage=dr --capabilities CAPABILITY_IAM
```

Expect it to fail or degrade first time — Bedrock model availability and inference profile IDs
differ by region. **That failure is the lesson.** Document in `adr/s6-multi-region.md`: what broke,
what had to be parameterised, and what a real DR posture would require (data replication, DNS
failover, per-region model access).

Measure latency from Malaysia to both regions.

**Tear down the Sydney stack as soon as it's measured.**

---

## Sub-task 10 — Amazon Lex front end (stretch E-2.5.4)

**Console path** — Amazon Lex → **Create bot** → `deskai-s6-lex-support`.

One intent `AskSupport` with a free-form slot, fulfilment by Lambda calling your API. Enable the
web UI or test in console.

**Lex has a generous free tier for text requests**; keep it text-only. Voice adds cost and nothing
to the story.

**Worth a paragraph in the post:** when a slot-based conversational interface is the right choice
versus a straight LLM chat surface. Lex gives deterministic intent matching and slot validation;
the LLM gives flexibility. The interesting answer is that they compose.

---

## Sub-task 11 — Recommendations for agents (stretch E-2.5.3)

Given the resolved ticket and retrieved policies, generate three suggested next actions for a human
agent, ranked, each citing its policy source. Small feature, strong demo moment — it shows the
system supporting a human rather than replacing one, which is the framing that lands better with
enterprise audiences.

---

## Sub-task 12 — Measure

1. **Throttling** — 200/429 split under 50 concurrent requests
2. **Cold start versus warm** latency for the gateway Lambda
3. **End-to-end p50/p95** through API Gateway versus direct Bedrock
4. **Deploy time** from merge to live
5. **Cross-region latency** Singapore versus Sydney from Malaysia
6. **DLQ behaviour** — events captured after repeated failure

---

## TEARDOWN

```bash
# Second region first
aws cloudformation delete-stack --stack-name deskai-s6-syd --region ap-southeast-2
aws cloudformation wait stack-delete-complete --stack-name deskai-s6-syd --region ap-southeast-2

# Lex
aws lexv2-models list-bots --region ap-southeast-1
aws lexv2-models delete-bot --bot-id <BOT_ID> --skip-resource-in-use-check --region ap-southeast-1

# Cognito
aws cognito-idp delete-user-pool --user-pool-id <POOL_ID> --region ap-southeast-1

# Main stack — removes API, Lambdas, tables, bus, queues, state machine
aws cloudformation delete-stack --stack-name deskai-s6 --region ap-southeast-1
aws cloudformation wait stack-delete-complete --stack-name deskai-s6 --region ap-southeast-1

# CloudWatch log groups survive stack deletion
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/deskai-s6 \
  --region ap-southeast-1 --query 'logGroups[].logGroupName' --output text

~/deskai/scripts/orphan_sweep.sh
```

**Note:** CloudFormation stack deletion is the single cleanest teardown in the programme — one
command removes a dozen resources. Worth saying out loud in the post, since it's the strongest
practical argument for IaC over console clicking, and you'll have felt the difference by now.

**Keep:** `infra/template.yaml`, the GitHub Actions workflow, all benchmarks and ADRs.

---

## Post angle

The IaC contrast. By this sprint you've torn down five sprints of hand-clicked resources one API
call at a time, and this one comes down with a single `delete-stack`. That's a real, earned opinion
about infrastructure management rather than a repeated received one.

Second: the 429 screenshot. Showing you deliberately overloaded your own API to verify the rate
limit fires is the kind of thing that separates people who configured a usage plan from people who
tested one.

Third, for the CI/CD audience: GitHub OIDC instead of stored access keys, and why.

## Notes for Codex

- Everything is deployed via SAM, not the console — that's the point of this sprint.
- Do not create a NAT Gateway. If a wizard offers a VPC with one, decline.
- Sydney stack is torn down immediately after measurement.
- CloudWatch log groups survive stack deletion — check them explicitly.
- Region `ap-southeast-1` unless a step says otherwise.

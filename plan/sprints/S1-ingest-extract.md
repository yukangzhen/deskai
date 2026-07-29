# SPRINT 1 — Ingest & Extract

> Tasks 1.1 and 1.3 · 7 core skills · Codex delivers one sub-task at a time.

## ASSUMPTIONS FROM PRIOR SPRINTS

Confirm before starting. If any is false, tell Codex and it adapts.

- [ ] S0 complete: budget, anomaly monitor, tags active, orphan sweep clean
- [ ] `core/bedrock.py` works; `converse()` returns a request ID
- [ ] Bedrock model access granted for Nova Micro, Lite, Pro
- [ ] Model invocation logging writing to `/aws/bedrock/deskai-invocations`
- [ ] `deskai-study-policy` attached; PT creation denied
- [ ] Baseline bucket `deskai-baseline-<suffix>` exists

**If Nova Pro was not granted** — use Nova Lite everywhere Pro appears below and note it.

---

**Objective** — A support ticket lands in S3; a Lambda extracts structured fields, validates them,
scores data quality, and writes a review-ready record. Bad tickets are quarantined, not silently
mangled.

**Skill IDs closed** — `1.1.1`, `1.1.2`, `1.1.3`, `1.3.1`, `1.3.2`, `1.3.3`, `1.3.4`
Stretch available: `E-1.1.1` (web interface — satisfied by the Streamlit work below)

**Cost ceiling** — $2. Realistic spend under $0.50.

**FORBIDDEN this sprint** — Knowledge Bases, OpenSearch (any flavour), SageMaker, Aurora, Kendra,
Bedrock Agents, Guardrails, Provisioned Throughput. If Codex proposes any of these, it has drifted.

**Baseline used** — `deskai-baseline-<suffix>`, `core/bedrock.py`, study IAM policy.

**Ephemeral created** — `deskai-s1-tickets-<suffix>`, `deskai-s1-fn-ingest`,
`deskai-s1-role-fn-ingest`. `TeardownBy` = sprint end + 1 day.

## Architecture

```
  Streamlit (upload)                    ┌─ Textract ──┐  (PDF / image attachments)
         │                              │             │
         ▼                              ▼             │
  S3  deskai-s1-tickets/raw/  ──event──▶ Lambda ──────┼─ Comprehend ─┐ (language, sentiment, PII)
                                          deskai-s1-  │             │
                                          fn-ingest   ▼             │
                                              │   Bedrock Converse ─┘  (field extraction, summary)
                                              │       │
                                              │       ▼
                                              │   validate + quality score
                                              │       │
                              ┌───────────────┴───────┴────────────┐
                              ▼                                    ▼
                  s3://…/processed/{id}.json          s3://…/quarantine/{id}.json
                        (schema valid)                   (failed validation)
                              │
                              ▼
                        CloudWatch Logs  ← request IDs for evidence
```

**Why this shape:** the event-driven S3→Lambda path is what Task 1.3 asks for, and it's also what
makes the request-ID evidence trail natural — every ticket produces a log line. The quarantine
branch matters more than it looks: a pipeline that silently accepts bad data is the failure mode
Task 1.3 is testing for.

---

## Sub-task 1 — Ticket landing bucket

**Goal** — Storage with the prefix structure the pipeline routes into.

**Console path** — S3 → **Create bucket**.

| Field | Value |
|---|---|
| Name | `deskai-s1-tickets-<last 4 of account id>` |
| Region | ap-southeast-1 |
| Block all public access | ON |
| Versioning | Enable |

Tags: `Project=deskai`, `Sprint=S1`, `Task=1.3`, `Ephemeral=true`, `TeardownBy=<sprint end +1d>`

Then create three folders in the bucket: `raw/`, `processed/`, `quarantine/`.

**You'll know it worked when** — bucket exists with three prefixes and five tags.

---

## Sub-task 2 — Build the test corpus

**Goal** — A deliberately varied corpus. A clean corpus proves nothing; the validation and
quarantine logic only demonstrates value against messy input.

Create `~/deskai/corpus/tickets/` with 10 files:

| File | Characteristic | Tests |
|---|---|---|
| `t01-clean.txt` | All fields present, clear | Happy path |
| `t02-missing-fields.txt` | No order ID, no date | Validation warnings |
| `t03-angry.txt` | Hostile tone, profanity-adjacent | Sentiment, tone handling |
| `t04-multilingual.txt` | Bahasa Malaysia | Language detection |
| `t05-pii-heavy.txt` | Names, emails, phone, partial card number | PII detection (real work in S7) |
| `t06-very-long.txt` | ~4000 words, rambling | Token limits, summarisation |
| `t07-ambiguous.txt` | Two unrelated issues in one ticket | Extraction under ambiguity |
| `t08-minimal.txt` | "it broke" | Near-empty extraction |
| `t09-scan.pdf` | Scanned image of a printed ticket | Textract path |
| `t10-injection.txt` | Contains "ignore previous instructions…" | Baseline for S3's guardrails |

Ask Codex to generate the text files. **Use entirely synthetic data** — invented names, invented
order numbers. Never real customer data, and label it as synthetic in the demo (this matters for
the LinkedIn post; fabricated-looking real data is a credibility problem either way).

Upload to `s3://deskai-s1-tickets-<suffix>/raw/`.

**You'll know it worked when** — 10 objects listed under `raw/`.

---

## Sub-task 3 — Prompt library (standardized component 1 of 3)

**Goal** — Task 1.1.3 asks for reusable standardized components. Reuse is what makes the skill
genuine, so these three modules are imported by every later sprint.

Create `~/deskai/core/prompts.py`:

```python
"""Versioned prompt templates. Every prompt in deskai lives here, never inline."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Prompt:
    id: str
    version: str
    system: str
    template: str

    def render(self, **kwargs) -> str:
        return self.template.format(**kwargs)


EXTRACT_TICKET = Prompt(
    id="extract_ticket",
    version="1.0.0",
    system=(
        "You are a support ticket parser. Extract only what is explicitly present. "
        "Never infer, guess, or invent a value. If a field is absent, return null. "
        "Respond with JSON only, no prose, no code fences."
    ),
    template="""Extract these fields from the support ticket below.

Fields:
- customer_name (string or null)
- order_id (string or null)
- issue_category (one of: billing, delivery, product_fault, account, other)
- issue_summary (string, max 25 words)
- requested_action (string or null)
- urgency (one of: low, medium, high)

Ticket:
---
{ticket_text}
---

JSON:""",
)

SUMMARISE_TICKET = Prompt(
    id="summarise_ticket",
    version="1.0.0",
    system="You write neutral, factual summaries for support agents. No speculation.",
    template=(
        "Summarise this ticket in two sentences for an agent picking it up cold. "
        "State what happened and what the customer wants.\n\n{ticket_text}"
    ),
)

REGISTRY = {p.id: p for p in (EXTRACT_TICKET, SUMMARISE_TICKET)}
```

**Why versioned and centralised:** Task 1.6 requires prompt governance and versioning. Building
that structure now means S3 extends this file rather than rewriting every call site.

**You'll know it worked when** — `python -c "from core.prompts import REGISTRY; print(REGISTRY.keys())"` lists both.

---

## Sub-task 4 — Schema and validator (standardized component 2 of 3)

Create `~/deskai/core/schema.py`:

```python
"""Ticket schema, validation and data-quality scoring (Task 1.3)."""
import json
import re
from dataclasses import dataclass, field

CATEGORIES = {"billing", "delivery", "product_fault", "account", "other"}
URGENCIES = {"low", "medium", "high"}

REQUIRED = ["issue_category", "issue_summary", "urgency"]
OPTIONAL = ["customer_name", "order_id", "requested_action"]


@dataclass
class ValidationResult:
    valid: bool
    record: dict
    errors: list = field(default_factory=list)
    warnings: list = field(default_factory=list)
    quality_score: float = 0.0


def _coerce_json(raw: str) -> dict:
    """Models sometimes wrap JSON in fences or prose. Recover rather than fail."""
    raw = raw.strip()
    fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", raw, re.S)
    if fenced:
        raw = fenced.group(1)
    else:
        brace = re.search(r"\{.*\}", raw, re.S)
        if brace:
            raw = brace.group(0)
    return json.loads(raw)


def validate(raw_output: str) -> ValidationResult:
    errors, warnings = [], []

    try:
        record = _coerce_json(raw_output)
    except (json.JSONDecodeError, AttributeError) as exc:
        return ValidationResult(False, {}, [f"unparseable model output: {exc}"], [], 0.0)

    for f in REQUIRED:
        if not record.get(f):
            errors.append(f"missing required field: {f}")

    for f in OPTIONAL:
        if not record.get(f):
            warnings.append(f"absent optional field: {f}")

    cat = record.get("issue_category")
    if cat and cat not in CATEGORIES:
        errors.append(f"issue_category '{cat}' not in {sorted(CATEGORIES)}")

    urg = record.get("urgency")
    if urg and urg not in URGENCIES:
        errors.append(f"urgency '{urg}' not in {sorted(URGENCIES)}")

    summary = record.get("issue_summary") or ""
    if len(summary.split()) > 25:
        warnings.append("issue_summary exceeds 25 words")

    present = sum(1 for f in REQUIRED + OPTIONAL if record.get(f))
    quality = present / len(REQUIRED + OPTIONAL)

    return ValidationResult(
        valid=not errors,
        record=record,
        errors=errors,
        warnings=warnings,
        quality_score=round(quality, 2),
    )
```

**Note the `_coerce_json` helper.** Models wrap JSON in code fences unpredictably. Failing the whole
record over a formatting artifact would be a false negative — this is exactly the "enhance input
data quality" skill (1.3.4) applied to model output rather than input.

**You'll know it worked when** — `validate('```json\\n{"issue_category":"billing","issue_summary":"x","urgency":"low"}\\n```')` returns `valid=True`.

---

## Sub-task 5 — Extraction pipeline (standardized component 3 of 3)

Create `~/deskai/core/extract.py`:

```python
"""Ticket extraction pipeline: enrich → extract → validate → score."""
from dataclasses import dataclass, asdict

import boto3

from core.bedrock import converse
from core.prompts import EXTRACT_TICKET, SUMMARISE_TICKET
from core.schema import validate

REGION = "ap-southeast-1"
_comprehend = boto3.client("comprehend", region_name=REGION)
_textract = boto3.client("textract", region_name=REGION)

MAX_COMPREHEND_BYTES = 5000


@dataclass
class Enrichment:
    language: str
    language_confidence: float
    sentiment: str
    pii_entity_types: list


def enrich(text: str) -> Enrichment:
    """Comprehend pass: language, sentiment, PII entity types (Task 1.3.2)."""
    sample = text[:MAX_COMPREHEND_BYTES]

    langs = _comprehend.detect_dominant_language(Text=sample)["Languages"]
    top = max(langs, key=lambda l: l["Score"]) if langs else {"LanguageCode": "en", "Score": 0.0}
    lang = top["LanguageCode"]

    # Sentiment supports a limited language set; fall back rather than error.
    sentiment_lang = lang if lang in {"en", "es", "fr", "de", "it", "pt", "ar", "hi", "ja", "ko", "zh", "zh-TW"} else "en"
    sentiment = _comprehend.detect_sentiment(Text=sample, LanguageCode=sentiment_lang)["Sentiment"]

    pii_types = []
    try:
        pii = _comprehend.detect_pii_entities(Text=sample, LanguageCode="en")
        pii_types = sorted({e["Type"] for e in pii.get("Entities", [])})
    except _comprehend.exceptions.UnsupportedLanguageException:
        pass

    return Enrichment(lang, round(top["Score"], 3), sentiment, pii_types)


def text_from_pdf(bucket: str, key: str) -> str:
    """Textract synchronous detection — single-page documents only (Task 1.3.2)."""
    resp = _textract.detect_document_text(
        Document={"S3Object": {"Bucket": bucket, "Name": key}}
    )
    return "\n".join(b["Text"] for b in resp["Blocks"] if b["BlockType"] == "LINE")


def process(text: str, model: str = "micro") -> dict:
    """Full pipeline for one ticket."""
    enrichment = enrich(text)

    extraction = converse(
        EXTRACT_TICKET.render(ticket_text=text),
        model=model,
        system=EXTRACT_TICKET.system,
        temperature=0.0,
    )
    result = validate(extraction.text)

    summary = converse(
        SUMMARISE_TICKET.render(ticket_text=text),
        model=model,
        system=SUMMARISE_TICKET.system,
        temperature=0.3,
        max_tokens=200,
    )

    return {
        "record": result.record,
        "summary": summary.text,
        "valid": result.valid,
        "errors": result.errors,
        "warnings": result.warnings,
        "quality_score": result.quality_score,
        "enrichment": asdict(enrichment),
        "trace": {
            "extract_request_id": extraction.request_id,
            "summary_request_id": summary.request_id,
            "model_id": extraction.model_id,
            "latency_ms": extraction.latency_ms + summary.latency_ms,
            "input_tokens": extraction.input_tokens + summary.input_tokens,
            "output_tokens": extraction.output_tokens + summary.output_tokens,
            "est_cost_usd": extraction.est_cost_usd + summary.est_cost_usd,
            "prompt_versions": {
                EXTRACT_TICKET.id: EXTRACT_TICKET.version,
                SUMMARISE_TICKET.id: SUMMARISE_TICKET.version,
            },
        },
    }
```

**You'll know it worked when** —

```bash
cd ~/deskai && source .venv/bin/activate
python -c "
from core.extract import process
print(process(open('corpus/tickets/t01-clean.txt').read())['record'])"
```

returns a populated dict.

---

## Sub-task 6 — Run the corpus locally and record the baseline

**Goal** — Establish the numbers before Lambda, so any later difference is attributable.

Create `~/deskai/scripts/run_corpus.py`:

```python
import json, pathlib, sys
from core.extract import process

out = []
for path in sorted(pathlib.Path("corpus/tickets").glob("*.txt")):
    text = path.read_text()
    try:
        r = process(text, model=sys.argv[1] if len(sys.argv) > 1 else "micro")
        r["file"] = path.name
        out.append(r)
        flag = "ok " if r["valid"] else "INV"
        print(f"{flag} {path.name:24} q={r['quality_score']:.2f} "
              f"{r['trace']['latency_ms']:>5}ms ${r['trace']['est_cost_usd']:.6f}")
    except Exception as exc:
        print(f"ERR {path.name:24} {exc}")

pathlib.Path("benchmarks").mkdir(exist_ok=True)
pathlib.Path("benchmarks/s1-baseline.json").write_text(json.dumps(out, indent=2))

total = sum(r["trace"]["est_cost_usd"] for r in out)
valid = sum(1 for r in out if r["valid"])
print(f"\n{valid}/{len(out)} valid · total ${total:.6f} · avg ${total/max(len(out),1):.6f}/ticket")
```

Run it against all three models:

```bash
python scripts/run_corpus.py micro
python scripts/run_corpus.py lite
python scripts/run_corpus.py pro
```

**You'll know it worked when** — `benchmarks/s1-baseline.json` exists and you can state cost per
ticket for each model. **This is the sprint's headline number.**

Expect `t08-minimal.txt` and `t10-injection.txt` to behave oddly. That's the point — note what
happens, it's the S3 sprint's starting material.

---

## Sub-task 7 — Lambda execution role

**Console path** — IAM → *Roles* → **Create role** → AWS service → Lambda.

Attach `AWSLambdaBasicExecutionRole`, then **Create inline policy** → JSON:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["bedrock:Converse", "bedrock:InvokeModel"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::deskai-s1-tickets-*",
        "arn:aws:s3:::deskai-s1-tickets-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "comprehend:DetectDominantLanguage",
        "comprehend:DetectSentiment",
        "comprehend:DetectPiiEntities",
        "textract:DetectDocumentText"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Deny",
      "Action": [
        "bedrock:CreateProvisionedModelThroughput",
        "bedrock:PurchaseProvisionedModelThroughput"
      ],
      "Resource": "*"
    }
  ]
}
```

Role name: `deskai-s1-role-fn-ingest`. Tag it per the convention.

**Note the scoped S3 resource and the repeated PT deny.** Every role in this programme carries that
deny — defence in depth, and it's a talking point when you post about the IAM design.

---

## Sub-task 8 — Package and deploy the Lambda

**Goal** — Same pipeline, event-driven.

Create `~/deskai/lambda/handler.py`:

```python
import json
import os
import urllib.parse

import boto3

from core.extract import process, text_from_pdf

s3 = boto3.client("s3")


def lambda_handler(event, context):
    results = []
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        if not key.startswith("raw/"):
            continue

        if key.lower().endswith(".pdf"):
            text = text_from_pdf(bucket, key)
        else:
            text = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode("utf-8")

        result = process(text)
        result["source_key"] = key
        result["lambda_request_id"] = context.aws_request_id

        prefix = "processed" if result["valid"] else "quarantine"
        name = key.split("/")[-1].rsplit(".", 1)[0]
        s3.put_object(
            Bucket=bucket,
            Key=f"{prefix}/{name}.json",
            Body=json.dumps(result, indent=2).encode("utf-8"),
            ContentType="application/json",
        )

        print(json.dumps({
            "source": key,
            "valid": result["valid"],
            "quality": result["quality_score"],
            "bedrock_request_id": result["trace"]["extract_request_id"],
            "cost_usd": result["trace"]["est_cost_usd"],
        }))
        results.append(result["valid"])

    return {"processed": len(results), "valid": sum(1 for r in results if r)}
```

Package:

```bash
cd ~/deskai
rm -rf build && mkdir build
pip install boto3 -t build/ --quiet
cp -r core build/
cp lambda/handler.py build/
cd build && zip -qr ../deskai-s1-fn-ingest.zip . && cd ..
ls -lh deskai-s1-fn-ingest.zip
```

**Console path** — Lambda → **Create function** → Author from scratch.

| Field | Value |
|---|---|
| Name | `deskai-s1-fn-ingest` |
| Runtime | Python 3.12 |
| Architecture | arm64 (cheaper) |
| Execution role | Use existing → `deskai-s1-role-fn-ingest` |

Then: *Code* → **Upload from** → .zip file → select the zip.
*Configuration → General configuration* → Edit → **Timeout 2 min**, **Memory 512 MB**.
*Configuration → Tags* → add the five tags.

**Why 2 minutes:** two Bedrock calls plus Comprehend on a long ticket will exceed the 3-second
default. Timeout is the most common first failure here.

**You'll know it worked when** — the function page shows Handler `handler.lambda_handler` and the
deployment package uploaded.

---

## Sub-task 9 — S3 event trigger

**Console path** — Lambda function page → *Configuration* → **Triggers** → **Add trigger** → S3.

| Field | Value |
|---|---|
| Bucket | `deskai-s1-tickets-<suffix>` |
| Event types | All object create events |
| Prefix | `raw/` |

**The prefix filter is not optional.** Without it, the Lambda writes to `processed/`, which fires
the trigger again, which writes again — a recursive invocation loop that bills until you notice.
This is the single most expensive mistake available in S1.

**You'll know it worked when** — the trigger appears and shows prefix `raw/`.

---

## Sub-task 10 — End-to-end test

```bash
aws s3 cp corpus/tickets/t01-clean.txt \
  s3://deskai-s1-tickets-<suffix>/raw/t01-retest.txt --region ap-southeast-1

sleep 25

aws s3 ls s3://deskai-s1-tickets-<suffix>/processed/ --region ap-southeast-1
aws s3 ls s3://deskai-s1-tickets-<suffix>/quarantine/ --region ap-southeast-1
```

Then upload the deliberately broken one:

```bash
aws s3 cp corpus/tickets/t08-minimal.txt \
  s3://deskai-s1-tickets-<suffix>/raw/t08-retest.txt --region ap-southeast-1
```

**You'll know it worked when** — `t01` lands in `processed/` and `t08` lands in `quarantine/`.
The split is the proof that validation does something.

**If nothing appears:** CloudWatch → Log groups → `/aws/lambda/deskai-s1-fn-ingest`. Most likely
causes in order: timeout too low, missing `core/` in the zip, IAM permission gap.

---

## Sub-task 11 — Streamlit extension

Extend `app/main.py` with a ticket tab showing extracted fields, validation state, quality score,
enrichment, and the Bedrock request ID. Codex will write this against `core/extract.process()`.

Required on screen: extracted fields · validation errors and warnings · quality score ·
detected language and sentiment · **Bedrock request ID** · latency · estimated cost.

**You'll know it worked when** — uploading `t02-missing-fields.txt` shows warnings rather than a
clean result. Demo the *failure* case; it's more convincing than the happy path.

---

## Sub-task 12 — Measure

Produce for the post:

1. **Cost per ticket** across Nova Micro / Lite / Pro, from `benchmarks/s1-baseline.json`
2. **Validation catch rate** — how many of the 10 corpus files were correctly quarantined
3. **p50 / p95 latency** per model
4. **Field-level extraction accuracy** — score each field against what you know is in the file

The interesting finding is usually that Micro matches Pro on structured extraction at a fraction of
the cost, because extraction is a constrained task. If that holds, it's the post.

---

## Sub-task 13 — Evidence pack

Into `~/deskai/evidence/s1/`:

- Console screenshot: Lambda function page with trigger visible
- CloudWatch Logs Insights: a Bedrock request ID from the UI, found in the log group
- CloudTrail: the `CreateFunction` event
- Cost Explorer filtered to `Sprint=S1`
- Screenshot of `processed/` and `quarantine/` side by side
- Terminal output of `orphan_sweep.sh` after teardown

---

## TEARDOWN

Run in order:

```bash
SUFFIX=<your suffix>

# 1. Remove the trigger first — otherwise deleting objects fires the Lambda
aws lambda list-event-source-mappings --function-name deskai-s1-fn-ingest --region ap-southeast-1
# (S3 notifications are on the bucket, not an event source mapping)
aws s3api put-bucket-notification-configuration \
  --bucket deskai-s1-tickets-$SUFFIX \
  --notification-configuration '{}' --region ap-southeast-1

# 2. Lambda
aws lambda delete-function --function-name deskai-s1-fn-ingest --region ap-southeast-1

# 3. Bucket contents, including versions
aws s3 rm s3://deskai-s1-tickets-$SUFFIX --recursive --region ap-southeast-1
aws s3api delete-bucket --bucket deskai-s1-tickets-$SUFFIX --region ap-southeast-1

# 4. IAM role
aws iam delete-role --role-name deskai-s1-role-fn-ingest

# 5. Verify
~/deskai/scripts/orphan_sweep.sh
```

**Keep:** the baseline bucket, `core/`, `benchmarks/s1-baseline.json`, the corpus, all evidence.

**Note on step 1:** removing the notification config before deleting objects prevents the recursive
firing described in sub-task 9. Order matters here.

**Versioned bucket caveat:** if `delete-bucket` fails with "bucket not empty", delete object
versions — S3 console → bucket → *Show versions* → select all → Delete.

---

## Post angle

The number: cost per ticket across three models, with the accuracy delta. The non-obvious finding:
whichever way the Micro-vs-Pro comparison lands, it's a real result about matching model capability
to task complexity — which is Task 4.1's skill, discovered early.

Show the quarantine split. Everyone posts the happy path; almost nobody shows the pipeline
correctly rejecting bad input.

## Notes for Codex

- One sub-task at a time; wait for confirmation.
- Sub-task 9's prefix filter is a hard requirement — flag it explicitly when you reach it.
- Do not propose any FORBIDDEN service. If a sub-task seems to need one, stop and say so.
- Region `ap-southeast-1` on every action.

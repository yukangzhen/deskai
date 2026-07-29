# SPRINT 2 — RAG & Vector Stores

> Tasks 1.4 and 1.5 · 11 core skills · **hero sprint** · highest cost risk so far.

## ASSUMPTIONS FROM PRIOR SPRINTS

- [ ] S1 complete and torn down; `orphan_sweep.sh` clean
- [ ] `core/bedrock.py`, `core/prompts.py`, `core/schema.py` working
- [ ] `benchmarks/s1-baseline.json` exists
- [ ] Titan Text Embeddings V2 access granted

**If Titan V2 was not granted** — substitute Cohere Embed Multilingual v3 and note the change; the
embedding comparison in sub-task 7 still works with any two models.

---

**Objective** — A support knowledge base that answers questions with citations, built three ways
across three vector stores and three chunking strategies, with measured retrieval quality and cost
per 1000 queries for each.

**Skill IDs closed** — `1.4.1`–`1.4.5`, `1.5.1`–`1.5.6`

**Cost ceiling** — $15. Realistic spend $6–10, *provided the timeboxes hold*.

**FORBIDDEN** — Kendra, SageMaker, Bedrock Agents, Provisioned Throughput, OpenSearch Serverless
**Classic** redundancy settings (use NextGen / scale-to-zero if offered), any Aurora instance above
the minimum ACU.

**Baseline used** — baseline bucket, `core/*`.

**Ephemeral created** — `deskai-s2-kb-source-<suffix>`, three Knowledge Bases, one S3 Vectors
index, one OpenSearch Serverless collection, one Aurora Serverless v2 cluster.
`TeardownBy` = **same day** for OSS and Aurora.

## Cost gates — read before starting

| Resource | Rate | Timebox | Budget |
|---|---|---|---|
| S3 Vectors | ~free at this scale | none | <$1 |
| OpenSearch Serverless | ~$0.24/OCU-hr | **3 hours, hard stop** | ~$3 |
| Aurora Serverless v2 (0.5 ACU min) | ~$0.06/ACU-hr + storage | **2 hours, hard stop** | ~$1 |
| Bedrock embeddings | ~$0.02/1M tokens | none | <$1 |
| Bedrock generation (eval runs) | see PRD §7.1 | 50-case set | ~$2 |

**Set a phone timer when you create the OpenSearch collection and the Aurora cluster.** These are
the two resources in the entire programme most likely to be forgotten. An OSS collection left up
for a month is several hundred dollars; left up for three hours it is three dollars. The difference
is entirely the timer.

## Architecture

```
                          corpus/policies/*.md  (30 support policy docs)
                                    │
                                    ▼
                     S3  deskai-s2-kb-source-<suffix>
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
  KB-A  fixed chunks         KB-B  hierarchical           KB-C  semantic
  (S3 Vectors)               (S3 Vectors)                 (S3 Vectors)
        └───────────────────────────┼───────────────────────────┘
                                    │
                            eval set (25 Q/A + known source chunk)
                                    │
                                    ▼
                     recall@5 · MRR · answer faithfulness
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
   S3 Vectors                OpenSearch Serverless          Aurora pgvector
   (persistent)              (3h timebox: hybrid            (2h timebox:
                              search + rerank)               SQL-side filtering)
        └───────────────────────────┼───────────────────────────┘
                                    ▼
                   latency p50/p95 · $/1000 queries · recall@5
                                    │
                                    ▼
                   Streamlit: answer + citation panel with scores
```

---

## Sub-task 1 — Build the policy corpus

**Goal** — ~30 support policy documents. Retrieval quality is only measurable against content you
know the ground truth for.

Create `~/deskai/corpus/policies/` with markdown documents covering: refunds, delivery windows,
warranty terms, account recovery, data handling, escalation paths, billing disputes, subscription
changes, damaged goods, international shipping.

Requirements that make the measurement meaningful:

- Each doc 300–1500 words, with headings and subsections (hierarchical chunking needs structure)
- **Deliberately place 3 near-duplicate passages** across different documents — this is what
  separates good retrieval from bad
- **Include 2 contradictory statements** in different docs (e.g. refund window 14 days in one,
  30 days in another) — this becomes the hallucination test in S3
- All synthetic. Label as such.

Upload to `s3://deskai-s2-kb-source-<suffix>/policies/`.

**You'll know it worked when** — 30 objects listed, with tags applied to the bucket.

---

## Sub-task 2 — Build the evaluation set

**Goal** — Do this *before* building any index. Building the eval set after seeing retrieval
results is how you accidentally tune the questions to the system.

Create `~/deskai/eval/rag_eval.json` — 25 entries:

```json
[
  {
    "id": "q01",
    "question": "How long do I have to request a refund on a damaged item?",
    "expected_source": "policies/refunds.md",
    "expected_section": "Damaged goods",
    "answer_contains": ["14 days", "damaged"],
    "type": "single_hop"
  },
  {
    "id": "q02",
    "question": "If my parcel is late and also damaged, what are my options?",
    "expected_source": ["policies/delivery.md", "policies/damaged-goods.md"],
    "answer_contains": ["redelivery", "replacement"],
    "type": "multi_hop"
  }
]
```

Distribution: 15 single-hop, 6 multi-hop (answer spans two documents), 4 unanswerable (the corpus
genuinely doesn't contain it — these test refusal, and they matter more than the easy ones).

**You'll know it worked when** — 25 entries with the type distribution above.

---

## Sub-task 3 — Knowledge Base A: fixed-size chunking on S3 Vectors

**Console path** — Amazon Bedrock → *Knowledge Bases* → **Create knowledge base** →
Knowledge Base with vector store.

| Field | Value |
|---|---|
| Name | `deskai-s2-kb-fixed` |
| IAM permissions | Create and use a new service role |
| Data source | Amazon S3 |
| S3 URI | `s3://deskai-s2-kb-source-<suffix>/policies/` |
| Chunking strategy | **Fixed-size chunking** |
| Max tokens | 300 |
| Overlap % | 20 |
| Embeddings model | Titan Text Embeddings V2 |
| Vector store | **Amazon S3 Vectors** |

**The vector store choice is the cost decision of this sprint.** The console may default to
OpenSearch Serverless. Select S3 Vectors. You will build OSS deliberately in sub-task 8 — but on a
timer, not as the persistent default.

After creation: *Data source* → **Sync**. Wait for status Available.

Tag the KB: `Project=deskai`, `Sprint=S2`, `Task=1.4`, `Ephemeral=true`, `TeardownBy=<sprint end>`.

**You'll know it worked when** — sync completes and the *Test knowledge base* panel returns
passages for "how do refunds work".

**Record the ingestion time.** It's a comparison metric in sub-task 6.

---

## Sub-task 4 — Knowledge Base B: hierarchical chunking

Repeat sub-task 3 with:

| Field | Value |
|---|---|
| Name | `deskai-s2-kb-hier` |
| Chunking strategy | **Hierarchical chunking** |
| Parent max tokens | 1500 |
| Child max tokens | 300 |
| Overlap tokens | 60 |

Same S3 source, same embedding model, same S3 Vectors store.

**Why this exists:** hierarchical retrieval returns the child chunk for matching but the parent for
context — usually better answers on structured documents, at higher storage cost. Task 1.5.1 is
asking whether you know when that trade is worth it.

---

## Sub-task 5 — Knowledge Base C: semantic chunking

| Field | Value |
|---|---|
| Name | `deskai-s2-kb-semantic` |
| Chunking strategy | **Semantic chunking** |
| Max buffer size | 1 |
| Max token size | 300 |
| Breakpoint percentile threshold | 95 |

**Note:** semantic chunking calls the embedding model during ingestion to find boundaries, so it
costs more and takes longer to sync than the other two. That cost difference is a finding, not a
problem — record it.

---

## Sub-task 6 — Measure the three chunking strategies

Create `~/deskai/scripts/eval_retrieval.py`:

```python
"""Retrieval quality across knowledge bases (Tasks 1.5.1, 1.5.4)."""
import json, statistics, sys, time

import boto3

REGION = "ap-southeast-1"
agent = boto3.client("bedrock-agent-runtime", region_name=REGION)

KBS = {
    "fixed":    "<KB_ID_A>",
    "hier":     "<KB_ID_B>",
    "semantic": "<KB_ID_C>",
}


def retrieve(kb_id, query, k=5):
    t0 = time.perf_counter()
    resp = agent.retrieve(
        knowledgeBaseId=kb_id,
        retrievalQuery={"text": query},
        retrievalConfiguration={
            "vectorSearchConfiguration": {"numberOfResults": k}
        },
    )
    latency_ms = int((time.perf_counter() - t0) * 1000)
    hits = [
        {
            "uri": r["location"]["s3Location"]["uri"],
            "score": r.get("score"),
            "text": r["content"]["text"][:200],
        }
        for r in resp["retrievalResults"]
    ]
    return hits, latency_ms


def sources_of(entry):
    exp = entry["expected_source"]
    return [exp] if isinstance(exp, str) else exp


def main():
    evalset = json.load(open("eval/rag_eval.json"))
    report = {}

    for name, kb_id in KBS.items():
        hits_at_5, rr, latencies = 0, [], []
        answerable = [e for e in evalset if e["type"] != "unanswerable"]

        for entry in answerable:
            hits, ms = retrieve(kb_id, entry["question"])
            latencies.append(ms)
            uris = [h["uri"] for h in hits]
            expected = sources_of(entry)

            rank = next(
                (i + 1 for i, u in enumerate(uris)
                 if any(e.split("/")[-1] in u for e in expected)),
                None,
            )
            if rank:
                hits_at_5 += 1
                rr.append(1 / rank)
            else:
                rr.append(0.0)

        report[name] = {
            "recall_at_5": round(hits_at_5 / len(answerable), 3),
            "mrr": round(statistics.mean(rr), 3),
            "p50_ms": int(statistics.median(latencies)),
            "p95_ms": int(sorted(latencies)[int(len(latencies) * 0.95) - 1]),
        }
        print(name, report[name])

    json.dump(report, open("benchmarks/s2-chunking.json", "w"), indent=2)


if __name__ == "__main__":
    main()
```

Fill in the three KB IDs from the console, then run it.

**You'll know it worked when** — `benchmarks/s2-chunking.json` shows recall@5 and MRR for all
three. **This is one of the two headline numbers.**

---

## Sub-task 7 — Embedding model comparison

**Goal** — Task 1.5.2. Create one additional KB identical to the winner from sub-task 6, but with
a different embedding model (Cohere Embed Multilingual v3, or Titan V2 at a different dimension —
V2 supports 1024/512/256).

Name: `deskai-s2-kb-embed-alt`. Re-run `eval_retrieval.py` with it added to `KBS`.

**The interesting question:** does dropping Titan V2 from 1024 to 256 dimensions measurably hurt
recall on this corpus? Smaller vectors mean cheaper storage and faster search. If recall holds,
that's a real cost finding and a good post line.

---

## Sub-task 8 — OpenSearch Serverless — TIMEBOXED 3 HOURS

> **Start a timer now. Write the deletion time on paper.**

**Goal** — Hybrid search and reranking, which S3 Vectors doesn't offer. Task 1.5.3 and 1.5.4
require it, and it's heavily examined.

**Console path** — Amazon Bedrock → *Knowledge Bases* → **Create knowledge base** →
same S3 source → **Vector store: Amazon OpenSearch Serverless** → *Quick create a new vector store*.

Name: `deskai-s2-kb-oss`. Collection will be created as `deskai-s2-aoss-bakeoff`.

**If offered a choice between Classic and NextGen collections, choose NextGen** — it scales
compute to zero after inactivity rather than holding a minimum OCU floor. If only Classic is
available, the 3-hour timebox is doing all the work; do not extend it.

Once synced, exercise what OSS uniquely provides:

```python
resp = agent.retrieve(
    knowledgeBaseId="<OSS_KB_ID>",
    retrievalQuery={"text": "refund window for damaged goods"},
    retrievalConfiguration={
        "vectorSearchConfiguration": {
            "numberOfResults": 5,
            "overrideSearchType": "HYBRID",   # semantic + keyword — not available on S3 Vectors
        }
    },
)
```

Then add reranking:

```python
resp = agent.retrieve_and_generate(
    input={"text": "How long do I have to return a damaged item?"},
    retrieveAndGenerateConfiguration={
        "type": "KNOWLEDGE_BASE",
        "knowledgeBaseConfiguration": {
            "knowledgeBaseId": "<OSS_KB_ID>",
            "modelArn": "apac.amazon.nova-pro-v1:0",
            "retrievalConfiguration": {
                "vectorSearchConfiguration": {
                    "numberOfResults": 10,
                    "overrideSearchType": "HYBRID",
                    "rerankingConfiguration": {
                        "type": "BEDROCK_RERANKING_MODEL",
                        "bedrockRerankingConfiguration": {
                            "numberOfRerankedResults": 5,
                            "modelConfiguration": {
                                "modelArn": "arn:aws:bedrock:ap-southeast-1::foundation-model/amazon.rerank-v1:0"
                            },
                        },
                    },
                }
            },
        },
    },
)
```

Run `eval_retrieval.py` against it — semantic only, then HYBRID, then HYBRID+rerank. Three rows.

**Capture the OCU metrics before you delete:** OpenSearch Serverless console → collection →
*Monitoring*. Screenshot the OCU usage graph. This is the evidence that makes your cost claim
concrete rather than quoted.

**You'll know it worked when** — you have recall@5 for semantic / hybrid / hybrid+rerank, and an
OCU screenshot.

### TEARDOWN — DO THIS BEFORE MOVING ON

```bash
aws bedrock-agent delete-knowledge-base --knowledge-base-id <OSS_KB_ID> --region ap-southeast-1
aws opensearchserverless list-collections --region ap-southeast-1
aws opensearchserverless delete-collection --id <COLLECTION_ID> --region ap-southeast-1
# also delete the associated security / network / encryption policies
aws opensearchserverless list-security-policies --type encryption --region ap-southeast-1
aws opensearchserverless list-security-policies --type network --region ap-southeast-1
aws opensearchserverless list-access-policies --type data --region ap-southeast-1
```

Then `~/deskai/scripts/orphan_sweep.sh` must report `clean OpenSearch Serverless`.

**Do not proceed to sub-task 9 until the sweep is clean.**

---

## Sub-task 9 — Aurora PostgreSQL Serverless v2 + pgvector — TIMEBOXED 2 HOURS

> **Timer again.**

**Goal** — The third architecture. Aurora gives SQL-side metadata filtering, which neither S3
Vectors nor OSS matches — that's Task 1.4.2's metadata framework skill.

**Console path** — RDS → **Create database** → Standard create → Amazon Aurora →
Amazon Aurora PostgreSQL-Compatible Edition.

| Field | Value |
|---|---|
| Engine version | Latest supporting pgvector (15.4+) |
| Template | **Dev/Test** |
| Cluster identifier | `deskai-s2-aurora-pgvector` |
| Capacity type | **Serverless v2** |
| Min ACU | **0.5** |
| Max ACU | **1** |
| Public access | No |
| Enable RDS Data API | **Yes** — required by Bedrock Knowledge Bases |
| Manage credentials | AWS Secrets Manager |

**Max ACU of 1 is a hard requirement here.** The default is far higher, and Aurora will scale into
it under ingestion load. This single field is the difference between a $1 experiment and a $20 one.

Once available, connect via the RDS Query Editor and run:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE SCHEMA IF NOT EXISTS bedrock_integration;

CREATE TABLE bedrock_integration.kb (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    embedding   vector(1024),
    chunks      text,
    metadata    jsonb
);

CREATE INDEX ON bedrock_integration.kb
  USING hnsw (embedding vector_cosine_ops);
CREATE INDEX ON bedrock_integration.kb USING gin (to_tsvector('simple', chunks));
```

Then create a fourth Knowledge Base pointing at it: **Vector store: Amazon Aurora PostgreSQL**,
supplying cluster ARN, secret ARN, database name, table `bedrock_integration.kb` and the field
names above.

Run `eval_retrieval.py` against it.

**Then demonstrate what only Aurora can do** — metadata filtering pushed into SQL:

```sql
SELECT chunks, metadata,
       1 - (embedding <=> :query_vector) AS similarity
FROM bedrock_integration.kb
WHERE metadata->>'category' = 'refunds'
ORDER BY embedding <=> :query_vector
LIMIT 5;
```

### TEARDOWN — IMMEDIATELY

```bash
aws bedrock-agent delete-knowledge-base --knowledge-base-id <AURORA_KB_ID> --region ap-southeast-1
aws rds delete-db-cluster --db-cluster-identifier deskai-s2-aurora-pgvector \
  --skip-final-snapshot --region ap-southeast-1
# instances inside the cluster may need deleting first:
aws rds describe-db-instances --region ap-southeast-1 \
  --query "DBInstances[?DBClusterIdentifier=='deskai-s2-aurora-pgvector'].DBInstanceIdentifier"
aws rds delete-db-instance --db-instance-identifier <INSTANCE_ID> \
  --skip-final-snapshot --region ap-southeast-1
```

Also delete the Secrets Manager secret (it has a recovery window and bills a small amount):

```bash
aws secretsmanager delete-secret --secret-id <SECRET_ARN> \
  --force-delete-without-recovery --region ap-southeast-1
```

Run `orphan_sweep.sh`. Both Aurora and OSS must read `clean`.

---

## Sub-task 10 — Query handling: expansion and decomposition

**Goal** — Task 1.5.5. Multi-hop questions fail on naive retrieval because no single chunk answers
them. Add a query-processing stage against the surviving S3 Vectors KB.

Add to `core/prompts.py`:

```python
DECOMPOSE_QUERY = Prompt(
    id="decompose_query",
    version="1.0.0",
    system="You split complex questions into independent sub-questions. JSON array of strings only.",
    template=(
        "Split this question into 1-3 independent sub-questions that could each be "
        "answered by a single policy document. If it is already simple, return it unchanged.\n\n"
        "Question: {question}\n\nJSON array:"
    ),
)
```

Retrieve for each sub-question, merge and deduplicate the passages, then generate one answer.

**Measure:** recall on the 6 multi-hop eval questions, with and without decomposition. If
decomposition doesn't help, that's still a finding — report it honestly rather than burying it.

---

## Sub-task 11 — Maintenance and metadata (Tasks 1.4.2, 1.4.5)

Two things that are easy to skip and are explicitly examined:

**Metadata framework.** Add a `.metadata.json` sidecar next to each policy document:

```json
{"metadataAttributes": {"category": "refunds", "effective_date": "2026-01-15", "version": "2.1", "region": "APAC"}}
```

Re-sync, then demonstrate a filtered retrieval:

```python
"retrievalConfiguration": {
    "vectorSearchConfiguration": {
        "numberOfResults": 5,
        "filter": {"equals": {"key": "category", "value": "refunds"}}
    }
}
```

**Maintenance.** Modify one policy document, re-sync, and show the retrieved passage changes.
Record the incremental sync time versus the full initial sync. Document the reindexing procedure
in `adr/s2-vector-maintenance.md`.

---

## Sub-task 12 — Streamlit citation panel

Extend the app: question in, answer out, plus a panel showing each retrieved chunk with its
similarity score, source document, and metadata. Include the Bedrock request ID.

**Required:** clicking a citation reveals the actual retrieved text. An answer with unverifiable
citations is the thing RAG demos usually fake, and showing the raw chunk is the cheapest possible
proof that you didn't.

---

## Sub-task 13 — Measure and evidence

**Headline numbers:**

1. **recall@5 and MRR by chunking strategy** (fixed / hierarchical / semantic)
2. **$/1000 queries and p50/p95 latency by vector store** (S3 Vectors / OSS / Aurora)

Build the cost column from actual Cost Explorer data filtered by `Sprint=S2`, not from list prices.
The gap between the two is itself worth mentioning.

**Evidence pack** → `evidence/s2/`: KB console screenshots · OCU usage graph · Aurora cluster
screenshot before deletion · Cost Explorer by sprint tag · CloudWatch request-ID correlation ·
clean `orphan_sweep.sh` after all teardowns.

---

## FINAL TEARDOWN

```bash
# Remaining S3 Vectors knowledge bases
for kb in <KB_A> <KB_B> <KB_C> <KB_EMBED_ALT>; do
  aws bedrock-agent delete-knowledge-base --knowledge-base-id $kb --region ap-southeast-1
done

# S3 vector index and bucket
aws s3vectors list-indexes --region ap-southeast-1
aws s3 rm s3://deskai-s2-kb-source-<suffix> --recursive --region ap-southeast-1
aws s3api delete-bucket --bucket deskai-s2-kb-source-<suffix> --region ap-southeast-1

~/deskai/scripts/orphan_sweep.sh
```

**Keep:** `corpus/policies/`, `eval/rag_eval.json`, `benchmarks/s2-*.json`, all evidence. The
corpus and eval set are reused in S3, S8 and S9 — do not delete them.

---

## Post angle

This is the hero post. Almost nobody publishes real numbers comparing S3 Vectors, OpenSearch
Serverless and Aurora pgvector on the same corpus with the same eval set. Lead with the
$/1000-queries table and the recall@5 figures side by side, because the interesting story is
usually that the cheapest option is not meaningfully worse for a corpus this size — and being able
to say *at what corpus size that stops being true* is the senior-level version of the answer.

Second angle: the OCU graph. Showing what OpenSearch Serverless actually costs per hour, and that
you ran it for three hours deliberately and deleted it, is a cost-discipline story most engineers
don't have.

## Notes for Codex

- **Sub-tasks 8 and 9 are timeboxed. Remind Yu of elapsed time at every interaction during them.**
- Do not proceed past a teardown step until `orphan_sweep.sh` reports clean.
- Aurora Max ACU must be 1. Flag it explicitly.
- If the KB creation wizard defaults to OpenSearch Serverless in sub-tasks 3–5, stop and correct it.
- Region `ap-southeast-1` throughout.

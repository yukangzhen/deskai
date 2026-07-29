# deskai — START HERE

Everything needed to run the AIP-C01 hands-on programme with Codex.

---

## 1. What's in here

```
AGENTS.md                    Codex reads this automatically — operating instructions
README.md                    this file
STATE.md                     ← current position. Codex reads first, you update last.
plan/
  PRD.md                     master plan: cost doctrine, naming, evidence, pause protocol
  coverage-matrix.csv        118 rows (97 skills + 21 stretch) tracked to DONE
  sprints/                   the eleven briefs, S0 → S10
scripts/
  orphan_sweep.sh            run before you stop, every session
  panic_teardown.sh          emergency stop for hourly-billed resources
core/ app/ lambda/ infra/    code — filled in as you build
corpus/ eval/                test data and evaluation sets
benchmarks/ evidence/        measured results and proof artifacts
adr/ docs/                   decision records and write-ups
reference/course-material/   the original AWS course text, for cross-checking
```

---

## 2. Before you open Codex

```bash
aws --version          # AWS CLI installed
python3 --version      # 3.10+
git --version
```

Confirm you can sign in to the AWS console with admin or billing permissions, and set the region
selector to **Asia Pacific (Singapore) ap-southeast-1**.

Then initialise the repo:

```bash
cd deskai
git init && git add -A
git commit -m "deskai: programme scaffold — PRD, 11 sprint briefs, scripts"
```

Push to a public GitHub repo named `deskai`. Let the commit history run across the whole
programme — a real timeline is part of the evidence (PRD §14).

---

## 3. Starting a sprint with Codex

Open a Codex thread **inside this folder**. Codex reads `AGENTS.md` automatically, which tells it
to check `STATE.md`, load `plan/PRD.md`, open the current sprint brief, and continue from where
you left off.

Put the AWS console in the browser on the right, Codex on the left, then say:

```
Read AGENTS.md and STATE.md, then start where I left off.
```

That's it. No long prompt to paste — the instructions live in the repo.

**If Codex ever drifts** — batching sub-tasks, skipping console paths, proposing a forbidden
service — say:

```
Re-read AGENTS.md. One sub-task at a time, full console paths, and check
the FORBIDDEN list in the current sprint brief.
```

---

## 4. The loop

```
   ┌─────────────────────────────────────────────┐
   │  1. Paste kickoff + PRD + SPRINT-N brief    │
   │  2. Confirm the ASSUMPTIONS block           │
   │  3. Work sub-tasks one at a time            │
   │  4. Measure — get the sprint's number       │
   │  5. Build the evidence pack (PRD §14)       │
   │  6. TEARDOWN, then orphan_sweep.sh          │
   │  7. Codex writes the checkpoint report      │
   │  8. Update coverage-matrix.csv and STATE.md │
   │  9. Commit and push                         │
   │ 10. Hand the checkpoint to the next sprint  │
   └─────────────────────────────────────────────┘
```

Post to LinkedIn whenever suits — the video and GIF come out of step 5, and the angle is at the
bottom of each brief. Tag `#awsexamprep` with the repo link so the AWS Exam Prep team can endorse
the skills.

---

## 5. Daily habits

**Before you stop working, every time:**

```bash
~/deskai/scripts/orphan_sweep.sh      # must print SWEEP CLEAN
```

**If you must stop suddenly:**

```bash
~/deskai/plan/panic_teardown.sh              # list what's billing
~/deskai/plan/panic_teardown.sh --delete     # then kill it
```

**Weekly:** update `coverage-matrix.csv`, check Cost Explorer against the $100 budget, commit
`STATE.md`.

---

## 6. Sprint order

| | Sprint | Tasks | Ceiling | Watch for |
|---|---|---|---|---|
| ▢ | S0 Foundation | — | $1 | Model invocation logging is OFF by default — sub-task 6 |
| ▢ | S1 Ingest & Extract | 1.1, 1.3 | $2 | S3 trigger needs the `raw/` prefix filter or it loops |
| ▢ | S2 RAG & Vector Stores | 1.4, 1.5 | $15 | 🔴 Two timeboxes. Aurora Max ACU = 1 |
| ▢ | S3 Prompting & Safety | 1.6, 3.1 | $5 | Measure false positives, not just block rate |
| ▢ | S4 Model Selection | 1.2, 2.2 | $12 | 🔴 SageMaker endpoint. Verify the PT deny first |
| ▢ | S5 Agentic & FM APIs | 2.1, 2.4 | $6 | DynamoDB must be on-demand |
| ▢ | S6 Enterprise Integration | 2.3, 2.5 | $8 | No NAT Gateway. Built from IaC, not console |
| ▢ | S7 Security & Governance | 3.2, 3.3, 3.4 | $10 | 🔴 Config recorder. KMS has a 7-day delete window |
| ▢ | S8 Cost & Performance | 4.1, 4.2 | $8 | Baseline first. Cache must not leak across tenants |
| ▢ | S9 Observability & Eval | 4.3, 5.1 | $15 | Eval cost policy — 50 cases, cheap judge, 2 full runs |
| ▢ | S10 Troubleshooting & Finale | 5.2 | $10 | Deploy, record, tear down same day |

Ceilings total $92 against the $100 budget. Realistic total is around $40.

---

## 7. If something goes wrong

| Situation | Do this |
|---|---|
| A model isn't available in Singapore | Note it, use the fallback in the brief's ASSUMPTIONS block. Single sub-task may run in us-east-1 (PRD §13 D4) |
| Console path has moved | Tell Codex what you're seeing; it adapts. Record the divergence for the checkpoint report |
| A sprint is taking far longer than expected | Fine — timeline isn't a constraint. Just never pause on a 🔴 sub-task |
| Budget alert fires | Cost Explorer by `Sprint` tag, then `orphan_sweep.sh`. Something is running that shouldn't be |
| You need to stop for weeks | Full teardown + `panic_teardown.sh`, commit `STATE.md`. Rebuilding takes 20 minutes; the evidence can't be recreated |
| Codex proposes a forbidden service | It has drifted. Re-paste the kickoff prompt and the FORBIDDEN line from the brief |

---

## 8. Right now

1. Check the prerequisites in §2 and `git init`
2. Open a Codex thread inside this folder
3. Say: *"Read AGENTS.md and STATE.md, then start where I left off."*
4. Work the 13 sub-tasks of S0
5. Update `STATE.md`, commit, and carry the checkpoint into S1

S0 creates nothing billable. Worst case you lose an evening.

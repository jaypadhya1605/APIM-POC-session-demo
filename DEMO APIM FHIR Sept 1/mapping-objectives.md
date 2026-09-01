# Objectives mapping — agenda to evidence

**Northwind Health · CMS-0057-F · 1 September 2026**

This document exists to answer one question: *for every item on the agenda and
every question the customer actually asked, where is it covered, and what proves
it?*

Read it as a traceability matrix. Nothing on the agenda should reach the room as
an assertion when it could reach the room as a demonstration.

---

## A. The agenda, as the customer set it

The eight items below are verbatim from the agenda. Columns: which slides carry
it, which portal surface backs it, which live code run proves it.

| # | Agenda item | Min | Slides | Portal surface | Live proof |
|---|---|---|---|---|---|
| 1 | Objectives and scope | 5 | 3, 4 | — | — (framing only) |
| 2 | Overview of APIM | 7 | 5, 6 | Tab 2 — APIM → APIs | — |
| 3 | APIM in the CMS architecture | 7 | 7, 8 | Tab 1 — resource group | — |
| 4 | Inbound vs outbound partitioning model | 8 | 9, 10 | Tab 3 — Named values | Assertions **7, 8, 9, 14** |
| 5 | Gateway isolation with tests | 12 | 11, 12 | Tab 5 — `fhir-payera` IAM | **All 16**, narrate **4, 12, 13b** |
| 6 | Policy walkthrough and debug trace | 10 | 13, 14 | APIM → Test → Trace | `payer-outbound.xml` L27–L321 |
| 7 | Payer credential, identity and deployment options | 7 | 15, 16 | Tab 4 — Managed identity | Assertion **12** (ties back) |
| 8 | Decisions and next steps | 4 | 17, 18 | — | — |

**Deliberate weighting.** Items 4, 5 and 6 hold 30 of the 60 minutes and are
highlighted on the agenda slide. Those three are the only items where the
customer asked a question we could get wrong. Items 1–3 are setup and 7–8 are
close; if the room already knows APIM, compress item 2 and give the time to 5.

---

## B. The questions the customer actually asked

Taken from the 12 August working session transcript and the follow-up question
set. These are the ones that must not go home unanswered.

### Q1 — Enterprise Architecture, 40:48 · separation between payers

> *What actually separates one payer's data from another's?*

| | |
|---|---|
| **Agenda item** | 3 and 5 |
| **Slides** | 8 (physical vs logical), 11, 12 |
| **Portal** | Tab 5 — one role assignment on `fhir-payera`, and it is APIM's |
| **Proof** | Assertion **4** (403, valid token, wrong payer) and assertion **12** (403 direct to AHDS) |
| **Answer** | Physical separation stops a mistake. Logical separation stops a query. We run both: one FHIR service per payer *and* contract-tag enforcement at the gateway. |
| **Strength** | **Demonstrated.** The 403 in assertion 4 is produced by a legitimately-issued token, so it tests the boundary rather than the signature check. |

### Q2 — Platform Engineering · one FHIR service for inbound and outbound

> *Can a single FHIR service safely serve both ingestion and distribution?*

| | |
|---|---|
| **Agenda item** | 4 |
| **Slides** | 9 (per-route allow-lists), 10 (tag stamping and forced `_tag`) |
| **Portal** | Tab 2 — four APIs, two per payer; Tab 3 — the entitlement map |
| **Proof** | Assertion **7** (write on outbound → 403), **8** (payer credential on inbound → 403), **9** (export on inbound → 403), **14** (untagged inbound write → 403) |
| **Answer** | Yes, because direction is enforced per-route, not per-service. *The route is not a suggestion about which door to use — it is the only door that exists, and each door runs a different allow-list before it opens.* |
| **Strength** | **Demonstrated**, four ways, including the negative case where a correct payer uses a correct credential on the wrong verb. |

### Q3 — Can a payer bypass the gateway?

| | |
|---|---|
| **Agenda item** | 5 and 7 |
| **Slides** | 12 (line 12), 15 (identity model) |
| **Portal** | Tab 4 — APIM managed identity object id; Tab 5 — the only role assignment |
| **Proof** | Assertion **12** — payer token straight to the FHIR hostname, no APIM in the path → **403, not 401** |
| **Answer** | No. The payer applications hold **zero** Azure role assignments. Entra authenticates them fine; AHDS then has no assignment to evaluate. Skipping the gateway does not skip the control — it removes the only means of access. |
| **Strength** | **Demonstrated**, and the 403-vs-401 distinction is the whole point. Say it explicitly or the result reads as a generic failure. |

### Q4 — Can a payer widen their own scope?

| | |
|---|---|
| **Agenda item** | 4 |
| **Slides** | 10 |
| **Portal** | Tab 3 — the entitlement named value |
| **Proof** | Assertion **13** (caller-supplied `_tag` overridden → 200) and **13b** (response body contains CT-3456 only) |
| **Answer** | No. Layer 4b **overwrites** the `_tag` rather than merging it. The payer cannot widen scope by editing the query string, nor narrow it onto someone else's contract. |
| **Strength** | **Demonstrated in the response body.** A 200 would have passed a status-code check; 13b inspects resource by resource. This is the strongest single assertion in the suite. |

### Q5 — What does onboarding a third payer cost?

| | |
|---|---|
| **Agenda item** | 4 and 8 |
| **Slides** | 3 (in scope), 10, 17 |
| **Portal** | Tab 3 — Named values, edited live |
| **Proof** | Configuration surface shown; no redeploy demonstrated |
| **Answer** | A named value edit plus a route. No new infrastructure, no redeploy, no code change. |
| **Strength** | **Shown, not run.** If they push, offer to add a `payerc` entitlement row live — it is a two-field edit — but do not volunteer it, because a new route needs a policy import and that is not a 30-second operation. |

### Q6 — Rate limiting and the overnight export stampede

| | |
|---|---|
| **Agenda item** | 5 and 7 |
| **Slides** | 13 (layer 5), 16 |
| **Portal** | Log Analytics — the throttling KQL printed by `show-env.ps1` |
| **Proof** | Assertion **15** — second export inside five minutes → **429** |
| **Answer** | 600 calls/min, 50,000/day, and one bulk export per payer per 300 seconds. That converts a stampede into a queue. |
| **Strength** | **Demonstrated**, but be honest: five minutes is a reasonable-sounding number, not the output of a capacity model. Sizing needs their real export volumes — flagged out of scope on slide 3. |

### Q7 — Production readiness and networking

| | |
|---|---|
| **Agenda item** | 7 |
| **Slides** | 16 |
| **Portal** | Tab 1 — resource group, tier visible |
| **Proof** | — |
| **Answer** | BasicV2 today, which has **no VNet injection**. Production wants Premium, or StandardV2 with private endpoints, plus availability zones and a multi-region gateway if RTO demands it. |
| **Strength** | **Stated, not proven.** Say the tier constraint out loud in the session. If they find it afterwards, every other claim gets re-examined. |

---

## C. The sixteen assertions, mapped

Every line the terminal prints, and what it is there for. **Narrate 4, 12 and
13b. Let the other thirteen scroll.**

| # | Assertion | Result | Agenda | Answers |
|---|---|---|---|---|
| 1 | Own data readable | 200 | 5 | Baseline — the happy path works |
| 2 | Group export accepted | 202 | 5 | Bulk export is scoped, not blocked |
| 3 | Capability statement | 200 | 5 | Metadata reachable |
| **4** | **Payer B app, valid payer A audience** | **403** | **5** | **Q1 — separation** |
| 5 | Payer B token, payer B audience | 401 | 5 | Audience validation |
| 6 | Unentitled Group export | 403 | 5 | Q4 — scope |
| 7 | Write on outbound route | 403 | 4 | **Q2 — direction** |
| 8 | Payer credential on inbound route | 403 | 4 | Q2 — direction |
| 9 | Export on inbound route | 403 | 4 | Q2 — direction |
| 10 | System-level export | 403 | 5 | Export is Group-scoped only |
| 11 | Patient-level export | 403 | 5 | Export is Group-scoped only |
| **12** | **Payer token straight to AHDS** | **403** | **5, 7** | **Q3 — bypass** |
| 13 | Caller-supplied `_tag` overridden | 200 | 4 | Q4 — scope |
| **13b** | **Body contains only own contracts** | **CT-3456** | **4, 5** | **Q4 — verified in data** |
| 14 | Untagged inbound write rejected | 403 | 4 | Q2 — direction |
| 15 | Second export within 5 min | 429 | 5, 7 | Q6 — throttling |

**Coverage:** 16 assertions across 7 customer questions. Q5 and Q7 are the only
two answered by configuration and statement rather than by a running test, and
both are flagged as such on slide 3.

---

## D. Slide-by-slide index

| Slide | Title | Agenda | Purpose |
|---|---|---|---|
| 1 | Title | — | — |
| 2 | Agenda | — | Sets the weighting; items 4–6 highlighted |
| 3 | What this session has to settle | 1 | In scope / out of scope, and the single question |
| 4 | Where we left off | 1 | The two 12 August quotes, attributed |
| 5 | What API Management actually is | 2 | Six components; the "AHDS has no concept of contract" line |
| 6 | The policy pipeline | 2 | Inbound → backend → outbound → on-error |
| 7 | Where APIM sits | 3 | Architecture lanes |
| 8 | Physical vs logical separation | 3 | **The thesis slide** |
| 9 | Two doors, two allow-lists | 4 | Q2 answered |
| 10 | Contract enforcement | 4 | Stamp on the way in, force `_tag` on the way out |
| 11 | Sixteen assertions | 5 | Grouped four ways; run command at the foot |
| 12 | The three lines to stop on | 5 | **Second-screen slide during the live run** |
| 13 | Six layers, with line numbers | 6 | Live line numbers into `payer-outbound.xml` |
| 14 | Debug trace | 6 | What the trace shows and why it matters to ops |
| 15 | Payer credential and identity | 7 | SMART Backend Services; secret → cert → FIC |
| 16 | Deployment options | 7 | Tier constraint stated honestly |
| 17 | Four decisions | 8 | The ask |
| 18 | Next steps | 8 | Owners and dates |

---

## E. Gaps, stated plainly

Three things this session does **not** prove. Say them before the customer finds
them.

1. **Capacity is not modelled.** The five-minute export lock and the 600/min
   ceiling are defensible defaults, not sized limits. Needs their real export
   volumes. *Slide 3, out of scope.*
2. **SMART on FHIR scope-level filtering is not implemented.** Contract scoping
   is done with `meta.tag` at the gateway because AHDS does not enforce contract
   scopes. That is a deliberate choice, not an omission — but it is a choice.
   *Slide 3, out of scope.*
3. **Networking is not production-shaped.** BasicV2 has no VNet injection. The
   isolation model is unaffected, but the deployment topology will change.
   *Slide 16.*

None of the three weakens the isolation claim. All three will surface in a
security review, and it is materially better if they surface from you first.

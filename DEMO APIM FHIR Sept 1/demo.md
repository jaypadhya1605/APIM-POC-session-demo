# Demo run book — APIM + Azure Health Data Services

**Northwind Health · CMS-0057-F Prior Authorization API · 1 September 2026 · 60 minutes**

> 🖥️ **Prepping? Open [`demo.html`](demo.html) instead.** Same content, colour-coded
> DO/SAY/EXPECT/PROVES/FAILS blocks, architecture and policy-layer diagrams, tick-off
> checklist with a progress ring, a 60-minute pacing clock, and eight flip-card drills.
> This markdown file stays as the plain-text source of record.

This is the document you drive the session from. Every part below is written as
**DO → SAY → EXPECT → PROVES → IF IT FAILS**, in the order the agenda runs.

The deck is `Prov-APIM-FHIR-Session-2026-09-01.pptx` — 18 slides, speaker notes on
every one. This file is the *actions*; the notes are the *words*. Slide numbers are called out in each part so you can keep both open.

---

## The one sentence this session exists to prove

> **Physical separation stops a mistake. Logical separation stops a query.**

Everything below is an attempt to make that sentence stop being a claim.

---

## Part 0 — Pre-flight

Run these in order. The clock is relative to the meeting start.

### T-60 · Confirm the environment is alive

```powershell
cd "CMS DQM POC\v4"
./scripts/show-env.ps1
```

**Look for:** exit code 0 and no red lines. It prints the resource group, the
APIM instance and its managed identity object id, both FHIR services with their
principal ids, and both payer app registrations. It also prints three KQL queries
— copy them into a Log Analytics tab now if you want live telemetry on screen.

**If it exits non-zero:** stop and read which check failed before doing anything
else. This script exists specifically so you find drift at T-60 and not at T-0.

### T-15 · Warm the run and confirm 16/16

```powershell
./scripts/run-isolation-tests.ps1 | Out-Null
```

**Why:** this proves the suite is green *today* against *this* environment. It
mints its own short-lived credentials, uses them, and destroys them on exit.
It never prints a secret — verified. You can run it on screen safely.

> ⚠️ **The five-minute trap.** Layer 5 holds a cache lock of one bulk export per
> payer per **300 seconds**. If you run the suite live within five minutes of this
> warm-up, assertion 2 comes back **429 instead of 202** and it looks like a
> failure. It isn't — but you will be explaining a rate limiter instead of
> explaining isolation.
>
> Either **wait the full five minutes** before the live run, or pass
> `-SkipThrottleTest` on the warm-up.

### T-10 · Wait out the export lock

Do not run anything. Use the time to re-read the notes on slides 12 and 14.

### T-2 · Stage the tabs

```powershell
cd "..\DEMO APIM FHIR Sept 1"
./open-demo-tabs.ps1 -StageOnly
```

Opens five portal tabs in demo order and prints, for each one, the blade to land
on, what to click, what to look for, and the capture filename.

Then:

- **Zoom to 100%** in the browser. Portal blades reflow badly at 110% and the
  role-assignment table loses a column.
- **Light theme.** The screenshots and the deck are light; switching mid-demo is
  jarring on a projector.
- Terminal font up to ~16pt, window in `CMS DQM POC\v4`.
- Close Teams notifications and anything with a customer name in the title bar.

### The six surfaces

| # | Surface | What it shows |
|---|---|---|
| 1 | Resource group `rg-ahds-fhir-poc` | The whole footprint on one screen |
| 2 | APIM → APIs | Four routes: payerA in/out, payerB in/out |
| 3 | APIM → Named values | The entitlement map, editable without redeploy |
| 4 | APIM → Managed identity | Object id `dddddddd-…` — the only privileged principal |
| 5 | `fhir-payera` → Access control (IAM) → Role assignments | **Exactly one** assignment, and it is APIM's |
| 6 | Terminal in `v4` | Where the 16 assertions run |

---

## Part 1 — Objectives and scope · 5 min · slides 3–4

**DO:** Slide 3, then slide 4.

**SAY:** Read the four in-scope questions off slide 3, then land on the green bar:
*"when two payers call the same platform, what physically prevents one from
reading the other's members?"*

Then slide 4 — the two quotes from the 12 August working session. Attribute them.
Enterprise Architecture asked about separation at 40:48. Platform Engineering
asked whether one FHIR service can safely serve inbound and outbound.

**PROVES:** Nothing yet. This part exists so that when the terminal scrolls in
Part 5, the room already knows which lines matter and who asked for them.

**IF IT FAILS:** N/A — but resist the urge to answer the questions here. You have
running code for both. Say *"we answer that in part four"* and move.

**Out of scope, say it explicitly:** production capacity sizing (needs their real
export volumes), SMART on FHIR scope-level filtering, payer contracting, and
migrating the existing dev workspace. Naming these now prevents them arriving as
objections at minute 50.

---

## Part 2 — Overview of APIM · 7 min · slides 5–6

**DO:** Slide 5 (six components), then slide 6 (the policy pipeline), then switch
to **portal tab 2** and show the four APIs.

**SAY:** Slide 5's amber bar is the load-bearing line:

> *"AHDS role-based access control has no concept of 'contract'. It can say
> 'this identity may read this FHIR service' and nothing finer. Every rule finer
> than that has to be enforced somewhere — and this is the somewhere."*

On slide 6, walk inbound → backend → outbound → on-error in about ninety seconds.
The only point that has to land: **policy runs before the backend is ever
contacted.** A denied call never reaches FHIR.

**EXPECT:** Portal tab 2 shows four APIs, two per payer.

**PROVES:** That the partitioning is a real object in the platform, not a
diagram.

**IF IT FAILS:** If the room already knows APIM, compress this to slide 6 only
and bank three minutes for Part 5.

---

## Part 3 — APIM in the CMS architecture · 7 min · slides 7–8

**DO:** Slide 7 (the lanes), then **portal tab 1** (resource group), then slide 8
(physical vs logical).

**SAY:** On tab 1, trace the path with the cursor: payer app → APIM → FHIR
service. Point out there is no compute in between. This is a gateway, not a
middleware tier.

Slide 8 is the decision slide. Physical separation — one FHIR service per payer —
stops an operator mistake. Logical separation — contract tags enforced at the
gateway — stops a *query*. We do both, and they answer different threats.

**PROVES:** That the architecture is small enough to hold in your head, which is
itself a security property.

**IF IT FAILS:** If the resource group blade is slow, `shots/` has a capture.

---

## Part 4 — Inbound vs outbound partitioning · 8 min · slides 9–10

This is Platform Engineering's question, answered.

**DO:** Slide 9 (per-route allow-lists), then slide 10 (tag stamping and forced
`_tag`), then **portal tab 3** (named values).

**SAY:** The line to deliver on slide 9:

> *"The route is not a suggestion about which door to use — it is the only door
> that exists, and each door runs a different allow-list before it opens."*

Outbound is read-only: GET plus the Group export, nothing else. Inbound accepts
writes but **rejects any resource that arrives without a contract tag**, and
overwrites the tag if the caller supplies one.

On slide 10, the mechanism in one breath: on the way in we *stamp*
`meta.tag`; on the way out we *force* `_tag` into the query. The payer cannot
widen their scope by editing the query string.

On portal tab 3, open the entitlement named value. This is where payer → contract
mapping lives. **This is the onboarding answer** — adding payer three is an edit
here plus a route, not a redeploy.

**PROVES:** One FHIR service can serve both directions because direction is
enforced per-route, not per-service.

**IF IT FAILS:** If named values won't expand, the same map is printed by
`show-env.ps1` output in `evidence/`.

---

## Part 5 — Gateway isolation with tests · 12 min · slides 11–12 · **LIVE**

The centre of the session. Everything before this was setup.

**DO — first, set the trap.** Go to **portal tab 5**: `fhir-payera` → Access
control (IAM) → Role assignments.

**SAY:** *"One role assignment. It belongs to the APIM managed identity — the
object id we saw in tab four. Now hold this in your head: the two payer
application registrations have zero Azure role assignments between them. Not
reduced. Zero."*

**DO — then run it.**

```powershell
cd "..\v4"
./scripts/run-isolation-tests.ps1
```

**EXPECT:** 16 assertions, 16 green. Roughly 90 seconds. It will scroll.

Slide 11 groups all sixteen; slide 12 is the one to have on the second screen.
**Narrate exactly three lines and no others:**

### Line 4 — Valid token. Wrong payer. → **403**

Fabrikam's application holding a technically valid token minted for Contoso's
audience. The signature checks out. Entra did its job correctly. Layer 2 reads
the `appid` claim, finds `payerb`, compares it to the payer implied by the route,
and refuses.

> *"The boundary holds against a legitimate credential, not just a forged one."*

### Line 12 — Payer goes straight to AHDS. → **403**

No APIM in the path at all. Payer token, FHIR hostname, direct.

**Stop on the status code.** 403, not 401. Entra authenticated the caller
perfectly well. AHDS then looked for a role assignment and found none.

> *"Skipping the gateway does not skip the control — it removes the only means of
> access."*

This is the line that closes the "can they just go around it" question, and it is
why you showed tab 5 first.

### Line 13b — We read the body, not the code. → **CT-3456 only**

Payer A holds two contracts. The response is inspected resource by resource and
asserted to contain CT-3456 only, because the Group being exported belongs to
that contract alone.

> *"A 200 would have passed a status-code check. Logical separation is verified in
> the data."*

**PROVES:** Isolation is enforced, not configured; and it is verified against
response bodies, not just status codes.

**IF IT FAILS:**

- **Assertion 2 returns 429** → you ran inside the 300-second export lock. Say
  *"that's the rate limiter, not the boundary — I ran this fifteen minutes ago"*
  and move on. Do not re-run.
- **Anything else red** → do not debug live. Say plainly: *"Let me show you the
  captured run from this morning"* and open `evidence/isolation-run.txt`. Never
  apologise for a captured run; announce it as one.

**Then invite the attack:**

> *"The strongest thing you can do with this is break it. If someone here can
> name a call that should be refused and isn't, say it now and we'll run it."*

If they name one, use the Bruno collection in `bruno/` — six requests, each with
the expected status asserted, and docs explaining what it proves.

---

## Part 6 — Policy walkthrough and debug trace · 10 min · slides 13–14

**DO:** Slide 13 (six layers with live line numbers), then a live trace.

**SAY:** Two minutes total on the six layers — not two minutes each. Open
`apim/policies/payer-outbound.xml` (378 lines) and jump the line numbers as you
name them:

| Layer | Line | What it does | Failure mode |
|---|---|---|---|
| 1 | 27 | Validate the Entra JWT | 401 |
| 2 | 47 | Entitlement + cross-payer guard | **403 — assertion 4** |
| 3 | 124 | Route method allow-list | 403 — assertion 7 |
| 4a | 165 | Group-scoped export only | 403 — assertion 6 |
| 4b | 239 | Force `_tag`, override caller's | 200 — assertion 13 |
| 5 | 262 | 600/min, 50k/day, 1 export / 5 min | 429 — assertion 15 |
| 6 | 317 | Trusted broker: swap to managed identity | 403 if bypassed — assertion 12 |

Line **321** is `authentication-managed-identity`. Stop there for a beat:

> *"This is the exchange. The payer's token ends here. Everything past this line
> travels on the gateway's identity, and the gateway's identity is the only one
> AHDS has ever been told about."*

**DO — the trace.** APIM → APIs → `payera/outbound` → **Test** → send a request
with tracing on → open **Trace**.

**SAY:** Walk the inbound section. Show the policies firing in order, with
timings. Then show a denied call and point at the exact policy that terminated
it.

**PROVES:** This is inspectable and debuggable by their operations team. It is
not a black box, and a denial names its own cause.

**IF IT FAILS:** Trace requires a valid `Ocp-Apim-Trace` token and the portal
sometimes needs a refresh to enable it. If it won't cooperate, `shots/` has a
captured trace. Ninety seconds of fumbling here costs you the close.

---

## Part 7 — Credentials, identity and deployment · 7 min · slides 15–16

**DO:** Slide 15, then **portal tab 4** (managed identity), then slide 16.

**SAY:** Slide 15 — the payer authenticates with SMART on FHIR Backend Services
shape: `client_credentials`, no user present. Client secret today; certificate
credential or federated identity credential in production. Cover the trade-off
honestly.

Tab 4 — this object id is the only principal with FHIR Data Contributor. Tie it
back to line 321 and to assertion 12. Three surfaces, one fact.

Slide 16 — deployment reality. We are on **BasicV2**, which has no VNet
injection. Production wants **Premium** or **StandardV2 + private endpoints**,
plus availability zones and a multi-region gateway if their RTO demands it. Say
the tier constraint out loud; do not let them discover it later.

**PROVES:** That the pattern survives contact with a production security review.

**IF IT FAILS:** N/A — this part is slides plus one blade.

---

## Part 8 — Decisions and next steps · 4 min · slides 17–18

**DO:** Slide 17. Read the four decisions. Stop talking.

**SAY:** *"These four are the reason this meeting was an hour and not a
document."* Then wait. Silence here is productive; the pause is what converts a
demo into a decision.

Slide 18 — next steps with owners and dates. If a decision doesn't land, write
down who owns it and by when, and say the date out loud.

**PROVES:** That there is a next action, which is the only outcome that matters.

---

## Fallbacks, ranked

1. **`evidence/isolation-run.txt`** — the full captured 16/16 run. Covers Part 5
   completely.
2. **`shots/`** — portal captures for every tab, including the trace.
3. **`render/s/Slide*.PNG`** — every slide as an image, if PowerPoint dies.
4. **`reference/`** — the prior DOCX runbook and deck.

Rule for all four: **announce the fallback, don't hide it.** *"This is a captured
run from this morning"* costs you nothing. Silently showing a screenshot while
implying it's live costs you the room.

---

## Key takeaways — the five sentences to leave behind

1. **Physical separation stops a mistake. Logical separation stops a query.** We
   do both, and they answer different threats.
2. **The payer applications hold zero Azure role assignments.** The gateway is
   not the recommended path to FHIR; it is the only one — assertion 12, 403 not
   401.
3. **Direction is enforced per-route, not per-service.** One FHIR service serves
   inbound and outbound safely because each route runs a different allow-list
   before it opens.
4. **Contract scope is forced, not requested.** The gateway overwrites a
   caller-supplied `_tag` rather than merging it, so a payer cannot widen their
   own scope — verified in the response body, not the status code.
5. **Onboarding payer three is a configuration change** — a named value edit and
   a route — not a redeploy and not new infrastructure.

---

## File map

| File | Use |
|---|---|
| `Prov-APIM-FHIR-Session-2026-09-01.pptx` | The deck. Speaker notes on all 18 slides. |
| `demo.html` | **Interactive prep console.** Diagrams, checklist, pacing clock, drills. |
| `demo.md` | This file. Actions, script, fallbacks — plain-text source of record. |
| `mapping-objectives.md` | Agenda → customer ask → slide → surface → assertion. |
| `open-demo-tabs.ps1` | Stages the five portal tabs in order. |
| `bruno/` | Six interactive requests for ad-hoc challenges. |
| `evidence/` | Captured runs, including `isolation-run.txt`. |
| `shots/` | Portal screenshots. `shots/portal/` wins over `shots/`. |
| `render/s/` | All 18 slides as PNG. |
| `../scripts/show-env.ps1` | T-60 pre-flight. |
| `../scripts/run-isolation-tests.ps1` | The 16 assertions. |
| `../apim/policies/payer-outbound.xml` | The six layers, 378 lines. |

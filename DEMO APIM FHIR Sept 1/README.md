# DEMO APIM FHIR — 1 September 2026

Everything for the Northwind Health session on API Management in front of Azure Health
Data Services, built to the eight-item agenda the customer set.

## Read these in order

1. **`demo.html`** — the interactive prep console. Open it in a browser. Everything
   `demo.md` contains, plus colour-coded DO/SAY/EXPECT/PROVES/FAILS blocks, an
   architecture diagram, the six policy layers laid out visually, a tick-off checklist
   with a progress ring, a 60-minute pacing clock, and eight flip-card drills.
   **This is the one to prep from.**
2. **`mapping-objectives.md`** — why each artifact exists. Agenda item → the
   question the customer actually asked → slides → portal surface → the assertion
   that proves it.
3. **`demo.md`** — the same run book as plain markdown. Source of record, and what
   you print or paste into a channel.
4. **`Prov-APIM-FHIR-Session-2026-09-01.pptx`** — 18 slides, speaker notes on
   every one (~4,000 words). The notes are the words; `demo.html` is the actions.

## Before the meeting

```powershell
cd "..\v4"
./scripts/show-env.ps1                      # T-60 · must exit 0
./scripts/run-isolation-tests.ps1 | Out-Null # T-15 · confirms 16/16 today
#                                             T-10 · wait 5 min, export lock
cd "..\DEMO APIM FHIR Sept 1"
./open-demo-tabs.ps1 -StageOnly             # T-2  · stages five portal tabs
```

> The five-minute wait is not optional. Layer 5 holds one bulk export per payer
> per 300 seconds, so a live run inside that window returns 429 on assertion 2
> and you end up explaining a rate limiter instead of explaining isolation.

## What is here

| Path | What it is |
|---|---|
| `demo.html` | **Interactive prep console** — diagrams, checklist, pacing clock, drills |
| `demo.md` | Run book — actions, script, fallbacks, key takeaways |
| `mapping-objectives.md` | Traceability matrix and stated gaps |
| `Prov-APIM-FHIR-Session-2026-09-01.pptx` | The deck |
| `build-deck.py` | Regenerates the deck. Self-verifies slide and notes counts. |
| `open-demo-tabs.ps1` | Opens the five portal tabs in demo order |
| `bruno/` | Six interactive requests for ad-hoc challenges from the room |
| `evidence/` | Captured runs. `isolation-run.txt` is the Part 5 fallback. |
| `shots/` | Portal screenshots. `shots/portal/` takes precedence. |
| `render/s/` | All 18 slides as PNG, if PowerPoint dies |
| `reference/` | Prior deck and DOCX runbook, kept for lineage |

Live code and policy live one level up in `..\v4\` — `scripts/`, `apim/policies/`,
`tests/`.

## Rebuilding the deck

```powershell
& "$env:LOCALAPPDATA\venvs\pptxbuild\Scripts\python.exe" build-deck.py
```

Prints slide count, any slides missing notes, and total notes words. Expected:
`Slides: 18  Notes missing on: none  Notes words: 4035`.

## Using the Bruno collection

Open the `bruno/` folder as a collection and select the **poc** environment.
`payerASecret` and `payerBSecret` are declared as Bruno **secret vars** — they are
deliberately empty and are not stored in this repository.

To fill them, mint a short-lived secret for each payer app registration, paste it
into the Bruno UI, and revoke it after the session. Requests 01 and 02 capture
their tokens into runtime variables that the other four requests consume, so run
them in order. Every request asserts its expected status and carries a `docs`
block explaining what it proves.

## The one sentence

> **Physical separation stops a mistake. Logical separation stops a query.**

Everything in this folder is an attempt to make that stop being a claim.

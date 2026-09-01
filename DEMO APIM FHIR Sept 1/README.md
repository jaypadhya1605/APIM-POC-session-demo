# Demo evidence and request collection

Supporting material for the session on API Management in front of Azure Health Data
Services. The prep material, run book and deck are not published here — what remains is
the evidence a reader needs to check the claims made in the top-level README.

## What is here

| Path | What it is |
|---|---|
| `bruno/` | Six interactive requests covering the isolation cases — mint a token, read own data, cross-payer denied, write-on-outbound denied, direct-to-AHDS denied |
| `evidence/` | Captured console output from live runs. `isolation-run.txt` is the full suite result. |
| `shots/` | Portal screenshots rendered from `evidence/` — resource group, APIs, both policies, named values, APIM identity, FHIR RBAC, test run |
| `render/` | The session slides as PNG |
| `reference/` | Word runbook, kept for lineage |

Live code and policy are in the repository root: `scripts/`, `apim/policies/`, `tests/`,
`infra/`.

## Using the Bruno collection

Open the `bruno/` folder as a collection and select the **poc** environment.
`payerASecret` and `payerBSecret` are declared as Bruno **secret vars** — they are
deliberately empty and are not stored in this repository.

To fill them, mint a short-lived secret for each payer app registration and paste it
into the environment at run time. Nothing is written back to disk.

## Reading the evidence files

Each `figNN-*.txt` is the raw output of the command named in its header, captured
against a live environment. `shots/` is the same content rendered as an image, so the
two should always agree. If they disagree, trust the `.txt`.

# v4 — Northwind Health CMS-0057-F POC on Azure Health Data Services

A deployed, runnable environment answering the open questions from the 2026-08-12 working session
and the integration lead's seven-question set.

**Start here:** [00-EXECUTIVE-BRIEF.md](00-EXECUTIVE-BRIEF.md)

| If you want to | Read |
|---|---|
| Know whether the asks are answered | [VALIDATION.md](VALIDATION.md) |
| Run the demo | [DEMO-SCRIPT.md](DEMO-SCRIPT.md) |
| Understand the design | [docs/01-architecture.md](docs/01-architecture.md) |

---

## What is deployed

Subscription `00000000-0000-0000-0000-000000000000` · resource group `rg-ahds-fhir-poc` · East US 2

| Resource | Name |
|---|---|
| AHDS workspace | `ahdspocdemo01` |
| FHIR service — Contoso Health Plan | `fhir-payera` (contracts `CT-3456`, `CT-7788`) |
| FHIR service — Fabrikam Medicare Advantage | `fhir-payerb` (contract `CT-9001`) |
| API Management | `apim-poc-ahds-demo01` |
| Storage (integration data store) | `stpocahdsdemo01` — containers `pdex`, `export`, `quarantine` |
| Key Vault | `kv-poc-ahds-demo01` |
| Log Analytics | `log-ahds-demo01` |

Gateway: `https://apim-poc-ahds-demo01.azure-api.net`

---

## Contents

```
00-EXECUTIVE-BRIEF.md        the read-first document
VALIDATION.md                every ask mapped to runnable evidence, plus the one open gap
DEMO-SCRIPT.md               how to run the demo: 3-minute proof or 25-minute walkthrough
docs/
  01-architecture.md         component-by-component walkthrough
  02-architecture-decisions.md     every open item from 8/12, closed
  03-platform-questions.md    all seven questions, incl. Q7 which had no prior answer
  04-import-403-rootcause.md   the $import 403: cause, fix, and how to retest correctly
  05-capacity-and-scale.md   the unanswered question, framed for the product group
  06-smart-backend-services.md
  07-apim-control-plane.md   the six policy layers and why they are ordered that way
diagrams/
  northwind-ahds-reference-architecture.drawio   4 pages, editable
  architecture.mmd                                Mermaid rendering
infra/
  main.bicep, main.bicepparam, modules/           the whole environment
apim/policies/
  payer-outbound.xml, payer-inbound.xml
scripts/
  generate-samples.ps1       synthetic FHIR NDJSON, namespaced ids, tagged
  load-fhir-direct.ps1       loads via REST (see the caveat below)
  run-import.ps1             $import with the 403 diagnostics built in
  onboard-payer.ps1          the seven-step onboarding, scripted
  run-isolation-tests.ps1    the proof suite, executable
  show-env.ps1               environment summary + a filled-in .http file
tests/
  isolation-proofs.http      the same assertions as raw HTTP
runbooks/
  payer-onboarding.md, import-troubleshooting.md
loadtest/
  run-loadtest.ps1           concurrent export measurement
```

> The APIM policy files are not strict-XML parseable — policy expressions such as
> `@(context.Variables["payerKey"])` embed unescaped double quotes inside attributes.
> This is how APIM stores them; `format: 'rawxml'` accepts it and the deployed policy
> matches these files byte for byte. Do not "fix" the quotes.

---

## Reproducing from scratch

```powershell
cd v4/infra
az deployment group create -g rg-ahds-fhir-poc -f main.bicep -p main.bicepparam

cd ../
./scripts/generate-samples.ps1 -PatientsPerContract 25
./scripts/load-fhir-direct.ps1                 # or ./scripts/run-import.ps1
./scripts/onboard-payer.ps1 -PayerKey payera -DisplayName 'Contoso Health Plan' -Contracts CT-3456,CT-7788
./scripts/onboard-payer.ps1 -PayerKey payerb -DisplayName 'Fabrikam Medicare Advantage' -Contracts CT-9001
./scripts/run-isolation-tests.ps1
```

Adding a payer is one entry in the `payers` array in
[infra/main.bicepparam](infra/main.bicepparam) plus one `onboard-payer.ps1` call. Nothing is
provisioned by hand — at 40 instances, configuration drift is the failure mode to design against.

---

## Two constraints in this demo subscription

Both are tenant governance controls on the Microsoft Non-Production tenant. Neither reflects the
architecture, and neither will apply in Northwind Health's own subscription — but they shaped how the
scripts work, so they are documented rather than hidden.

**1. Storage and Key Vault public network access is force-disabled.** An ARM `PATCH` setting
`publicNetworkAccess: Enabled` is silently reverted by a Modify-effect policy. Consequences:

- NDJSON cannot be uploaded to the `pdex` container from outside Azure, so `$import` could not be
  exercised here. [scripts/load-fhir-direct.ps1](scripts/load-fhir-direct.ps1) loads the same data
  over the FHIR REST API instead, with the same PUT semantics (ids preserved verbatim).
- The RBAC fix that resolves the platform lead's 403 **is deployed and verifiable**:

  ```powershell
  az role assignment list --scope $(az storage account show -g rg-ahds-fhir-poc -n stpocahdsdemo01 --query id -o tsv) `
    --query "[].{role:roleDefinitionName, principal:principalId}" -o table
  ```

  Both FHIR services' system-assigned principals hold Storage Blob Data Contributor.
  [scripts/run-import.ps1](scripts/run-import.ps1) remains the production path.

**2. Application secrets are capped at 30 days** (`policies/defaultAppManagementPolicy`,
`passwordLifetime: P30D`), and the vault cannot be written to. So
[scripts/run-isolation-tests.ps1](scripts/run-isolation-tests.ps1) mints an ephemeral credential,
proves the model, and revokes it inside one process. Nothing is ever written to disk or displayed —
which is better hygiene than the Key Vault path it replaces.

---

## Tearing down

```powershell
az group delete -n rg-ahds-fhir-poc --yes --no-wait
```

Everything is in Bicep, so the environment rebuilds from nothing when it is next needed.

---

## Scope

Synthetic data only; no PHI has been placed in this subscription. POC network posture is public
endpoints with no private endpoints or VNet — production needs both, and that gap is configuration
rather than architecture.

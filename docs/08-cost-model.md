# Cost model

East US pricing, USD. Unit rates pulled from the Azure retail price list on 2026-09-01; the POC
figures are actual billed consumption, not estimates. Verify current rates before quoting
externally.

---

## Unit rates

| Component | Rate |
|---|---|
| AHDS FHIR service runtime | **none — there is no hourly meter** |
| AHDS API requests | $0.54 / 100,000 |
| AHDS structured storage | $0.39 / GB-month |
| AHDS bulk export, batch | $0.19 / GB |
| AHDS bulk export, streaming | $0.34 / GB |
| AHDS notifications | $0.59 / 1M |
| Blob storage, Hot LRS | $0.0208 / GB-month |
| APIM Developer | ~$50 / month |
| APIM BasicV2 | ~$150 / month |
| APIM StandardV2 | ~$700 / month |
| Log Analytics ingestion | ~$2.30 / GB after 5 GB free |
| Key Vault | negligible |

> **The $0.40/hour "Standard Service Runtime" meter is not ours.** It belongs to the retail product
> `Azure Health Data APIs`, the legacy standalone Azure API for FHIR. Workspace-based Azure Health
> Data Services — `Microsoft.HealthcareApis/workspaces/fhirservices`, what this POC deploys — has no
> hourly meter of any kind. Every AHDS charge is consumption: requests, storage, export GB,
> notifications.

---

## This POC

Actual billed cost for `rg-ahds-fhir-poc`, August 2026, by meter:

| Meter | Billed |
|---|---|
| APIM Basic v2 unit | $84.86 |
| Application Insights / monitoring nodes | $7.80 |
| Log Analytics ingestion | $0.07 |
| FHIR — API requests, structured storage, export batch | **$0.00** |
| Storage account, Key Vault, Event Grid | $0.00 |
| **Total** | **$92.74** |

APIM was deployed part-way through the month. Projected forward for a full month at the same shape:

| Component | Monthly |
|---|---|
| APIM BasicV2, 1 unit | ~$150 |
| Monitoring | ~$10 |
| 2 × FHIR service | ~$0 — demo volume sits inside the free request and storage grants |
| **Total, 24×7** | **≈ $160** |

| Usage pattern | Cost |
|---|---|
| Deleted between demos, ~4 demo days/month | **≈ $20** |
| A two-hour smoke test | **< $1** |
| Left running for a month | ≈ $160 |

**The thing worth deleting is APIM, not FHIR.** FHIR bills nothing at rest beyond stored GB, so an
idle FHIR service costs essentially zero. APIM BasicV2 bills ~$0.21/hour whether or not a call
arrives, and it is 96% of this bill. Delete the resource group after demos and redeploy from
[infra/main.bicep](../infra/main.bicep) — the whole environment rebuilds in about 20 minutes, and
APIM is the only slow part.

```powershell
az group delete -n rg-ahds-fhir-poc --yes --no-wait
```

---

## Northwind Health production estimate

Based on the stated volumes: ~1.4 TB, ~30M resources/month, 30–40 payers.

| Component | Monthly |
|---|---|
| API requests (~30M ingest + payer reads) | ~$200 |
| Structured storage (1.4 TB) | ~$560 |
| Bulk export (batch, volume not yet known) | ~$40 |
| Blob staging (500 GB incremental, Hot) | ~$10 |
| APIM StandardV2 (production tier) | ~$700 |
| Log Analytics | ~$150 |
| **Total** | **≈ $1,700 / month** |

The FHIR portion of that is **≈ $800**, and it is the same $800 whether the traffic lands on one
service or on forty.

Order-of-magnitude. Real cost depends on the request pattern more than on data volume, and the
export burst profile is the dominant unknown — the export line above is a placeholder until the
volume numbers arrive. See [05-capacity-and-scale.md](05-capacity-and-scale.md).

---

## The objection this document exists to answer

> *"Forty FHIR instances will cost forty times as much."*

**It will not.** AHDS FHIR has **no hourly meter at all** — billing is consumption-based across
requests, storage, export GB and notifications. Forty lightly-used payer instances consume the same
total as one instance handling the same aggregate traffic. The August bill above is the proof: two
FHIR services ran the whole month and billed $0.00.

The same arithmetic answers the narrower question, *"is one FHIR service per payer cheaper than
two?"* — no, and neither is it more expensive. Instance count is not a billable dimension.

What changes with instance count:

| Scales with instances | Scales with usage |
|---|---|
| Operational surface: diagnostics, alerts, RBAC, upgrade windows | Request charges |
| Quota consumption (10 → 40, by support ticket) | Storage charges |
| IaC complexity — mitigated by the `payers` array | Throughput charges |

The real cost of Option 1 is **operational**, not financial, and it is controlled by never
provisioning an instance by hand. That is why [infra/main.bicep](../infra/main.bicep) takes an array
rather than shipping one template per payer.

---

## Levers, in order of impact

1. **Delete idle APIM instances.** Largest single saving in non-production, because APIM is the only
   component that bills by the hour. Dev and QA gateways do not need to exist overnight.
2. **Right-size APIM.** BasicV2 proves the policy model. StandardV2 is a production decision driven
   by the load test, not a default. At ~$700/month it is the largest single line in the production
   estimate — larger than all FHIR consumption combined.
3. **Lifecycle the blob staging tier.** NDJSON already imported can move to Cool after 30 days and
   Archive after 90. Import staging is write-once, read-once.
4. **Cap Log Analytics retention.** 30 days is set here. Compliance may require longer for audit
   logs specifically — apply per-table retention rather than raising the workspace default.
5. **Do not enable provisioned throughput speculatively.** Autoscale is free. Provisioned RU/s is
   a fixed charge for a guarantee you may not need; decide after measurement.

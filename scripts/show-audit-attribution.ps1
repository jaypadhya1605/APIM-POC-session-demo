<#
.SYNOPSIS
  Shows who called the FHIR service, as recorded by the FHIR service itself.

.DESCRIPTION
  APIM stamps X-MS-AZUREFHIR-AUDIT-* headers on every brokered request. AHDS is
  the only component that persists them, so this view is independent of APIM's
  own logs - a call that bypassed the gateway cannot fake attribution.

.EXAMPLE
  ./show-audit-attribution.ps1
  ./show-audit-attribution.ps1 -Minutes 120
#>
[CmdletBinding()]
param(
  [string]$ResourceGroup = 'rg-ahds-fhir-poc',
  [string]$Workspace     = 'log-ahds-demo01',
  [int]$Minutes          = 30
)

$ErrorActionPreference = 'Stop'
$sub = az account show --query id -o tsv

# The ARM proxy is used instead of api.loganalytics.io: that hostname does not
# always resolve behind Global Secure Access, and failing mid-demo looks bad.
$token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
$hdr = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
$url = "https://management.azure.com/subscriptions/$sub/resourceGroups/$ResourceGroup" +
       "/providers/Microsoft.OperationalInsights/workspaces/$Workspace/api/query?api-version=2020-08-01"

$kql = @"
MicrosoftHealthcareApisAuditLogs
| where TimeGenerated > ago(${Minutes}m) and StatusCode > 0
| extend P = parse_json(Properties)
| project TimeGenerated, StatusCode, CallerIPAddress,
          Payer     = tostring(P['x-ms-azurefhir-audit-payer']),
          Caller    = tostring(P['x-ms-azurefhir-audit-caller']),
          Contracts = tostring(P['x-ms-azurefhir-audit-contracts']),
          Resource  = tostring(P.fhirResourceType)
| order by TimeGenerated asc
"@

$r = Invoke-RestMethod -Uri $url -Headers $hdr -Method POST -Body (@{ query = $kql } | ConvertTo-Json)
$rows = $r.tables[0].rows

if (-not $rows) {
  Write-Host "No audit rows in the last $Minutes minutes. Run run-isolation-tests.ps1 first." -ForegroundColor Yellow
  return
}

Write-Host "`nFHIR audit log - last $Minutes minutes`n" -ForegroundColor Cyan
"{0,-10} {1,-5} {2,-16} {3,-9} {4,-20} {5}" -f 'Time','Code','Source IP','Payer','Contracts','Resource'
"{0,-10} {1,-5} {2,-16} {3,-9} {4,-20} {5}" -f '----','----','---------','-----','---------','--------'

foreach ($row in $rows) {
  $t         = ([datetime]$row[0]).ToString('HH:mm:ss')
  $code      = $row[1]
  $ip        = $row[2]
  $payer     = if ($row[3]) { $row[3] } else { '-' }
  $contracts = if ($row[5]) { $row[5] } else { '-' }
  $res       = $row[6]

  # No attribution means the request never passed through APIM.
  $colour = if ($payer -eq '-') { 'Red' } elseif ($code -ge 400) { 'Yellow' } else { 'Green' }
  Write-Host ("{0,-10} {1,-5} {2,-16} {3,-9} {4,-20} {5}" -f $t, $code, $ip, $payer, $contracts, $res) -ForegroundColor $colour
}

$unattributed = @($rows | Where-Object { -not $_[3] }).Count
Write-Host ""
Write-Host "  green  = brokered by APIM, attributed to a payer and contract set" -ForegroundColor DarkGray
Write-Host "  red    = no attribution, so it did not come through the gateway"   -ForegroundColor DarkGray
Write-Host ""
Write-Host ("$($rows.Count) calls, $unattributed without attribution.") -ForegroundColor Cyan

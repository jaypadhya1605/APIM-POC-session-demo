<#
.SYNOPSIS
  Revokes a payer's contract live, shows the data shrink, then restores it.

.DESCRIPTION
  The same token and the same URL return different data before and after, with
  no redeploy and no restart. Entitlement lives in an APIM named value, so the
  change takes effect in about five seconds.

  This is the answer to "how do we cut a payer off?" - and it is reversible on
  stage, which the isolation suite is not.

  The payer's credential is untouched throughout. Revocation is an entitlement
  decision, not a credential one.

.NOTES
  Restore runs in a finally block. If you kill this with Ctrl-C the entitlement
  may be left narrowed - re-run with -RestoreOnly to put it back.

.EXAMPLE
  ./demo-revoke-contract.ps1
  ./demo-revoke-contract.ps1 -NoPause
  ./demo-revoke-contract.ps1 -RestoreOnly
#>
[CmdletBinding()]
param(
  [string]$ResourceGroup = 'rg-ahds-fhir-poc',
  [string]$PayerKey      = 'payera',
  [string]$DisplayName   = 'Contoso Health Plan',
  [string[]]$Contracts   = @('CT-3456','CT-7788'),
  [string]$Revoke        = 'CT-7788',
  [switch]$NoPause,
  [switch]$RestoreOnly
)

$ErrorActionPreference = 'Stop'
$Contracts = @($Contracts | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$onboard = Join-Path $PSScriptRoot 'onboard-payer.ps1'

function Set-Entitlement([string[]]$c) {
  & $onboard -PayerKey $PayerKey -DisplayName $DisplayName -Contracts $c -SkipCredential *>&1 | Out-Null
}

if ($RestoreOnly) {
  Set-Entitlement $Contracts
  Write-Host "restored: $($Contracts -join ', ')" -ForegroundColor Green
  return
}

function Pause-Here($msg) {
  if ($NoPause) { return }
  Write-Host "`n  $msg" -ForegroundColor DarkGray
  [void][Console]::ReadKey($true)
}

# ---------------------------------------------------------------- setup
$tenantId = az account show --query tenantId -o tsv
$ws       = az resource list -g $ResourceGroup --resource-type 'Microsoft.HealthcareApis/workspaces' --query "[0].name" -o tsv
$apimName = az apim list -g $ResourceGroup --query "[0].name" -o tsv
$gateway  = az apim show -g $ResourceGroup -n $apimName --query gatewayUrl -o tsv
$appId    = az ad app list --display-name "cmsdqm-$PayerKey" --query "[0].appId" -o tsv
$fhirUrl  = "https://$ws-fhir-$PayerKey.fhir.azurehealthcareapis.com"

# Ephemeral credential, revoked in the finally block. Never written to disk.
$end = (Get-Date).AddDays(1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$secret = az ad app credential reset --id $appId --end-date $end --append --display-name 'demo-revoke' --query password -o tsv 2>$null
if ([string]::IsNullOrWhiteSpace($secret)) { throw "Could not mint a credential for $PayerKey." }

$token = $null
$form = "client_id=$appId&scope=$fhirUrl/.default&client_secret=$secret&grant_type=client_credentials"
for ($i = 0; $i -lt 6 -and -not $token; $i++) {
  try {
    $token = (Invoke-RestMethod -Method POST -ContentType 'application/x-www-form-urlencoded' `
      -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $form).access_token
  } catch { Start-Sleep -Seconds 5 }
}
Clear-Variable secret, form
if (-not $token) { throw "Token acquisition failed." }

$probeUri = "$gateway/$PayerKey/outbound/Patient?_count=50"

function Read-AsPayer {
  $r = Invoke-WebRequest -Uri $probeUri -Headers @{ Authorization = "Bearer $token" } -SkipHttpErrorCheck
  # AHDS returns application/fhir+json with no charset, so Content is a byte[].
  $t = if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
  [pscustomobject]@{
    Code     = [int]$r.StatusCode
    Patients = ([regex]::Matches($t, '"resourceType"\s*:\s*"Patient"')).Count
    Tags     = (([regex]::Matches($t, 'CT-\d+') | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ', ')
  }
}

function Show-Result($label, $p, $colour) {
  Write-Host ("  {0,-10} HTTP {1}   {2,3} patients   contracts: {3}" -f $label, $p.Code, $p.Patients, $p.Tags) -ForegroundColor $colour
}

function Wait-ForChange([scriptblock]$until) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  do {
    Start-Sleep -Seconds 3
    $p = Read-AsPayer
  } while (-not (& $until $p) -and $sw.Elapsed.TotalSeconds -lt 120)
  return @{ Probe = $p; Seconds = [int]$sw.Elapsed.TotalSeconds }
}

try {
  Write-Host "`n  Payer:    $DisplayName ($appId)"
  Write-Host   "  Request:  GET $probeUri"
  Write-Host   "  This token and this URL do not change for the rest of the demo.`n"

  Show-Result 'BEFORE' (Read-AsPayer) 'Green'

  Pause-Here "press a key to revoke $Revoke"

  $kept = @($Contracts | Where-Object { $_ -ne $Revoke })
  Write-Host "`n  Revoking $Revoke - payer keeps $($kept -join ', ')" -ForegroundColor Yellow
  Set-Entitlement $kept

  $r = Wait-ForChange { param($p) $p.Tags -notmatch [regex]::Escape($Revoke) }
  Show-Result 'AFTER' $r.Probe 'Yellow'
  Write-Host ("  took {0}s - no redeploy, no restart, credential untouched" -f $r.Seconds) -ForegroundColor DarkGray

  Pause-Here "press a key to restore $Revoke"
}
finally {
  Write-Host "`n  Restoring $($Contracts -join ', ')" -ForegroundColor Yellow
  Set-Entitlement $Contracts

  if ($token) {
    $r = Wait-ForChange { param($p) $p.Tags -match [regex]::Escape($Revoke) }
    Show-Result 'RESTORED' $r.Probe 'Green'
  }

  $keyId = az ad app credential list --id $appId --query "[?displayName=='demo-revoke'].keyId | [0]" -o tsv 2>$null
  if ($keyId) { az ad app credential delete --id $appId --key-id $keyId 2>$null }
  Write-Host "  demo credential revoked`n" -ForegroundColor DarkGray
}

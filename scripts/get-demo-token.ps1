<#
.SYNOPSIS
  Prints a short-lived bearer token to paste into the APIM portal test console.

.DESCRIPTION
  Defaults reproduce slide 16: payer B's application asking for a token whose
  audience is payer A's FHIR service. The token is genuine and correctly signed
  - APIM refuses it at the cross-payer guard, which is what the trace shows.

  The client secret is deleted before the script exits. The access token keeps
  working until it expires (about an hour) because a JWT is self-contained.

.EXAMPLE
  ./get-demo-token.ps1                          # payer B app, payer A audience -> 403
  ./get-demo-token.ps1 -App payera              # payer A app, payer A audience -> 200
#>
[CmdletBinding()]
param(
  [ValidateSet('payera','payerb')][string]$App      = 'payerb',
  [ValidateSet('payera','payerb')][string]$Audience = 'payera',
  [string]$ResourceGroup = 'rg-ahds-fhir-poc',
  [switch]$NoCopy
)

$ErrorActionPreference = 'Stop'

$tenantId = az account show --query tenantId -o tsv
$ws       = az resource list -g $ResourceGroup --resource-type 'Microsoft.HealthcareApis/workspaces' --query "[0].name" -o tsv
$apimName = az apim list -g $ResourceGroup --query "[0].name" -o tsv
$gateway  = az apim show -g $ResourceGroup -n $apimName --query gatewayUrl -o tsv
$appId    = az ad app list --display-name "cmsdqm-$App" --query "[0].appId" -o tsv
$fhirUrl  = "https://$ws-fhir-$Audience.fhir.azurehealthcareapis.com"

if (-not $appId) { throw "No app registration named cmsdqm-$App." }

$end = (Get-Date).AddDays(1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$secret = az ad app credential reset --id $appId --end-date $end --append --display-name 'demo-trace' --query password -o tsv 2>$null
if ([string]::IsNullOrWhiteSpace($secret)) { throw "Could not mint a credential for $App." }

try {
  $form = "client_id=$appId&scope=$fhirUrl/.default&client_secret=$secret&grant_type=client_credentials"
  $token = $null
  for ($i = 0; $i -lt 6 -and -not $token; $i++) {
    try {
      $token = (Invoke-RestMethod -Method POST -ContentType 'application/x-www-form-urlencoded' `
        -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $form).access_token
    } catch { Start-Sleep -Seconds 5 }
  }
}
finally {
  Clear-Variable secret, form -ErrorAction SilentlyContinue
  $keyId = az ad app credential list --id $appId --query "[?displayName=='demo-trace'].keyId | [0]" -o tsv 2>$null
  if ($keyId) { az ad app credential delete --id $appId --key-id $keyId 2>$null }
}
if (-not $token) { throw "Token acquisition failed." }

$exp = [DateTimeOffset]::FromUnixTimeSeconds(
  ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(
    $token.Split('.')[1].Replace('-','+').Replace('_','/').PadRight(
      [int][Math]::Ceiling($token.Split('.')[1].Length / 4) * 4, '='))) | ConvertFrom-Json).exp).LocalDateTime

$expected = if ($App -eq $Audience) { '200 - own data' } else { '403 - cross-payer guard, layer 2' }

Write-Host ""
Write-Host "  App           cmsdqm-$App  ($appId)"
Write-Host "  Audience      $fhirUrl"
Write-Host "  Expect        $expected" -ForegroundColor Yellow
Write-Host "  Valid until   $($exp.ToString('HH:mm:ss'))"
Write-Host ""
Write-Host "  Portal test console - $apimName" -ForegroundColor Cyan
Write-Host "    API                   $(if($Audience -eq 'payera'){'Contoso Health Plan'}else{'Fabrikam Medicare Adv.'}) - Outbound"
Write-Host "    Operation             GET (wildcard)"
Write-Host "    Template parameter    *  =  Patient"
Write-Host "    Header                Authorization  =  the value below"
Write-Host "    Then click            Trace   (not Send)"
Write-Host ""
Write-Host "  Equivalent URL          $gateway/$Audience/outbound/Patient" -ForegroundColor DarkGray
Write-Host ""

$header = "Bearer $token"
Write-Host $header -ForegroundColor Green
Write-Host ""

if (-not $NoCopy) {
  Set-Clipboard -Value $header
  Write-Host "  copied to clipboard - paste straight into the Authorization header" -ForegroundColor DarkGray
  Write-Host ""
}

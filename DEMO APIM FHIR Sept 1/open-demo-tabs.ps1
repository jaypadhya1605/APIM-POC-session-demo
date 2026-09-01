<#
    open-demo-tabs.ps1

    Stages the browser exactly as the runbook pre-flight describes, and prints
    what to click and capture in each tab.

    Two uses:
      1. Rehearsal / screenshot walk  ->  .\open-demo-tabs.ps1
      2. T-2 minutes before the call  ->  .\open-demo-tabs.ps1 -StageOnly

    Save any screenshots you take into  shots\portal\  using the exact filename
    shown for that tab. build-runbook.ps1 prefers shots\portal\ over the
    generated evidence figures, so your captures survive a re-render.
#>

[CmdletBinding()]
param(
    [switch]$StageOnly
)

$ErrorActionPreference = 'Stop'

$sub      = '00000000-0000-0000-0000-000000000000'
$tenant   = 'contoso.onmicrosoft.com'
$rg       = 'rg-ahds-fhir-poc'
$apimName = 'apim-poc-ahds-demo01'
$wsName   = 'ahdspocdemo01'

$rgUrl   = "https://portal.azure.com/#@$tenant/resource/subscriptions/$sub/resourceGroups/$rg/overview"
$apimUrl = "https://portal.azure.com/#@$tenant/resource/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName"
$fhirUrl = "https://portal.azure.com/#@$tenant/resource/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.HealthcareApis/workspaces/$wsName/fhirservices/fhir-payera"

$tabs = @(
    [pscustomobject]@{
        N = 1; Url = $rgUrl; Segment = 'A'
        Blade = 'Resource group rg-ahds-fhir-poc  ->  Overview'
        Click = 'Nothing. The Overview list is the shot.'
        Look  = 'The two rows fhir-payera and fhir-payerb. That is the physical payer boundary.'
        Shot  = '01-rg-overview.png'
    }
    [pscustomobject]@{
        N = 2; Url = "$apimUrl/apis"; Segment = 'B, C, H'
        Blade = 'API Management  ->  APIs'
        Click = 'Left nav: APIs. For segment C then open "Contoso Health Plan - Outbound (payer pull)" -> All operations -> the </> policy icon.'
        Look  = 'Four APIs and the Path column: payera/inbound, payera/outbound, payerb/inbound, payerb/outbound.'
        Shot  = '02-apim-apis.png  (and 03-outbound-policy.png from the policy editor)'
    }
    [pscustomobject]@{
        N = 3; Url = "$apimUrl/namedValues"; Segment = 'D'
        Blade = 'API Management  ->  Named values'
        Click = 'Open payer-entitlements to show the JSON.'
        Look  = 'payer-entitlements and ingest-principals are NOT secret so values display. The three GUID-named ones are secret and stay hidden.'
        Shot  = '04-named-values.png'
    }
    [pscustomobject]@{
        N = 4; Url = "$apimUrl/managedIdentity"; Segment = 'E'
        Blade = 'API Management  ->  Managed identities'
        Click = 'Nothing. System assigned tab.'
        Look  = 'Status On, and the Object (principal) ID dddddddd-dddd-dddd-dddd-dddddddddddd.'
        Shot  = '05-apim-identity.png'
    }
    [pscustomobject]@{
        N = 5; Url = "$fhirUrl/users"; Segment = 'E'
        Blade = 'FHIR service fhir-payera  ->  Access control (IAM)  ->  Role assignments'
        Click = 'Role assignments tab. Filter to "This resource" so inherited noise drops away.'
        Look  = 'Exactly two: the APIM identity with FHIR Data Contributor, and your admin account. NO payer app. That absence is the whole control.'
        Shot  = '06-fhir-rbac.png'
    }
    [pscustomobject]@{
        N = 6; Url = $null; Segment = 'F'
        Blade = 'Terminal, already in the v4 folder'
        Click = 'Run  ./scripts/run-isolation-tests.ps1'
        Look  = 'Sixteen green PASS rows, ending "All 16 assertions passed."'
        Shot  = '07-test-run.png'
    }
)

Write-Host ''
Write-Host '  DEMO TAB STAGING  -  open left to right, do not reorder' -ForegroundColor Cyan
Write-Host '  ------------------------------------------------------' -ForegroundColor Cyan

foreach ($t in $tabs) {
    Write-Host ''
    Write-Host ("  TAB {0}   [segment {1}]" -f $t.N, $t.Segment) -ForegroundColor Yellow
    Write-Host ("    blade   : {0}" -f $t.Blade)
    Write-Host ("    click   : {0}" -f $t.Click)
    Write-Host ("    look for: {0}" -f $t.Look) -ForegroundColor Green
    Write-Host ("    capture : {0}" -f $t.Shot) -ForegroundColor DarkGray

    if ($t.Url) { Start-Process $t.Url; Start-Sleep -Milliseconds 900 }
}

Write-Host ''
Write-Host '  ------------------------------------------------------' -ForegroundColor Cyan
if (-not $StageOnly) {
    Write-Host '  Screenshot walk:' -ForegroundColor Cyan
    Write-Host '    Win+Shift+S to snip, save into  briefing\shots\portal\  with the'
    Write-Host '    exact filename listed above, then rebuild:'
    Write-Host ''
    Write-Host '        pwsh -NoProfile -File .\build-runbook.ps1' -ForegroundColor White
    Write-Host ''
    Write-Host '    Your captures take priority over the generated figures.'
}
Write-Host '  Set zoom to 100%, light theme, and close unrelated tabs.' -ForegroundColor DarkGray
Write-Host ''

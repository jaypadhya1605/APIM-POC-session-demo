$ErrorActionPreference = 'Stop'

# Builds the presenter runbook DOCX. Screenshots are optional: any missing shot
# renders as a labelled placeholder so the document always builds.

$briefingRoot = $PSScriptRoot
$shotsDir     = Join-Path $briefingRoot 'shots'
$evidenceDir  = Join-Path $briefingRoot 'evidence'
$outputPath   = Join-Path $briefingRoot 'Prov-APIM-Briefing-Demo-Runbook.docx'

$script:word     = $null
$script:document = $null
$script:missingShots = @()
$script:figureNumber = 0

# ---------------------------------------------------------------- environment
$env_ = [ordered]@{
    Subscription   = 'MCAPS-DataAICSA2023 - demouser-DEMO'
    SubscriptionId = '00000000-0000-0000-0000-000000000000'
    Tenant         = 'contoso.onmicrosoft.com (11111111-1111-1111-1111-111111111111)'
    ResourceGroup  = 'rg-ahds-fhir-poc'
    Region         = 'East US 2'
    Apim           = 'apim-poc-ahds-demo01'
    ApimSku        = 'Basic v2'
    Gateway        = 'https://apim-poc-ahds-demo01.azure-api.net'
    ApimIdentity   = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
    Workspace      = 'ahdspocdemo01'
    FhirPayerA     = 'https://ahdspocdemo01-fhir-payera.fhir.azurehealthcareapis.com'
    FhirPayerB     = 'https://ahdspocdemo01-fhir-payerb.fhir.azurehealthcareapis.com'
    KeyVault       = 'kv-poc-ahds-demo01'
    Storage        = 'stpocahdsdemo01'
    AppInsights    = 'appi-ahds-demo01'
}

$portalBase = 'https://portal.azure.com/#@contoso.onmicrosoft.com/resource/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ahds-fhir-poc'
$apimBase   = "$portalBase/providers/Microsoft.ApiManagement/service/apim-poc-ahds-demo01"

# ------------------------------------------------------------------- helpers
function Get-EndRange {
    $range = $script:document.Content.Duplicate
    $range.Collapse(0)
    return $range
}

function Save-FlatOpcAsDocx {
    param(
        [Parameter(Mandatory)][string]$FlatOpc,
        [Parameter(Mandatory)][string]$Path
    )

    Add-Type -AssemblyName System.IO.Compression
    $package = [System.Xml.XmlDocument]::new()
    $package.PreserveWhitespace = $true
    $package.LoadXml($FlatOpc)

    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($package.NameTable)
    $packageNamespace = 'http://schemas.microsoft.com/office/2006/xmlPackage'
    $namespaceManager.AddNamespace('pkg', $packageNamespace)

    $contentTypesNamespace = 'http://schemas.openxmlformats.org/package/2006/content-types'
    $contentTypes = [System.Xml.XmlDocument]::new()
    $typesElement = $contentTypes.CreateElement('Types', $contentTypesNamespace)
    [void]$contentTypes.AppendChild($typesElement)
    $relationshipDefault = $contentTypes.CreateElement('Default', $contentTypesNamespace)
    $relationshipDefault.SetAttribute('Extension', 'rels')
    $relationshipDefault.SetAttribute('ContentType', 'application/vnd.openxmlformats-package.relationships+xml')
    [void]$typesElement.AppendChild($relationshipDefault)
    $binaryExtensions = @{}

    foreach ($part in $package.SelectNodes('/pkg:package/pkg:part', $namespaceManager)) {
        $packagePartName = $part.GetAttribute('name', $packageNamespace)
        $packageContentType = $part.GetAttribute('contentType', $packageNamespace)
        if ($packagePartName.EndsWith('.rels', [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $binaryData = $part.SelectSingleNode('pkg:binaryData', $namespaceManager)
        if ($null -ne $binaryData) {
            $extension = [System.IO.Path]::GetExtension($packagePartName).TrimStart('.').ToLowerInvariant()
            if (-not $binaryExtensions.ContainsKey($extension)) {
                $binaryDefault = $contentTypes.CreateElement('Default', $contentTypesNamespace)
                $binaryDefault.SetAttribute('Extension', $extension)
                $binaryDefault.SetAttribute('ContentType', $packageContentType)
                [void]$typesElement.AppendChild($binaryDefault)
                $binaryExtensions[$extension] = $true
            }
            continue
        }

        $override = $contentTypes.CreateElement('Override', $contentTypesNamespace)
        $override.SetAttribute('PartName', $packagePartName)
        $override.SetAttribute('ContentType', $packageContentType)
        [void]$typesElement.AppendChild($override)
    }

    $temporaryPath = Join-Path $env:TEMP ('runbook-{0}.docx' -f [guid]::NewGuid().ToString('N'))
    $fileStream = $null
    $archive = $null
    try {
        $fileStream = [System.IO.File]::Open($temporaryPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $archive = [System.IO.Compression.ZipArchive]::new($fileStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        $utf8 = [System.Text.UTF8Encoding]::new($false)

        foreach ($part in $package.SelectNodes('/pkg:package/pkg:part', $namespaceManager)) {
            $partName = $part.GetAttribute('name', $packageNamespace).TrimStart('/')
            if ([string]::IsNullOrWhiteSpace($partName)) { continue }

            $entry = $archive.CreateEntry($partName, [System.IO.Compression.CompressionLevel]::Optimal)
            $entryStream = $entry.Open()
            try {
                $binaryData = $part.SelectSingleNode('pkg:binaryData', $namespaceManager)
                if ($null -ne $binaryData) {
                    $bytes = [Convert]::FromBase64String(($binaryData.InnerText -replace '\s', ''))
                }
                else {
                    $xmlData = $part.SelectSingleNode('pkg:xmlData', $namespaceManager)
                    if ($null -eq $xmlData) { throw "Package part has no payload: $partName" }
                    $bytes = $utf8.GetBytes($xmlData.InnerXml)
                }
                $entryStream.Write($bytes, 0, $bytes.Length)
            }
            finally { $entryStream.Dispose() }
        }

        $contentTypesEntry = $archive.CreateEntry('[Content_Types].xml', [System.IO.Compression.CompressionLevel]::Optimal)
        $contentTypesStream = $contentTypesEntry.Open()
        try {
            $contentTypesBytes = $utf8.GetBytes($contentTypes.OuterXml)
            $contentTypesStream.Write($contentTypesBytes, 0, $contentTypesBytes.Length)
        }
        finally { $contentTypesStream.Dispose() }
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
        if ($null -ne $fileStream) { $fileStream.Dispose() }
    }

    try { [System.IO.File]::Copy($temporaryPath, $Path, $true) }
    finally { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
}

function Add-Paragraph {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$Style = 'Normal',
        [bool]$Bold = $false,
        [bool]$Italic = $false,
        [int]$Alignment = 0,
        [int]$SpaceAfter = 6,
        [bool]$KeepWithNext = $false
    )

    $paragraph = $script:document.Paragraphs.Add((Get-EndRange))
    $paragraph.Range.Text = $Text
    $paragraph.Range.Style = $Style
    $paragraph.Range.Bold = if ($Bold) { -1 } else { 0 }
    $paragraph.Range.Italic = if ($Italic) { -1 } else { 0 }
    $paragraph.Format.Alignment = $Alignment
    $paragraph.Format.SpaceAfter = $SpaceAfter
    $paragraph.Format.KeepWithNext = if ($KeepWithNext) { -1 } else { 0 }
    $paragraph.Range.InsertParagraphAfter()
    return $paragraph
}

function Add-Heading {
    param(
        [Parameter(Mandatory)][string]$Text,
        [ValidateRange(1, 3)][int]$Level = 1
    )
    $null = Add-Paragraph -Text $Text -Style "Heading $Level" -SpaceAfter 8 -KeepWithNext $true
}

function Add-Bullet {
    param([Parameter(Mandatory)][string]$Text)
    $paragraph = Add-Paragraph -Text $Text -SpaceAfter 3
    $paragraph.Range.ListFormat.ApplyBulletDefault()
}

function Add-PageBreak {
    $range = Get-EndRange
    $range.InsertBreak(7)
}

function Add-Table {
    param(
        [Parameter(Mandatory)][string[]]$Headers,
        [Parameter(Mandatory)][object[]]$Rows,
        [int]$FontSize = 9,
        [int[]]$ColumnWidths = $null
    )

    $table = $script:document.Tables.Add((Get-EndRange), $Rows.Count + 1, $Headers.Count)
    try { $table.Style = 'Light Shading Accent 1' } catch { $table.Style = 'Table Grid' }
    $table.AllowAutoFit = -1
    $table.AutoFitBehavior(2)
    $table.Range.Font.Name = 'Arial'
    $table.Range.Font.Size = $FontSize
    $table.Rows.Item(1).Range.Bold = -1
    $table.Rows.Item(1).HeadingFormat = -1
    $table.Borders.Enable = 1

    for ($column = 0; $column -lt $Headers.Count; $column++) {
        $table.Cell(1, $column + 1).Range.Text = $Headers[$column]
    }
    for ($row = 0; $row -lt $Rows.Count; $row++) {
        for ($column = 0; $column -lt $Headers.Count; $column++) {
            $value = if ($column -lt $Rows[$row].Count) { [string]$Rows[$row][$column] } else { '' }
            $table.Cell($row + 2, $column + 1).Range.Text = $value
        }
    }

    if ($null -ne $ColumnWidths) {
        for ($column = 0; $column -lt $ColumnWidths.Count; $column++) {
            $table.Columns.Item($column + 1).PreferredWidthType = 3
            $table.Columns.Item($column + 1).PreferredWidth = $ColumnWidths[$column]
        }
    }

    $afterTable = $script:document.Range($table.Range.End, $table.Range.End)
    $afterTable.InsertParagraphAfter()
    return $table
}

function Add-Code {
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [int]$FontSize = 9
    )
    foreach ($line in $Lines) {
        $paragraph = Add-Paragraph -Text $line -SpaceAfter 0
        $paragraph.Range.Font.Name = 'Consolas'
        $paragraph.Range.Font.Size = $FontSize
        $paragraph.Format.LeftIndent = 18
        $paragraph.Range.Shading.BackgroundPatternColor = 15921906
    }
    $null = Add-Paragraph -Text '' -SpaceAfter 6
}

function Add-Say {
    param([Parameter(Mandatory)][string]$Text)
    $paragraph = Add-Paragraph -Text ('SAY:  ' + $Text) -SpaceAfter 8
    $paragraph.Format.LeftIndent = 18
    $paragraph.Range.Italic = -1
    $paragraph.Range.Shading.BackgroundPatternColor = 15987699
}

function Add-Do {
    param([Parameter(Mandatory)][string]$Text)
    $paragraph = Add-Paragraph -Text ('DO:  ' + $Text) -SpaceAfter 4
    $paragraph.Format.LeftIndent = 18
    $paragraph.Range.Bold = -1
}

function Add-Expect {
    param([Parameter(Mandatory)][string]$Text)
    $paragraph = Add-Paragraph -Text ('EXPECT:  ' + $Text) -SpaceAfter 8
    $paragraph.Format.LeftIndent = 18
}

function Add-Fallback {
    param([Parameter(Mandatory)][string]$Text)
    $paragraph = Add-Paragraph -Text ('IF IT FAILS:  ' + $Text) -SpaceAfter 10
    $paragraph.Format.LeftIndent = 18
    $paragraph.Range.Italic = -1
}

function Add-Screenshot {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string]$Caption
    )

    $script:figureNumber++

    # A real portal capture in shots\portal\ always wins over the generated
    # evidence figure in shots\, so re-running render-figures.ps1 can never
    # clobber a screenshot taken by hand.
    $portalPath = Join-Path (Join-Path $shotsDir 'portal') $FileName
    $path = if (Test-Path -LiteralPath $portalPath) { $portalPath } else { Join-Path $shotsDir $FileName }

    if (-not (Test-Path -LiteralPath $path)) {
        $script:missingShots += $FileName
        $placeholder = Add-Paragraph -Text ('[ screenshot placeholder - ' + $FileName + ' ]') -Alignment 1 -SpaceAfter 4
        $placeholder.Range.Font.Name = 'Consolas'
        $placeholder.Range.Font.Size = 9
        $placeholder.Range.Shading.BackgroundPatternColor = 14150650
    }
    else {
        $range = Get-EndRange
        $image = $script:document.InlineShapes.AddPicture($path, $false, $true, $range)
        $image.LockAspectRatio = -1
        # Fit inside the text column (468pt) AND inside a sensible slice of the
        # page (430pt), so a tall figure cannot push the caption onto its own page.
        if ($image.Width -gt 468) { $image.Width = 468 }
        if ($image.Height -gt 430) { $image.Height = 430 }
        $image.AlternativeText = $Caption
        $image.Range.ParagraphFormat.Alignment = 1
        $imageParagraphEnd = Get-EndRange
        $imageParagraphEnd.InsertAfter("`r")
    }

    $null = Add-Paragraph -Text ('Figure ' + $script:figureNumber + '. ' + $Caption) -Style 'Caption' -Alignment 1 -SpaceAfter 12 -KeepWithNext $false
}

# --------------------------------------------------------------------- build
try {
    $script:word = New-Object -ComObject Word.Application
    $script:word.Visible = $false
    $script:word.DisplayAlerts = 0
    $script:document = $script:word.Documents.Add()

    $section = $script:document.Sections.Item(1)
    $section.PageSetup.TopMargin = 54
    $section.PageSetup.BottomMargin = 54
    $section.PageSetup.LeftMargin = 63
    $section.PageSetup.RightMargin = 63

    $footer = $section.Footers.Item(1).Range
    $footer.Text = 'Prov - Azure APIM Briefing - Presenter Runbook    |    Microsoft Health & Life Sciences    |    Page '
    $footer.Collapse(0)
    $null = $script:document.Fields.Add($footer, 33)
    $section.Footers.Item(1).Range.Font.Size = 8
    $section.Footers.Item(1).Range.Font.Name = 'Arial'

    # ---- cover
    $title = Add-Paragraph -Text 'Prov - Azure APIM Briefing' -Style 'Title' -SpaceAfter 4
    $title.Range.Font.Size = 30
    $null = Add-Paragraph -Text 'Presenter Runbook: hands-on demo script, portal walkthrough, and narration' -Italic $true -SpaceAfter 14

    $null = Add-Table -Headers @('Field', 'Value') -Rows @(
        @('Session', 'Prov - Azure APIM Briefing (60 minutes)'),
        @('Audience', 'Northwind Health: Enterprise Architecture, Integration Engineering, Platform Engineering, Program Management, Security'),
        @('Presenter', 'Jay Padhya, Microsoft Health & Life Sciences'),
        @('Supporting', 'Steve Ordahl (FHIR), Joe Overton (account), APIM specialist (to be named)'),
        @('Companion deck', 'Prov-Azure-APIM-Briefing.pptx (17 slides, speaker notes embedded)'),
        @('Environment', $env_.ResourceGroup + '  /  ' + $env_.Region),
        @('Subscription', $env_.Subscription),
        @('Gateway', $env_.Gateway),
        @('Document built', (Get-Date -Format 'dddd, dd MMMM yyyy HH:mm'))
    ) -FontSize 9

    $null = Add-Paragraph -Text ''
    Add-Heading -Text 'How to use this runbook' -Level 2
    Add-Bullet -Text 'DO lines are the exact action: a click path, or a command to paste.'
    Add-Bullet -Text 'SAY lines are the narration. Shaded and italic. Say them close to verbatim - they are written to land the point in one pass.'
    Add-Bullet -Text 'EXPECT lines tell you what should appear, so you can tell success from failure instantly.'
    Add-Bullet -Text 'IF IT FAILS lines are the recovery. Every live step has one. Never debug in front of the room.'
    Add-Bullet -Text 'Figures are verified evidence captured live from this environment - CLI output and real policy source, rendered legibly. They are deliberately not portal screenshots: the portal chrome changes, the facts do not. Each figure carries its provenance in the footer.'
    Add-Bullet -Text 'Every portal step also gives you a deep link. Open the real blade on the projector; use the figure as your reference for what should be on screen, and as the fallback if the portal is slow or sign-in stalls.'

    $null = Add-Paragraph -Text ''
    $warning = Add-Paragraph -Text 'This demo runs against a live deployed environment. Complete the pre-flight before the call. The bulk export lock is held for 300 seconds per payer, so a warm-up run must be followed by a five minute gap before the live run.' -SpaceAfter 10
    $warning.Range.Bold = -1
    $warning.Range.Shading.BackgroundPatternColor = 13303807

    Add-PageBreak

    # ---- toc
    Add-Heading -Text 'Contents' -Level 1
    $tocRange = Get-EndRange
    $null = $script:document.TablesOfContents.Add($tocRange, $true, 1, 3)
    Add-PageBreak

    # ---- 1 preflight
    Add-Heading -Text '1. Pre-flight' -Level 1
    $null = Add-Paragraph -Text 'Three checkpoints. Do not skip the warm-up: a cold Basic v2 gateway can add several seconds to the first call, which reads as a failure in front of an audience.'

    Add-Heading -Text 'T-60 minutes - confirm the environment is alive' -Level 2
    Add-Code -Lines @(
        'cd "<repo>/CMS DQM POC/v4"',
        'az account set --subscription 00000000-0000-0000-0000-000000000000',
        './scripts/show-env.ps1'
    )
    Add-Expect -Text 'Resource names print, including apim-poc-ahds-demo01 and both FHIR services. If the resource group was deleted to save cost, rebuild now - allow about 20 minutes, almost all of it API Management.'

    Add-Heading -Text 'T-15 minutes - warm the gateway' -Level 2
    Add-Code -Lines @('./scripts/run-isolation-tests.ps1 | Out-Null')
    Add-Expect -Text 'Completes silently. This warms the gateway and pre-JITs the policy expressions.'
    Add-Fallback -Text 'If it throws, run it again without the pipe and read the error. A 401 usually means the CLI token expired - run az login and retry.'

    $null = Add-Paragraph -Text 'Then wait five minutes before the live run, or pass -SkipThrottleTest. The export concurrency lock is per payer and is held for 300 seconds; running too soon turns assertion 2 red for the wrong reason.' -SpaceAfter 10

    Add-Heading -Text 'T-2 minutes - stage the browser' -Level 2
    $null = Add-Paragraph -Text 'Open these tabs in order, left to right. You will move through them without searching.'
    $null = Add-Table -Headers @('Tab', 'Blade', 'Used in') -Rows @(
        @('1', 'Resource group overview - rg-ahds-fhir-poc', 'Segment A'),
        @('2', 'API Management - apim-poc-ahds-demo01 - APIs', 'Segments B, C, H'),
        @('3', 'API Management - Named values', 'Segment D'),
        @('4', 'API Management - Managed identities', 'Segment E'),
        @('5', 'FHIR service fhir-payera - Access control (IAM) - Role assignments', 'Segment E'),
        @('6', 'Terminal, already in the v4 folder', 'Segment F')
    ) -FontSize 9

    Add-Bullet -Text 'Set browser zoom to 100 percent and the portal to light theme. Dark theme screenshots read badly on projectors.'
    Add-Bullet -Text 'Close unrelated tabs. The subscription name is visible on screen throughout.'
    Add-Bullet -Text 'Have briefing/evidence/isolation-run.txt open in a scratch editor as the fallback for Segment F.'

    Add-PageBreak

    # ---- 2 environment
    Add-Heading -Text '2. Environment reference' -Level 1
    $null = Add-Paragraph -Text 'Every name below was verified against the live subscription while this runbook was generated. If something on screen does not match, the environment drifted - stop and reconcile before presenting.'

    $envRows = @()
    foreach ($key in $env_.Keys) { $envRows += , @($key, $env_[$key]) }
    $null = Add-Table -Headers @('Item', 'Value') -Rows $envRows -FontSize 8.5

    Add-Heading -Text 'The four APIM APIs' -Level 2
    $null = Add-Paragraph -Text 'This table is the whole inbound / outbound answer in one place. Two payers, two directions, four separately authorised routes, two backing FHIR services.'
    $null = Add-Table -Headers @('API name', 'Display name', 'Path', 'Backend') -Rows @(
        @('fhir-payera-inbound',  'Contoso Health Plan - Inbound (ingest)',       'payera/inbound',  'fhir-payera'),
        @('fhir-payera-outbound', 'Contoso Health Plan - Outbound (payer pull)',  'payera/outbound', 'fhir-payera'),
        @('fhir-payerb-inbound',  'Fabrikam Medicare Advantage - Inbound',        'payerb/inbound',  'fhir-payerb'),
        @('fhir-payerb-outbound', 'Fabrikam Medicare Advantage - Outbound',       'payerb/outbound', 'fhir-payerb')
    ) -FontSize 8.5

    Add-PageBreak

    # ---- 3 run of show
    Add-Heading -Text '3. Run of show' -Level 1
    $null = Add-Table -Headers @('Time', 'Topic', 'Slides', 'Live artefact') -Rows @(
        @('00-05', 'Objectives and scope',                        '1-2',   'none'),
        @('05-12', 'APIM in the CMS-0057-F architecture',         '3-5',   'Segment A - portal'),
        @('12-20', 'Inbound vs outbound partitioning model',      '6',     'Segment B - portal'),
        @('20-35', 'Live demo - gateway isolation tests',         '12',    'Segments C, D, E, F'),
        @('35-45', 'Policy walkthrough and debug trace',          '7-11',  'Segments G, H'),
        @('45-52', 'Payer credential and identity options',       '13',    'none'),
        @('52-58', 'Deployment options at Northwind Health',            '14-15', 'none'),
        @('58-60', 'Decisions, actions, next steps',              '16-17', 'none')
    ) -FontSize 9

    $null = Add-Paragraph -Text 'Time discipline: the live demo is the centre of gravity. If you are running late, compress the policy walkthrough (Segments G and H), never the demo.' -SpaceAfter 10

    Add-PageBreak

    # ---- 4 segments
    Add-Heading -Text '4. Demo segments' -Level 1

    # --- A
    Add-Heading -Text 'Segment A - Physical separation is real, not a diagram' -Level 2
    $null = Add-Paragraph -Text 'Goal: establish that the payer boundary is a separate FHIR service, before any policy is discussed. Two minutes.'
    Add-Do -Text 'Tab 1. Resource group rg-ahds-fhir-poc, Overview. Point at the two FHIR service rows: fhir-payera and fhir-payerb.'
    Add-Say -Text 'Before we talk about a single policy, I want you to see where the boundary actually is. Contoso and Fabrikam are not two filters over one database. They are two separate FHIR services, each with its own URL and its own access control. If every policy I show you today were deleted, Fabrikam still could not read Contoso data, because there is no route from one to the other. That is the decision this group made on the twelfth - physical where a mistake would be unrecoverable, logical where it is recoverable.'
    Add-Expect -Text 'Ten resources listed, including ahdspocdemo01/fhir-payera and ahdspocdemo01/fhir-payerb.'
    Add-Fallback -Text 'Use the environment reference table in section 2 and move on. Do not troubleshoot the portal live.'
    Add-Screenshot -FileName '01-rg-overview.png' -Caption 'Resource group rg-ahds-fhir-poc. Two FHIR services under one workspace - the physical payer boundary.'

    # --- B
    Add-Heading -Text 'Segment B - Four routes: the direction split' -Level 2
    $null = Add-Paragraph -Text 'Goal: answer the question Platform Engineering asked on the twelfth and Ashay reopened on the eighteenth. Three minutes.'
    Add-Do -Text 'Tab 2. API Management, APIs blade. Point at the four APIs, then at the Path column.'
    Add-Say -Text 'The question was: within one FHIR service, can inbound and outbound be isolated from each other - we do not want a payer querying our inbound data. The answer is yes, and here is the shape of it. One FHIR service per payer, but two APIs in front of it. Different path, different credential, different allow list. Isolation is not a property of the FHIR service. It is a property of the route. A credential entitled to the inbound route can write and import but cannot export. A credential entitled to the outbound route can export but cannot write. Neither can reach the other, because the entitlement record names the route.'
    Add-Expect -Text 'Four APIs listed with paths payera/inbound, payera/outbound, payerb/inbound, payerb/outbound.'
    Add-Screenshot -FileName '02-apim-apis.png' -Caption 'Four APIs - two payers by two directions. The direction split is a routing decision, not a data-layer feature.'

    # --- C
    Add-Heading -Text 'Segment C - The outbound policy, read top to bottom' -Level 2
    $null = Add-Paragraph -Text 'Goal: show that the controls are ordered by cost - cheapest rejection first. Four minutes. This is the segment to compress if you are behind.'
    Add-Do -Text 'Tab 2. Select Contoso Health Plan - Outbound (payer pull), then All operations, then the policy code editor icon (</>).'
    Add-Say -Text 'Six layers, and the order is deliberate - each one is cheaper than the one below it, so we reject as early as we can. Layer one, validate the token signature and audience. Layer two, resolve the calling application to the contracts it holds; if it maps to nothing, it is done here for the price of a dictionary lookup. Layer three is the route allow list - this endpoint is read only, so every write verb dies here. Layer four is scoping: a payer may only export a Group that belongs to one of its own contracts, which is what stops the open query. Layer five is rate limiting. Layer six is the part I care most about, and I will show it separately.'
    Add-Do -Text 'Scroll to the cross-payer guard block and pause on it.'
    Add-Say -Text 'This block is worth ten seconds on its own. Even if the token is completely valid and correctly audienced, if the entitlement says Contoso and the endpoint is Fabrikam, it is refused. A valid token from the wrong payer is still the wrong payer.'
    Add-Expect -Text 'Policy XML opens with validate-jwt at the top and clearly commented layer blocks.'
    Add-Fallback -Text 'The same file is in the repo at v4/apim/policies/payer-outbound.xml. Open it in the editor instead - it is the identical content with fuller comments.'
    Add-Screenshot -FileName '03-outbound-policy.png' -Caption 'The outbound policy. Layers ordered by cost: signature, entitlement, route, scope, rate, identity.'

    # --- D
    Add-Heading -Text 'Segment D - Entitlements are data, not code' -Level 2
    $null = Add-Paragraph -Text 'Goal: pre-empt the operational objection that onboarding a payer means editing policy. Two minutes.'
    Add-Do -Text 'Tab 3. Named values. Open payer-entitlements and show the JSON.'
    Add-Say -Text 'Notice that onboarding a payer is not a policy change. The entitlement map is data. Application identifier maps to a payer and a list of contracts. In production this is a cached lookup against your contract master rather than a named value, but the policy does not change - only the source of the answer does. That matters for your change control: adding a payer is a data change, not a gateway deployment.'
    Add-Expect -Text 'payer-entitlements and ingest-principals are both visible and not marked secret, so the values display.'
    Add-Screenshot -FileName '04-named-values.png' -Caption 'Entitlements held as data. Onboarding a payer is a data change, not a policy deployment. Secret named values are withheld by the platform even from an authorised reader.'

    # --- E
    Add-Heading -Text 'Segment E - Why the gateway cannot be bypassed' -Level 2
    $null = Add-Paragraph -Text 'Goal: this is the keystone control and the single most important two minutes in the session. Everything else is only as good as this.'
    Add-Do -Text 'Tab 4. API Management, Managed identities. Show the system-assigned identity is On.'
    Add-Do -Text 'Tab 5. FHIR service fhir-payera, Access control (IAM), Role assignments. Show that the APIM managed identity holds FHIR Data Contributor, and that neither payer application appears anywhere in the list.'
    Add-Say -Text 'Here is the control that makes all of this a boundary rather than a speed bump. The payer application has no Azure role on the FHIR service at all. None. Only the gateway managed identity holds the data role, and the gateway only ever uses it after every check above has passed. So if a payer takes their perfectly valid token and sends it straight to the FHIR service, skipping us entirely, they do not get a 401 - they get a 403. Entra authenticated them just fine. They simply hold no permission. That is assertion twelve in the test run, and it is the one I would put in front of your security review.'
    Add-Expect -Text 'Role assignment list shows the APIM identity with a FHIR data role and no payer application entries.'
    Add-Fallback -Text 'Assertion 12 in the live run proves the same thing empirically. Lean on that instead.'
    Add-Screenshot -FileName '05-apim-identity.png' -Caption 'The APIM system-assigned managed identity - the only principal holding a FHIR data role.'
    Add-Screenshot -FileName '06-fhir-rbac.png' -Caption 'Verified live: each FHIR service has exactly two direct role assignments - the APIM managed identity and an admin break-glass account. Both payer applications hold zero Azure role assignments anywhere in the subscription. Bypass is not blocked, it is unrepresentable.'

    Add-PageBreak

    # --- F
    Add-Heading -Text 'Segment F - The live proof run' -Level 2
    $null = Add-Paragraph -Text 'Goal: replace assertion with evidence. Six minutes including narration. This is the centrepiece.'
    Add-Do -Text 'Tab 6. Run the suite.'
    Add-Code -Lines @('./scripts/run-isolation-tests.ps1')
    Add-Say -Text 'While this runs - it is minting a short lived credential for each of two payers, exercising sixteen assertions against the live gateway, and then revoking the credentials. Nothing is written to disk. The point is that these assertions are the security guarantees themselves. If the model is wrong, this goes red in front of you.'
    Add-Expect -Text 'A green table, sixteen PASS rows, ending with "All 16 assertions passed."'
    Add-Fallback -Text 'Open briefing/evidence/isolation-run.txt and walk the captured result instead. Say plainly that you are showing a captured run - do not present it as live.'
    Add-Screenshot -FileName '07-test-run.png' -Caption 'Sixteen assertions against the live gateway.'

    $null = Add-Paragraph -Text 'Then stop on exactly three lines. Do not narrate all sixteen - you will lose the room.' -SpaceAfter 8

    $null = Add-Table -Headers @('Line', 'What to say') -Rows @(
        @('4',   'A valid, correctly audienced token from the wrong payer is refused. This is the PHI boundary, and it holds even when the token itself is entirely legitimate.'),
        @('12',  'The payer token sent directly to the FHIR service returns 403, not 401. Entra issued the token. The application simply holds no role. This is why I call the gateway a boundary and not a speed bump.'),
        @('13b', 'We inspected the response body, not just the status code. Only the caller own contracts came back - CT-3456, and not CT-7788.')
    ) -FontSize 9

    Add-Say -Text 'That is the entire argument on one screen. Physical separation between payers, logical separation between contracts, and a gateway that cannot be walked around.'

    # --- G
    Add-Heading -Text 'Segment G - Rate limiting and the service limits conversation' -Level 2
    $null = Add-Paragraph -Text 'Goal: connect the gateway to the AHDS capacity issue this group already raised. Three minutes.'
    Add-Do -Text 'Point at assertion 15 in the completed run - second export within five minutes returns 429.'
    Add-Say -Text 'This one connects to the service limits thread you have already been pulling on. The FHIR service has request throughput limits, and a payer running concurrent bulk exports is the fastest way to find them. Rather than letting a payer discover your ceiling, the gateway enforces its own: one concurrent export per payer, and a per-application request ceiling. A payer that pushes too hard gets a clean 429 with a Retry-After, not a degraded experience for everyone else. This is also why the instance count conversation and the gateway conversation are the same conversation.'
    Add-Expect -Text 'Assertion 15 shows expect 429, got 429, PASS.'

    # --- H
    Add-Heading -Text 'Segment H - The inbound policy, mirrored' -Level 2
    $null = Add-Paragraph -Text 'Goal: close the loop on the direction question. Two minutes. Compress or cut if behind.'
    Add-Do -Text 'Tab 2. Select Contoso Health Plan - Inbound (ingest), open the policy editor, scroll to the $export deny block and the contract stamping block.'
    Add-Say -Text 'The inbound route is the mirror image. Bulk export is refused outright here, so a compromised ingest credential cannot be turned into an exfiltration tool. And every write is stamped with the contract it arrived under. That stamping is what makes the outbound filter meaningful - if ingest does not tag, export cannot filter. We deliberately reject untagged writes rather than accept them, because silently untagged data is invisible to every payer and effectively lost.'
    Add-Expect -Text 'The policy shows the export deny block returning 403 and the mandatory X-Payer-Contract header check.'
    Add-Screenshot -FileName '08-inbound-policy.png' -Caption 'The inbound policy. Export denied, contract stamping mandatory.'

    Add-PageBreak

    # ---- 5 assertions
    Add-Heading -Text '5. What each assertion proves' -Level 1
    $null = Add-Paragraph -Text 'Reference for questions. You will not walk this table live, but you should be able to answer from it.'
    $null = Add-Table -Headers @('#', 'Assertion', 'Proves') -Rows @(
        @('1',   'own data readable',                   'The happy path works - a legitimate payer reads its own data.'),
        @('2',   'Group export accepted',               'CMS-0057-F bulk export works through the gateway.'),
        @('3',   'capability statement',                'Discovery endpoints stay reachable for conformance tooling.'),
        @('4',   'payer B app, valid payer A audience', 'The PHI boundary holds against a valid but wrong-payer token.'),
        @('5',   'payer B token, payer B audience',     'Audience confusion is rejected.'),
        @('6',   'unentitled Group export',             'Contract scoping - a payer cannot export another contract Group.'),
        @('7',   'write on outbound route',             'The outbound route is genuinely read only.'),
        @('8',   'payer credential on inbound route',   'Payer credentials cannot reach the ingest route.'),
        @('9',   'export on inbound route',             'Ingest credentials cannot be used to exfiltrate.'),
        @('10',  'system-level export',                 'No unscoped bulk export.'),
        @('11',  'patient-level export',                'No patient-level bulk export for payers.'),
        @('12',  'payer token straight to AHDS',        'The gateway cannot be bypassed. The keystone control.'),
        @('13',  'caller-supplied _tag overridden',     'A caller cannot widen its own scope by supplying tags.'),
        @('13b', 'body contains only own contracts',    'Response body verified, not just the status code.'),
        @('14',  'untagged inbound write rejected',     'Ingest must stamp the contract or the write is refused.'),
        @('15',  'second export within 5 min',          'Export concurrency limiting protects the FHIR service.')
    ) -FontSize 8.5

    Add-PageBreak

    # ---- 6 qa
    Add-Heading -Text '6. Anticipated questions' -Level 1
    $null = Add-Paragraph -Text 'Ordered by how likely they are to come up, based on the 12 and 18 August sessions.'

    $qa = @(
        @('Do we actually need APIM for this?',
          'Not for everything. Steve made this point on the eighteenth and it is worth repeating honestly: plan-level filtering can be done directly against the FHIR service endpoints using SMART scopes. APIM earns its place when you need contract-level scoping, inbound and outbound separation over one service, per-payer rate limiting, and a single enforcement point you can audit. If none of those apply, you do not need it.'),
        @('Why Basic v2 in the POC, and what would production be?',
          'Basic v2 is the cheapest tier that carries the full policy engine, which is all the POC needs. It does not support VNet injection. Production would be Standard v2 or Premium v2 depending on whether you need VNet integration, multi-region, and availability zones. That is one of the six decisions.'),
        @('Can we use our existing APIM estate rather than a new instance?',
          'Probably, and that is a decision for this group. The trade-off is blast radius and change control against cost and operational familiarity. If the existing estate is already in the payer network path, reusing it is likely the faster route.'),
        @('How long does it take to get an APIM instance provisioned here?',
          'Joe expects it to move faster than AHDS did, because Northwind Health already runs APIM elsewhere so it is past first-use review. Ashay estimated a couple of weeks regardless. The request needs to go to Sunil and Surya with the proxy and network team.'),
        @('What happens when a payer sends a client certificate instead of a secret?',
          'APIM can terminate and validate it. You install the trusted certificate on the instance, issue the client certificate to the payer, and validate at the gateway. This is the direction Steve recommended - it gets you off shared secrets and it is a gateway feature, not an application change.'),
        @('Where do payer identities live?',
          'Not in the Northwind Health enterprise tenant, in almost all cases. External ID gives you a separate tenant hanging off yours that keeps external parties out of your directory while still giving you Entra token issuance. Adding payers directly to the enterprise tenant is possible and makes RBAC simpler, but very few organisations want external parties in their corporate directory.'),
        @('What is the blast radius if someone makes a mistake in a policy?',
          'Bounded by the physical separation. A policy bug can leak one contract to another inside a single payer. It cannot leak Contoso data to Fabrikam, because Fabrikam credentials have no path to the Contoso FHIR service. That is precisely why the physical boundary sits at the payer.'),
        @('How do we manage policy across environments?',
          'Policies are XML in source control and deploy with the rest of the infrastructure. APIOps is the usual pattern. The named values differ per environment. That is the sixth decision - who owns the policy lifecycle.')
    )
    foreach ($pair in $qa) {
        $question = Add-Paragraph -Text ('Q.  ' + $pair[0]) -SpaceAfter 2
        $question.Range.Bold = -1
        $answer = Add-Paragraph -Text ('A.  ' + $pair[1]) -SpaceAfter 10
        $answer.Format.LeftIndent = 18
    }

    Add-PageBreak

    # ---- 7 decisions
    Add-Heading -Text '7. Decisions to close' -Level 1
    $null = Add-Paragraph -Text 'Capture the owner and the date live, on screen, in this table. A decision without a name against it did not happen.'
    $null = Add-Table -Headers @('#', 'Decision', 'Owner', 'By when') -Rows @(
        @('1', 'Dedicated APIM instance or existing Northwind Health estate', '', ''),
        @('2', 'Tier for POC and for production (VNet, multi-region, zones)', '', ''),
        @('3', 'Network mode and where the existing proxy terminates', '', ''),
        @('4', 'Payer credential type - shared secret or certificate', '', ''),
        @('5', 'Payer identity home - External ID or enterprise tenant', '', ''),
        @('6', 'Policy lifecycle ownership and promotion path', '', '')
    ) -FontSize 9

    Add-Heading -Text 'Actions' -Level 2
    $null = Add-Table -Headers @('Action', 'Owner', 'Notes') -Rows @(
        @('File the APIM provisioning request', 'Northwind Health - Ashay', 'Route to Sunil, Surya, and the proxy and network team. Names to be confirmed - the 18 August recording garbled them.'),
        @('Name the APIM specialist for the follow-up', 'Microsoft - Joe', 'Commitment made on 18 August at 1:15:09.'),
        @('Circulate deck, runbook, and policy files', 'Microsoft - Jay', 'Same day as the session.'),
        @('Confirm production tier and network mode', 'Northwind Health - Platform Engineering', 'Depends on decisions 2 and 3.')
    ) -FontSize 9

    Add-Heading -Text 'Out of scope for this session' -Level 2
    Add-Bullet -Text 'Developer portal and payer self-service onboarding'
    Add-Bullet -Text 'Monetization and quota products'
    Add-Bullet -Text 'GraphQL and AI gateway capabilities'
    Add-Bullet -Text 'APIM for non-FHIR Northwind Health workloads'

    # ---- finalise
    $script:document.TablesOfContents.Item(1).Update() | Out-Null
    $script:document.Repaginate()

    $flatOpc = $script:document.WordOpenXML
    Save-FlatOpcAsDocx -FlatOpc $flatOpc -Path $outputPath

    Write-Host ''
    Write-Host ('Runbook written: ' + $outputPath)
    Write-Host ('Figures referenced: ' + $script:figureNumber)
    if ($script:missingShots.Count -gt 0) {
        Write-Host ('Missing screenshots (placeholders inserted): ' + ($script:missingShots -join ', '))
    }
    else {
        Write-Host 'All screenshots embedded.'
    }
}
finally {
    if ($null -ne $script:document) {
        $script:document.Close($false)
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($script:document)
    }
    if ($null -ne $script:word) {
        $script:word.Quit()
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($script:word)
    }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}

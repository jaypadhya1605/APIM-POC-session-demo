<#
    render-figures.ps1
    Renders the verified evidence text files in .\evidence into presentation-quality
    PNGs in .\shots, using the exact filenames build-runbook.ps1 expects.

    These are NOT Azure portal screenshots. They are live CLI output and real policy
    source captured from rg-ahds-fhir-poc, rendered legibly. Each figure is stamped
    with its provenance so nothing in the runbook can be mistaken for a portal capture.

    Run with Windows PowerShell 5.1 (System.Drawing is guaranteed there):
        powershell.exe -NoProfile -File .\render-figures.ps1
#>

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$evidence = Join-Path $root 'evidence'
$shots    = Join-Path $root 'shots'
New-Item -ItemType Directory -Force -Path $shots | Out-Null

# 2x render scale so the images stay crisp when Word scales them to ~6.5in.
$fontSize  = 26
$titleSize = 30
$subSize   = 20
$footSize  = 17
$lineH     = 36
$padX      = 44
$padY      = 34
$headerH   = 104

$accent    = [System.Drawing.ColorTranslator]::FromHtml('#0F5C9E')
$inkColor  = [System.Drawing.ColorTranslator]::FromHtml('#1A1A1A')
$hiColor   = [System.Drawing.ColorTranslator]::FromHtml('#B00020')
$dimColor  = [System.Drawing.ColorTranslator]::FromHtml('#6B6B6B')
$ruleColor = [System.Drawing.ColorTranslator]::FromHtml('#D8D8D8')

$mono      = New-Object System.Drawing.Font('Consolas', $fontSize, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$monoBold  = New-Object System.Drawing.Font('Consolas', $fontSize, [System.Drawing.FontStyle]::Bold,    [System.Drawing.GraphicsUnit]::Pixel)
$titleFont = New-Object System.Drawing.Font('Segoe UI', $titleSize, [System.Drawing.FontStyle]::Bold,   [System.Drawing.GraphicsUnit]::Pixel)
$subFont   = New-Object System.Drawing.Font('Segoe UI', $subSize,  [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$footFont  = New-Object System.Drawing.Font('Segoe UI', $footSize, [System.Drawing.FontStyle]::Italic,  [System.Drawing.GraphicsUnit]::Pixel)

$fmt = [System.Drawing.StringFormat]::GenericTypographic.Clone()
$fmt.FormatFlags = $fmt.FormatFlags -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces

function Get-CleanLines {
    param([string]$Path)
    $raw = (Get-Content -LiteralPath $Path -Raw) -replace "`r", ''
    $raw = $raw -replace "`n{3,}", "`n`n"          # collapse runaway blank lines
    return ($raw.TrimEnd() -split "`n")
}

function New-Figure {
    param(
        [string[]]$Lines,
        [string]$Title,
        [string]$Subtitle,
        [string]$Footer,
        [string]$OutFile
    )

    # --- measure ----------------------------------------------------------
    $probe = New-Object System.Drawing.Bitmap 8, 8
    $pg    = [System.Drawing.Graphics]::FromImage($probe)
    $pg.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $maxW = 0.0
    foreach ($l in $Lines) {
        if ([string]::IsNullOrEmpty($l)) { continue }
        $w = $pg.MeasureString($l, $mono, [int]4000, $fmt).Width
        if ($w -gt $maxW) { $maxW = $w }
    }
    $tW = $pg.MeasureString($Title,    $titleFont, [int]4000, $fmt).Width
    $sW = $pg.MeasureString($Subtitle, $subFont,   [int]4000, $fmt).Width
    foreach ($w in @($tW, $sW)) { if ($w -gt $maxW) { $maxW = $w } }
    $pg.Dispose(); $probe.Dispose()

    $imgW = [int]([Math]::Ceiling($maxW) + ($padX * 2) + 16)
    $imgH = [int]($headerH + $padY + ($Lines.Count * $lineH) + $padY + 46)

    # --- draw -------------------------------------------------------------
    $bmp = New-Object System.Drawing.Bitmap $imgW, $imgH
    $bmp.SetResolution(192, 192)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::White)

    $headerBrush = New-Object System.Drawing.SolidBrush $accent
    $g.FillRectangle($headerBrush, 0, 0, $imgW, $headerH)

    $whiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $g.DrawString($Title, $titleFont, $whiteBrush, [single]$padX, [single]18, $fmt)
    $paleBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(226, 238, 250))
    $g.DrawString($Subtitle, $subFont, $paleBrush, [single]$padX, [single](18 + $titleSize + 12), $fmt)

    $inkBrush = New-Object System.Drawing.SolidBrush $inkColor
    $hiBrush  = New-Object System.Drawing.SolidBrush $hiColor
    $dimBrush = New-Object System.Drawing.SolidBrush $dimColor

    $y = $headerH + $padY
    foreach ($l in $Lines) {
        if (-not [string]::IsNullOrWhiteSpace($l)) {
            $brush = $inkBrush
            $font  = $mono
            if ($l -match '<===|<---|\bZERO\b|<- APIM|<== ') { $brush = $hiBrush; $font = $monoBold }
            elseif ($l -match '^-{5,}$|^\s*-{20,}') { $brush = $dimBrush }
            elseif ($l -match '^[A-Z0-9][A-Z0-9 ,.:()/$_''-]{6,}$') { $font = $monoBold }
            $g.DrawString($l, $font, $brush, [single]$padX, [single]$y, $fmt)
        }
        $y += $lineH
    }

    $pen = New-Object System.Drawing.Pen $ruleColor, 2
    $g.DrawLine($pen, [single]$padX, [single]($imgH - 44), [single]($imgW - $padX), [single]($imgH - 44))
    $g.DrawString($Footer, $footFont, $dimBrush, [single]$padX, [single]($imgH - 34), $fmt)

    $borderPen = New-Object System.Drawing.Pen $ruleColor, 2
    $g.DrawRectangle($borderPen, 1, 1, $imgW - 3, $imgH - 3)

    $bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)

    foreach ($d in @($headerBrush, $whiteBrush, $paleBrush, $inkBrush, $hiBrush, $dimBrush, $pen, $borderPen, $g, $bmp)) {
        if ($d) { $d.Dispose() }
    }
    return @{ W = $imgW; H = $imgH }
}

$stamp = Get-Date -Format 'yyyy-MM-dd'
$prov  = "Captured live from rg-ahds-fhir-poc on $stamp. CLI output / policy source - not an Azure portal screenshot."

$figures = @(
    @{ src='fig01-resources.txt';       out='01-rg-overview.png';     t='Resource group: rg-ahds-fhir-poc';           s='az resource list  |  subscription 00000000  |  East US 2' }
    @{ src='fig02-apis.txt';            out='02-apim-apis.png';       t='APIM: four separately governed routes';      s='az apim api list  |  apim-poc-ahds-demo01 (BasicV2)' }
    @{ src='fig03-outbound-policy.txt'; out='03-outbound-policy.png'; t='Outbound policy: entitlement + payer guard'; s='Layer 2 of 6  |  proves assertion 4 (wrong-payer 403)' }
    @{ src='fig04-named-values.txt';    out='04-named-values.png';    t='Named values: the entitlement map';          s='Secrets are flagged secret:True and withheld by the API' }
    @{ src='fig05-identity.txt';        out='05-apim-identity.png';   t='APIM system-assigned managed identity';      s='The only principal permitted to reach FHIR data' }
    @{ src='fig06-rbac.txt';            out='06-fhir-rbac.png';       t='RBAC proof: payers hold zero Azure roles';   s='The keystone control  |  proves assertion 12 (direct 403)' }
    @{ src='isolation-run.txt';         out='07-test-run.png';        t='Isolation suite: 16 of 16 assertions PASS';  s='scripts\run-isolation-tests.ps1  |  reproduced twice' }
    @{ src='fig08-inbound-policy.txt';  out='08-inbound-policy.png';  t='Inbound policy: $export deny + stamping';    s='Ingest stamps the contract; export filters on it' }
)

$made = 0
foreach ($f in $figures) {
    $srcPath = Join-Path $evidence $f.src
    if (-not (Test-Path -LiteralPath $srcPath)) {
        Write-Warning ("missing evidence source: {0}" -f $f.src)
        continue
    }
    $lines   = Get-CleanLines -Path $srcPath
    $outPath = Join-Path $shots $f.out
    $dim = New-Figure -Lines $lines -Title $f.t -Subtitle $f.s -Footer $prov -OutFile $outPath
    '  {0,-24} {1,4} x {2,4} px   <- {3}' -f $f.out, $dim.W, $dim.H, $f.src
    $made++
}

foreach ($d in @($mono, $monoBold, $titleFont, $subFont, $footFont)) { $d.Dispose() }
Write-Host ''
Write-Host ("rendered {0} of {1} figures into {2}" -f $made, $figures.Count, $shots)

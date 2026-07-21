# rename-hub.ps1
# Rename a Maps hub everywhere: vault wikilinks, hub note file, and all SSOT-derived docs.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File "rename-hub.ps1" -OldName "English Journal" -NewName "Eng Study"
#   powershell -ExecutionPolicy Bypass -File "rename-hub.ps1" -OldName "X" -NewName "Y" -DryRun
#
# Covers (auto):
#   1. [[OldName]] / [[OldName|alias]] / [[OldName#heading]] across the whole vault
#   2. 000_Maps/OldName.md  ->  NewName.md  (+ title frontmatter & # heading inside)
#   3. validate-config.json  hubList entry
#   4. CLAUDE.md / SKILL.md / Ontology guide  backtick `OldName` -> `NewName`
# Manual (warned): n8n "Build Claude Body" system prompt.

param(
    [Parameter(Mandatory=$true)][string]$OldName,
    [Parameter(Mandatory=$true)][string]$NewName,
    # Path to your Obsidian vault. Defaults to the OBSIDIAN_VAULT env var.
    [string]$VaultPath = $env:OBSIDIAN_VAULT,
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "config\ontology.json"),
    # Optional: extra docs (agent instructions, guides) where `OldName` should also be replaced.
    [string[]]$DerivedDocs = @(),
    [switch]$DryRun
)

if ([string]::IsNullOrWhiteSpace($VaultPath)) {
    Write-Host "ERROR: vault path not set." -ForegroundColor Red
    Write-Host '  Pass -VaultPath "C:\path\to\vault", or set $env:OBSIDIAN_VAULT' -ForegroundColor Yellow
    exit 1
}

$vaultPath  = $VaultPath
$configPath = $ConfigPath
# Derived docs are optional in the open-source template (personal agent files stay local).
$claudePath = if ($DerivedDocs.Count -ge 1) { $DerivedDocs[0] } else { $null }
$guidePath  = if ($DerivedDocs.Count -ge 2) { $DerivedDocs[1] } else { $null }
$skillPath  = if ($DerivedDocs.Count -ge 3) { $DerivedDocs[2] } else { $null }
$mapsPath   = Join-Path $vaultPath "000_Maps"

$enc = [System.Text.Encoding]::UTF8

function Read-Utf8  { param([string]$p) [System.IO.File]::ReadAllText($p, $enc) }
function Write-Utf8 { param([string]$p,[string]$t) [System.IO.File]::WriteAllText($p, $t, $enc) }

# ── Header ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
$mode = if ($DryRun) { "[DRY RUN]" } else { "[LIVE]" }
Write-Host "  Hub Rename  $mode" -ForegroundColor Cyan
Write-Host "  '$OldName'  ->  '$NewName'" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ── Guard: validate against SSOT ──────────────────────────────────────────
$config  = Read-Utf8 $configPath | ConvertFrom-Json
$hubList = @($config.hubList)
if ($hubList -notcontains $OldName) {
    Write-Host "[ABORT] '$OldName' is not in hubList. Nothing to rename." -ForegroundColor Red
    exit 1
}
if ($hubList -contains $NewName) {
    Write-Host "[ABORT] '$NewName' already exists in hubList. Pick another name." -ForegroundColor Red
    exit 1
}

$oldEsc = [regex]::Escape($OldName)

# ════════════════════════════════════════════════════════════════════════════
# STEP 1  Vault wikilinks: [[OldName]] / [[OldName|...]] / [[OldName#...]]
# ════════════════════════════════════════════════════════════════════════════
Write-Host "[1] Vault wikilinks..." -ForegroundColor White
# match the OldName immediately after [[ when followed by ]] , | or #
$wikiPattern = '\[\[' + $oldEsc + '(?=[\]\|#])'
$wikiRepl    = '[[' + $NewName

$allMd = Get-ChildItem -Path $vaultPath -Recurse -Filter "*.md"
$wikiFiles = 0; $wikiHits = 0
foreach ($f in $allMd) {
    $raw = Read-Utf8 $f.FullName
    $m   = [regex]::Matches($raw, $wikiPattern)
    if ($m.Count -gt 0) {
        $wikiFiles++; $wikiHits += $m.Count
        $rel = $f.FullName.Replace($vaultPath + "\", "")
        Write-Host "    $rel  ($($m.Count))" -ForegroundColor Yellow
        if (-not $DryRun) {
            $new = [regex]::Replace($raw, $wikiPattern, $wikiRepl)
            Write-Utf8 $f.FullName $new
        }
    }
}
Write-Host "    -> $wikiHits links in $wikiFiles files" -ForegroundColor Green
Write-Host ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 2  Hub note file rename + internal title/heading
# ════════════════════════════════════════════════════════════════════════════
Write-Host "[2] Hub note file..." -ForegroundColor White
$oldFile = Join-Path $mapsPath "$OldName.md"
$newFile = Join-Path $mapsPath "$NewName.md"
if (Test-Path $oldFile) {
    if (-not $DryRun) {
        $hub = Read-Utf8 $oldFile
        $hub = $hub -replace ('title:\s*"?' + $oldEsc + '"?'), "title: `"$NewName`""
        $hub = $hub -replace ('^#\s+' + $oldEsc + '\s*$'), "# $NewName"
        Write-Utf8 $oldFile $hub
        Move-Item -LiteralPath $oldFile -Destination $newFile -Force
    }
    Write-Host "    000_Maps/$OldName.md -> $NewName.md (+ title/heading)" -ForegroundColor Green
} else {
    Write-Host "    [WARN] hub note not found: $oldFile" -ForegroundColor Yellow
}
Write-Host ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 3  validate-config.json hubList entry
# ════════════════════════════════════════════════════════════════════════════
Write-Host "[3] validate-config.json hubList..." -ForegroundColor White
$cfgRaw = Read-Utf8 $configPath
# scope replacement to the hubList [ ... ] block so we never touch other values
$listBlockPattern = '("hubList"\s*:\s*\[)(.*?)(\])'
$cfgRaw2 = [regex]::Replace($cfgRaw, $listBlockPattern, {
    param($mm)
    $body = $mm.Groups[2].Value -replace ('"' + $oldEsc + '"'), "`"$NewName`""
    $mm.Groups[1].Value + $body + $mm.Groups[3].Value
}, [System.Text.RegularExpressions.RegexOptions]::Singleline)
if ($cfgRaw2 -ne $cfgRaw) {
    if (-not $DryRun) { Write-Utf8 $configPath $cfgRaw2 }
    Write-Host "    hubList: '$OldName' -> '$NewName'" -ForegroundColor Green
} else {
    Write-Host "    [WARN] no hubList entry changed" -ForegroundColor Yellow
}
Write-Host ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 4  Backtick `OldName` in CLAUDE.md / SKILL.md / Ontology guide
# ════════════════════════════════════════════════════════════════════════════
Write-Host "[4] Backtick references in derived docs..." -ForegroundColor White
$bt        = [char]0x60
$btOld     = "$bt$OldName$bt"
$btNew     = "$bt$NewName$bt"
$btTargets = @(
    @{ Path = $claudePath; Label = "Derived doc 1" },
    @{ Path = $skillPath;  Label = "Derived doc 3" },
    @{ Path = $guidePath;  Label = "Derived doc 2" }
) | Where-Object { $_.Path }   # -DerivedDocs is optional; skip unset slots
foreach ($t in $btTargets) {
    if (-not (Test-Path $t.Path)) {
        Write-Host "    [WARN] $($t.Label) not found" -ForegroundColor Yellow
        continue
    }
    $raw = Read-Utf8 $t.Path
    $cnt = ([regex]::Matches($raw, [regex]::Escape($btOld))).Count
    if ($cnt -gt 0) {
        if (-not $DryRun) { Write-Utf8 $t.Path ($raw.Replace($btOld, $btNew)) }
        Write-Host "    $($t.Label): $cnt replaced" -ForegroundColor Green
    } else {
        Write-Host "    $($t.Label): no match" -ForegroundColor DarkGray
    }
}
Write-Host ""

# ════════════════════════════════════════════════════════════════════════════
# Summary + manual reminder
# ════════════════════════════════════════════════════════════════════════════
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Done $mode" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Wikilinks: $wikiHits in $wikiFiles files"
Write-Host ""
Write-Host "  MANUAL: update n8n 'Build Claude Body' system prompt hub list" -ForegroundColor Yellow
Write-Host "  TIP:    run sync-ontology.ps1 to re-verify hub-list lines"     -ForegroundColor DarkGray
if ($DryRun) {
    Write-Host ""
    Write-Host "  * DRY RUN -- no files were modified" -ForegroundColor DarkYellow
}
Write-Host ""

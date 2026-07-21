# sync-ontology.ps1
# SSOT sync: validate-config.json -> SKILL.md hub list + all vault note Dataview queries
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File "sync-ontology.ps1"          # live run
#   powershell -ExecutionPolicy Bypass -File "sync-ontology.ps1" -DryRun  # preview only

param(
    # Path to your Obsidian vault. Defaults to the OBSIDIAN_VAULT env var.
    [string]$VaultPath = $env:OBSIDIAN_VAULT,
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "config\ontology.json"),
    # Optional: agent instruction files whose hub list should be kept in sync.
    # Leave empty to skip. Example: -DerivedDocs @("C:\...\SKILL.md", "C:\...\CLAUDE.md")
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
$skillPath  = if ($DerivedDocs.Count -ge 1) { $DerivedDocs[0] } else { $null }
$claudePath = if ($DerivedDocs.Count -ge 2) { $DerivedDocs[1] } else { $null }

# ── Load config ───────────────────────────────────────────────────────────
$config   = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$hubList  = @($config.hubList)
# All relation types across buckets (invest/biz/default), deduped; 'related' stays last (fallback)
$allTypes = @($config.validRelationTypes.PSObject.Properties | ForEach-Object { $_.Value }) | Select-Object -Unique
$relTypes = @($allTypes | Where-Object { $_ -ne "related" }) + @("related")

# ── Dataview choice() chain builder ───────────────────────────────────────
function Build-ChoiceChain {
    param([string[]]$types, [string]$direction, [int]$baseIndent)
    $n = $types.Count; $lines = @()
    for ($i = 0; $i -lt ($n - 1); $i++) {
        $t   = $types[$i]
        $pad = " " * ($baseIndent + $i * 2)
        if ($direction -eq "out") {
            $cond = "contains(list(this.$t), file.link)"
        } else {
            $cond = "contains(list(file.$t), this.file.link)"
        }
        $lines += "${pad}choice($cond, `"$t`","
    }
    $fallbackPad = " " * ($baseIndent + ($n - 1) * 2)
    $closes      = ')' * ($n - 1)
    $lines      += "${fallbackPad}`"$($types[-1])`"$closes"
    return ($lines -join "`n")
}

function Build-DataviewBlock {
    param([string[]]$types)
    $nl       = "`n"
    $outChain = Build-ChoiceChain -types $types -direction "out" -baseIndent 4
    $inChain  = Build-ChoiceChain -types $types -direction "in"  -baseIndent 4
    return (
        '```dataview' + $nl +
        'TABLE file.folder AS "Folder",' + $nl +
        '  choice(' + $nl +
        '    contains(this.file.outlinks, file.link),' + $nl +
        $outChain + ',' + $nl +
        $inChain + $nl +
        '  ) AS "Relation",' + $nl +
        '  updated AS "Updated"' + $nl +
        'FROM ""' + $nl +
        'WHERE file.path != this.file.path AND (' + $nl +
        '  contains(this.file.outlinks, file.link) OR' + $nl +
        '  contains(this.file.inlinks, file.link)' + $nl +
        ')' + $nl +
        'SORT updated DESC' + $nl +
        '```'
    )
}

# ── Hub-list line sync (SKILL.md / CLAUDE.md share the same shape) ─────────
# Both files have a header line containing "(<count>)" followed (within a few
# lines) by a backtick-wrapped, middle-dot-separated hub list. This function
# rewrites both the count and the list from the SSOT hubList.
function Sync-HubListFile {
    param(
        [string]$Path,
        [string]$HeaderRegex,   # must capture the count in group 1
        [string]$Label,
        [string[]]$HubList,
        [switch]$DryRun
    )
    if (-not (Test-Path $Path)) {
        Write-Host "  [WARN] $Label not found: $Path" -ForegroundColor Yellow
        return 0
    }
    $dot        = [char]0x00B7
    $newHubLine = ($HubList | ForEach-Object { "``$_``" }) -join " $dot "
    $newCount   = $HubList.Count

    $raw   = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $lines = $raw -split "`n"

    # locate header line (carries the count)
    $hdrIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $HeaderRegex) { $hdrIdx = $i; break }
    }
    if ($hdrIdx -eq -1) {
        Write-Host "  [WARN] ${Label}: header not found (regex: $HeaderRegex)" -ForegroundColor Yellow
        return 0
    }
    $oldCount = 0
    if ($lines[$hdrIdx] -match $HeaderRegex) { $oldCount = [int]$Matches[1] }

    # hub list = first backtick-leading line within 5 lines after header
    # (use StartsWith with the literal backtick char; -like would treat ` as an escape)
    $backtick = [char]0x60
    $listIdx  = -1
    $limit    = [Math]::Min($hdrIdx + 6, $lines.Count)
    for ($j = $hdrIdx + 1; $j -lt $limit; $j++) {
        if ($lines[$j].TrimStart().StartsWith($backtick)) { $listIdx = $j; break }
    }
    if ($listIdx -eq -1) {
        Write-Host "  [WARN] ${Label}: hub list line not found after header" -ForegroundColor Yellow
        return 0
    }
    $oldHubListLine = $lines[$listIdx].TrimEnd("`r")

    if (($oldHubListLine -eq $newHubLine) -and ($oldCount -eq $newCount)) {
        Write-Host "  $Label hub list: unchanged ($newCount hubs)" -ForegroundColor Green
        return 0
    }

    Write-Host "  $Label OLD ($oldCount): $oldHubListLine" -ForegroundColor Yellow
    Write-Host "  $Label NEW ($newCount): $newHubLine"     -ForegroundColor Green

    if (-not $DryRun) {
        $lines[$hdrIdx]  = $lines[$hdrIdx] -replace '\(\d+', "($newCount"
        $lines[$listIdx] = $newHubLine
        [System.IO.File]::WriteAllText($Path, ($lines -join "`n"), [System.Text.Encoding]::UTF8)
        Write-Host "  ${Label}: updated" -ForegroundColor Green
    } else {
        Write-Host "  [DRY RUN] would update $Label" -ForegroundColor DarkYellow
    }
    return 1
}

$newDataviewBlock = Build-DataviewBlock -types $relTypes
$n                = $hubList.Count

# ── Header ───────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "  Ontology Sync  [DRY RUN]              " -ForegroundColor Cyan
} else {
    Write-Host "  Ontology Sync  [LIVE]                 " -ForegroundColor Cyan
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$totalUpdated = 0

# ════════════════════════════════════════════════════════════════════════════
# PART A  Hub list lines in SKILL.md + CLAUDE.md
# ════════════════════════════════════════════════════════════════════════════
if ($skillPath -or $claudePath) {
    Write-Host "[ Hub lists ] Syncing derived agent docs..." -ForegroundColor White

    # Expected header shape:  "Current Maps hubs (22):"
    if ($skillPath) {
        $totalUpdated += Sync-HubListFile -Path $skillPath `
            -HeaderRegex '^Current Maps hubs \((\d+)' -Label "SKILL.md" `
            -HubList $hubList -DryRun:$DryRun
    }

    # Expected header shape: "## Current 000_Maps hubs (22)"  (matched via ASCII 000_Maps + count)
    if ($claudePath) {
        $totalUpdated += Sync-HubListFile -Path $claudePath `
            -HeaderRegex '000_Maps.*\((\d+)' -Label "CLAUDE.md" `
            -HubList $hubList -DryRun:$DryRun
    }
} else {
    Write-Host "[ Hub lists ] Skipped (no -DerivedDocs given)." -ForegroundColor DarkGray
}

Write-Host ""

# ════════════════════════════════════════════════════════════════════════════
# PART B  Vault notes: sync ## Related Notes Dataview blocks
# ════════════════════════════════════════════════════════════════════════════
Write-Host "[ Vault Notes ] Syncing Related Notes Dataview blocks..." -ForegroundColor White

# 99_Templates is intentionally NOT skipped: the template's Related Notes block is
# the canonical copy that weekly-review points to, so sync must keep it stamped.
$skipFolders = @("000_Maps", "00_System", "97_Obsidian Tips", "98_Screenshots", "4_Archives")

$files = Get-ChildItem -Path $vaultPath -Recurse -Filter "*.md" | Where-Object {
    $skip = $false
    foreach ($folder in $skipFolders) {
        if ($_.FullName -like "*\$folder\*" -or $_.Name -eq $folder) {
            $skip = $true; break
        }
    }
    -not $skip
}

$noteUpdated   = 0
$noteUnchanged = 0
$noteSkipped   = 0   # no ## Related Notes section (expected for many notes)
$noteMalformed = 0   # section exists but the dataview block did not match - silent-failure guard

# Pattern: ```dataview block immediately following ## Related Notes
# The block ends at closing ``` on its own line
$blockPattern = '(?s)(## Related Notes\s*\r?\n\s*\r?\n)(```dataview.*?```)'

foreach ($file in $files) {
    $raw = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)

    if ($raw -notmatch '## Related Notes') {
        $noteSkipped++
        continue
    }

    if ($raw -match $blockPattern) {
        $fullMatch   = $Matches[0]
        $prefix      = $Matches[1]
        $oldBlock    = $Matches[2]

        if ($oldBlock -eq $newDataviewBlock) {
            $noteUnchanged++
            continue
        }

        $rel = $file.FullName.Replace($vaultPath + "\", "")
        Write-Host "  UPDATE: $rel" -ForegroundColor Yellow

        if (-not $DryRun) {
            $replacement = $prefix + $newDataviewBlock
            $newRaw = $raw.Replace($fullMatch, $replacement)
            [System.IO.File]::WriteAllText($file.FullName, $newRaw, [System.Text.Encoding]::UTF8)
        }
        $noteUpdated++
    } else {
        # Section present but dataview block unmatched -> count separately and print the file, so this never fails silently
        $rel = $file.FullName.Replace($vaultPath + "\", "")
        Write-Host "  [MALFORMED] $rel  (has ## Related Notes but the dataview block did not match the expected pattern - check manually)" -ForegroundColor Red
        $noteMalformed++
    }
}

$totalUpdated += $noteUpdated

# ════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Hub count:       $n hubs"
Write-Host "  Notes updated:   $noteUpdated"   -ForegroundColor $(if ($noteUpdated   -gt 0) { "Green" } else { "White" })
Write-Host "  Notes unchanged: $noteUnchanged" -ForegroundColor White
Write-Host "  Notes skipped:   $noteSkipped  (no ## Related Notes section)" -ForegroundColor DarkGray
Write-Host "  Notes malformed: $noteMalformed  (## Related Notes present but block unmatched)" -ForegroundColor $(if ($noteMalformed -gt 0) { "Red" } else { "DarkGray" })
if ($DryRun) {
    Write-Host ""
    Write-Host "  * DRY RUN -- no files were modified" -ForegroundColor DarkYellow
}
Write-Host ""

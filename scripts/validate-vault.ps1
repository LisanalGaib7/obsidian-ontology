# Obsidian Vault Frontmatter Validator + Auto-Fixer
# Usage:
#   powershell -ExecutionPolicy Bypass -File "validate-vault.ps1"           # detect only
#   powershell -ExecutionPolicy Bypass -File "validate-vault.ps1" -AutoFix  # detect + fix

param(
    # Path to your Obsidian vault. Defaults to the OBSIDIAN_VAULT env var.
    [string]$VaultPath = $env:OBSIDIAN_VAULT,
    # Path to the ontology SSOT. Defaults to ../config/ontology.json next to this script.
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "config\ontology.json"),
    [switch]$AutoFix
)

if ([string]::IsNullOrWhiteSpace($VaultPath)) {
    Write-Host "ERROR: vault path not set." -ForegroundColor Red
    Write-Host '  Pass -VaultPath "C:\path\to\vault", or set $env:OBSIDIAN_VAULT' -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path $VaultPath)) { Write-Host "ERROR: vault not found: $VaultPath" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $ConfigPath)) { Write-Host "ERROR: config not found: $ConfigPath" -ForegroundColor Red; exit 1 }

$vaultPath     = $VaultPath
$configPath    = $ConfigPath

# === Load Korean data from JSON (UTF-8 read - no BOM needed for data files) ===
$config        = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$validSectors  = $config.validSectors
$validIndustries = @{}
$config.validIndustries.PSObject.Properties | ForEach-Object {
    $validIndustries[$_.Name] = @($_.Value)
}
$fallbackSector = $validSectors[-1]   # last entry is the catch-all bucket ("Other")
$validRelTypesInvest  = @($config.validRelationTypes.invest)
$validRelTypesBiz     = @($config.validRelationTypes.biz)
$validRelTypesDefault = @($config.validRelationTypes.default)
$hubList              = @($config.hubList)
$validDomains         = @($config.validDomains)
$validSources         = @($config.validSources)

# === Valid para_types ===
$validParaTypes = @("project", "area", "resource", "archive", "zk")

# === para_type -> expected folder (from config SSOT) ===
$paraTypeToFolder = @{}
$config.folderMap.PSObject.Properties | ForEach-Object {
    $paraTypeToFolder[$_.Name] = $_.Value
}

# === Dataview choice() chain builder ===
function Build-ChoiceChain {
    param(
        [string[]]$types,
        [string]$direction,
        [int]$baseIndent
    )
    $n     = $types.Count
    $lines = @()
    for ($i = 0; $i -lt ($n - 1); $i++) {
        $t   = $types[$i]
        $pad = " " * ($baseIndent + $i * 2)
        if ($direction -eq "out") {
            $cond = "length(filter(list(this.$t), (l) => contains(string(l), file.name))) > 0"
        } else {
            $cond = "length(filter(list(file.$t), (l) => contains(string(l), this.file.name))) > 0"
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

# === Related Notes Dataview block (generated from config) ===
$nl = "`n"
$relatedNotesBlock = $nl + $nl + "---" + $nl + $nl + "## Related Notes" + $nl + $nl +
    (Build-DataviewBlock -types $validRelTypesInvest) + $nl

# === Skip Folders ===
$skipFolders = @("000_Maps", "00_System", "99_Templates", "97_Obsidian Tips", "98_Screenshots", "4_Archives")

# === Helpers ===
function Parse-Frontmatter($rawContent) {
    $fm = @{}
    if ($rawContent -notmatch "(?s)^---`r?`n(.+?)`r?`n---") { return $fm }
    $block = $Matches[1]
    $lines = $block -split "`r?`n"
    $i = 0
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        if ($line -match "^([\w\-]+):\s*(.*)$") {
            $key = $Matches[1].Trim()
            $val = $Matches[2].Trim()
            if ($val -eq "") {
                $listItems = @()
                $j = $i + 1
                while ($j -lt $lines.Count -and $lines[$j] -match "^\s+-\s+(.+)$") {
                    $listItems += $Matches[1].Trim().Trim('"')
                    $j++
                }
                if ($listItems.Count -gt 0) {
                    $fm[$key] = "[" + ($listItems -join ", ") + "]"
                    $i = $j
                    continue
                }
            }
            $fm[$key] = $val
        }
        $i++
    }
    return $fm
}

function Set-FrontmatterField($filePath, $rawContent, $field, $newValue) {
    if ($rawContent -match "(?m)^($field\s*:).*$") {
        $newContent = $rawContent -replace "(?m)^($field\s*:).*$", "`${1} $newValue"
        $newContent | Out-File -FilePath $filePath -Encoding UTF8 -NoNewline
        return $true
    }
    return $false
}

function Add-FrontmatterField($filePath, $rawContent, $field, $value) {
    if ($rawContent -match "(?s)(^---`r?`n.+?`r?`n)(---)") {
        $newContent = $rawContent -replace "(?s)(^---`r?`n.+?`r?`n)(---)", "`${1}${field}: ${value}`n`${2}"
        $newContent | Out-File -FilePath $filePath -Encoding UTF8 -NoNewline
        return $true
    }
    return $false
}

# === Main ===
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($AutoFix) {
    Write-Host "  Vault Validator + Auto-Fixer          " -ForegroundColor Cyan
} else {
    Write-Host "  Obsidian Vault Frontmatter Validator  " -ForegroundColor Cyan
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$files = Get-ChildItem -Path $vaultPath -Recurse -Filter "*.md" | Where-Object {
    $skip = $false
    foreach ($folder in $skipFolders) {
        if ($_.FullName -like "*\$folder\*" -or $_.Name -eq $folder) {
            $skip = $true; break
        }
    }
    -not $skip
}

# === Set of every note name in the vault (for dangling-link detection; includes skip folders such as 000_Maps) ===
# === + inbound link index (for orphan detection; every name referenced as [[link]] anywhere in the vault) ===
$allNoteNames   = New-Object System.Collections.Generic.HashSet[string]
$inboundTargets = New-Object System.Collections.Generic.HashSet[string]
$wikilinkRegex  = [regex]'\[\[([^\]]+)\]\]'
Get-ChildItem -Path $vaultPath -Recurse -Filter "*.md" | Where-Object { $_.FullName -notlike "*\.obsidian\*" } | ForEach-Object {
    [void]$allNoteNames.Add($_.BaseName)
    $c = Get-Content $_.FullName -Raw -Encoding UTF8
    foreach ($m in $wikilinkRegex.Matches($c)) {
        $t = ($m.Groups[1].Value -split '\|')[0]
        $t = ($t -split '#')[0]
        $t = ($t -split '[\\/]')[-1].Trim()
        if ($t -ne "") { [void]$inboundTargets.Add($t) }
    }
}
$attachmentPattern = '\.(png|jpe?g|gif|webp|svg|pdf|mp4|mov|xlsx?|docx?|pptx?)$'

$totalFiles = $files.Count
$errorCount = 0
$warnCount  = 0
$cleanCount = 0
$fixCount   = 0

foreach ($file in $files) {
    $rawContent = Get-Content $file.FullName -Raw -Encoding UTF8
    $fm = Parse-Frontmatter $rawContent

    if ($fm.Count -eq 0) { $cleanCount++; continue }

    $rel    = $file.FullName.Replace($vaultPath + "\", "")
    $issues = @()
    $fixed  = @()

    # 1. para_type validation
    if ($fm.ContainsKey("para_type")) {
        $pt = $fm["para_type"].Trim('"')
        if ($pt -notin $validParaTypes) {
            if ($AutoFix) {
                if (Set-FrontmatterField $file.FullName $rawContent "para_type" "resource") {
                    $rawContent = Get-Content $file.FullName -Raw -Encoding UTF8
                    $fixed += "para_type '$pt' -> 'resource'"
                    $fixCount++
                }
            } else {
                $issues += [PSCustomObject]@{ Level="ERROR"; Msg="para_type '$pt' invalid (valid: $($validParaTypes -join ', '))" }
            }
        }
    }

    # 1b. domain validation
    if ($fm.ContainsKey("domain")) {
        $dom = $fm["domain"].Trim('"')
        if ($dom -notin $validDomains) {
            $issues += [PSCustomObject]@{ Level="ERROR"; Msg="domain '$dom' invalid (valid: $($validDomains -join ', '))" }
        }
    }

    # 1c. source validation (only when present; WARN to avoid noise on legacy notes)
    if ($fm.ContainsKey("source")) {
        $src = $fm["source"].Trim('"')
        if ($src -ne "" -and $src -notin $validSources) {
            $issues += [PSCustomObject]@{ Level="WARN"; Msg="source '$src' invalid (valid: $($validSources -join ', '))" }
        }
    }

    # 2. sector validation (invest domain only)
    if ($fm["domain"] -eq "invest" -and $fm.ContainsKey("sector")) {
        $sec = $fm["sector"].Trim('"')
        if ($sec -notin $validSectors) {
            if ($AutoFix) {
                if (Set-FrontmatterField $file.FullName $rawContent "sector" $fallbackSector) {
                    $rawContent = Get-Content $file.FullName -Raw -Encoding UTF8
                    $fm["sector"] = $fallbackSector
                    $sec = $fallbackSector
                    $fixed += "sector -> '$fallbackSector'"
                    $fixCount++
                }
            } else {
                $issues += [PSCustomObject]@{ Level="ERROR"; Msg="sector '$sec' invalid (valid: $($validSectors -join ', '))" }
            }
        }

        # 3. industry validation
        if ($sec -in $validSectors -and $fm.ContainsKey("industry")) {
            $ind = $fm["industry"].Trim('"')
            if ($ind -ne "" -and $validIndustries.ContainsKey($sec)) {
                if ($ind -notin $validIndustries[$sec]) {
                    $defaultInd = $validIndustries[$sec][0]
                    if ($AutoFix) {
                        if (Set-FrontmatterField $file.FullName $rawContent "industry" $defaultInd) {
                            $rawContent = Get-Content $file.FullName -Raw -Encoding UTF8
                            $fixed += "industry '$ind' -> '$defaultInd'"
                            $fixCount++
                        }
                    } else {
                        $issues += [PSCustomObject]@{ Level="ERROR"; Msg="industry '$ind' invalid for sector '$sec' (valid: $($validIndustries[$sec] -join ', '))" }
                    }
                }
            }
        }
    }

    # 4. Relations section + inline fields check (invest domain)
    if ($fm["domain"] -eq "invest") {
        if ($rawContent -notmatch '## Relations') {
            $issues += [PSCustomObject]@{ Level="WARN"; Msg="## Relations section missing — add inline fields (hub:: [[Name]] etc.)" }
        } elseif ($rawContent -match '(?s)## Relations\s*\r?\n(.*?)(?:\r?\n## |\Z)') {
            $relSection = $Matches[1].Trim()
            if ($relSection -notmatch '::\s*\[\[') {
                $issues += [PSCustomObject]@{ Level="WARN"; Msg="## Relations section has no inline fields (hub:: [[Name]] etc.)" }
            }
        }
    }

    # 5. currency check (invest notes with asset field)
    if ($fm["domain"] -eq "invest" -and $fm.ContainsKey("asset") -and $fm["asset"] -ne "") {
        if (-not $fm.ContainsKey("currency") -or $fm["currency"] -eq "") {
            $issues += [PSCustomObject]@{ Level="WARN"; Msg="asset present but currency missing (KRW or USD)" }
        }
    }

    # 6. [NEW] title != filename mismatch (normalize filename-unsafe chars before compare)
    #     Skip when: title_alias:true (intentional alias) OR note is in 0_Inbox (staging area)
    if ($fm.ContainsKey("title")) {
        $titleVal     = $fm["title"].Trim('"')
        $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $titleAlias   = $fm.ContainsKey("title_alias") -and ($fm["title_alias"].Trim('"') -eq "true")
        $inInbox      = (Split-Path $file.DirectoryName -Leaf) -eq "0_Inbox"
        # Normalize both sides: treat ':' and '-' as equivalent separators (Windows filename policy)
        $titleNorm = $titleVal     -replace '[\\/:*?"<>|]', ' ' -replace '\s*-\s*', ' ' -replace '\s+', ' ' -replace '^\s+|\s+$', ''
        $fileNorm  = $fileBaseName                              -replace '\s*-\s*', ' ' -replace '\s+', ' ' -replace '^\s+|\s+$', ''
        if ($titleNorm -ne $fileNorm -and -not $titleAlias -and -not $inInbox) {
            $issues += [PSCustomObject]@{ Level="WARN"; Msg="title != filename (broken related link risk)`n         title:    `"$titleVal`"`n         filename: `"$fileBaseName`"" }
        # (Note: ':' in title -> ' - ' in filename is an allowed exception per Ontology guide)
        }
    }

    # 7. [NEW] Related Notes section missing (invest domain, AutoFix supported)
    if ($fm["domain"] -eq "invest") {
        if ($rawContent -notmatch '## Related Notes') {
            if ($AutoFix) {
                $newContent = $rawContent.TrimEnd() + $relatedNotesBlock
                [System.IO.File]::WriteAllText($file.FullName, $newContent, [System.Text.Encoding]::UTF8)
                $rawContent = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
                $fixed += "## Related Notes section added"
                $fixCount++
            } else {
                $issues += [PSCustomObject]@{ Level="WARN"; Msg="## Related Notes section missing" }
            }
        }
    }

    # 9. Inline fields type validation in ## Relations section
    if ($rawContent -match '(?s)## Relations\s*\r?\n(.*?)(?:\r?\n## |\Z)') {
        $relSection = $Matches[1]
        $domain = $fm["domain"]
        $allowedTypes = if ($domain -eq "invest") { $validRelTypesInvest } elseif ($domain -eq "biz") { $validRelTypesBiz } else { $validRelTypesDefault }
        foreach ($line in ($relSection -split '\r?\n')) {
            $line = $line.Trim()
            if ($line -match '^(\w+)::\s*\[\[([^\]]+)\]\]') {
                $relType   = $Matches[1]
                $linkTitle = $Matches[2]
                if ($relType -notin $allowedTypes) {
                    $issues += [PSCustomObject]@{ Level="WARN"; Msg="inline relation type '$relType' on [[$linkTitle]] invalid for domain '$domain' (valid: $($allowedTypes -join ', '))" }
                }
                # Dangling edge check: does the relation target actually exist?
                $tgt = ($linkTitle -split '\|')[0]      # strip display alias
                $tgt = ($tgt -split '#')[0]              # strip heading anchor
                $tgt = ($tgt -split '[\\/]')[-1].Trim()  # path form -> basename
                if ($tgt -ne "" -and $tgt -notmatch $attachmentPattern -and $tgt -notmatch '^https?://') {
                    if (-not $allNoteNames.Contains($tgt)) {
                        $issues += [PSCustomObject]@{ Level="WARN"; Msg="dangling relation '$relType:: [[$linkTitle]]' - target note does not exist" }
                    }
                }
            }
        }
    }

    # 8. [NEW] para_type <-> folder mismatch (skip 0. Inbox - staging area)
    if ($fm.ContainsKey("para_type")) {
        $pt           = $fm["para_type"].Trim('"')
        $parentFolder = Split-Path $file.DirectoryName -Leaf
        if ($paraTypeToFolder.ContainsKey($pt) -and $parentFolder -ne "0_Inbox") {
            $expectedFolder = $paraTypeToFolder[$pt]
            if ($parentFolder -ne $expectedFolder) {
                $issues += [PSCustomObject]@{ Level="WARN"; Msg="para_type '$pt' but folder is '$parentFolder' (expected: '$expectedFolder')" }
            }
        }
    }

    # 10. Orphan check: zero outgoing links to existing notes AND zero inbound links = isolated in the graph (0_Inbox excluded, it is a staging area)
    if ((Split-Path $file.DirectoryName -Leaf) -ne "0_Inbox") {
        $hasOutgoing = $false
        foreach ($m in $wikilinkRegex.Matches($rawContent)) {
            $t = ($m.Groups[1].Value -split '\|')[0]
            $t = ($t -split '#')[0]
            $t = ($t -split '[\\/]')[-1].Trim()
            if ($t -ne "" -and $t -ne $file.BaseName -and $t -notmatch $attachmentPattern -and $allNoteNames.Contains($t)) {
                $hasOutgoing = $true; break
            }
        }
        $hasInbound = $inboundTargets.Contains($file.BaseName)
        if (-not $hasOutgoing -and -not $hasInbound) {
            $issues += [PSCustomObject]@{ Level="WARN"; Msg="orphan - zero graph connections (no outgoing links, no inbound links); consider linking it to a hub" }
        }
    }

    # Output
    $hasOutput = ($issues.Count -gt 0) -or ($fixed.Count -gt 0)
    if ($hasOutput) {
        Write-Host "[$rel]" -ForegroundColor White
        foreach ($f in $fixed) {
            Write-Host "  [FIXED] $f" -ForegroundColor Green
        }
        foreach ($issue in $issues) {
            if ($issue.Level -eq "ERROR") {
                Write-Host "  [ERROR] $($issue.Msg)" -ForegroundColor Red
                $errorCount++
            } else {
                Write-Host "  [WARN]  $($issue.Msg)" -ForegroundColor Yellow
                $warnCount++
            }
        }
        Write-Host ""
    } else {
        $cleanCount++
    }
}

# === Summary ===
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Scanned: $totalFiles notes"
Write-Host "  Clean:   $cleanCount" -ForegroundColor Green
if ($AutoFix -and $fixCount -gt 0) {
    Write-Host "  Fixed:   $fixCount" -ForegroundColor Green
}
Write-Host "  ERROR:   $errorCount" -ForegroundColor Red
Write-Host "  WARN:    $warnCount" -ForegroundColor Yellow
Write-Host ""
if ($AutoFix) {
    Write-Host "  * WARN items cannot be auto-fixed -- manual review required" -ForegroundColor DarkYellow
    Write-Host ""
}

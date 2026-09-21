[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Version,
    [Parameter(Mandatory = $false)]
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$liveRoot = Join-Path $projectRoot 'LIVE'
$addonNames = @(
    'Holy_Storm', 'Holy_Storm_UI', 'Holy_Storm_Chat', 'Holy_Storm_Characters', 'Holy_Storm_Equipment', 'Holy_Storm_Raids',
    'Holy_Storm_MythicPlus', 'Holy_Storm_Delves', 'Holy_Storm_Calendar',
    'Holy_Storm_Professions', 'Holy_Storm_Guild', 'Holy_Storm_GuildLog',
    'Holy_Storm_News', 'Holy_Storm_Achievements', 'Holy_Storm_POI', 'Holy_Storm_Positions'
)
$sourceRoot = Join-Path $liveRoot 'Holy_Storm'
$tocPath = Join-Path $sourceRoot 'Holy_Storm.toc'
$releaseRoot = Join-Path $projectRoot 'RELEASES'

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/')
    $pathFullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $pathFullPath.StartsWith($baseFullPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Pfad liegt ausserhalb des erwarteten Basisverzeichnisses: $pathFullPath"
    }

    return $pathFullPath.Substring($baseFullPath.Length + 1)
}

function Test-IsExcluded {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalized = $RelativePath.Replace('\', '/')
    $segments = $normalized.Split('/')
    $excludedDirectories = @('.git', '.github', 'RELEASES', 'tools', '_ace3_source', 'test', 'tests', 'backup', 'backups')

    foreach ($segment in $segments) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        if ($segment.StartsWith('.')) { return $true }
        if ($excludedDirectories -contains $segment) { return $true }
    }

    $fileName = [System.IO.Path]::GetFileName($normalized)
    if ($fileName -match '(?i)\.zip$|\.code-workspace$|^\.luarc\.json$') { return $true }
    if ($fileName -match '(?i)(\.tmp|\.temp|\.bak|\.backup|\.old|\.orig|\.rej|~)$') { return $true }
    if ($fileName -match '(?i)^(test[-_].*|.*\.(test|tests)\.[^.]+)$') { return $true }

    return $false
}

function Get-TocReferences {
    param([Parameter(Mandatory = $true)][string]$Path)

    $references = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -LiteralPath $Path) {
        $entry = $line.Trim()
        if ($entry.Length -eq 0 -or $entry.StartsWith('#')) { continue }
        $references.Add($entry.Replace('/', '\'))
    }
    return $references.ToArray()
}

function Assert-TocFilesExist {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$References,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($reference in $References) {
        $candidate = Join-Path $Root $reference
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $missing.Add($reference)
        }
    }

    if ($missing.Count -gt 0) {
        throw "TOC-Validierung fehlgeschlagen ($Context). Fehlende Dateien:`n - $($missing -join "`n - ")"
    }
}

$tocContracts = New-Object System.Collections.Generic.List[object]
foreach ($addonName in $addonNames) {
    $addonRoot = Join-Path $liveRoot $addonName
    $addonToc = Join-Path $addonRoot ($addonName + '.toc')
    if (-not (Test-Path -LiteralPath $addonRoot -PathType Container)) { throw "Addon-Quellordner nicht gefunden: $addonRoot" }
    if (-not (Test-Path -LiteralPath $addonToc -PathType Leaf)) { throw "TOC-Datei nicht gefunden: $addonToc" }
    $references = @(Get-TocReferences -Path $addonToc)
    if ($references.Count -eq 0) { throw "Die TOC-Datei enthaelt keine referenzierten Addon-Dateien: $addonToc" }
    Assert-TocFilesExist -Root $addonRoot -References $references -Context $addonName
    $tocContracts.Add([pscustomobject]@{ Name=$addonName; Root=$addonRoot; Toc=$addonToc; References=$references })
}

$tocVersionMatch = Select-String -LiteralPath $tocPath -Pattern '^\s*##\s*Version\s*:\s*(\S.*?)\s*$' | Select-Object -First 1
if (-not $tocVersionMatch) {
    throw "Keine gueltige Zeile '## Version:' in $tocPath gefunden."
}
$tocVersion = $tocVersionMatch.Matches[0].Groups[1].Value.Trim()
$packageVersion = if ($PSBoundParameters.ContainsKey('Version')) { $Version.Trim() } else { $tocVersion }
if ([string]::IsNullOrWhiteSpace($packageVersion)) {
    throw 'Die Paketversion darf nicht leer sein.'
}
if ($packageVersion.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
    throw "Die Paketversion enthaelt ungueltige Zeichen fuer einen Dateinamen: $packageVersion"
}

$tocReferences = @($tocContracts | ForEach-Object { $_.References })

if ($ValidateOnly) {
    Write-Host "Quellvalidierung: Erfolgreich ($($tocReferences.Count) referenzierte Dateien in $($addonNames.Count) Addons vorhanden)"
    return
}

if (-not (Test-Path -LiteralPath $releaseRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $releaseRoot | Out-Null
}

$releasePath = Join-Path $releaseRoot ("Holy Storm v{0}.zip" -f $packageVersion)
$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("HolyStorm-Release-{0}" -f [guid]::NewGuid().ToString('N'))
$temporaryZip = Join-Path ([System.IO.Path]::GetTempPath()) ("HolyStorm-Release-{0}.zip" -f [guid]::NewGuid().ToString('N'))
$archive = $null
$zipStream = $null

try {
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

    foreach ($contract in $tocContracts) {
        $stagedAddonRoot = Join-Path $stagingRoot $contract.Name
        New-Item -ItemType Directory -Path $stagedAddonRoot -Force | Out-Null
        $sourceItems = Get-ChildItem -LiteralPath $contract.Root -Recurse -Force
        foreach ($item in $sourceItems) {
            $relativePath = Get-RelativePath -BasePath $contract.Root -Path $item.FullName
            if (Test-IsExcluded -RelativePath $relativePath) { continue }
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Verknuepfte Datei oder Verzeichnis im Addon wird aus Sicherheitsgruenden nicht paketiert: $($contract.Name)/$relativePath"
            }

            $destination = Join-Path $stagedAddonRoot $relativePath
            if ($item.PSIsContainer) {
                New-Item -ItemType Directory -Path $destination -Force | Out-Null
            }
            else {
                $destinationDirectory = Split-Path -Parent $destination
                if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
                    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
                }
                Copy-Item -LiteralPath $item.FullName -Destination $destination
            }
        }
        Assert-TocFilesExist -Root $stagedAddonRoot -References $contract.References -Context ("Staging " + $contract.Name)
    }

    $zipStream = [System.IO.File]::Open($temporaryZip, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $archive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create, $true)

    $stagedDirectories = Get-ChildItem -LiteralPath $stagingRoot -Directory -Recurse | Sort-Object FullName
    foreach ($directory in $stagedDirectories) {
        $relativePath = (Get-RelativePath -BasePath $stagingRoot -Path $directory.FullName).Replace('\', '/') + '/'
        [void]$archive.CreateEntry($relativePath)
    }

    $stagedFiles = Get-ChildItem -LiteralPath $stagingRoot -File -Recurse | Sort-Object FullName
    foreach ($file in $stagedFiles) {
        $entryName = (Get-RelativePath -BasePath $stagingRoot -Path $file.FullName).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive,
            $file.FullName,
            $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal
        )
    }

    $archive.Dispose()
    $archive = $null
    $zipStream.Dispose()
    $zipStream = $null

    if (-not (Test-Path -LiteralPath $temporaryZip -PathType Leaf)) {
        throw 'Die temporaere ZIP-Datei wurde nicht erzeugt.'
    }
    if ((Get-Item -LiteralPath $temporaryZip).Length -le 0) {
        throw 'Die erzeugte ZIP-Datei ist leer.'
    }

    $validationArchive = [System.IO.Compression.ZipFile]::OpenRead($temporaryZip)
    try {
        $entryNames = @($validationArchive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        $fileEntryNames = @($entryNames | Where-Object { -not $_.EndsWith('/') })
        if ($fileEntryNames.Count -eq 0) { throw 'Die ZIP-Datei enthaelt keine Dateien.' }

        $wrongTopLevel = @($entryNames | Where-Object {
            $entryName = $_
            -not ($addonNames | Where-Object { $entryName -eq ($_ + '/') -or $entryName.StartsWith($_ + '/') } | Select-Object -First 1)
        })
        if ($wrongTopLevel.Count -gt 0) {
            throw "Unerwartete Eintraege ausserhalb der Addon-Ordner: $($wrongTopLevel -join ', ')"
        }

        $requiredEntries = @(
            'Holy_Storm/Holy_Storm.toc',
            'Holy_Storm/Core/',
            'Holy_Storm/Libs/',
            'Holy_Storm/Locales/',
            'Holy_Storm/Persistence/',
            'Holy_Storm_UI/Holy_Storm_UI.toc',
            'Holy_Storm_UI/UI/',
            'Holy_Storm_UI/Libs/'
        )
        $requiredEntries += @($addonNames | Where-Object { $_ -ne 'Holy_Storm' } | ForEach-Object { $_ + '/' + $_ + '.toc' })
        foreach ($requiredEntry in $requiredEntries) {
            $exists = if ($requiredEntry.EndsWith('/')) {
                @($entryNames | Where-Object { $_.StartsWith($requiredEntry, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
            }
            else {
                @($entryNames | Where-Object { $_.Equals($requiredEntry, [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 1
            }
            if (-not $exists) { throw "Erforderlicher ZIP-Eintrag fehlt: $requiredEntry" }
        }

        $forbiddenPatterns = @('LIVE/', 'RELEASES/', 'tools/', '_ace3_source/')
        foreach ($forbiddenPattern in $forbiddenPatterns) {
            if (@($entryNames | Where-Object { $_.IndexOf($forbiddenPattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0) {
                throw "Verbotener Pfad in ZIP gefunden: $forbiddenPattern"
            }
        }
        if (@($fileEntryNames | Where-Object { $_.EndsWith('.zip', [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
            throw 'Eine vorherige ZIP-Datei wurde versehentlich in das Archiv aufgenommen.'
        }

        $archiveEntrySet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($entryName in $fileEntryNames) { [void]$archiveEntrySet.Add($entryName) }
        $missingTocEntries = New-Object System.Collections.Generic.List[string]
        foreach ($contract in $tocContracts) {
            foreach ($reference in $contract.References) {
                $expectedEntry = $contract.Name + '/' + $reference.Replace('\', '/')
                if (-not $archiveEntrySet.Contains($expectedEntry)) { $missingTocEntries.Add($expectedEntry) }
            }
        }
        if ($missingTocEntries.Count -gt 0) {
            throw "TOC-Validierung im ZIP fehlgeschlagen. Fehlende Dateien:`n - $($missingTocEntries -join "`n - ")"
        }

        $containedFileCount = $fileEntryNames.Count
    }
    finally {
        $validationArchive.Dispose()
    }

    if (Test-Path -LiteralPath $releasePath -PathType Leaf) {
        Remove-Item -LiteralPath $releasePath -Force
    }
    Move-Item -LiteralPath $temporaryZip -Destination $releasePath

    $releaseFile = Get-Item -LiteralPath $releasePath
    Write-Host "Erkannte Addon-Version: $tocVersion"
    Write-Host "Erzeugte ZIP-Datei: $($releaseFile.FullName)"
    Write-Host "Dateigroesse: $($releaseFile.Length) Bytes"
    Write-Host "Enthaltene Dateien: $containedFileCount"
    Write-Host "TOC-Validierung: Erfolgreich ($($tocReferences.Count) referenzierte Dateien in $($addonNames.Count) Addons vorhanden)"
    Write-Host 'ZIP-Strukturpruefung: Erfolgreich (nur die erwarteten Holy-Storm-Addonordner enthalten)'
    Write-Host "Build-Skript: $PSCommandPath"
}
finally {
    if ($archive) { $archive.Dispose() }
    if ($zipStream) { $zipStream.Dispose() }
    if (Test-Path -LiteralPath $temporaryZip -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryZip -Force
    }
    if (Test-Path -LiteralPath $stagingRoot -PathType Container) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}

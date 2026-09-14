$addonRoot = Join-Path $PSScriptRoot "..\LIVE\Holy_Storm"
function Get-LocalizationKeys([string]$filePath) {
    $content = Get-Content -LiteralPath $filePath -Raw
    return [regex]::Matches($content, 'L\["([^"\r\n]+)"\]\s*=') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
}

$errors = [System.Collections.Generic.List[string]]::new()
$englishFiles = Get-ChildItem -LiteralPath $addonRoot -Recurse -Filter "enUS.lua" -File |
    Where-Object { $_.FullName -notmatch "[\\/]Libs[\\/]" }
$englishKeys = [System.Collections.Generic.HashSet[string]]::new()

foreach ($englishFile in $englishFiles) {
    $englishContent = Get-Content -LiteralPath $englishFile.FullName -Raw
    if ([regex]::IsMatch($englishContent, '=\s*L\s*\[')) {
        $errors.Add("AceLocale registration proxy read in $($englishFile.FullName)")
    }

    $moduleKeys = Get-LocalizationKeys $englishFile.FullName
    $moduleKeys | ForEach-Object { [void]$englishKeys.Add($_) }
    $germanFile = Join-Path $englishFile.DirectoryName "deDE.lua"

    if (-not (Test-Path -LiteralPath $germanFile -PathType Leaf)) {
        $errors.Add("Missing deDE.lua for $($englishFile.DirectoryName)")
        continue
    }


    $germanContent = Get-Content -LiteralPath $germanFile -Raw
    if ([regex]::IsMatch($germanContent, '=\s*L\s*\[')) {
        $errors.Add("AceLocale registration proxy read in $germanFile")
    }

    $germanKeys = Get-LocalizationKeys $germanFile
    $missingKeys = $moduleKeys | Where-Object { $_ -notin $germanKeys }

    foreach ($key in $missingKeys) {
        $errors.Add("Missing translation in ${germanFile}: $key")
    }
}

$sourceFiles = Get-ChildItem -LiteralPath $addonRoot -Recurse -Filter "*.lua" -File |
    Where-Object {
        $_.FullName -notmatch "[\\/]Libs[\\/]" -and
        $_.FullName -notmatch "[\\/]Locales[\\/]"
    }

$usedKeys = [System.Collections.Generic.HashSet[string]]::new()
# Empty SetText("") calls only clear widgets and are not user-facing output.
$directOutputPattern = '(?:(?:print|AddMessage|AddLine)\s*\(\s*["''])|(?:SetText\s*\(\s*["''][^"''])'

foreach ($sourceFile in $sourceFiles) {
    $content = Get-Content -LiteralPath $sourceFile.FullName -Raw

    foreach ($match in [regex]::Matches($content, 'L\["([^"\r\n]+)"\]')) {
        [void]$usedKeys.Add($match.Groups[1].Value)
    }

    if ([regex]::IsMatch($content, $directOutputPattern)) {
        $errors.Add("Potentially unlocalized direct output in $($sourceFile.FullName)")
    }
}

foreach ($key in $usedKeys) {
    if (-not $englishKeys.Contains($key)) {
        $errors.Add("Localization key used but missing in an enUS.lua file: $key")
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "Localization check passed."

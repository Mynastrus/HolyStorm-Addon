param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("major", "minor", "patch")]
    [string]$ChangeType,

    [Parameter(Mandatory = $true)]
    [string[]]$Path
)

foreach ($filePath in $Path) {
    $content = Get-Content -LiteralPath $filePath -Raw
    $match = [regex]::Match($content, '(?m)^local addonVersion = "(\d+)\.(\d+)\.(\d+)"')

    if (-not $match.Success) {
        throw "No addonVersion declaration found in '$filePath'."
    }

    $major = [int]$match.Groups[1].Value
    $minor = [int]$match.Groups[2].Value
    $patch = [int]$match.Groups[3].Value

    switch ($ChangeType) {
        "major" {
            $major++
            $minor = 0
            $patch = 0
        }
        "minor" {
            $minor++
            $patch = 0
        }
        "patch" {
            $patch++
        }
    }

    $newVersion = "$major.$minor.$patch"
    $updatedContent = [regex]::Replace(
        $content,
        '(?m)^local addonVersion = "\d+\.\d+\.\d+"',
        "local addonVersion = `"$newVersion`"",
        1
    )

    Set-Content -LiteralPath $filePath -Value $updatedContent -Encoding utf8NoBOM
    Write-Output "$filePath -> $newVersion"
}

#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string]$Tag,
    [string]$Repo = 'hammercui/ham-claw-site',
    [switch]$RequireAuthenticode,
    [switch]$ConfirmPublish
)

$ErrorActionPreference = 'Stop'
$validator = Join-Path $PSScriptRoot 'Test-ReleaseBundle.ps1'
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    throw 'PUBLISH_DRAFT_GH_REQUIRED'
}
& $gh.Source auth status *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'PUBLISH_DRAFT_GH_AUTH_REQUIRED'
}

$release = & $gh.Source release view $Tag --repo $Repo --json isDraft,tagName,url,assets | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $release.isDraft -or $release.tagName -cne $Tag) {
    throw 'PUBLISH_DRAFT_STATE_INVALID'
}

$expectedAssets = @('OpenClawConsole.exe', 'OpenClawConsole.exe.minisig', 'SHA256SUMS.txt', 'latest.json', 'release-provenance.json')
$actualAssets = @($release.assets | ForEach-Object name | Sort-Object)
if (Compare-Object -ReferenceObject @($expectedAssets | Sort-Object) -DifferenceObject $actualAssets) {
    throw 'PUBLISH_DRAFT_ASSET_SET_INVALID'
}

$downloadDir = Join-Path ([IO.Path]::GetTempPath()) ("hamclaw-publish-verify-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $downloadDir | Out-Null
try {
    & $gh.Source release download $Tag --repo $Repo --dir $downloadDir
    if ($LASTEXITCODE -ne 0) {
        throw 'PUBLISH_DRAFT_DOWNLOAD_FAILED'
    }
    $validation = & $validator -BundleDir $downloadDir -Tag $Tag -RequireAuthenticode:$RequireAuthenticode
    if (-not $ConfirmPublish) {
        [pscustomobject]@{
            Verified = $validation.Valid
            Draft = $true
            WillPublish = $false
            Tag = $Tag
            Url = $release.url
            Next = 'Rerun with -ConfirmPublish after human approval'
        }
        return
    }

    & $gh.Source release edit $Tag --repo $Repo --draft=false
    if ($LASTEXITCODE -ne 0) {
        throw 'PUBLISH_DRAFT_EDIT_FAILED'
    }
    $published = & $gh.Source release view $Tag --repo $Repo --json isDraft,tagName,url | ConvertFrom-Json
    if ($published.isDraft -or $published.tagName -cne $Tag) {
        throw 'PUBLISH_DRAFT_POSTFLIGHT_FAILED'
    }
    [pscustomobject]@{
        Published = $true
        Tag = $Tag
        Url = $published.url
        StableManifestChanged = $false
        Next = 'Publish the identical latest.json to the stable vendor endpoint last'
    }
}
finally {
    if (Test-Path -LiteralPath $downloadDir) {
        Remove-Item -LiteralPath $downloadDir -Recurse -Force
    }
}

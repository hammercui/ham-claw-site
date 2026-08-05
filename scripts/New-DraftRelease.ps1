#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundleDir,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string]$Tag,
    [Parameter(Mandatory = $true)]
    [string]$ReleaseNotesFile,
    [string]$Repo = 'hammercui/ham-claw-site',
    [string]$Title = '',
    [switch]$RequireAuthenticode,
    [switch]$Prerelease,
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
$validator = Join-Path $PSScriptRoot 'Test-ReleaseBundle.ps1'
$bundle = (Resolve-Path -LiteralPath $BundleDir).Path
$notes = (Resolve-Path -LiteralPath $ReleaseNotesFile).Path
$releaseTitle = if ([string]::IsNullOrWhiteSpace($Title)) { "龙虾卫士 $Tag" } else { $Title }
$requiredAssets = @(
    'OpenClawConsole.exe',
    'OpenClawConsole.exe.minisig',
    'SHA256SUMS.txt',
    'latest.json',
    'release-provenance.json'
)

$validation = & $validator -BundleDir $bundle -Tag $Tag -RequireAuthenticode:$RequireAuthenticode
if (-not $validation.Valid) {
    throw 'DRAFT_RELEASE_LOCAL_VALIDATION_FAILED'
}

$plan = [pscustomobject]@{
    Action = if ($Execute) { 'CreateDraft' } else { 'ValidateOnly' }
    Repo = $Repo
    Tag = $Tag
    Title = $releaseTitle
    Assets = $requiredAssets
    Sha256 = $validation.Sha256
    Authenticode = $validation.Authenticode
    Prerelease = [bool]$Prerelease
    PublicEffect = 'Draft only; stable latest.json is not changed'
}
if (-not $Execute) {
    $plan
    return
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    throw 'DRAFT_RELEASE_GH_REQUIRED'
}
& $gh.Source auth status *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'DRAFT_RELEASE_GH_AUTH_REQUIRED'
}
& $gh.Source repo view $Repo --json nameWithOwner *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'DRAFT_RELEASE_REPO_UNREACHABLE'
}
$previousErrorActionPreference = $ErrorActionPreference
try {
    # A missing release is the expected path. Windows PowerShell 5.1 turns
    # native stderr into an ErrorRecord under Stop before LASTEXITCODE can be
    # inspected, so contain that one probe and classify its exit explicitly.
    $ErrorActionPreference = 'Continue'
    & $gh.Source release view $Tag --repo $Repo --json tagName 2>$null | Out-Null
    $releaseProbeExit = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($releaseProbeExit -eq 0) {
    throw 'DRAFT_RELEASE_TAG_ALREADY_EXISTS'
}
if ($releaseProbeExit -ne 1) {
    throw "DRAFT_RELEASE_TAG_PROBE_FAILED: exit=$releaseProbeExit"
}

$assetPaths = @($requiredAssets | ForEach-Object { Join-Path $bundle $_ })
$createArguments = @('release', 'create', $Tag, '--repo', $Repo, '--draft', '--title', $releaseTitle, '--notes-file', $notes)
if ($Prerelease) {
    $createArguments += '--prerelease'
}
$createArguments += $assetPaths
& $gh.Source @createArguments
if ($LASTEXITCODE -ne 0) {
    throw 'DRAFT_RELEASE_CREATE_FAILED'
}

$downloadDir = Join-Path ([IO.Path]::GetTempPath()) ("hamclaw-draft-verify-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $downloadDir | Out-Null
try {
    & $gh.Source release download $Tag --repo $Repo --dir $downloadDir
    if ($LASTEXITCODE -ne 0) {
        throw 'DRAFT_RELEASE_DOWNLOAD_FAILED'
    }
    $remoteValidation = & $validator -BundleDir $downloadDir -Tag $Tag -RequireAuthenticode:$RequireAuthenticode
    foreach ($name in $requiredAssets) {
        $localHash = (Get-FileHash -LiteralPath (Join-Path $bundle $name) -Algorithm SHA256).Hash
        $remoteHash = (Get-FileHash -LiteralPath (Join-Path $downloadDir $name) -Algorithm SHA256).Hash
        if ($localHash -cne $remoteHash) {
            throw "DRAFT_RELEASE_REMOTE_ASSET_MISMATCH: $name"
        }
    }
    $release = & $gh.Source release view $Tag --repo $Repo --json isDraft,isPrerelease,tagName,url | ConvertFrom-Json
    if (-not $release.isDraft -or
        $release.tagName -cne $Tag -or
        [bool]$release.isPrerelease -ne [bool]$Prerelease) {
        throw 'DRAFT_RELEASE_REMOTE_STATE_INVALID'
    }
    [pscustomobject]@{
        Created = $true
        Verified = $remoteValidation.Valid
        Draft = $release.isDraft
        Prerelease = $release.isPrerelease
        Tag = $Tag
        Url = $release.url
        StableManifestChanged = $false
    }
}
finally {
    if (Test-Path -LiteralPath $downloadDir) {
        Remove-Item -LiteralPath $downloadDir -Recurse -Force
    }
}

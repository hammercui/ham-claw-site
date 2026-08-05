#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundleDir,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string]$Tag,
    [switch]$RequireAuthenticode,
    [ValidatePattern('^RW[A-Za-z0-9+/]{40,}$')]
    [string]$PublicKey = 'RWSN701ZUoQPuvaL2UVa59eRzF7ULwkBVQ/fQMuBT8ILN/KxOC7gxngr'
)

$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $BundleDir).Path
$required = @(
    'OpenClawConsole.exe',
    'OpenClawConsole.exe.minisig',
    'SHA256SUMS.txt',
    'latest.json',
    'release-provenance.json'
)

function Assert-ExactProperties {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$ErrorCode
    )
    $actual = @($Value.PSObject.Properties.Name | Sort-Object)
    $wanted = @($Expected | Sort-Object)
    if (Compare-Object -ReferenceObject $wanted -DifferenceObject $actual) {
        throw $ErrorCode
    }
}

$entries = @(Get-ChildItem -LiteralPath $resolved -Force)
$entryNames = @($entries | ForEach-Object Name | Sort-Object)
$requiredNames = @($required | Sort-Object)
if (Compare-Object -ReferenceObject $requiredNames -DifferenceObject $entryNames) {
    throw 'RELEASE_BUNDLE_FILE_SET_INVALID'
}
foreach ($entry in $entries) {
    if (-not $entry.PSIsContainer -and ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "RELEASE_BUNDLE_REPARSE_POINT_FORBIDDEN: $($entry.Name)"
    }
    if ($entry.PSIsContainer) {
        throw "RELEASE_BUNDLE_DIRECTORY_FORBIDDEN: $($entry.Name)"
    }
}

$exe = Join-Path $resolved 'OpenClawConsole.exe'
$signaturePath = Join-Path $resolved 'OpenClawConsole.exe.minisig'
$manifestPath = Join-Path $resolved 'latest.json'
$provenancePath = Join-Path $resolved 'release-provenance.json'
$checksumsPath = Join-Path $resolved 'SHA256SUMS.txt'
$exeInfo = Get-Item -LiteralPath $exe
if ($exeInfo.Length -le 0 -or $exeInfo.Length -gt 256MB) {
    throw 'RELEASE_BUNDLE_EXE_SIZE_INVALID'
}

$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$provenance = Get-Content -LiteralPath $provenancePath -Raw -Encoding UTF8 | ConvertFrom-Json
$signatureText = [IO.File]::ReadAllText($signaturePath)
$version = $Tag.Substring(1)

Assert-ExactProperties $manifest @('version', 'pub_date', 'url', 'sha256', 'sig', 'notes') 'RELEASE_BUNDLE_MANIFEST_SCHEMA_INVALID'
Assert-ExactProperties $provenance @('schemaVersion', 'product', 'version', 'tag', 'publishedAt', 'target', 'artifact', 'sha256', 'signed') 'RELEASE_BUNDLE_PROVENANCE_SCHEMA_INVALID'

if ($manifest.version -ne $version -or $provenance.version -ne $version -or $provenance.tag -ne $Tag) {
    throw 'RELEASE_BUNDLE_VERSION_MISMATCH'
}
if ($manifest.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $provenance.sha256 -cnotmatch '^[a-f0-9]{64}$') {
    throw 'RELEASE_BUNDLE_HASH_FORMAT_INVALID'
}
if ($manifest.sha256 -cne $hash -or $provenance.sha256 -cne $hash) {
    throw 'RELEASE_BUNDLE_HASH_MISMATCH'
}

$expectedPath = "/hammercui/ham-claw-site/releases/download/$Tag/OpenClawConsole.exe"
$downloadUri = $null
if (-not [Uri]::TryCreate([string]$manifest.url, [UriKind]::Absolute, [ref]$downloadUri) -or
    $downloadUri.Scheme -ne 'https' -or
    $downloadUri.Host -ne 'github.com' -or
    $downloadUri.AbsolutePath -cne $expectedPath -or
    -not [string]::IsNullOrEmpty($downloadUri.Query) -or
    -not [string]::IsNullOrEmpty($downloadUri.Fragment)) {
    throw 'RELEASE_BUNDLE_URL_NOT_IMMUTABLE'
}

$manifestDate = [DateTimeOffset]::MinValue
$provenanceDate = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse([string]$manifest.pub_date, [ref]$manifestDate) -or
    -not [DateTimeOffset]::TryParse([string]$provenance.publishedAt, [ref]$provenanceDate)) {
    throw 'RELEASE_BUNDLE_DATE_INVALID'
}
if ([string]::IsNullOrWhiteSpace([string]$manifest.notes) -or ([string]$manifest.notes).Length -gt 4000) {
    throw 'RELEASE_BUNDLE_NOTES_INVALID'
}
$manifestSignature = (([string]$manifest.sig) -replace "`r`n", "`n").Trim()
$fileSignature = ($signatureText -replace "`r`n", "`n").Trim()
if ([string]::IsNullOrWhiteSpace($signatureText) -or $manifestSignature -cne $fileSignature) {
    throw "RELEASE_BUNDLE_SIGNATURE_MISMATCH: manifestChars=$($manifestSignature.Length) fileChars=$($fileSignature.Length)"
}

if ($provenance.schemaVersion -ne 1 -or
    $provenance.product -cne '龙虾卫士' -or
    $provenance.target -cne 'windows-x86_64' -or
    $provenance.artifact -cne 'OpenClawConsole.exe' -or
    $provenance.signed -isnot [bool]) {
    throw 'RELEASE_BUNDLE_PROVENANCE_INVALID'
}

$checksumText = (Get-Content -LiteralPath $checksumsPath -Raw -Encoding UTF8).Trim()
if ($checksumText -cnotmatch "^$([regex]::Escape($hash))\s+\*?OpenClawConsole\.exe$") {
    throw 'RELEASE_BUNDLE_CHECKSUM_FILE_MISMATCH'
}

$rsign = Get-Command rsign -ErrorAction SilentlyContinue
if (-not $rsign) {
    throw 'RELEASE_BUNDLE_RSIGN_REQUIRED'
}
& $rsign.Source verify -q -P $PublicKey -x $signaturePath $exe
if ($LASTEXITCODE -ne 0) {
    throw 'RELEASE_BUNDLE_MINISIGN_INVALID'
}

$authenticode = Get-AuthenticodeSignature -FilePath $exe
if ($provenance.signed -and $authenticode.Status -ne 'Valid') {
    throw "RELEASE_BUNDLE_AUTHENTICODE_CLAIM_INVALID: $($authenticode.Status)"
}
if ($RequireAuthenticode -and (-not $provenance.signed -or $authenticode.Status -ne 'Valid')) {
    throw "RELEASE_BUNDLE_AUTHENTICODE_INVALID: $($authenticode.Status)"
}

[pscustomobject]@{
    Valid = $true
    Tag = $Tag
    Version = $version
    Sha256 = $hash
    Bytes = $exeInfo.Length
    Authenticode = $authenticode.Status.ToString()
    BundleDir = $resolved
}

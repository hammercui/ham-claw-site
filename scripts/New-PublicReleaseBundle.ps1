#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [Parameter(Mandatory = $true)]
    [string]$OutputDir,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string]$Tag,
    [string]$ReleaseNotesFile = '',
    [ValidatePattern('^RW[A-Za-z0-9+/]{40,}$')]
    [string]$PublicKey = 'RWSN701ZUoQPuvaL2UVa59eRzF7ULwkBVQ/fQMuBT8ILN/KxOC7gxngr'
)

$ErrorActionPreference = 'Stop'
$validator = Join-Path $PSScriptRoot 'Test-ReleaseBundle.ps1'
$source = (Resolve-Path -LiteralPath $SourceDir).Path
$output = [IO.Path]::GetFullPath($OutputDir)
$version = $Tag.Substring(1)
$versionedName = "OpenClawConsole-v$version.exe"
$sourceExe = Join-Path $source $versionedName
$sourceSignature = "$sourceExe.minisig"
$sourceManifestPath = Join-Path $source 'latest.json'
$sourceChecksumsPath = Join-Path $source 'SHA256SUMS.txt'
$notesPath = if ([string]::IsNullOrWhiteSpace($ReleaseNotesFile)) {
    "$output-notes.md"
} else {
    [IO.Path]::GetFullPath($ReleaseNotesFile)
}
$outputParent = Split-Path -Parent $output
$temp = Join-Path $outputParent ((Split-Path -Leaf $output) + '.tmp-' + [guid]::NewGuid().ToString('N'))

if (Test-Path -LiteralPath $output) {
    throw 'PUBLIC_BUNDLE_OUTPUT_ALREADY_EXISTS'
}
if (Test-Path -LiteralPath $notesPath) {
    throw 'PUBLIC_BUNDLE_NOTES_ALREADY_EXISTS'
}
foreach ($required in @($sourceExe, $sourceSignature, $sourceManifestPath, $sourceChecksumsPath, $validator)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "PUBLIC_BUNDLE_SOURCE_FILE_MISSING: $required"
    }
}

if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
}

try {
    $manifest = [IO.File]::ReadAllText($sourceManifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $expectedProperties = @('notes', 'pub_date', 'sha256', 'sig', 'url', 'version')
    $actualProperties = @($manifest.PSObject.Properties.Name | Sort-Object)
    if (Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties) {
        throw 'PUBLIC_BUNDLE_SOURCE_MANIFEST_SCHEMA_INVALID'
    }
    if ([string]$manifest.version -cne $version) {
        throw 'PUBLIC_BUNDLE_SOURCE_VERSION_MISMATCH'
    }
    if ($manifest.sig -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$manifest.sig)) {
        throw 'PUBLIC_BUNDLE_SOURCE_SIGNATURE_NOT_STRING'
    }

    $sourceSignatureText = [IO.File]::ReadAllText($sourceSignature, [Text.Encoding]::UTF8)
    if ([string]$manifest.sig -cne $sourceSignatureText) {
        throw 'PUBLIC_BUNDLE_SOURCE_SIGNATURE_MISMATCH'
    }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.notes) -or ([string]$manifest.notes).Length -gt 4000) {
        throw 'PUBLIC_BUNDLE_SOURCE_NOTES_INVALID'
    }

    $sourceUri = $null
    if (-not [Uri]::TryCreate([string]$manifest.url, [UriKind]::Absolute, [ref]$sourceUri) -or
        $sourceUri.Scheme -cne 'https' -or
        [IO.Path]::GetFileName($sourceUri.AbsolutePath) -cne $versionedName) {
        throw 'PUBLIC_BUNDLE_SOURCE_URL_INVALID'
    }

    $hash = (Get-FileHash -LiteralPath $sourceExe -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$manifest.sha256 -cne $hash) {
        throw 'PUBLIC_BUNDLE_SOURCE_HASH_MISMATCH'
    }
    $sourceChecksum = [IO.File]::ReadAllText($sourceChecksumsPath, [Text.Encoding]::UTF8).Trim()
    if ($sourceChecksum -cnotmatch "^$([regex]::Escape($hash))\s+\*?$([regex]::Escape($versionedName))$") {
        throw 'PUBLIC_BUNDLE_SOURCE_CHECKSUM_MISMATCH'
    }

    $rsign = Get-Command rsign -ErrorAction SilentlyContinue
    if (-not $rsign) {
        throw 'PUBLIC_BUNDLE_RSIGN_REQUIRED'
    }
    & $rsign.Source verify -q -P $PublicKey -x $sourceSignature $sourceExe
    if ($LASTEXITCODE -ne 0) {
        throw 'PUBLIC_BUNDLE_SOURCE_MINISIGN_INVALID'
    }

    New-Item -ItemType Directory -Path $temp | Out-Null
    $publicExe = Join-Path $temp 'OpenClawConsole.exe'
    $publicSignature = Join-Path $temp 'OpenClawConsole.exe.minisig'
    [IO.File]::Copy($sourceExe, $publicExe, $false)
    [IO.File]::Copy($sourceSignature, $publicSignature, $false)
    if ((Get-FileHash -LiteralPath $publicExe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash) {
        throw 'PUBLIC_BUNDLE_BYTE_COPY_MISMATCH'
    }

    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $temp 'SHA256SUMS.txt'), "$hash  OpenClawConsole.exe`n", [Text.Encoding]::ASCII)
    $publicManifest = [ordered]@{
        version = $version
        pub_date = [string]$manifest.pub_date
        url = "https://github.com/hammercui/ham-claw-site/releases/download/$Tag/OpenClawConsole.exe"
        sha256 = $hash
        sig = [string]$manifest.sig
        notes = [string]$manifest.notes
    }
    $authenticode = Get-AuthenticodeSignature -FilePath $publicExe
    $provenance = [ordered]@{
        schemaVersion = 1
        product = '龙虾卫士'
        version = $version
        tag = $Tag
        publishedAt = [string]$manifest.pub_date
        target = 'windows-x86_64'
        artifact = 'OpenClawConsole.exe'
        sha256 = $hash
        signed = ($authenticode.Status -eq 'Valid')
    }
    [IO.File]::WriteAllText((Join-Path $temp 'latest.json'), ($publicManifest | ConvertTo-Json -Depth 4), $utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $temp 'release-provenance.json'), ($provenance | ConvertTo-Json -Depth 4), $utf8NoBom)

    $validation = & $validator -BundleDir $temp -Tag $Tag -PublicKey $PublicKey
    if (-not $validation.Valid) {
        throw 'PUBLIC_BUNDLE_FINAL_VALIDATION_FAILED'
    }

    $notes = @"
# 龙虾卫士 $Tag Public Preview

$($manifest.notes)

- 平台：Windows 10/11 x64
- 文件：OpenClawConsole.exe
- SHA-256：$hash
- 更新签名：minisign（生产公钥可在官网安全页核对）
- 代码签名：$($authenticode.Status)

这是 Public Preview。安装前请核对 SHA-256 与 minisign；Windows 可能显示未知发布者提示。
"@
    [IO.File]::WriteAllText($notesPath, $notes.Trim() + "`n", $utf8NoBom)
    Move-Item -LiteralPath $temp -Destination $output

    [pscustomobject]@{
        Created = $true
        Tag = $Tag
        Version = $version
        Sha256 = $hash
        Bytes = (Get-Item -LiteralPath (Join-Path $output 'OpenClawConsole.exe')).Length
        Authenticode = $authenticode.Status.ToString()
        BundleDir = $output
        ReleaseNotesFile = $notesPath
    }
}
finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Recurse -Force
    }
}

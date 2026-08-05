#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hamclaw-release-publisher-test-" + [guid]::NewGuid().ToString('N'))
$bundle = Join-Path $tempRoot 'bundle'
$publicKeyPath = Join-Path $tempRoot 'test-public.key'
$secretKeyPath = Join-Path $tempRoot 'test-secret.key'
$validator = Join-Path $PSScriptRoot 'Test-ReleaseBundle.ps1'
$bundleBuilder = Join-Path $PSScriptRoot 'New-PublicReleaseBundle.ps1'
$draftPublisher = Join-Path $PSScriptRoot 'New-DraftRelease.ps1'
$verifiedPublisher = Join-Path $PSScriptRoot 'Publish-VerifiedDraft.ps1'

function Assert-ThrowsCode {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Code
    )
    try {
        & $Action
        throw "EXPECTED_FAILURE_NOT_RAISED: $Code"
    }
    catch {
        if ($_.Exception.Message -notmatch [regex]::Escape($Code)) {
            throw "EXPECTED_$Code BUT_GOT: $($_.Exception.Message)"
        }
    }
}

New-Item -ItemType Directory -Path $bundle -Force | Out-Null
try {
    $rsign = Get-Command rsign -ErrorAction SilentlyContinue
    if (-not $rsign) {
        throw 'TEST_RSIGN_REQUIRED'
    }
    & $rsign.Source generate -W -f -p $publicKeyPath -s $secretKeyPath
    if ($LASTEXITCODE -ne 0) { throw 'TEST_KEY_GENERATION_FAILED' }

    $exe = Join-Path $bundle 'OpenClawConsole.exe'
    [IO.File]::WriteAllBytes($exe, [byte[]](0x4d, 0x5a, 0x00, 0x01, 0x02, 0x03, 0x04))
    $signature = Join-Path $bundle 'OpenClawConsole.exe.minisig'
    & $rsign.Source sign -W -s $secretKeyPath -x $signature $exe
    if ($LASTEXITCODE -ne 0) { throw 'TEST_SIGNING_FAILED' }

    $publicKey = Get-Content -LiteralPath $publicKeyPath | Where-Object { $_ -match '^RW' } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($publicKey)) { throw 'TEST_PUBLIC_KEY_MISSING' }
    $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
    $signatureText = [IO.File]::ReadAllText($signature)
    $timestamp = '2026-08-05T00:00:00Z'
    $manifest = [ordered]@{
        version = '1.2.3'
        pub_date = $timestamp
        url = 'https://github.com/hammercui/ham-claw-site/releases/download/v1.2.3/OpenClawConsole.exe'
        sha256 = $hash
        sig = $signatureText
        notes = '测试发布契约'
    }
    $provenance = [ordered]@{
        schemaVersion = 1
        product = '龙虾卫士'
        version = '1.2.3'
        tag = 'v1.2.3'
        publishedAt = $timestamp
        target = 'windows-x86_64'
        artifact = 'OpenClawConsole.exe'
        sha256 = $hash
        signed = $false
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $bundle 'latest.json') -Encoding UTF8
    $provenance | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $bundle 'release-provenance.json') -Encoding UTF8
    "$hash  OpenClawConsole.exe" | Set-Content -LiteralPath (Join-Path $bundle 'SHA256SUMS.txt') -Encoding ASCII

    $valid = & $validator -BundleDir $bundle -Tag 'v1.2.3' -PublicKey $publicKey
    if (-not $valid.Valid) { throw 'TEST_VALID_BUNDLE_REJECTED' }

    $sourceBundle = Join-Path $tempRoot 'source-bundle'
    $builtBundle = Join-Path $tempRoot 'built-bundle'
    $builtNotes = Join-Path $tempRoot 'built-notes.md'
    New-Item -ItemType Directory -Path $sourceBundle | Out-Null
    $sourceExe = Join-Path $sourceBundle 'OpenClawConsole-v1.2.3.exe'
    $sourceSignature = "$sourceExe.minisig"
    [IO.File]::Copy($exe, $sourceExe)
    [IO.File]::Copy($signature, $sourceSignature)
    $sourceManifest = [ordered]@{
        version = '1.2.3'
        pub_date = $timestamp
        url = 'https://github.com/hammercui/ham-claw-site/releases/download/v1.2.3/OpenClawConsole-v1.2.3.exe'
        sha256 = $hash
        sig = $signatureText
        notes = '测试发布契约'
    }
    $sourceManifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $sourceBundle 'latest.json') -Encoding UTF8
    "$hash  OpenClawConsole-v1.2.3.exe" | Set-Content -LiteralPath (Join-Path $sourceBundle 'SHA256SUMS.txt') -Encoding ASCII

    $built = & $bundleBuilder `
        -SourceDir $sourceBundle `
        -OutputDir $builtBundle `
        -Tag 'v1.2.3' `
        -ReleaseNotesFile $builtNotes `
        -PublicKey $publicKey
    if (-not $built.Created -or $built.Sha256 -cne $hash -or -not (Test-Path -LiteralPath $builtNotes -PathType Leaf)) {
        throw 'PUBLIC_BUNDLE_BUILDER_VALID_OUTPUT_REJECTED'
    }
    $builtValidation = & $validator -BundleDir $builtBundle -Tag 'v1.2.3' -PublicKey $publicKey
    if (-not $builtValidation.Valid) { throw 'PUBLIC_BUNDLE_BUILDER_OUTPUT_INVALID' }
    Assert-ThrowsCode {
        & $bundleBuilder `
            -SourceDir $sourceBundle `
            -OutputDir $builtBundle `
            -Tag 'v1.2.3' `
            -ReleaseNotesFile $builtNotes `
            -PublicKey $publicKey
    } 'PUBLIC_BUNDLE_OUTPUT_ALREADY_EXISTS'

    $extra = Join-Path $bundle 'unexpected.txt'
    'unexpected' | Set-Content -LiteralPath $extra
    Assert-ThrowsCode { & $validator -BundleDir $bundle -Tag 'v1.2.3' -PublicKey $publicKey } 'RELEASE_BUNDLE_FILE_SET_INVALID'
    Remove-Item -LiteralPath $extra -Force

    $manifest.url = 'https://github.com/hammercui/ham-claw-site/releases/latest/download/OpenClawConsole.exe'
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $bundle 'latest.json') -Encoding UTF8
    Assert-ThrowsCode { & $validator -BundleDir $bundle -Tag 'v1.2.3' -PublicKey $publicKey } 'RELEASE_BUNDLE_URL_NOT_IMMUTABLE'

    $manifest.url = 'https://github.com/hammercui/ham-claw-site/releases/download/v1.2.3/OpenClawConsole.exe'
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $bundle 'latest.json') -Encoding UTF8
    [IO.File]::AppendAllText($exe, 'tamper')
    Assert-ThrowsCode { & $validator -BundleDir $bundle -Tag 'v1.2.3' -PublicKey $publicKey } 'RELEASE_BUNDLE_HASH_MISMATCH'

    $builderSource = Get-Content -LiteralPath $bundleBuilder -Raw
    $draftSource = Get-Content -LiteralPath $draftPublisher -Raw
    $publishSource = Get-Content -LiteralPath $verifiedPublisher -Raw
    if ($draftSource -notmatch "'--draft'" -or
        $draftSource -notmatch 'release download' -or
        $draftSource -notmatch 'DRAFT_RELEASE_TAG_PROBE_FAILED' -or
        $draftSource -notmatch "'--prerelease'" -or
        $draftSource -match "'--clobber'") {
        throw 'DRAFT_RELEASE_FAIL_CLOSED_CONTRACT_MISSING'
    }
    if ($publishSource -notmatch 'ConfirmPublish' -or $publishSource -notmatch '--draft=false' -or $publishSource -notmatch 'Test-ReleaseBundle') {
        throw 'PUBLISH_RELEASE_APPROVAL_CONTRACT_MISSING'
    }
    if (($draftSource + $publishSource) -match 'src[/\\]data[/\\]release\.json') {
        throw 'PUBLISHER_MUST_NOT_MUTATE_PUBLIC_SITE_STATE'
    }
    if ($builderSource -match 'secret-key|\bsign\b' -or $builderSource -notmatch 'PUBLIC_BUNDLE_BYTE_COPY_MISMATCH') {
        throw 'PUBLIC_BUNDLE_MUST_BE_BYTE_PRESERVING_WITHOUT_PRIVATE_KEY'
    }

    Write-Host 'Release publisher contracts passed.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

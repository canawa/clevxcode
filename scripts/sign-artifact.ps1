param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [string]$Description = "ClevVPN"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $FilePath)) {
    throw "File not found: $FilePath"
}

$Root = Split-Path -Parent $PSScriptRoot
$CertDir = Join-Path $Root "certs"
$PfxPath = if ($env:CODESIGN_PFX) { $env:CODESIGN_PFX } else { Join-Path $CertDir "clevvpn.pfx" }
$PfxPassword = if ($env:CODESIGN_PFX_PASSWORD) { $env:CODESIGN_PFX_PASSWORD } else { "ClevVPN" }

function Get-SignToolPath {
    $kitsRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    if (-not (Test-Path $kitsRoot)) {
        return $null
    }

    $latest = Get-ChildItem $kitsRoot -Directory |
        Where-Object { $_.Name -match '^\d' } |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if (-not $latest) {
        return $null
    }

    $tool = Join-Path $latest.FullName "x64\signtool.exe"
    if (Test-Path $tool) {
        return $tool
    }

    return $null
}

function Ensure-SigningCertificate {
    param([string]$Path, [string]$Password)

    if (Test-Path $Path) {
        return
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null

    $cert = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject "CN=ClevVPN" `
        -FriendlyName "ClevVPN Code Signing" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyExportPolicy Exportable `
        -NotAfter (Get-Date).AddYears(5)

    $securePassword = ConvertTo-SecureString -String $Password -Force -AsPlainText
    Export-PfxCertificate -Cert $cert -FilePath $Path -Password $securePassword | Out-Null
    Write-Host "Created signing certificate: $Path" -ForegroundColor Yellow
}

$signTool = Get-SignToolPath
if (-not $signTool) {
    Write-Host "signtool.exe not found. Install Windows SDK to sign binaries." -ForegroundColor Yellow
    return
}

Ensure-SigningCertificate -Path $PfxPath -Password $PfxPassword

$arguments = @(
    "sign",
    "/f", $PfxPath,
    "/p", $PfxPassword,
    "/fd", "SHA256",
    "/tr", "http://timestamp.digicert.com",
    "/td", "SHA256",
    "/d", $Description,
    "/du", "https://t.me/ClevVPN_bot",
    $FilePath
)

Write-Host "Signing $FilePath" -ForegroundColor Cyan

$maxAttempts = 5
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    & $signTool @arguments
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Signed: $FilePath" -ForegroundColor Green
        return
    }

    if ($attempt -lt $maxAttempts) {
        Write-Host "signtool busy, retry $attempt/$maxAttempts..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
}

throw "signtool failed with exit code $LASTEXITCODE"

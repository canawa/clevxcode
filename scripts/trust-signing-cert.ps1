$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$PfxPath = if ($env:CODESIGN_PFX) { $env:CODESIGN_PFX } else { Join-Path $Root "certs\clevvpn.pfx" }
$PfxPassword = if ($env:CODESIGN_PFX_PASSWORD) { $env:CODESIGN_PFX_PASSWORD } else { "ClevVPN" }

if (-not (Test-Path $PfxPath)) {
    throw "Certificate not found: $PfxPath. Run build-release.ps1 first."
}

$securePassword = ConvertTo-SecureString -String $PfxPassword -Force -AsPlainText
$cert = Import-PfxCertificate -FilePath $PfxPath -Password $securePassword -CertStoreLocation Cert:\LocalMachine\Root
Import-PfxCertificate -FilePath $PfxPath -Password $securePassword -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null

Write-Host "Trusted publisher certificate installed: $($cert.Subject)" -ForegroundColor Green
Write-Host "UAC should now show the publisher name on this PC." -ForegroundColor Green

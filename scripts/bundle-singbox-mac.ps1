# Downloads official sing-box darwin binaries into ClevVPNMac/Core/
# Usage: powershell -ExecutionPolicy Bypass -File scripts\bundle-singbox-mac.ps1
param(
    [string]$Version = "1.14.2"
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Out = Join-Path $Root "ClevVPNMac\Core"
$Tmp = Join-Path $Out "_tmp"
New-Item -ItemType Directory -Force -Path $Out, $Tmp | Out-Null
$Base = "https://github.com/SagerNet/sing-box/releases/download/v$Version"

foreach ($Arch in @("arm64", "amd64")) {
    $Name = "sing-box-$Version-darwin-$Arch.tar.gz"
    $Tar = Join-Path $Tmp $Name
    Write-Host "==> Downloading $Name"
    Invoke-WebRequest -Uri "$Base/$Name" -OutFile $Tar -UseBasicParsing
    $ExtractTo = Join-Path $Tmp $Arch
    New-Item -ItemType Directory -Force -Path $ExtractTo | Out-Null
    tar -xzf $Tar -C $ExtractTo
    $Bin = Get-ChildItem $ExtractTo -Recurse -Filter "sing-box" | Select-Object -First 1
    if (-not $Bin) { throw "sing-box not found in $Name" }
    Copy-Item $Bin.FullName (Join-Path $Out "sing-box-$Arch") -Force
    Write-Host "    -> sing-box-$Arch"
}

Set-Content -Path (Join-Path $Out "VERSION") -Value $Version -Encoding ascii
Remove-Item $Tmp -Recurse -Force
Write-Host "==> Bundled sing-box v$Version"

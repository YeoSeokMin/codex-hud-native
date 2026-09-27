# Build the patched codex.exe on your own machine (same steps as the GitHub Actions release).
#
#   powershell -ExecutionPolicy Bypass -File scripts\build-local.ps1          # HUD only
#   powershell -ExecutionPolicy Bypass -File scripts\build-local.ps1 -Ui      # HUD + UI
#   ... build-local.ps1 -Version 0.158.0                                      # another codex version
#
# Needs: Git, rustup, Visual Studio 2022 Build Tools (C++ workload), ~25 GB free disk, 16 GB RAM.
# First build takes 30+ minutes. Output: <Dir>\codex\codex-rs\target\release\codex.exe
# (ASCII only on purpose: Windows PowerShell 5.1 misreads non-ASCII in BOM-less files.)
param(
    [switch]$Ui,
    [string]$Version,  # codex version to build (default: CODEX_VERSION, the version the patches were ported to)
    [string]$Dir = (Join-Path $HOME 'codex-hud-build'),
    [int]$Jobs = 4  # full parallelism can run out of memory while linking
)
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot
$version = if ($Version) { $Version } else { (Get-Content (Join-Path $root 'CODEX_VERSION') -Raw).Trim() }
$src = Join-Path $Dir 'codex'

if (-not (Test-Path $src)) {
    New-Item -ItemType Directory -Force $Dir | Out-Null
    git -c core.autocrlf=false -c core.longpaths=true clone --depth 1 --branch "rust-v$version" https://github.com/openai/codex.git $src
    if ($LASTEXITCODE) { throw 'git clone failed' }
    git -C $src config core.longpaths true
} else {
    git -C $src fetch --depth 1 origin tag "rust-v$version"
    if ($LASTEXITCODE) { throw "tag rust-v$version not found" }
}

# 1) LF checkout so the LF patches apply
git -C $src config core.autocrlf false
git -C $src checkout -q -f "rust-v$version"
if ($LASTEXITCODE) { throw "checkout rust-v$version failed" }
git -C $src rm -q -r --cached .
git -C $src reset -q --hard
git -C $src clean -fdq

git -C $src apply (Join-Path $root 'patches\hud.patch')
if ($LASTEXITCODE) { throw 'hud.patch does not apply' }
if ($Ui) {
    git -C $src apply (Join-Path $root 'patches\ui.patch')
    if ($LASTEXITCODE) { throw 'ui.patch does not apply' }
}

# 2) Back to a CRLF checkout, like the official Windows build. sqlx embeds a checksum of each
#    migration .sql file including its line endings; an LF build rejects conversation DBs created
#    by official codex with "migration N was previously applied but has been modified".
git -C $src add -A
git -C $src -c user.name=local -c user.email=local@localhost commit -q -m 'codex-hud-native patches'
git -C $src config core.autocrlf true
git -C $src rm -q -r --cached .
git -C $src reset -q --hard

Push-Location (Join-Path $src 'codex-rs')
try {
    $channel = (Select-String -Path rust-toolchain.toml -Pattern 'channel\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
    $env:RUSTUP_TOOLCHAIN = "$channel-x86_64-pc-windows-msvc"  # v8 only ships MSVC builds
    rustup toolchain install $env:RUSTUP_TOOLCHAIN --profile minimal
    $env:AWS_LC_SYS_PREBUILT_NASM = '1'
    cargo build --release -j $Jobs -p codex-cli --bin codex
    if ($LASTEXITCODE) { throw 'cargo build failed' }
} finally {
    Pop-Location
}

$exe = Join-Path $src 'codex-rs\target\release\codex.exe'
& $exe --version
Write-Host ''
Write-Host "Built: $exe"
Write-Host 'To use it, close every codex window, back up the official codex.exe in'
Write-Host '  <npm root -g>\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\bin'
Write-Host "as codex.official.exe, then copy the built codex.exe over it (npm must have codex $version installed)."

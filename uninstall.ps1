# codex-hud-native 제거 스크립트 (Windows x64)
#
#   irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/uninstall.ps1 | iex
#
# 공식 codex.exe 복원 → config.toml 에서 설치 때 넣은 줄 제거·주석 처리했던 줄 복원 → HUD 스크립트 삭제
# 이 파일은 BOM 없는 UTF-8 이어야 한다 (BOM 이 있으면 irm | iex 가 첫 줄에서 깨짐).

function Uninstall-CodexHud {
    $ErrorActionPreference = 'Stop'
    $Mark = '  # codex-hud-native'
    $Off = '#codex-hud-native-off# '

    function Write-Step([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }

    # ---- 1. 공식 codex.exe 복원 ----
    if (Get-Command npm.cmd -ErrorAction SilentlyContinue) {
        $npmRoot = (& npm.cmd root -g | Select-Object -Last 1).Trim()
        $packageDir = Join-Path $npmRoot '@openai\codex'
        $exe = $null
        foreach ($dir in @('@openai\codex\node_modules\@openai\codex-win32-x64', '@openai\codex-win32-x64', '@openai\codex')) {
            $candidate = Join-Path $npmRoot (Join-Path $dir 'vendor\x86_64-pc-windows-msvc\bin\codex.exe')
            if (Test-Path -LiteralPath $candidate) { $exe = $candidate; break }
        }
        if ($exe) {
            $running = @(Get-Process -ErrorAction SilentlyContinue |
                    Where-Object { $_.Path -and $_.Path.StartsWith($packageDir, [StringComparison]::OrdinalIgnoreCase) })
            if ($running.Count) { throw '열려 있는 codex 를 모두 종료한 뒤 다시 실행하세요.' }
            $backup = Join-Path (Split-Path $exe) 'codex.official.exe'
            if (Test-Path -LiteralPath $backup) {
                Write-Step '공식 codex.exe 복원'
                Move-Item -LiteralPath $backup -Destination $exe -Force
            } else {
                $version = (Get-Content -LiteralPath (Join-Path $packageDir 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version
                Write-Step "백업이 없어 npm 으로 공식 codex $version 재설치"
                & npm.cmd install -g "@openai/codex@$version" --force
                if ($LASTEXITCODE -ne 0) { throw "npm install -g @openai/codex@$version 실패" }
            }
        } else {
            Write-Step 'npm 으로 설치된 codex 가 없어 실행 파일 복원은 건너뜀'
        }
    }

    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }

    # ---- 2. config.toml 되돌리기 ----
    $configPath = Join-Path $codexHome 'config.toml'
    if (Test-Path -LiteralPath $configPath) {
        $old = [IO.File]::ReadAllText($configPath)
        $nl = if ($old.Contains("`r`n")) { "`r`n" } else { "`n" }
        $lines = New-Object 'System.Collections.Generic.List[string]'
        foreach ($line in ($old -split '\r?\n')) {
            if ($line.EndsWith($Mark)) { continue }
            if ($line.StartsWith($Off)) { $line = $line.Substring($Off.Length) }
            $lines.Add($line)
        }
        while ($lines.Count -and $lines[$lines.Count - 1].Trim() -eq '') { $lines.RemoveAt($lines.Count - 1) }
        $new = if ($lines.Count) { ($lines -join $nl) + $nl } else { '' }
        if ($new -cne $old) {
            Write-Step "설정 되돌리기 ($configPath)"
            Copy-Item -LiteralPath $configPath -Destination ("$configPath.bak-codex-hud-uninstall-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
            [IO.File]::WriteAllText($configPath, $new, (New-Object System.Text.UTF8Encoding $false))
        }
    }

    # ---- 3. HUD 스크립트 삭제 ----
    $hudDir = Join-Path $codexHome 'hud'
    foreach ($name in 'codex-hud.mjs', 'codex-hud.mjs.bak') {
        $path = Join-Path $hudDir $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if ((Test-Path -LiteralPath $hudDir) -and -not (Get-ChildItem -LiteralPath $hudDir -Force)) {
        Remove-Item -LiteralPath $hudDir -Force
    }

    Write-Host ''
    Write-Host '제거 완료: 공식 codex 로 돌아왔고 업데이트 알림도 다시 켜졌습니다.' -ForegroundColor Green
}

try {
    Uninstall-CodexHud
} catch {
    Write-Host ''
    Write-Host "제거 실패: $($_.Exception.Message)" -ForegroundColor Red
}

# codex-hud-native 제거 스크립트 (Windows x64)
#
#   irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/uninstall.ps1 | iex
#
# 설치 기록(~/.codex/hud/install-state.json)을 보고 되돌린다.
#   기본 교체 방식: 공식 codex.exe 복원 → config.toml 에서 넣은 줄 제거·주석 처리했던 줄 복원
#   -Side 방식:     codex-hud 명령·실행기·codex-hud.exe 삭제
#   공통:           HUD 스크립트와 설치 기록 삭제. codex 버전은 낮추지 않는다(대화 기록 DB 보호).
# 이 파일은 BOM 없는 UTF-8 이어야 한다 (BOM 이 있으면 irm | iex 가 첫 줄에서 깨짐).

# irm | iex 로 실행하면 사용자 창을 닫지 않도록 exit 하지 않는다. 이 파일을 직접 실행했을 때만 exit 1.
$CodexHudInvokedAsFile = ($MyInvocation.MyCommand.CommandType -eq 'ExternalScript') -and
    ($MyInvocation.MyCommand.ScriptContents -match 'function Uninstall-CodexHud')

function Uninstall-CodexHud {
    $ErrorActionPreference = 'Stop'
    $Mark = '  # codex-hud-native'
    $Off = '#codex-hud-native-off# '

    function Write-Step([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }

    function Invoke-Quiet([scriptblock]$Block) {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'  # PS 5.1 은 네이티브 stderr 를 오류로 바꿔 던지므로 잠시 끈다
        try { & $Block } finally { $ErrorActionPreference = $prev }
    }

    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
    $hudDir = Join-Path $codexHome 'hud'
    $stateFile = Join-Path $hudDir 'install-state.json'
    $state = $null
    if (Test-Path -LiteralPath $stateFile) { $state = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json }

    $npmRoot = $null
    if (Get-Command npm.cmd -ErrorAction SilentlyContinue) {
        $npmRoot = Invoke-Quiet { & npm.cmd root -g | Select-Object -Last 1 }
        if ($npmRoot) { $npmRoot = $npmRoot.Trim() }
    }
    $notes = @()

    if ($npmRoot) {
        $npmPrefix = Split-Path $npmRoot -Parent
        $packageDir = Join-Path $npmRoot '@openai\codex'
        $running = @(Get-Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -and $_.Path.StartsWith($packageDir, [StringComparison]::OrdinalIgnoreCase) })
        if ($running.Count) { throw '열려 있는 codex 를 모두 종료한 뒤 다시 실행하세요. 아무것도 바꾸지 않았습니다.' }

        $exe = $null
        foreach ($dir in @('@openai\codex\node_modules\@openai\codex-win32-x64', '@openai\codex-win32-x64', '@openai\codex')) {
            $candidate = Join-Path $npmRoot (Join-Path $dir 'vendor\x86_64-pc-windows-msvc\bin\codex.exe')
            if (Test-Path -LiteralPath $candidate) { $exe = $candidate; break }
        }
        $version = $null
        if (Test-Path -LiteralPath (Join-Path $packageDir 'package.json')) {
            $version = (Get-Content -LiteralPath (Join-Path $packageDir 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version
        }

        # ---- 1. codex-hud 명령 (-Side) ----
        $sideFiles = @('codex-hud.cmd', 'codex-hud', 'codex-hud-launcher.mjs', 'codex-hud.json') | ForEach-Object { Join-Path $npmPrefix $_ }
        if ($exe) { $sideFiles += Join-Path (Split-Path $exe) 'codex-hud.exe' }
        $existing = @($sideFiles | Where-Object { Test-Path -LiteralPath $_ })
        if ($existing.Count) {
            Write-Step 'codex-hud 명령 삭제'
            Remove-Item -LiteralPath $existing -Force
        }

        # ---- 2. 공식 codex.exe 복원 (기본 교체 방식) ----
        if ($exe) {
            $backup = Join-Path (Split-Path $exe) 'codex.official.exe'
            if (Test-Path -LiteralPath $backup) {
                Write-Step '공식 codex.exe 복원'
                Move-Item -LiteralPath $backup -Destination $exe -Force
            } else {
                # 백업이 없는데 codex.exe 가 HUD 빌드인지: HUD 빌드만 status_line_command 에 숫자를 주면 거부한다
                Invoke-Quiet { & $exe -c 'tui.status_line_command=3' features list *> $null }
                if ($LASTEXITCODE -ne 0) {
                    Invoke-Quiet { & $exe -c 'tui.status_line_command=x' features list *> $null }
                    if ($LASTEXITCODE -eq 0 -and $version) {
                        Write-Step "백업이 없어 npm 으로 공식 codex $version 을 다시 받음 (버전 변경 없음)"
                        Invoke-Quiet { & npm.cmd install -g "@openai/codex@$version" --force }
                        if ($LASTEXITCODE -ne 0) { throw "npm install -g @openai/codex@$version 실패" }
                    }
                }
            }
        }

        if ($state -and $state.version_change -eq 'upgrade' -and $state.previous_version) {
            $notes += "설치할 때 codex 를 $($state.previous_version) → $($state.codex_version) 으로 올렸습니다. 버전을 다시 낮추면 대화 기록 DB 가 깨질 수 있어 그대로 둡니다."
        } elseif ($state -and $state.version_change -eq 'fresh') {
            $notes += "codex 는 설치할 때 새로 깔았습니다. 필요 없으면: npm uninstall -g @openai/codex"
        }
    } else {
        $notes += 'npm 을 찾지 못해 codex 실행 파일은 확인하지 못했습니다.'
    }

    # ---- 3. config.toml 되돌리기 ----
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

    # ---- 4. HUD 스크립트와 설치 기록 삭제 ----
    foreach ($name in 'codex-hud.mjs', 'codex-hud.mjs.bak', 'install-state.json') {
        $path = Join-Path $hudDir $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if ((Test-Path -LiteralPath $hudDir) -and -not (Get-ChildItem -LiteralPath $hudDir -Force)) {
        Remove-Item -LiteralPath $hudDir -Force
    }

    Write-Host ''
    Write-Host '제거 완료: 공식 codex 로 돌아왔습니다.' -ForegroundColor Green
    foreach ($note in $notes) { Write-Host "  - $note" }
}

try {
    Uninstall-CodexHud
    $global:LASTEXITCODE = 0
} catch {
    Write-Host ''
    Write-Host "제거 실패: $($_.Exception.Message)" -ForegroundColor Red
    $global:LASTEXITCODE = 1
    # 파일로 실행했거나 powershell -Command 로 한 번 실행하고 끝나는 경우만 exit 1 (대화형 창은 닫지 않는다)
    $hostArgs = [Environment]::GetCommandLineArgs()
    $oneShot = @($hostArgs | Where-Object { $_ -match '^[-/](c|command|ec|encodedcommand|f|file)$' }).Count -gt 0 -and
        @($hostArgs | Where-Object { $_ -match '^[-/]noexit$' }).Count -eq 0
    if ($CodexHudInvokedAsFile -or $oneShot) { exit 1 }
}

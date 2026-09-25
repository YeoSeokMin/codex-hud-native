# codex-hud-native 설치 스크립트 (Windows x64)
#
#   HUD만:        irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/install.ps1 | iex
#   HUD + UI 개조: iex "& { $(irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/install.ps1) } -Ui"
#
# 순서: 릴리스 정보 확인 → npm 으로 codex 버전 맞춤 → 공식 codex.exe 를 codex.official.exe 로 백업
#       → 패치된 codex.exe 로 교체 → HUD 스크립트 설치 → config.toml 에 설정 추가 → 검증
# 이 파일은 BOM 없는 UTF-8 이어야 한다 (BOM 이 있으면 irm | iex 가 첫 줄에서 깨짐).
param(
    [switch]$Ui,               # HUD + Claude 식 화면 개조 버전
    [string]$Tag,              # 특정 릴리스 태그 (기본: 최신 릴리스)
    [switch]$KeepUpdateCheck,  # codex 업데이트 알림을 끄지 않음
    [string]$ReleaseBase       # (개발용) 릴리스 파일을 받을 주소
)

function Install-CodexHud {
    param([switch]$Ui, [string]$Tag, [switch]$KeepUpdateCheck, [string]$ReleaseBase)

    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'  # PS 5.1 은 진행률 표시 때문에 다운로드가 매우 느려짐
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $Repo = 'YeoSeokMin/codex-hud-native'
    $Mark = '  # codex-hud-native'
    $Off = '#codex-hud-native-off# '
    if (-not $ReleaseBase) {
        $ReleaseBase = if ($Tag) { "https://github.com/$Repo/releases/download/$Tag" } else { "https://github.com/$Repo/releases/latest/download" }
    }
    $Variant = if ($Ui) { 'hud-ui' } else { 'hud' }
    $Label = if ($Ui) { 'HUD + UI 개조' } else { 'HUD' }

    function Write-Step([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }

    function Get-Sha256([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }

    function Find-CodexExe([string]$NpmRoot) {
        $tail = 'vendor\x86_64-pc-windows-msvc\bin\codex.exe'
        foreach ($dir in @(
                '@openai\codex\node_modules\@openai\codex-win32-x64',
                '@openai\codex-win32-x64',
                '@openai\codex')) {
            $candidate = Join-Path $NpmRoot (Join-Path $dir $tail)
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
        return $null
    }

    function Assert-NotRunning([string]$Dir) {
        if (-not (Test-Path -LiteralPath $Dir)) { return }
        $running = @(Get-Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -and $_.Path.StartsWith($Dir, [StringComparison]::OrdinalIgnoreCase) })
        if ($running.Count) {
            $ids = ($running | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ', '
            throw "codex 가 실행 중입니다: $ids`n    열려 있는 codex 를 모두 종료한 뒤 다시 실행하세요."
        }
    }

    function Save-File([string]$Name, [string]$Dest, [string]$Sha256) {
        Invoke-WebRequest -UseBasicParsing -Uri "$ReleaseBase/$Name" -OutFile $Dest
        if ($Sha256 -and (Get-Sha256 $Dest) -ne $Sha256.ToLowerInvariant()) {
            throw "$Name 해시가 릴리스 정보와 다릅니다. 다운로드가 손상됐을 수 있으니 다시 실행하세요."
        }
    }

    # config.toml 을 줄 단위로 고친다. 추가한 줄은 끝에 $Mark, 끈 줄은 앞에 $Off 를 붙여 제거 스크립트가 되돌릴 수 있게 한다.
    function Update-CodexConfig([string]$Path, [string]$HudPath, [bool]$DisableUpdateCheck) {
        $old = if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { '' }
        $nl = if ($old.Contains("`r`n")) { "`r`n" } else { "`n" }

        # 이전 설치 흔적을 먼저 되돌려서 다시 설치해도 중복되지 않게 한다
        $lines = New-Object 'System.Collections.Generic.List[string]'
        foreach ($line in ($old -split '\r?\n')) {
            if ($line.EndsWith($Mark)) { continue }
            if ($line.StartsWith($Off)) { $line = $line.Substring($Off.Length) }
            $lines.Add($line)
        }
        while ($lines.Count -and $lines[$lines.Count - 1].Trim() -eq '') { $lines.RemoveAt($lines.Count - 1) }

        $firstHeader = $lines.Count
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[') { $firstHeader = $i; break } }
        for ($i = 0; $i -lt $firstHeader; $i++) {
            if ($lines[$i] -match '^\s*tui\s*[.=]') {
                throw "config.toml 에 tui 설정이 [tui] 표가 아닌 형태($($lines[$i].Trim()))로 있어 자동 수정을 멈췄습니다.`n    [tui] 표로 바꾼 뒤 다시 실행하세요."
            }
        }

        $hud = $HudPath -replace '\\', '/'
        $ours = [string[]]@(
            ('status_line_command = "node \"' + $hud + '\""' + $Mark),
            ('status_line = []' + $Mark)
        )

        $tuiIndex = -1
        for ($i = $firstHeader; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[\s*tui\s*\]\s*(#.*)?$') { $tuiIndex = $i; break } }
        if ($tuiIndex -ge 0) {
            # 기존 status_line / status_line_command 는 지우지 않고 주석 처리 (여러 줄 배열 포함)
            $inArray = $false
            for ($i = $tuiIndex + 1; $i -lt $lines.Count -and $lines[$i] -notmatch '^\s*\['; $i++) {
                if ($inArray) {
                    if ($lines[$i] -match '\]') { $inArray = $false }
                    $lines[$i] = $Off + $lines[$i]
                } elseif ($lines[$i] -match '^\s*status_line(_command)?\s*=') {
                    $inArray = ($lines[$i] -match '=\s*\[') -and ($lines[$i] -notmatch '\]')
                    $lines[$i] = $Off + $lines[$i]
                }
            }
            $lines.InsertRange($tuiIndex + 1, $ours)
        } else {
            if ($lines.Count) { $lines.Add('') }
            $lines.Add('[tui]' + $Mark)
            $lines.AddRange($ours)
        }

        if ($DisableUpdateCheck) {
            for ($i = 0; $i -lt $firstHeader; $i++) {
                if ($lines[$i] -match '^\s*check_for_update_on_startup\s*=') { $lines[$i] = $Off + $lines[$i] }
            }
            $lines.Insert(0, 'check_for_update_on_startup = false' + $Mark)
        }

        $new = ($lines -join $nl) + $nl
        if ($new -ceq $old) { return $null }
        $backup = $null
        if ($old) {
            $backup = "$Path.bak-codex-hud-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
            Copy-Item -LiteralPath $Path -Destination $backup
        }
        [IO.File]::WriteAllText($Path, $new, (New-Object System.Text.UTF8Encoding $false))
        return $backup
    }

    # ---- 0. 환경 확인 ----
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if ($arch -ne 'AMD64') { throw "Windows x64 만 지원합니다 (현재: $arch)." }
    if (-not (Get-Command node.exe -ErrorAction SilentlyContinue) -or -not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
        throw 'Node.js(npm 포함)가 필요합니다. https://nodejs.org 에서 LTS 를 설치하고 새 PowerShell 창에서 다시 실행하세요.'
    }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('codex-hud-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        # ---- 1. 릴리스 정보 ----
        Write-Step '릴리스 정보 확인'
        # GitHub 릴리스 파일은 octet-stream 으로 오므로 파일로 받아 UTF-8 로 읽는다
        $manifestFile = Join-Path $tmp 'manifest.json'
        Save-File 'manifest.json' $manifestFile $null
        $manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $version = $manifest.codex_version
        $asset = $manifest.variants.$Variant
        if (-not $version -or -not $asset) { throw "릴리스 정보에 '$Variant' 버전이 없습니다." }
        Write-Host "    릴리스 $($manifest.tag): codex $version + $Label"

        # ---- 2. codex 버전 맞추기 ----
        $npmRoot = (& npm.cmd root -g | Select-Object -Last 1)
        if ($LASTEXITCODE -ne 0 -or -not $npmRoot) { throw 'npm 전역 폴더를 찾지 못했습니다 (npm root -g 실패).' }
        $npmRoot = $npmRoot.Trim()
        $packageDir = Join-Path $npmRoot '@openai\codex'
        $packageJson = Join-Path $packageDir 'package.json'
        Assert-NotRunning $packageDir  # 다운로드 전에 미리 알려준다 (교체 직전에 한 번 더 확인)
        $installed = $null
        if (Test-Path -LiteralPath $packageJson) {
            $installed = (Get-Content -LiteralPath $packageJson -Raw -Encoding UTF8 | ConvertFrom-Json).version
        }

        $exe = Find-CodexExe $npmRoot
        $isOfficial = $false
        $needInstall = ($installed -ne $version) -or (-not $exe)
        if (-not $needInstall) {
            $backup = Join-Path (Split-Path $exe) 'codex.official.exe'
            $isOfficial = (Get-Sha256 $exe) -eq $manifest.official_sha256
            $backupOk = (Test-Path -LiteralPath $backup) -and ((Get-Sha256 $backup) -eq $manifest.official_sha256)
            # 지금 codex.exe 가 공식본도 아니고 공식 백업도 없으면 상태를 믿을 수 없으니 공식본부터 다시 받는다
            if (-not $isOfficial -and -not $backupOk) { $needInstall = $true }
        }

        if ($needInstall) {
            $from = if ($installed) { "$installed → " } else { '' }
            Write-Step "codex 설치 (npm, $from$version)"
            & npm.cmd install -g "@openai/codex@$version"
            if ($LASTEXITCODE -ne 0) {
                throw "npm install -g @openai/codex@$version 실패. 권한 오류(EPERM)라면 관리자 PowerShell 에서 다시 실행하세요."
            }
            $exe = Find-CodexExe $npmRoot
            if (-not $exe) { throw 'npm 설치 후에도 codex.exe 를 찾지 못했습니다.' }
            if ((Get-Sha256 $exe) -ne $manifest.official_sha256) {
                Write-Warning '방금 받은 공식 codex.exe 해시가 릴리스 정보와 다릅니다. 새로 받은 파일을 공식본으로 보고 계속합니다.'
            }
            $isOfficial = $true
        } else {
            Write-Step "codex $version 이미 설치됨"
        }

        # ---- 3. 패치된 codex.exe 받기 ----
        Write-Step "패치된 codex 다운로드 ($($asset.file))"
        $zip = Join-Path $tmp $asset.file
        Save-File $asset.file $zip $asset.sha256
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'x') -Force
        $patched = Join-Path $tmp 'x\codex.exe'
        if (-not (Test-Path -LiteralPath $patched) -or (Get-Sha256 $patched) -ne $asset.exe_sha256) {
            throw '압축을 푼 codex.exe 가 릴리스 정보와 다릅니다.'
        }

        # ---- 4. 백업 후 교체 ----
        $backup = Join-Path (Split-Path $exe) 'codex.official.exe'
        if ((Get-Sha256 $exe) -eq $asset.exe_sha256) {
            Write-Step 'codex.exe 는 이미 이 버전으로 패치돼 있음'
        } else {
            Write-Step 'codex.exe 교체 (공식본은 codex.official.exe 로 보관)'
            Assert-NotRunning $packageDir
            if ($isOfficial) { Copy-Item -LiteralPath $exe -Destination $backup -Force }
            Copy-Item -LiteralPath $patched -Destination $exe -Force
        }

        # ---- 5. HUD 스크립트 ----
        $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
        $hudDir = Join-Path $codexHome 'hud'
        $hudFile = Join-Path $hudDir 'codex-hud.mjs'
        Write-Step "HUD 스크립트 설치 ($hudFile)"
        New-Item -ItemType Directory -Force -Path $hudDir | Out-Null
        $hudNew = Join-Path $tmp 'codex-hud.mjs'
        Save-File 'codex-hud.mjs' $hudNew $manifest.hud_script_sha256
        if ((Test-Path -LiteralPath $hudFile) -and (Get-Sha256 $hudFile) -ne $manifest.hud_script_sha256) {
            Copy-Item -LiteralPath $hudFile -Destination "$hudFile.bak" -Force
            Write-Host "    기존 스크립트는 $hudFile.bak 으로 보관"
        }
        Copy-Item -LiteralPath $hudNew -Destination $hudFile -Force
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ---- 6. config.toml ----
    $configPath = Join-Path $codexHome 'config.toml'
    Write-Step "설정 추가 ($configPath)"
    $configBackup = Update-CodexConfig $configPath $hudFile (-not $KeepUpdateCheck)
    if ($configBackup) { Write-Host "    원래 설정은 $configBackup 에 백업" }

    # ---- 7. 검증 ----
    Write-Step '검증'
    $prevPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'  # PS 5.1 은 네이티브 stderr 를 오류로 바꿔 던지므로 잠시 끈다
    $versionText = & $exe --version 2>$null | Select-Object -First 1
    & $exe features list *> $null
    $configOk = $LASTEXITCODE -eq 0
    $hudText = '{}' | & node.exe $hudFile 2>$null
    $hudOk = ($LASTEXITCODE -eq 0) -and $hudText
    $ErrorActionPreference = $prevPreference
    if (-not $configOk) {
        if ($configBackup) { Copy-Item -LiteralPath $configBackup -Destination $configPath -Force }
        throw "수정한 config.toml 을 codex 가 읽지 못해 원래대로 되돌렸습니다. $configPath 를 확인하세요."
    }
    if (-not $hudOk) { throw "HUD 스크립트 실행 실패: node `"$hudFile`"" }
    Write-Host "    $versionText / 설정 OK / HUD 스크립트 OK"

    $first = Get-Command codex -All -ErrorAction SilentlyContinue | Where-Object { $_.Source } | Select-Object -First 1
    $npmPrefix = Split-Path $npmRoot
    if ($first -and -not $first.Source.StartsWith($npmPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Warning "PATH 에서 다른 codex($($first.Source))가 먼저 잡힙니다. 그 codex 로는 HUD 가 보이지 않습니다."
    }

    Write-Host ''
    Write-Host "설치 완료: codex $version + $Label" -ForegroundColor Green
    Write-Host '  - 새로 codex 를 실행하면 입력창 아래에 HUD 가 보입니다.'
    Write-Host '  - 5시간/주간 사용량 줄은 ChatGPT 로그인 상태에서 첫 응답을 받은 뒤부터 나옵니다.'
    if (-not $KeepUpdateCheck) {
        Write-Host '  - codex 업데이트 알림을 껐습니다. 업데이트하면 공식본으로 덮여 HUD 가 사라지기 때문입니다.'
    }
    Write-Host '  - 새 버전이 나오면 같은 설치 명령을 다시 실행하세요.'
    Write-Host "  - 제거: irm https://raw.githubusercontent.com/$Repo/main/uninstall.ps1 | iex"
}

try {
    Install-CodexHud -Ui:$Ui -Tag $Tag -KeepUpdateCheck:$KeepUpdateCheck -ReleaseBase $ReleaseBase
} catch {
    Write-Host ''
    Write-Host "설치 실패: $($_.Exception.Message)" -ForegroundColor Red
}

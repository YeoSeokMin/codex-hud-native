# codex-hud-native 설치 스크립트 (Windows x64)
#
#   HUD만:            irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/install.ps1 | iex
#   HUD + UI 개조:     iex "& { $(irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/install.ps1) } -Ui"
#   codex-hud 명령으로: iex "& { $(irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/install.ps1) } -Side"
#
# 순서: 설치된 codex 버전에 맞는 릴리스 고르기(버전은 절대 낮추지 않음) → 다운로드·해시 검증 → 사전 점검
#       (실행 중, 설정, codex 명령 연결, DB) → 변경(실패하면 되돌림) → 검증 → 설치 기록 저장
# 이 파일은 BOM 없는 UTF-8 이어야 한다 (BOM 이 있으면 irm | iex 가 첫 줄에서 깨짐).
param(
    [switch]$Ui,               # HUD + Claude 식 화면 개조 버전
    [switch]$Side,             # 공식 codex 는 그대로 두고 codex-hud 명령을 따로 설치
    [string]$Tag,              # 특정 릴리스 태그 (기본: 설치된 codex 버전에 맞는 릴리스)
    [switch]$KeepUpdateCheck,  # codex 업데이트 알림을 끄지 않음 (기본 교체 방식에서만 의미 있음)
    [switch]$NoCommandCheck,   # codex 명령이 npm codex 가 아닌 파일을 가리켜도 진행 (직접 만든 래퍼가 npm codex 를 부를 때)
    [string]$ReleaseBase       # (개발용) manifest.json 을 받을 주소. 지정하면 릴리스 고르기를 건너뜀
)

# irm | iex 로 실행하면 사용자 창을 닫지 않도록 exit 하지 않는다. 이 파일을 직접 실행했을 때만 exit 1.
$CodexHudInvokedAsFile = ($MyInvocation.MyCommand.CommandType -eq 'ExternalScript') -and
    ($MyInvocation.MyCommand.ScriptContents -match 'function Install-CodexHud')

function Install-CodexHud {
    param([switch]$Ui, [switch]$Side, [string]$Tag, [switch]$KeepUpdateCheck, [switch]$NoCommandCheck, [string]$ReleaseBase)

    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'  # PS 5.1 은 진행률 표시 때문에 다운로드가 매우 느려짐
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $Repo = 'YeoSeokMin/codex-hud-native'
    $RawBase = "https://raw.githubusercontent.com/$Repo/main"
    $Mark = '  # codex-hud-native'
    $Off = '#codex-hud-native-off# '
    $Variant = if ($Ui) { 'hud-ui' } else { 'hud' }
    $Label = if ($Ui) { 'HUD + UI 개조' } else { 'HUD' }
    $ModeLabel = if ($Side) { 'codex-hud 명령 따로 설치' } else { '기본 codex 교체' }

    function Write-Step([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }

    function Get-Sha256([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }

    # 0.157.1 / 0.158.0-alpha.1 같은 문자열을 비교용 [version] 으로
    function ConvertTo-CodexVersion([string]$Text) { [version](($Text -split '[-+]')[0]) }

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
            throw "codex 가 실행 중입니다: $ids`n    열려 있는 codex 를 모두 종료한 뒤 다시 실행하세요. 아무것도 바꾸지 않았습니다."
        }
    }

    function Save-File([string]$Url, [string]$Dest, [string]$Sha256) {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Dest
        if ($Sha256 -and (Get-Sha256 $Dest) -ne $Sha256.ToLowerInvariant()) {
            throw "$(Split-Path $Url -Leaf) 해시가 릴리스 정보와 다릅니다. 다운로드가 손상됐을 수 있으니 다시 실행하세요."
        }
    }

    # 릴리스 태그 v<codex 버전> 또는 v<codex 버전>-<N> 목록. API 가 막히면 $null
    function Get-ReleaseList {
        try {
            $items = Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/$Repo/releases?per_page=100" -Headers @{ 'User-Agent' = 'codex-hud-native-installer' }
        } catch { return $null }
        $list = @()
        foreach ($r in @($items)) {
            if ($r.draft -or $r.prerelease) { continue }
            if ($r.tag_name -match '^v(\d+\.\d+\.\d+)(?:-(\d+))?$') {
                $list += [pscustomobject]@{ Tag = $r.tag_name; Version = $Matches[1]; Rev = [int]('0' + $Matches[2]) }
            }
        }
        return , $list
    }

    function Test-UrlExists([string]$Url) {
        try { Invoke-WebRequest -UseBasicParsing -Uri $Url -Method Head | Out-Null; return $true } catch { return $false }
    }

    # config.toml 새 내용을 만든다(쓰지는 않음). 추가 줄 끝엔 $Mark, 끈 줄 앞엔 $Off 를 붙여 제거 스크립트가 되돌릴 수 있게 한다.
    function New-ConfigText([string]$Old, [string]$HudCommand, [bool]$DisableUpdateCheck) {
        $nl = if ($Old.Contains("`r`n")) { "`r`n" } else { "`n" }
        $lines = New-Object 'System.Collections.Generic.List[string]'
        foreach ($line in ($Old -split '\r?\n')) {
            if ($line.EndsWith($Mark)) { continue }  # 이전 설치 흔적은 되돌려서 중복되지 않게
            if ($line.StartsWith($Off)) { $line = $line.Substring($Off.Length) }
            $lines.Add($line)
        }
        while ($lines.Count -and $lines[$lines.Count - 1].Trim() -eq '') { $lines.RemoveAt($lines.Count - 1) }

        $firstHeader = $lines.Count
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[') { $firstHeader = $i; break } }
        for ($i = 0; $i -lt $firstHeader; $i++) {
            if ($lines[$i] -match '^\s*tui\s*[.=]') {
                throw "config.toml 에 tui 설정이 [tui] 표가 아닌 형태($($lines[$i].Trim()))로 있어 멈췄습니다. 아무것도 바꾸지 않았습니다.`n    [tui] 표로 바꾼 뒤 다시 실행하세요."
            }
        }

        $ours = [string[]]@(('status_line_command = ' + $HudCommand + $Mark), ('status_line = []' + $Mark))
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
        return ($lines -join $nl) + $nl
    }

    # codex 가 대화 기록 DB(sqlite)를 열 수 있는지. app-server 는 입력이 없으면 DB 를 초기화하고 바로 끝난다.
    # migration 불일치(다른 버전이 만든 DB)면 여기서 실패한다. 실패해도 DB 파일은 건드리지 않는다.
    function Test-StateDb([string]$Exe) {
        $empty = Join-Path $tmp 'empty-stdin.txt'
        [IO.File]::WriteAllBytes($empty, [byte[]]@())
        $errFile = Join-Path $tmp 'db-check-err.txt'
        $p = Start-Process -FilePath $Exe -ArgumentList 'app-server' -WorkingDirectory $tmp -NoNewWindow -PassThru `
            -RedirectStandardInput $empty -RedirectStandardOutput (Join-Path $tmp 'db-check-out.txt') -RedirectStandardError $errFile
        $null = $p.Handle  # PS 5.1 은 이걸 잡아 두지 않으면 ExitCode 가 비어 있음
        if (-not $p.WaitForExit(60000)) {
            try { $p.Kill() } catch { }
            return 'DB 확인이 60초 안에 끝나지 않았습니다.'
        }
        if ($p.ExitCode -eq 0) { return $null }
        $text = if (Test-Path -LiteralPath $errFile) { [IO.File]::ReadAllText($errFile) -replace "$([char]27)\[[0-9;]*m", '' } else { '' }
        $lines = @($text -split '\r?\n' | Where-Object { $_ -match 'error|migration' -and $_ -notmatch 'Project-local config' } | Select-Object -First 3)
        return "exit $($p.ExitCode): " + ($lines -join ' / ')
    }

    # 사용자가 치는 명령이 HUD 빌드를 실행하는지. HUD 빌드만 tui.status_line_command 에 숫자를 주면 설정 오류로 거부한다.
    function Test-HudCommand([scriptblock]$Run) {
        if ((& $Run 'tui.status_line_command=x') -ne 0) { return 'error' }
        if ((& $Run 'tui.status_line_command=3') -ne 0) { return 'hud' }
        return 'official'
    }

    function Invoke-Quiet([scriptblock]$Block) {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'  # PS 5.1 은 네이티브 stderr 를 오류로 바꿔 던지므로 잠시 끈다
        try { & $Block } finally { $ErrorActionPreference = $prev }
    }

    function Get-FirstCommandTargets([string]$Name) {
        $ps = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        $psText = if (-not $ps) { $null } elseif ($ps.CommandType -in 'Application', 'ExternalScript') { $ps.Source } else { "$($ps.CommandType) $Name" }
        $cmdText = Invoke-Quiet { & where.exe $Name 2>$null | Select-Object -First 1 }
        return [pscustomobject]@{ PowerShell = $psText; Cmd = $cmdText }
    }

    function Test-UnderDir([string]$Path, [string]$Dir) {
        $Path -and ((Split-Path $Path -Parent).TrimEnd('\') -ieq $Dir.TrimEnd('\'))
    }

    # ---- 0. 환경 확인 ----
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if ($arch -ne 'AMD64') { throw "Windows x64 만 지원합니다 (현재: $arch)." }
    if (-not (Get-Command node.exe -ErrorAction SilentlyContinue) -or -not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
        throw 'Node.js(npm 포함)가 필요합니다. https://nodejs.org 에서 LTS 를 설치하고 새 PowerShell 창에서 다시 실행하세요.'
    }

    $npmRoot = Invoke-Quiet { & npm.cmd root -g | Select-Object -Last 1 }
    if (-not $npmRoot) { throw 'npm 전역 폴더를 찾지 못했습니다 (npm root -g 실패).' }
    $npmRoot = $npmRoot.Trim()
    $npmPrefix = Split-Path $npmRoot -Parent
    $packageDir = Join-Path $npmRoot '@openai\codex'
    $packageJson = Join-Path $packageDir 'package.json'
    $installed = $null
    if (Test-Path -LiteralPath $packageJson) {
        $installed = (Get-Content -LiteralPath $packageJson -Raw -Encoding UTF8 | ConvertFrom-Json).version
    }
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
    $hudDir = Join-Path $codexHome 'hud'
    $hudFile = Join-Path $hudDir 'codex-hud.mjs'
    $stateFile = Join-Path $hudDir 'install-state.json'
    $configPath = Join-Path $codexHome 'config.toml'
    $shimCmd = Join-Path $npmPrefix 'codex-hud.cmd'
    $shimSh = Join-Path $npmPrefix 'codex-hud'
    $launcher = Join-Path $npmPrefix 'codex-hud-launcher.mjs'
    $launcherState = Join-Path $npmPrefix 'codex-hud.json'

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('codex-hud-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        # ---- 1. 릴리스 고르기: 설치된 codex 와 같은 버전 우선, 버전은 절대 낮추지 않는다 ----
        Write-Step '릴리스 고르기'
        $installedText = if ($installed) { $installed } else { '(설치 안 됨)' }
        Write-Host "    현재 npm codex: $installedText / 방식: $ModeLabel / 버전: $Label"
        if ($ReleaseBase) {
            $base = $ReleaseBase
        } elseif ($Tag) {
            $base = "https://github.com/$Repo/releases/download/$Tag"
        } else {
            $releases = Get-ReleaseList
            $pick = $null
            if ($releases -and $releases.Count) {
                if ($installed) {
                    $pick = $releases | Where-Object { $_.Version -eq $installed } | Sort-Object Rev -Descending | Select-Object -First 1
                }
                if (-not $pick) {
                    $pick = $releases | Sort-Object { ConvertTo-CodexVersion $_.Version }, Rev -Descending | Select-Object -First 1
                }
                $base = "https://github.com/$Repo/releases/download/$($pick.Tag)"
            } elseif ($null -ne $releases) {
                $want = if ($installed) { "codex $installed 용 " } else { '' }
                throw "아직 설치할 수 있는 $($want)HUD 빌드가 없습니다. 새 빌드는 보통 하루 안에 자동으로 올라옵니다. 아무것도 바꾸지 않았습니다.`n    빌드 목록: https://github.com/$Repo/releases"
            } elseif ($installed -and (Test-UrlExists "https://github.com/$Repo/releases/download/v$installed/manifest.json")) {
                $base = "https://github.com/$Repo/releases/download/v$installed"  # API 가 막혔을 때
            } else {
                $base = "https://github.com/$Repo/releases/latest/download"
            }
        }
        $manifestFile = Join-Path $tmp 'manifest.json'
        try {
            Save-File "$base/manifest.json" $manifestFile $null  # GitHub 릴리스 파일은 octet-stream 이라 파일로 받아 읽는다
        } catch {
            throw "릴리스 정보를 받지 못했습니다 ($base/manifest.json). 네트워크를 확인하거나 https://github.com/$Repo/releases 를 확인하세요. 아무것도 바꾸지 않았습니다."
        }
        $manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $version = $manifest.codex_version
        $asset = $manifest.variants.$Variant
        if (-not $version -or -not $asset) { throw "릴리스 정보에 '$Variant' 버전이 없습니다." }

        if ($installed -and (ConvertTo-CodexVersion $version) -lt (ConvertTo-CodexVersion $installed)) {
            throw (@(
                    "지금 codex $installed 에 맞는 HUD 빌드가 아직 없습니다 (가장 최근 빌드: codex $version).",
                    '    codex 버전을 낮추면 대화 기록 DB 를 새 버전이 이미 바꿔 놓아서 codex 가 실행되지 않을 수 있습니다.',
                    '    그래서 설치를 멈췄고, 아무것도 바꾸지 않았습니다.',
                    '    - 새 codex 버전용 빌드는 보통 하루 안에 자동으로 올라옵니다. 그 뒤에 같은 명령을 다시 실행하세요.',
                    "    - 빌드 목록: https://github.com/$Repo/releases"
                ) -join "`n")
        }
        $change = if (-not $installed) { 'fresh' } elseif ($installed -ne $version) { 'upgrade' } else { 'none' }
        switch ($change) {
            'none' { Write-Host "    릴리스 $($manifest.tag): codex $version 그대로 사용 (버전 변경 없음)" }
            'upgrade' { Write-Host "    릴리스 $($manifest.tag): codex 를 $installed → $version 으로 올립니다 ($installed 용 빌드가 없어 가장 가까운 새 버전 사용)" -ForegroundColor Yellow }
            'fresh' { Write-Host "    릴리스 $($manifest.tag): codex $version 을 npm 으로 새로 설치합니다" }
        }

        # ---- 2. 다운로드와 해시 검증 (아직 아무것도 바꾸지 않음) ----
        Write-Step "다운로드 ($($asset.file))"
        $zip = Join-Path $tmp $asset.file
        Save-File "$base/$($asset.file)" $zip $asset.sha256
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'x') -Force
        $patched = Join-Path $tmp 'x\codex.exe'
        if (-not (Test-Path -LiteralPath $patched) -or (Get-Sha256 $patched) -ne $asset.exe_sha256) {
            throw '압축을 푼 codex.exe 가 릴리스 정보와 다릅니다.'
        }
        $hudNew = Join-Path $tmp 'codex-hud.mjs'
        Save-File "$base/codex-hud.mjs" $hudNew $manifest.hud_script_sha256
        $launcherNew = Join-Path $tmp 'codex-hud-launcher.mjs'
        if ($Side) {
            # 실행기가 없는 옛 릴리스는 저장소 main 의 실행기를 쓴다
            if ($manifest.launcher_sha256) { Save-File "$base/codex-hud-launcher.mjs" $launcherNew $manifest.launcher_sha256 }
            else { Save-File "$RawBase/hud/codex-hud-launcher.mjs" $launcherNew $null }
        }

        # ---- 3. 사전 점검 (아직 아무것도 바꾸지 않음) ----
        Write-Step '사전 점검'
        Assert-NotRunning $packageDir
        $prevState = $null
        if (Test-Path -LiteralPath $stateFile) { $prevState = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json }
        $oldConfig = if (Test-Path -LiteralPath $configPath) { [IO.File]::ReadAllText($configPath) } else { '' }
        $exe = Find-CodexExe $npmRoot
        $officialBackup = if ($exe) { Join-Path (Split-Path $exe) 'codex.official.exe' } else { $null }
        $replacePresent = ($officialBackup -and (Test-Path -LiteralPath $officialBackup)) -or $oldConfig.Contains($Mark) -or ($prevState -and $prevState.mode -eq 'replace')
        $sidePresent = (Test-Path -LiteralPath $shimCmd) -or ($prevState -and $prevState.mode -eq 'side')
        $uninstallLine = "irm $RawBase/uninstall.ps1 | iex"
        if ($Side -and $replacePresent) { throw "기본 codex 교체 방식으로 이미 설치돼 있습니다. 먼저 제거한 뒤 -Side 로 다시 설치하세요.`n    제거: $uninstallLine" }
        if (-not $Side -and $sidePresent) { throw "codex-hud 명령 방식(-Side)으로 이미 설치돼 있습니다. 먼저 제거한 뒤 다시 설치하세요.`n    제거: $uninstallLine" }

        $hudCommand = 'node "' + ($hudFile -replace '\\', '/') + '"'
        $hudCommandToml = '"' + ($hudCommand -replace '\\', '\\' -replace '"', '\"') + '"'
        $newConfig = $null
        if (-not $Side) {
            $newConfig = New-ConfigText $oldConfig $hudCommandToml (-not $KeepUpdateCheck)
            if (-not $NoCommandCheck) {
                $targets = Get-FirstCommandTargets 'codex'
                $pathDirs = @($env:Path -split ';' | ForEach-Object { $_.TrimEnd('\') })
                $shadow = @()
                if ($targets.PowerShell -and -not (Test-UnderDir $targets.PowerShell $npmPrefix)) { $shadow += "PowerShell: $($targets.PowerShell)" }
                if ($targets.Cmd -and -not (Test-UnderDir $targets.Cmd $npmPrefix)) { $shadow += "cmd: $($targets.Cmd)" }
                if (-not $targets.PowerShell -and -not $targets.Cmd -and ($pathDirs -notcontains $npmPrefix.TrimEnd('\'))) { $shadow += "PATH 에 npm 폴더($npmPrefix)가 없음" }
                if ($shadow.Count) {
                    throw (@(
                            "지금 'codex' 명령이 npm codex 가 아닌 다른 것을 먼저 실행합니다:",
                            (($shadow | ForEach-Object { "      $_" }) -join "`n"),
                            "    이대로 바꾸면 'codex' 를 실행해도 HUD 가 보이지 않아서 멈췄습니다. 아무것도 바꾸지 않았습니다.",
                            "    - 지금 codex 는 그대로 두고 'codex-hud' 명령으로 쓰기: 설치 명령 끝에 -Side 를 붙여 다시 실행",
                            '    - 직접 만든 codex 래퍼가 npm codex 를 부르는 경우: -NoCommandCheck 를 붙여 다시 실행'
                        ) -join "`n")
                }
            }
        } else {
            $targets = Get-FirstCommandTargets 'codex-hud'
            if ($targets.PowerShell -and $targets.PowerShell -notin @($shimCmd, $shimSh)) { throw "이미 다른 'codex-hud' 명령이 있습니다: $($targets.PowerShell)" }
        }
        if ($change -eq 'none' -and $exe) {
            # 같은 버전이면 DB 스키마도 같아야 한다. 이미 문제가 있는 DB 면 아무것도 바꾸기 전에 알린다.
            $dbError = Test-StateDb $patched
            if ($dbError) {
                # 공식 codex 로도 열어 봐서 빌드 문제인지 원래 DB 문제인지 가른다
                $officialExe = $null
                if (Test-Path -LiteralPath $officialBackup) { $officialExe = $officialBackup }
                elseif ((Get-Sha256 $exe) -eq $manifest.official_sha256) { $officialExe = $exe }
                $officialError = if ($officialExe) { Test-StateDb $officialExe } else { '확인 못 함' }
                if (-not $officialError) {
                    throw (@(
                            "이 HUD 빌드($($manifest.tag))가 지금 대화 기록 DB 를 열지 못합니다. 공식 codex 는 정상입니다 ($dbError).",
                            '    빌드 쪽 문제라 설치를 멈췄습니다. 아무것도 바꾸지 않았고 DB 파일도 건드리지 않았습니다.',
                            "    https://github.com/$Repo/issues 에 알려 주세요."
                        ) -join "`n")
                }
                throw (@(
                        "codex $version 이 대화 기록 DB 를 열지 못합니다 ($dbError). 공식 codex 도 마찬가지입니다.",
                        '    설치와 무관하게 이미 문제가 있는 상태라 멈췄습니다. 아무것도 바꾸지 않았고 DB 파일도 건드리지 않았습니다.',
                        '    흔한 원인: 더 새 버전의 codex(데스크톱 앱·IDE 확장 포함)가 같은 폴더의 DB 를 먼저 바꿔 놓은 경우',
                        "    DB 위치: $codexHome"
                    ) -join "`n")
            }
        }
        Write-Host '    OK'

        # ---- 4. 변경 (실패하면 거꾸로 되돌림) ----
        $undo = New-Object 'System.Collections.Generic.List[scriptblock]'
        $npmChanged = $false
        try {
            $isOfficial = $false
            if ($change -eq 'none') {
                $isOfficial = (Get-Sha256 $exe) -eq $manifest.official_sha256
                $backupOk = (Test-Path -LiteralPath $officialBackup) -and ((Get-Sha256 $officialBackup) -eq $manifest.official_sha256)
                if (-not $isOfficial -and -not $backupOk -and -not $Side) {
                    # 지금 codex.exe 가 공식본도 아니고 공식 백업도 없으면 같은 버전 공식본을 다시 받는다 (버전 변경 없음)
                    Write-Step "공식 codex $version 다시 받기 (npm)"
                    Invoke-Quiet { & npm.cmd install -g "@openai/codex@$version" --force }
                    if ($LASTEXITCODE -ne 0) { throw "npm install -g @openai/codex@$version 실패" }
                    $exe = Find-CodexExe $npmRoot
                    $isOfficial = $true
                }
            } else {
                Write-Step "codex $version 설치 (npm)"
                Invoke-Quiet { & npm.cmd install -g "@openai/codex@$version" }
                if ($LASTEXITCODE -ne 0) {
                    throw "npm install -g @openai/codex@$version 실패. 권한 오류(EPERM)라면 관리자 PowerShell 에서 다시 실행하세요."
                }
                $npmChanged = $true
                $exe = Find-CodexExe $npmRoot
                if (-not $exe) { throw 'npm 설치 후에도 codex.exe 를 찾지 못했습니다.' }
                if ((Get-Sha256 $exe) -ne $manifest.official_sha256) {
                    Write-Warning '방금 받은 공식 codex.exe 해시가 릴리스 정보와 다릅니다. 새로 받은 파일을 공식본으로 보고 계속합니다.'
                }
                $isOfficial = $true
            }
            $binDir = Split-Path $exe
            $officialBackup = Join-Path $binDir 'codex.official.exe'
            $sideExe = Join-Path $binDir 'codex-hud.exe'

            if (-not $Side) {
                if ((Get-Sha256 $exe) -ne $asset.exe_sha256) {
                    Write-Step 'codex.exe 교체 (공식본은 codex.official.exe 로 보관)'
                    $backupExisted = Test-Path -LiteralPath $officialBackup
                    if ($isOfficial) { Copy-Item -LiteralPath $exe -Destination $officialBackup -Force }
                    $undo.Insert(0, {
                            Copy-Item -LiteralPath $officialBackup -Destination $exe -Force
                            if (-not $backupExisted) { Remove-Item -LiteralPath $officialBackup -Force }
                        }.GetNewClosure())
                    Copy-Item -LiteralPath $patched -Destination $exe -Force
                } else {
                    Write-Step 'codex.exe 는 이미 이 빌드로 패치돼 있음'
                }
            } else {
                Write-Step "codex-hud 명령 설치 ($shimCmd)"
                Copy-Item -LiteralPath $patched -Destination $sideExe -Force
                $undo.Insert(0, { Remove-Item -LiteralPath $sideExe -Force -ErrorAction SilentlyContinue }.GetNewClosure())
            }

            Write-Step "HUD 스크립트 설치 ($hudFile)"
            if (-not (Test-Path -LiteralPath $hudDir)) {
                # 되돌리기는 거꾸로 실행되므로 이 폴더 정리가 맨 마지막에 돈다
                $undo.Insert(0, { if (-not (Get-ChildItem -LiteralPath $hudDir -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $hudDir -Force -ErrorAction SilentlyContinue } }.GetNewClosure())
            }
            New-Item -ItemType Directory -Force -Path $hudDir | Out-Null
            if (Test-Path -LiteralPath $hudFile) {
                $hudPrev = Join-Path $tmp 'codex-hud.prev.mjs'
                Copy-Item -LiteralPath $hudFile -Destination $hudPrev
                $undo.Insert(0, { Copy-Item -LiteralPath $hudPrev -Destination $hudFile -Force }.GetNewClosure())
                if ((Get-Sha256 $hudFile) -ne $manifest.hud_script_sha256) {
                    Copy-Item -LiteralPath $hudFile -Destination "$hudFile.bak" -Force
                    Write-Host "    기존 스크립트는 $hudFile.bak 으로 보관"
                }
            } else {
                $undo.Insert(0, { Remove-Item -LiteralPath $hudFile -Force -ErrorAction SilentlyContinue }.GetNewClosure())
            }
            Copy-Item -LiteralPath $hudNew -Destination $hudFile -Force

            $configBackup = $null
            if (-not $Side -and $newConfig -cne $oldConfig) {
                Write-Step "설정 추가 ($configPath)"
                if (Test-Path -LiteralPath $configPath) {
                    $configBackup = "$configPath.bak-codex-hud-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
                    Copy-Item -LiteralPath $configPath -Destination $configBackup
                    $undo.Insert(0, { Copy-Item -LiteralPath $configBackup -Destination $configPath -Force }.GetNewClosure())
                    Write-Host "    원래 설정은 $configBackup 에 백업"
                } else {
                    $undo.Insert(0, { Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue }.GetNewClosure())
                }
                [IO.File]::WriteAllText($configPath, $newConfig, (New-Object System.Text.UTF8Encoding $false))
            }

            $state = [ordered]@{
                mode             = if ($Side) { 'side' } else { 'replace' }
                variant          = $Variant
                tag              = $manifest.tag
                codex_version    = $version
                previous_version = $installed
                version_change   = $change
                package_root     = $packageDir
                codex_exe        = $exe
                official_backup  = if ($Side) { $null } else { $officialBackup }
                side_exe         = if ($Side) { $sideExe } else { $null }
                config_backup    = $configBackup
                status_line_command = $hudCommand
                installed_at     = (Get-Date).ToString('s')
            }
            $stateJson = $state | ConvertTo-Json
            $utf8 = New-Object System.Text.UTF8Encoding $false
            [IO.File]::WriteAllText($stateFile, $stateJson, $utf8)
            $undo.Insert(0, { Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue }.GetNewClosure())

            if ($Side) {
                # 실행기와 shim 은 npm 폴더에 둔다. shim 은 %~dp0 상대 경로만 써서 한글 경로 인코딩 문제가 없다.
                Copy-Item -LiteralPath $launcherNew -Destination $launcher -Force
                [IO.File]::WriteAllText($launcherState, $stateJson, $utf8)
                [IO.File]::WriteAllText($shimCmd, "@echo off`r`nnode `"%~dp0codex-hud-launcher.mjs`" %*`r`n", $utf8)
                [IO.File]::WriteAllText($shimSh, "#!/bin/sh`nbasedir=`$(dirname `"`$(echo `"`$0`" | sed -e 's,\\\\,/,g')`")`nexec node `"`$basedir/codex-hud-launcher.mjs`" `"`$@`"`n", $utf8)
                $undo.Insert(0, { Remove-Item -LiteralPath $shimCmd, $shimSh, $launcher, $launcherState -Force -ErrorAction SilentlyContinue }.GetNewClosure())
            }

            # ---- 5. 검증 ----
            Write-Step '검증'
            $runExe = if ($Side) { $sideExe } else { $exe }
            $versionText = Invoke-Quiet { & $runExe --version 2>$null | Select-Object -First 1 }
            if ($versionText -notmatch [regex]::Escape($version)) { throw "설치한 codex 버전이 이상합니다: $versionText" }
            if ($Side) {
                Invoke-Quiet { & cmd.exe /d /c "`"$shimCmd`" features list >nul 2>&1" }
            } else {
                Invoke-Quiet { & $exe features list *> $null }
            }
            if ($LASTEXITCODE -ne 0) { throw 'codex 가 바뀐 설정을 읽지 못했습니다.' }
            $dbError = Test-StateDb $runExe
            if ($dbError) { throw "codex 가 대화 기록 DB 를 열지 못했습니다 ($dbError). DB 파일은 건드리지 않았습니다." }
            $hudText = Invoke-Quiet { '{}' | & node.exe $hudFile 2>$null }
            if ($LASTEXITCODE -ne 0 -or -not $hudText) { throw "HUD 스크립트 실행 실패: node `"$hudFile`"" }
            Write-Host "    $versionText / 설정 OK / DB OK / HUD 스크립트 OK"

            $commandNote = $null
            if (-not $Side) {
                $psResult = Test-HudCommand { param($kv) Invoke-Quiet { & codex -c $kv features list *> $null; $LASTEXITCODE } }
                $cmdResult = Test-HudCommand { param($kv) Invoke-Quiet { & cmd.exe /d /c "codex -c $kv features list >nul 2>&1"; $LASTEXITCODE } }
                Write-Host "    'codex' 명령 확인: PowerShell=$psResult, cmd=$cmdResult"
                if ($psResult -eq 'official' -or $cmdResult -eq 'official') {
                    $msg = "'codex' 명령이 여전히 공식 codex 를 실행합니다 (PowerShell=$psResult, cmd=$cmdResult)."
                    if (-not $NoCommandCheck) { throw "$msg`n    이대로는 HUD 가 보이지 않아 되돌렸습니다. -Side 로 설치하면 'codex-hud' 명령으로 쓸 수 있습니다." }
                    $commandNote = $msg
                } elseif ($psResult -eq 'error' -or $cmdResult -eq 'error') {
                    $commandNote = "'codex' 명령을 실행해 확인하지 못했습니다 (PowerShell=$psResult, cmd=$cmdResult). 새 창에서 codex 를 실행해 HUD 가 보이는지 확인하세요."
                }
            } else {
                $t = Get-FirstCommandTargets 'codex-hud'
                if (-not (Test-UnderDir $t.Cmd $npmPrefix)) { $commandNote = "PATH 에서 codex-hud 를 찾지 못했습니다. 새 창에서 다시 확인하거나 `"$shimCmd`" 로 실행하세요." }
            }
        } catch {
            if ($undo.Count) {
                Write-Host '    실패해서 바꾼 것을 되돌립니다...' -ForegroundColor Yellow
                foreach ($step in $undo) { try { & $step } catch { Write-Warning "되돌리기 실패: $($_.Exception.Message)" } }
            }
            $note = if ($npmChanged) { "`n    (npm codex 는 $version 으로 설치된 상태로 둡니다. 버전을 다시 낮추면 대화 기록 DB 가 깨질 수 있습니다.)" } else { '' }
            throw "$($_.Exception.Message)$note"
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Write-Host "설치 완료: codex $version + $Label ($ModeLabel)" -ForegroundColor Green
    if ($Side) {
        Write-Host "  - 새 창에서 'codex-hud' 를 실행하면 HUD 가 보입니다. 'codex' 는 공식본 그대로입니다."
        Write-Host "  - 공식 codex 가 업데이트되면 codex-hud 는 버전이 달라져 실행을 멈추고 안내합니다. 그때 이 설치 명령을 다시 실행하세요."
    } else {
        Write-Host "  - 새 창에서 'codex' 를 실행하면 입력창 아래에 HUD 가 보입니다."
        if (-not $KeepUpdateCheck) {
            Write-Host '  - codex 업데이트 알림을 껐습니다. 업데이트하면 공식본으로 덮여 HUD 가 사라지기 때문입니다.'
        }
        Write-Host '  - 새 codex 버전을 쓰고 싶으면 같은 설치 명령을 다시 실행하세요. 그 버전용 빌드가 있으면 맞춰 줍니다.'
    }
    Write-Host '  - 5시간/주간 사용량 줄은 ChatGPT 로그인 상태에서 codex 가 사용량을 받아온 뒤부터 나옵니다.'
    Write-Host "  - 제거: $uninstallLine"
    if ($commandNote) { Write-Warning $commandNote }
}

try {
    Install-CodexHud -Ui:$Ui -Side:$Side -Tag $Tag -KeepUpdateCheck:$KeepUpdateCheck -NoCommandCheck:$NoCommandCheck -ReleaseBase $ReleaseBase
    $global:LASTEXITCODE = 0
} catch {
    Write-Host ''
    Write-Host "설치 실패: $($_.Exception.Message)" -ForegroundColor Red
    $global:LASTEXITCODE = 1
    # 파일로 실행했거나 powershell -Command 로 한 번 실행하고 끝나는 경우만 exit 1 (대화형 창은 닫지 않는다)
    $hostArgs = [Environment]::GetCommandLineArgs()
    $oneShot = @($hostArgs | Where-Object { $_ -match '^[-/](c|command|ec|encodedcommand|f|file)$' }).Count -gt 0 -and
        @($hostArgs | Where-Object { $_ -match '^[-/]noexit$' }).Count -eq 0
    if ($CodexHudInvokedAsFile -or $oneShot) { exit 1 }
}

# Codex HUD Native

OpenAI Codex CLI의 **입력창 바로 아래**에 Claude Code HUD 같은 상태줄을 띄우는 codex 패치 빌드예요. Windows x64 전용이에요.

HUD만 설치한 codex 화면이에요(실제로는 색이 들어가요). 입력창 아래 네 줄이 HUD예요.

```
› Ask Codex to do anything

  ? for shortcuts                                              79% context left
  [GPT-6-Astra | xhigh] PLUS my-project
  컨텍스트  21% ██░░░░░░░░ 58k/272k 12분
  5시간     12% █░░░░░░░░░ 3시간 27분
  주간       9% █░░░░░░░░░ 6일 10시간 9분
```

tmux로 옆 창에 HUD를 띄우는 방식이 아니라, codex 화면 안에 직접 그려요. 공식 codex에는 외부 명령으로 상태줄을 그리는 기능이 없어서, 그 기능(`tui.status_line_command`)을 codex 소스에 추가해 빌드했어요.

- [claude-hud-custom](https://github.com/YeoSeokMin/claude-hud-custom)(Claude Code용)과 같은 모양이에요.
- 모델과 추론 강도, 요금제, 프로젝트, 컨텍스트 사용량, 세션 시간, 5시간/주간 사용 한도를 보여줘요.

## 설치 (PowerShell 한 줄)

PowerShell을 열고 아래 중 하나를 붙여넣으세요. 관리자 권한은 필요 없어요. **실행 중인 codex는 먼저 모두 닫아야 해요.**

**HUD만** (`codex` 명령에 바로 적용)

```powershell
irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/install.ps1 | iex
```

**HUD + Claude식 UI 개조**

```powershell
iex "& { $(irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/install.ps1) } -Ui"
```

**공식 codex는 그대로 두고 `codex-hud` 명령을 따로 설치**

```powershell
iex "& { $(irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/install.ps1) } -Side"
```

옵션은 같이 쓸 수 있어요. 예를 들어 `} -Side -Ui"` 로 쓰면 `codex-hud` 명령에 UI 개조 버전이 설치돼요.

**필요한 것**

- Windows 10/11 x64
- [Node.js](https://nodejs.org) 18 이상. npm으로 codex를 설치했다면 이미 있어요. codex가 없으면 설치 스크립트가 npm으로 함께 설치해요.

### 설치 방식 고르기

| | 기본 (교체) | `-Side` (따로 설치) |
|---|---|---|
| HUD가 보이는 명령 | `codex` | `codex-hud` |
| 공식 `codex` | HUD 빌드로 바뀜 | 그대로 |
| `config.toml` | HUD 설정 추가 | 건드리지 않음 |
| codex 업데이트 알림 | 끔 | 공식 `codex` 에서 그대로 받음 |
| codex를 업데이트하면 | HUD가 사라짐 (codex는 정상) | `codex-hud` 가 실행을 멈추고 안내 |

직접 만든 `codex` 래퍼가 PATH 앞쪽에 있거나 공식 설치를 건드리고 싶지 않다면 `-Side` 가 편해요.

### HUD와 HUD + UI 개조의 차이

UI 개조 버전은 화면이 Claude Code처럼 바뀌어요.

- 내 메시지: `>` 로 표시 (회색 띠 없음)
- 답변: `●` 로 표시
- 생각 중: `∴` 로 표시
- 도구 결과: `⎿` 로 표시
- 입력창: 위아래에 가로줄
- 시작 화면: 주황색 `✻ Welcome to Codex!`
- 작업 시간: `✻ Worked for 1m 20s` 처럼 표시하고, 완료 시각은 숨김

## codex 버전은 어떻게 정해지나요

HUD 빌드는 codex 버전마다 따로 있어요. 설치 스크립트는 **지금 설치된 codex 버전에 맞는 빌드를 고르고, codex 버전은 절대 낮추지 않아요.**

| 지금 설치된 codex | 설치 스크립트가 하는 일 |
|---|---|
| 같은 버전의 HUD 빌드가 있음 | 버전은 그대로 두고 설치 |
| 모든 HUD 빌드보다 새 버전 | **설치를 멈추고 아무것도 바꾸지 않음** |
| 더 옛 버전 (맞는 빌드 없음) | 가장 가까운 새 버전으로 올림 (공식 업데이트와 같음) |
| 설치 안 됨 | 가장 최근 HUD 빌드 버전을 npm으로 설치 |

버전을 낮추지 않는 이유가 있어요. 새 버전 codex는 대화 기록 DB(`~/.codex/*.sqlite`)를 새 형식으로 바꿔 둬요. 그 뒤에 옛 버전으로 열면 `migration N was previously applied but has been modified` 같은 오류가 나며 codex가 실행되지 않을 수 있어요.

새 codex 버전이 나오면 GitHub Actions가 매일 한 번 확인해서 그 버전의 HUD 빌드를 자동으로 만들어요. 보통 하루 안에 올라오고, 올라오면 같은 설치 명령을 다시 실행하면 돼요. 빌드 목록은 [Releases](https://github.com/YeoSeokMin/codex-hud-native/releases) 에 있어요.

## 설치 스크립트가 하는 일

1. **릴리스 고르기**: 위 표대로 고르고, "현재 버전 → 설치할 버전"을 먼저 보여줘요.
2. **다운로드와 검증**: HUD 빌드와 HUD 스크립트를 받아 SHA256으로 검증해요. 이 단계까지는 아무것도 바꾸지 않아요.
3. **사전 점검**: 아래 중 하나라도 걸리면 **아무것도 바꾸지 않고** 멈춰요.
   - codex가 실행 중일 때
   - 이미 다른 방식(기본/`-Side`)으로 설치돼 있을 때
   - `config.toml` 형식을 자동으로 고칠 수 없을 때
   - 기본 방식인데, `codex` 명령이 npm codex가 아닌 다른 파일을 먼저 실행할 때
   - 받은 HUD 빌드가 지금 대화 기록 DB를 열지 못할 때. 이때는 공식 codex로도 열어 봐서 빌드 문제인지, 원래 DB 문제인지 구분해 알려줘요.
4. **변경**
   - 필요할 때만 npm으로 codex 버전을 맞춰요.
   - 기본 방식이면 공식 `codex.exe`를 `codex.official.exe` 로 백업하고 HUD 빌드로 바꿔요. `config.toml` 에 아래 줄을 추가하고, 원본은 `config.toml.bak-codex-hud-<날짜>` 로 백업해요.

     ```toml
     check_for_update_on_startup = false  # codex-hud-native

     [tui]
     status_line_command = "node \"C:/Users/<사용자>/.codex/hud/codex-hud.mjs\""  # codex-hud-native
     status_line = []  # codex-hud-native
     ```

   - `-Side` 방식이면 npm 폴더에 `codex-hud` 명령과 `codex-hud.exe` 를 추가해요. 설정 파일은 건드리지 않아요.
   - 공통으로 HUD 스크립트(`~/.codex/hud/codex-hud.mjs`)와 설치 기록(`~/.codex/hud/install-state.json`)을 저장해요.
5. **검증**: 아래를 모두 확인해요.
   - 버전과 설정 읽기
   - 대화 기록 DB 열기
   - HUD 스크립트 실행
   - **실제로 `codex`(또는 `codex-hud`) 명령을 쳤을 때 HUD 빌드가 실행되는지** (PowerShell과 cmd 둘 다)

   하나라도 실패하면 exe·설정·HUD 스크립트를 **설치 전 상태로 되돌리고** 실패로 끝나요. 단, 버전을 올렸다면 npm codex 버전은 그대로 둬요. 다시 낮추면 DB가 깨질 수 있기 때문이에요.

같은 명령을 다시 실행해도 괜찮아요. 줄이 중복되지 않고, 이미 패치돼 있으면 교체를 건너뛰어요.

## ⚠️ 주의사항

1. **codex를 업데이트하면 HUD가 사라져요.** (기본 방식)
   - `npm install -g @openai/codex`, `codex update`, codex 화면의 업데이트 안내 수락은 모두 `codex.exe`를 공식본으로 덮어써요.
   - 그래서 설치할 때 업데이트 알림을 꺼 둬요. 알림을 그대로 두려면 `-KeepUpdateCheck` 를 붙이세요(`iex "& { ... } -KeepUpdateCheck"` 형태).
   - 업데이트해도 codex는 정상으로 돌아가고 HUD만 없어져요. 새 버전의 HUD 빌드가 올라온 뒤 설치 명령을 다시 실행하세요.
   - `-Side` 방식은 공식 codex를 마음대로 업데이트해도 돼요. 버전이 달라지면 `codex-hud` 가 실행을 멈추고 안내해요.
2. **codex 버전은 올라갈 수는 있어도 내려가지는 않아요.** 자세한 내용은 [위](#codex-버전은-어떻게-정해지나요)에 있어요.
3. **비공식 수정 빌드예요.**
   - OpenAI와는 관계없어요.
   - 코드 서명이 없어서 백신이나 SmartScreen이 경고할 수 있어요.
   - 바이너리는 이 레포의 [`patches/`](patches) 로 GitHub Actions가 빌드해요. 빌드 로그는 Actions 탭에서 볼 수 있어요.
   - 믿기 어렵다면 [직접 빌드](#직접-빌드)하세요.
4. **설치·제거할 때는 codex를 모두 닫아야 해요.** 실행 중인 exe는 바꿀 수 없어서 스크립트가 멈추고 안내해요.
5. **npm으로 설치한 codex CLI에만 적용돼요.**
   - Codex 데스크톱 앱, VS Code·Cursor 확장, 다른 방법으로 설치한 codex에는 적용되지 않아요.
   - 그런데 이 앱들도 같은 `~/.codex` 폴더(대화 기록 DB)를 써요. 버전이 크게 다른 codex를 번갈아 쓰면 공식 codex끼리도 위의 DB 오류가 날 수 있어요.
6. **5시간/주간 사용량 줄**은 ChatGPT 계정으로 로그인했을 때만 나와요.
   - codex가 사용량 정보를 받아온 뒤부터 보여요.
   - API 키로 로그인했다면 한도 정보가 없어서 이 줄이 나오지 않아요.
   - 요금제에 5시간 창이 없으면 주간 줄만 나와요.
7. **HUD 스크립트는 약 1초마다 `node`로 실행돼요.** 가벼운 스크립트지만 node 프로세스가 계속 짧게 떴다 사라져요.
8. **기존 설정을 지우지 않아요.** `config.toml`의 `[tui]` 아래에 있던 `status_line`·`status_line_command`는 `#codex-hud-native-off#` 를 붙여 주석 처리해요. 제거하면 원래대로 돌아와요.
9. **HUD 스크립트를 고쳐 썼다면**, 다시 설치할 때 덮어써져요. 기존 파일은 `codex-hud.mjs.bak` 으로 남아요.
10. **스크립트 파일을 받아서 `powershell -File install.ps1` 로 실행하지 마세요.** Windows PowerShell 5.1은 이 파일의 한글을 잘못 읽어요. 위의 한 줄 명령을 쓰세요.

## 자동 설치·테스트에서 쓰기

한 번 실행하고 끝나는 PowerShell에서 돌리면, 실패할 때 **종료 코드 1**로 끝나요.

```powershell
powershell -NoProfile -Command "irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/install.ps1 | iex"
```

- 창을 열어 직접 붙여넣었을 때는 창이 닫히지 않도록 `exit` 하지 않아요. 대신 `$LASTEXITCODE` 가 1이 돼요.
- 제거 스크립트도 똑같이 동작해요.

## 제거

```powershell
irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/uninstall.ps1 | iex
```

- 기본 방식: `codex.official.exe`를 `codex.exe`로 되돌려요. 백업이 없으면 **같은 버전**의 공식본을 npm으로 다시 받아요. 그리고 `config.toml`에서 추가했던 줄을 지우고, 주석 처리했던 줄은 원래대로 돌려요.
- `-Side` 방식: `codex-hud` 명령, 실행기, `codex-hud.exe` 를 지워요.
- 공통: HUD 스크립트와 설치 기록을 지워요.
- **codex 버전은 되돌리지 않아요.**
  - 설치할 때 버전을 올렸다면 그 버전으로 남고, 제거 끝에 알려줘요.
  - 설치할 때 codex를 새로 깔았다면 codex는 남겨 두고, 지우는 명령(`npm uninstall -g @openai/codex`)을 알려줘요.

## 문제 해결

**`migration N was previously applied but has been modified` 오류로 codex가 안 켜져요**

대화 기록 DB를 만든 codex와 지금 여는 codex가 서로 맞지 않을 때 나는 오류예요.

- 버전이 다른 codex(옛 버전 CLI, 데스크톱 앱, IDE 확장 등)가 같은 `~/.codex` 를 쓰고 있지 않은지 확인하세요.
- `v0.156.1` 첫 빌드(2026-09-25)는 빌드 방식 문제로 이 오류가 날 수 있었어요. 그 빌드는 설치 대상에서 뺐어요. 제거 명령을 실행한 뒤 다시 설치하세요.
- `.sqlite` 파일을 다른 폴더로 옮겨서 임시로 해결했다면, 원래 DB를 되돌릴 수 있어요.
  1. codex를 모두 끄세요.
  2. 새로 생긴 `~/.codex/*.sqlite*` 를 치우고, 옮겨 둔 파일을 제자리에 두세요.
  3. 최신 공식 codex나 그 버전에 맞는 HUD 빌드로 여세요.
- 설치 스크립트는 어떤 경우에도 `.sqlite` 파일을 지우거나 옮기지 않아요.

**설치하다 "`codex` 명령이 npm codex 가 아닌 다른 것을 먼저 실행합니다"에서 멈춰요**

PATH 앞쪽에 다른 `codex.cmd`·`codex.ps1`(직접 만든 래퍼 등)이 있다는 뜻이에요. 방법은 두 가지예요.

- `-Side` 로 설치해서 `codex-hud` 명령으로 쓰세요.
- 그 래퍼가 결국 npm codex를 실행한다면 `-NoCommandCheck` 를 붙여 설치하세요.

## HUD 모양 바꾸기

`~/.codex/hud/codex-hud.mjs` 를 고치면 돼요. 기본 방식이라면 `status_line_command` 에 다른 명령(Python, 셸 스크립트 등)을 넣어도 돼요.

- codex는 명령을 약 1초마다, 그리고 상태가 바뀔 때 실행해요. 세션 정보는 JSON으로 stdin에 넘겨줘요.
- 명령이 stdout에 출력한 내용을 입력창 아래에 그려요. 최대 10줄까지, ANSI 색을 지원해요.
- 5초 안에 끝나지 않거나 종료 코드가 0이 아니면 이전 출력을 그대로 유지해요.

필드 이름은 Claude Code의 statusLine과 최대한 같게 맞췄어요.

| 필드 | 내용 |
|---|---|
| `model.id`, `model.display_name` | 모델 |
| `effort.level` | 추론 강도 (`low`, `medium`, `high`, `xhigh` 등) |
| `context_window.used_percentage` | 컨텍스트 사용률(%) |
| `context_window.context_window_size` | 컨텍스트 크기(토큰) |
| `context_window.current_usage.total_tokens` | 현재 사용 토큰 |
| `rate_limits.five_hour`, `rate_limits.seven_day` | `used_percentage`, `resets_at`(유닉스 초), `window_minutes` |
| `rate_limits.plan_type`, `codex.plan_type` | 요금제 |
| `cwd`, `transcript_path`, `session_id`, `version` | 작업 폴더, 세션 기록 파일, 세션 ID, codex 버전 |
| `codex.run_state`, `codex.thread_name` | 진행 상태, 스레드 이름 |

## 직접 빌드

릴리스 바이너리 대신 직접 빌드하려면 이 레포를 받아서 실행하세요.

```powershell
git clone https://github.com/YeoSeokMin/codex-hud-native.git
cd codex-hud-native
powershell -ExecutionPolicy Bypass -File scripts\build-local.ps1                     # HUD만
powershell -ExecutionPolicy Bypass -File scripts\build-local.ps1 -Ui                 # HUD + UI
powershell -ExecutionPolicy Bypass -File scripts\build-local.ps1 -Version 0.158.0    # 다른 codex 버전
```

- 필요한 것: Git, rustup, Visual Studio 2022 Build Tools(C++ 워크로드).
- 디스크는 약 25GB, 램은 16GB가 필요해요. 첫 빌드는 30분 이상 걸려요.
- 빌드가 끝나면 스크립트가 exe 위치와 교체 방법을 알려줘요.
- 패치는 LF로 받은 소스에 적용한 뒤, 공식 Windows 빌드처럼 **CRLF로 다시 받아서** 빌드해요. 대화 기록 DB의 migration 체크섬이 `.sql` 파일의 줄바꿈까지 포함하기 때문이에요. LF 그대로 빌드하면 공식 codex가 만든 DB를 열지 못해요.

## 새 codex 버전 대응 (관리자용)

- GitHub Actions(`release` 워크플로)가 매일 06:17(KST)에 npm 최신 codex를 확인해요. 그 버전 릴리스가 없으면 빌드하고 릴리스까지 만들어요.
  - 빌드할 때 공식 codex가 만든 DB를 HUD 빌드가 여는지 확인해요.
  - 패치가 새 버전에 맞지 않으면 워크플로가 실패해요. GitHub가 실패를 메일로 알려줘요.
- 패치를 새 버전에 맞게 고치는 방법:
  1. `scripts\build-local.ps1 -Version <새 버전>` 으로 어디가 안 맞는지 확인하고 `patches/` 를 고쳐요.
  2. [`CODEX_VERSION`](CODEX_VERSION) 을 새 버전으로 바꾸고 push해요.
  3. Actions 탭에서 `release` 를 수동 실행하세요(Run workflow). 또는 `v<버전>` 태그를 push해도 돼요.
- 같은 codex 버전을 다시 빌드할 때는 `v<버전>-2` 처럼 태그를 붙여요. 설치 스크립트는 번호가 가장 큰 것을 골라요.
- 공개 레포에서 60일 동안 활동이 없으면 GitHub가 예약 실행을 멈춰요. 멈췄다면 Actions 탭에서 다시 켜 주세요.

## 라이선스

[Apache-2.0](LICENSE)이에요. codex와 같은 라이선스예요.

`patches/` 는 [openai/codex](https://github.com/openai/codex)를 수정한 내용이에요. 이 프로젝트는 OpenAI와 관계없어요.

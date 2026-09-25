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

**HUD만**

```powershell
irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/install.ps1 | iex
```

**HUD + Claude식 UI 개조**

```powershell
iex "& { $(irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/install.ps1) } -Ui"
```

설치가 끝나면 codex를 새로 실행하세요. 입력창 아래에 HUD가 보여요.

**필요한 것**

- Windows 10/11 x64
- [Node.js](https://nodejs.org) 18 이상. npm으로 codex를 설치했다면 이미 있어요. codex가 없으면 설치 스크립트가 npm으로 함께 설치해요.

### 두 버전의 차이

| | HUD | HUD + UI 개조 |
|---|---|---|
| 입력창 아래 HUD | O | O |
| 화면 모양 | 공식 codex 그대로 | Claude Code 비슷하게 바뀜 |

UI 개조 버전에서는 다음이 바뀌어요.

- 내 메시지: `>` 로 표시 (회색 띠 없음)
- 답변: `●` 로 표시
- 생각 중: `∴` 로 표시
- 도구 결과: `⎿` 로 표시
- 입력창: 위아래에 가로줄
- 시작 화면: 주황색 `✻ Welcome to Codex!`
- 작업 시간: `✻ Worked for 1m 20s` 처럼 표시하고, 완료 시각은 숨김

### 설치 스크립트가 하는 일

1. 최신 릴리스의 `manifest.json`을 읽어요. 대상 codex 버전과 파일 해시가 들어 있어요.
2. npm 전역 codex 버전이 릴리스와 다르면 `npm install -g @openai/codex@<버전>` 으로 맞춰요.
3. 공식 `codex.exe`를 같은 폴더의 `codex.official.exe` 로 백업해요. 그다음 패치된 `codex.exe`로 바꿔요. 받은 파일은 SHA256으로 검증해요.
4. HUD 스크립트를 `~/.codex/hud/codex-hud.mjs` 에 넣어요.
5. `~/.codex/config.toml` 에 아래 줄을 추가해요. 원본은 `config.toml.bak-codex-hud-<날짜>` 로 백업해요.

   ```toml
   check_for_update_on_startup = false  # codex-hud-native

   [tui]
   status_line_command = "node \"C:/Users/<사용자>/.codex/hud/codex-hud.mjs\""  # codex-hud-native
   status_line = []  # codex-hud-native
   ```

6. codex가 바뀐 설정을 읽을 수 있는지(`codex features list`), HUD 스크립트가 도는지 확인해요. 설정을 못 읽으면 백업으로 되돌려요.

같은 명령을 다시 실행해도 괜찮아요. 줄이 중복되지 않고, 이미 패치돼 있으면 교체를 건너뛰어요.

## ⚠️ 주의사항

1. **codex를 업데이트하면 HUD가 사라져요.**
   - `npm install -g @openai/codex`, `codex update`, codex 화면의 업데이트 안내 수락은 모두 `codex.exe`를 공식본으로 덮어써요.
   - 그래서 설치할 때 업데이트 알림을 꺼 둬요(`check_for_update_on_startup = false`). 알림을 그대로 두려면 설치 명령 끝에 `-KeepUpdateCheck` 를 붙이세요(HUD + UI 명령처럼 `iex "& { ... } -KeepUpdateCheck"` 형태로).
   - 새 codex 버전을 쓰려면, 이 레포에 그 버전의 릴리스가 올라온 뒤 설치 명령을 다시 실행하세요.
   - 급하면 그냥 업데이트해도 돼요. codex는 정상으로 돌아가고 HUD만 없어져요.
2. **codex 버전이 릴리스 버전으로 바뀌어요.** 더 새로운 codex를 쓰고 있었다면 릴리스 버전으로 내려가요. 현재 대상 버전은 [`CODEX_VERSION`](CODEX_VERSION) 에 있어요.
3. **비공식 수정 빌드예요.**
   - OpenAI와는 관계없어요.
   - 코드 서명이 없어서 백신이나 SmartScreen이 경고할 수 있어요.
   - 바이너리는 이 레포의 [`patches/`](patches) 로 GitHub Actions가 빌드해요. 빌드 로그는 Actions 탭에서 볼 수 있어요.
   - 믿기 어렵다면 [직접 빌드](#직접-빌드)하세요.
4. **설치·제거할 때는 codex를 모두 닫아야 해요.** 실행 중인 exe는 바꿀 수 없어서 스크립트가 멈추고 안내해요.
5. **npm으로 설치한 codex CLI에만 적용돼요.**
   - Codex 데스크톱 앱, VS Code·Cursor 확장, 다른 방법으로 설치한 codex에는 적용되지 않아요.
   - PATH에서 다른 codex가 먼저 잡히면 설치 끝에 경고가 나와요.
6. **5시간/주간 사용량 줄**은 ChatGPT 계정으로 로그인했을 때만 나와요.
   - codex가 사용량 정보를 받아온 뒤부터 보여요(보통 첫 응답 뒤).
   - API 키로 로그인했다면 한도 정보가 없어서 이 줄이 나오지 않아요.
   - 요금제에 5시간 창이 없으면 주간 줄만 나와요.
7. **HUD 스크립트는 약 1초마다 `node`로 실행돼요.** 가벼운 스크립트지만 node 프로세스가 계속 짧게 떴다 사라져요.
8. **기존 설정을 지우지 않아요.** `config.toml`의 `[tui]` 아래에 있던 `status_line`·`status_line_command`는 `#codex-hud-native-off#` 를 붙여 주석 처리해요. 제거하면 원래대로 돌아와요.
9. **HUD 스크립트를 고쳐 썼다면**, 다시 설치할 때 덮어써져요. 기존 파일은 `codex-hud.mjs.bak` 으로 남아요.

## 제거

```powershell
irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/uninstall.ps1 | iex
```

- `codex.official.exe`를 `codex.exe`로 되돌려요. 백업이 없으면 npm으로 공식본을 다시 받아요.
- `config.toml`에서 추가했던 줄을 지우고, 주석 처리했던 줄은 원래대로 돌려요.
- HUD 스크립트를 지워요.

## HUD 모양 바꾸기

`~/.codex/hud/codex-hud.mjs` 를 고치면 돼요. `status_line_command` 에 다른 명령(Python, 셸 스크립트 등)을 넣어도 돼요.

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
powershell -ExecutionPolicy Bypass -File scripts\build-local.ps1        # HUD만
powershell -ExecutionPolicy Bypass -File scripts\build-local.ps1 -Ui    # HUD + UI
```

- 필요한 것: Git, rustup, Visual Studio 2022 Build Tools(C++ 워크로드).
- 디스크는 약 25GB, 램은 16GB가 필요해요. 첫 빌드는 30분 이상 걸려요.
- 빌드가 끝나면 스크립트가 exe 위치와 교체 방법을 알려줘요.

## 새 codex 버전 대응 (관리자용)

1. [`CODEX_VERSION`](CODEX_VERSION) 을 새 버전으로 바꿔요.
2. `scripts\build-local.ps1` 로 패치가 새 버전에 적용되는지 확인해요. 안 맞으면 패치를 새 버전에 맞게 고쳐요.
3. `git tag v<버전>` 후 태그를 push해요. 같은 codex 버전을 다시 올릴 때는 `v<버전>-2` 처럼 붙여요.
4. GitHub Actions가 두 버전을 빌드하고 릴리스를 만들어요. 1~2시간쯤 걸려요.

## 라이선스

[Apache-2.0](LICENSE)이에요. codex와 같은 라이선스예요.

`patches/` 는 [openai/codex](https://github.com/openai/codex)를 수정한 내용이에요. 이 프로젝트는 OpenAI와 관계없어요.

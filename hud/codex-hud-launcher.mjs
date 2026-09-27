#!/usr/bin/env node
// codex-hud 명령 (-Side 설치). HUD 빌드(codex-hud.exe)를 공식 codex 와 같은 버전일 때만 실행한다.
// 버전이 다른 codex 가 같은 대화 기록 DB 를 열면 migration 불일치로 깨질 수 있어서다.
// install.ps1 이 npm 전역 폴더에 codex-hud.cmd / codex-hud 와 함께 설치하고, 설치 정보는 옆의 codex-hud.json 에 둔다.
import { spawn } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const reinstall =
  'PowerShell 에서 다시 설치하세요:\n    iex "& { $(irm https://raw.githubusercontent.com/YeoSeokMin/codex-hud-native/main/install.ps1) } -Side"';

function fail(message) {
  console.error(`codex-hud: ${message}`);
  process.exit(1);
}

let state;
try {
  state = JSON.parse(readFileSync(path.join(here, 'codex-hud.json'), 'utf8'));
} catch {
  fail(`설치 정보(codex-hud.json)를 읽지 못했습니다. ${reinstall}`);
}

let current = null;
try {
  current = JSON.parse(readFileSync(path.join(state.package_root, 'package.json'), 'utf8')).version;
} catch {
  // npm codex 가 지워졌으면 아래에서 안내한다
}

if (current !== state.codex_version || !existsSync(state.side_exe)) {
  fail(
    [
      `공식 codex 가 ${current ?? '(없음)'} 로 바뀌어 HUD 빌드(codex ${state.codex_version})를 실행하지 않습니다.`,
      '  버전이 다른 codex 로 같은 대화 기록을 열면 DB 가 깨질 수 있기 때문입니다. 공식 codex 는 그대로 쓸 수 있습니다.',
      `  HUD 를 다시 쓰려면 그 버전용 빌드가 나온 뒤 ${reinstall}`,
    ].join('\n'),
  );
}

// 공식 codex.js 와 같은 환경 변수를 넘겨 npm 설치본으로 동작하게 한다
const env = { ...process.env, CODEX_MANAGED_PACKAGE_ROOT: state.package_root };
delete env.CODEX_MANAGED_BY_BUN;
delete env.CODEX_MANAGED_BY_PNPM;
delete env.CODEX_MANAGED_BY_VITE_PLUS;
env.CODEX_MANAGED_BY_NPM = '1';

// 업데이트 알림은 공식 codex 쪽에서 받는다. 여기서 업데이트하면 버전이 달라져 바로 HUD 가 멈추기 때문.
const args = [
  '-c',
  `tui.status_line_command=${JSON.stringify(state.status_line_command)}`,
  '-c',
  'tui.status_line=[]',
  '-c',
  'check_for_update_on_startup=false',
  ...process.argv.slice(2),
];
const child = spawn(state.side_exe, args, { stdio: 'inherit', env });

child.on('error', (err) => fail(String(err)));

for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(signal, () => {
    if (!child.killed) {
      try {
        child.kill(signal);
      } catch {
        // 이미 끝났으면 무시
      }
    }
  });
}

child.on('exit', (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  else process.exit(code ?? 1);
});

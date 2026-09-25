#!/usr/bin/env node
// Codex용 HUD — claude-hud-custom 과 같은 모양.
// 패치된 codex 의 tui.status_line_command 가 1초마다 실행하고, 세션 JSON 을 stdin 으로 넘긴다.
import path from 'node:path';

const RESET = '\x1b[0m';
const DIM = '\x1b[2m';
const RED = '\x1b[31m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const CYAN = '\x1b[36m';
const BRIGHT_BLUE = '\x1b[94m';

const cyan = (t) => `${CYAN}${t}${RESET}`;
const green = (t) => `${GREEN}${t}${RESET}`;
const dim = (t) => `${DIM}${t}${RESET}`;

function contextColor(percent) {
  if (percent >= 85) return RED;
  if (percent >= 70) return YELLOW;
  return GREEN;
}

function bar(color, percent, width = 10) {
  const safe = Number.isFinite(percent) ? Math.min(100, Math.max(0, percent)) : 0;
  const filled = Math.round((safe / 100) * width);
  return `${color}${'█'.repeat(filled)}${DIM}${'░'.repeat(width - filled)}${RESET}`;
}

// 한글 2칸, 그 외 1칸 기준으로 라벨 폭 맞춤
function padLabel(label, width = 8) {
  const w = [...label].reduce((acc, c) => acc + (c.charCodeAt(0) > 127 ? 2 : 1), 0);
  return label + ' '.repeat(Math.max(0, width - w));
}

function padPercent(percent) {
  const text = `${percent}%`;
  return ' '.repeat(Math.max(0, 4 - text.length)) + contextColor(percent) + text + RESET;
}

function formatTokens(n) {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1000) return `${(n / 1000).toFixed(0)}k`;
  return String(n);
}

function formatRemaining(ms) {
  if (ms <= 0) return '';
  const totalMins = Math.floor(ms / 60000);
  const days = Math.floor(totalMins / 1440);
  const hours = Math.floor((totalMins % 1440) / 60);
  const mins = totalMins % 60;
  const parts = [];
  if (days > 0) parts.push(`${days}일`);
  if (hours > 0) parts.push(`${hours}시간`);
  if (mins > 0) parts.push(`${mins}분`);
  return parts.length ? parts.join(' ') : '1분 미만';
}

// rollout-2026-09-22T16-27-08-<id>.jsonl (로컬 시각) → 세션 시작 시각
function sessionStart(transcriptPath) {
  const m = /rollout-(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})/.exec(
    path.basename(transcriptPath ?? ''),
  );
  if (!m) return null;
  const [, y, mo, d, h, mi, s] = m.map(Number);
  return new Date(y, mo - 1, d, h, mi, s);
}

function formatDuration(start) {
  if (!start) return '0분';
  const mins = Math.floor((Date.now() - start.getTime()) / 60000);
  if (mins < 1) return '1분 미만';
  if (mins < 60) return `${mins}분`;
  return `${Math.floor(mins / 60)}시간 ${mins % 60}분`;
}

function limitLine(label, color, limit) {
  if (!limit) return null;
  const resetsAtMs = (limit.resets_at ?? 0) * 1000;
  const expired = resetsAtMs > 0 && resetsAtMs <= Date.now();
  const used = expired ? 0 : Math.round(limit.used_percentage ?? 0);
  const reset = expired ? '' : formatRemaining(resetsAtMs - Date.now());
  return `${padLabel(label)} ${padPercent(used)} ${bar(color, used)}${reset ? ` ${dim(reset)}` : ''}`;
}

function render(data) {
  const model = data.model?.display_name || data.model?.id || 'codex';
  const effort = data.effort?.level;
  const modelPart = cyan(`[${effort && effort !== 'default' ? `${model} | ${effort}` : model}]`);
  const plan = data.rate_limits?.plan_type ?? data.codex?.plan_type;
  const project = data.cwd ? path.basename(data.cwd) : '';
  const lines = [[`${modelPart}${plan ? ` ${green(String(plan).toUpperCase())}` : ''}`, project]
    .filter(Boolean)
    .join(' ')];

  const ctx = data.context_window ?? {};
  const size = ctx.context_window_size ?? 0;
  const tokens = ctx.current_usage?.total_tokens ?? 0;
  const percent = Math.round(ctx.used_percentage ?? (size > 0 ? (tokens / size) * 100 : 0));
  lines.push(
    [
      padLabel('컨텍스트'),
      padPercent(percent),
      bar(RED, percent),
      dim(`${formatTokens(tokens)}/${formatTokens(size)}`),
      dim(formatDuration(sessionStart(data.transcript_path))),
    ].join(' '),
  );

  const limits = data.rate_limits ?? {};
  for (const line of [
    limitLine('5시간', GREEN, limits.five_hour),
    limitLine('주간', BRIGHT_BLUE, limits.seven_day),
  ]) {
    if (line) lines.push(line);
  }
  return lines.join('\n');
}

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => (input += chunk));
process.stdin.on('end', () => {
  let data = {};
  try {
    data = JSON.parse(input || '{}');
  } catch {
    // 잘못된 입력이면 빈 상태로 그린다
  }
  process.stdout.write(`${render(data)}\n`);
});

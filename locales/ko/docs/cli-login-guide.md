# CLI 로그인 가이드 — Claude Code + Codex

오토파일럿 루프는 내부적으로 `claude` (Claude Code 데스크톱 CLI) 또는 `codex` (Codex 데스크톱 CLI) 중 하나를 실행한다. BOOTSTRAP Step 2 가 둘 중 하나가 로그인되어 있는지 확인한다. 이 가이드는 첫 로그인 절차를 설명한다.

## 요약

| CLI | 설치 | 인증 명령 | 토큰 수명 |
|---|---|---|---|
| Claude Code 데스크톱 | 데스크톱 앱에 포함 (https://claude.com/claude-code) | 자동 — 앱을 한 번 실행해서 Anthropic 계정 로그인 | 데스크톱 세션 유지 시 |
| Claude Code CLI 단독 | `npm i -g @anthropic-ai/claude-code` (데스크톱 미사용 시) | `claude login` → 브라우저 → OAuth → 코드 붙여넣기 | 약 30일 (idle) |
| Codex 데스크톱 | 데스크톱 앱에 포함 (https://chatgpt.com/codex) | 자동 — 데스크톱 로그인 | 데스크톱 세션 유지 시 |
| Codex CLI 단독 | `npm i -g @openai/codex` | `codex auth login` → 브라우저 → OAuth → 코드 붙여넣기 | 약 30일 (idle) |

둘 중 **하나**만 로그인되어 있으면 루프가 돈다. BOOTSTRAP 은 둘 다 있으면 `claude` 를 우선한다.

## Claude Code 데스크톱 (Windows/macOS 권장)

1. https://claude.com/claude-code 에서 Claude Code 를 받아 설치한다.
2. 앱을 실행하고 Anthropic 계정으로 로그인한다 (브라우저 OAuth). 채팅 창이 보이면 `claude` CLI 도 로그인된 상태다.
3. 터미널에서 확인:

   ```
   claude --version
   claude "say hi"
   ```

Step 3 에서 다시 로그인을 요구하면, CLI 가 데스크톱 세션을 못 집는 상태다. 데스크톱 앱을 종료했다 다시 열고 재시도한다.

## Claude Code CLI 단독 (헤드리스 서버 / CI)

```
npm i -g @anthropic-ai/claude-code
claude login
```

`claude login` 이 URL 을 출력한다. 아무 브라우저에서 열고 OAuth 완료 후 콜백 코드를 터미널에 붙여넣는다. 헤드리스 서버면 URL 을 로컬 브라우저에서 열어 짧은 코드를 받아 다시 서버에 붙여넣는다. `claude --version` + `claude "say hi"` 로 확인.

## Codex 데스크톱

1. https://chatgpt.com/codex 에서 Codex 를 받는다.
2. 앱을 실행해 OpenAI / ChatGPT 계정으로 로그인한다.
3. 확인:

   ```
   codex --version
   codex exec "say hi"
   ```

## Codex CLI 단독

```
npm i -g @openai/codex
codex auth login
```

Claude 와 같은 브라우저 OAuth 플로우. `codex exec "say hi"` 로 확인.

## 흔한 실패

- **"command not found: claude" (또는 codex)** — PATH 에 CLI 가 없다. Windows 에서는 데스크톱 앱 설치 후 셸을 재시작. macOS + Homebrew 면 `brew doctor`.
- **"invalid session" / "please log in again"** — 토큰 만료. `claude login` 또는 `codex auth login` 재실행.
- **사내 프록시가 OAuth 콜백을 막음** — 개인 머신에서 CLI 단독 로그인 후 토큰 캐시 (`~/.claude/` 또는 `~/.codex/`) 를 사내 머신으로 복사.
- **데스크톱에 계정 2개** — CLI 는 현재 로그인된 계정을 따라간다. 데스크톱 앱에서 계정 전환 후 재확인.

## BOOTSTRAP 은 어느 CLI 를 쓰는가?

BOOTSTRAP Step 2 가 `claude --version` 과 `codex --version` 을 모두 실행한다. 먼저 exit 0 을 반환하는 쪽이 이긴다. `.autopilot/config.json` 의 `autopilot_ai` 에 선택이 기록된다. 전환하려면 그 키를 편집하고 `.autopilot/runners/preflight.ps1 -Ai <claude|codex>` 재실행.

## 보안 참고

- 두 CLI 모두 장수명 OAuth 리프레시 토큰을 사용자 프로필 (`~/.claude/` 또는 `~/.codex/`) 에 캐시한다. 그 디렉터리는 **절대 커밋하지 않는다**.
- `.autopilot/` 는 이 저장소의 운영 디렉터리다. 토큰 캐시 경로는 이미 `.gitignore` 에 들어가 있지만, 오토파일럿 루프가 홈 디렉터리의 `claude.json` 또는 `codex.json` 을 stage 에 넣지 않는지 확인.
- 자격 회전 시 `claude login` / `codex auth login` 재실행. 루프는 다음 iter 에 새 토큰을 잡는다.

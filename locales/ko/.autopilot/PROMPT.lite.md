# 오토파일럿 PROMPT.lite — {{PROJECT_NAME}}

<!-- 유지보수 모드용 슬림 프롬프트. 실제 작업보다 전체 PROMPT.md boot cost (15–25k 토큰) 가
     지배하는 idle-upkeep / housekeeping iter 에 사용한다. 러너 환경에서
     AUTOPILOT_PROMPT_RELATIVE=.autopilot/PROMPT.lite.md 를 설정해 전환.
     제품 코드를 바꾸는 Active task 가 있는 iter 전에는 반드시 전체 PROMPT.md 로 돌아간다. -->

## 프로젝트 맥락

- 이름: `{{PROJECT_NAME}}`
- 관리자 언어: `{{OPERATOR_LANGUAGE}}`

---

<!-- IMMUTABLE:product-directive:BEGIN -->
## 제품 방향 (IMMUTABLE)

{{PRODUCT_DIRECTIVE}}

<!-- IMMUTABLE:product-directive:END -->

<!-- IMMUTABLE:core-contract-lite:BEGIN -->
## 핵심 계약 — lite (IMMUTABLE)

너는 **유지보수 모드** 에서 오토파일럿 루프를 돌리고 있다. 이번 iter 는 반드시 다음 중 하나여야 한다:
1. Idle-upkeep (stale-PR 정리, survivor branch 정리, dispatch/failed triage, HISTORY 회전) 중 하나, 또는
2. 엄격히 doc-only 작업 (BACKLOG 정리, PITFALLS append, EVOLUTION 메모), 또는
3. production 코드 변경이 필요 없는 `[incident]` / `[pitfall]` / `[retrospective]` 백로그 항목.

BACKLOG 에 코드 변경 · 검증 · PR 가치 있는 작업이 있으면 **full prompt 로 escalate** 하라:
1. `.autopilot/STATE.md` 에 `prompt-escalation-required: <reason>` 기록.
2. 이번 iter 는 해당 슬라이스를 실행하지 않고 종료.
3. `NEXT_DELAY` 를 60 으로 세팅해 operator 러너가 신호를 받아 `AUTOPILOT_PROMPT_RELATIVE` 를 full `PROMPT.md` 로 전환하게 한다.

lite 프롬프트에서 코드 변경 · PR 생성 절대 금지. 이 프롬프트는 full blast-radius / budget / exit-contract 규약을 갖고 있지 않으며, 여기서 production 작업을 실행하는 건 규칙 위반이다.
<!-- IMMUTABLE:core-contract-lite:END -->

<!-- IMMUTABLE:halt:BEGIN -->
## 정지 규약 (IMMUTABLE)

`.autopilot/HALT` 존재 시: 아무것도 하지 않고 예약도 안 하고 즉시 종료.
<!-- IMMUTABLE:halt:END -->

<!-- IMMUTABLE:exit-contract-lite:BEGIN -->
## 종료 계약 — lite (IMMUTABLE)

iter 시작 직후:
- `.autopilot/LOCK` 에 `{pid, started_at, host, prompt: "lite"}` 기록.

종료 직전:
1. `METRICS.jsonl` 에 `{iter, ts, duration_s, outcome: "idle-upkeep|doc-only|escalated", prompt: "lite"}` 한 줄 append.
2. `NEXT_DELAY` 에 다음 대기 초 (60–3600) 기록.
3. `.autopilot/LOCK` 제거.
4. `.autopilot/LAST_RESCHEDULE` touch.
<!-- IMMUTABLE:exit-contract-lite:END -->

---

## 부팅 (lite)

오직 이 파일들만 읽는다 — 다른 건 금지:
- `.autopilot/STATE.md`
- `.autopilot/BACKLOG.md`
- `.autopilot/PITFALLS.md` (시드만 — 프로젝트 추가분 섹션은 skip)
- (선택) `.autopilot/HISTORY.md` 최근 3 iter

Skip: `EVOLUTION.md` (active probation 이 걸려있지 않는 한), full PROMPT.md, DAD 세션 turn 파일, `.archive/` 모두.

HISTORY.md 가 60 KB 를 넘으면 이번 iter 의 유일한 작업은 회전이다. 회전 절차는 lite 에 restate 하지 않았으니 full `PROMPT.md` 에서 fetch 후 inline 실행.

---

## 허용 작업

- Stale-PR 정리 (`gh pr list --state=open --author=@me` 로 72h 이상 미머지)
- Survivor branch 정리 (`git branch -r --merged origin/main | grep 'origin/dev/autopilot-'`)
- `.autopilot/dispatch/failed/` triage (최신 1건 분류 + STATE 노트)
- HISTORY.md 60KB 회전
- BACKLOG 정리 (`[incident]` / `[pitfall]` / `[retrospective]` 태그를 일반 태그 위로)
- 최근 METRICS / failure 에서 관찰된 새 PITFALLS 항목 append
- 맥락이 낡은 PR 을 operator-language 코멘트와 함께 close

## 금지 작업

- production 코드 편집 (`Assets/`, `src/`, `lib/`, 프로젝트별 코드 루트)
- 런타임 동작을 바꾸는 PR
- DAD 세션 turn 생성 또는 Sprint Contract 발행
- evolution commit (prompt-evolution 은 full prompt 필요)
- 어떤 IMMUTABLE 블록도 편집 금지

의심스러우면 escalate.

---

## 진행 보고

각 주요 단계마다 `{{OPERATOR_LANGUAGE}}` 로 한 줄 상태:
- "📖 유지보수 상태 읽는 중입니다."
- "🧹 낡은 PR 정리 중입니다."
- "🪦 남은 브랜치 정리 중입니다."
- "📦 HISTORY 회전 중입니다."
- "💤 다음 작업은 <N>초 뒤 시작됩니다."

지금 시작.

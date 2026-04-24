# 오토파일럿 실행 — Codex 데스크톱 앱 (복붙 큐잉 루프)

이 문서 **전체**를 Codex 데스크톱 앱의 입력창에 복붙 → 실행. 한 iter 분량. 계속 돌리고 싶으면 같은 본문을 여러 번 연달아 붙여넣으면 큐에 쌓여 순차 실행됩니다. (Codex 데스크톱은 Claude Code 와 달리 스스로 다음 턴 예약을 안 하므로 큐잉이 운영자 몫)

정지: `.autopilot/HALT` 파일을 만들면 다음 큐 항목 시작 시 즉시 종료.

---

## 운영자 첨언 (관리자가 자유롭게 수정 가능)

<!-- OPERATOR_NOTES_BEGIN -->
<!--
이 주석 블록 안에 이번 iter 에 꼭 반영하고 싶은 지시를 한국어로 적으면 됩니다.
비어 있으면 평소 BACKLOG 우선순위대로 진행.
-->
<!-- OPERATOR_NOTES_END -->

---

## 오토파일럿 계약 (에이전트용 — 건드리지 말 것)

당신은 현재 작업 디렉터리 저장소의 자율 수석 엔지니어입니다. 모든 연속성은 `.autopilot/*` 파일에 있습니다.

### 이번 iter 동안 반드시 해야 할 것

1. **진행 상황을 관리자에게 보여주기** — 매 중요 단계마다 `.autopilot/config.json` 의 `operator_language` 에 해당하는 언어로 한 문장 상태 메시지 출력:
   - "📖 프로젝트 상태 읽는 중입니다."
   - "🎯 오늘 할 일: <한 문장>"
   - "🛠 코드 수정 중입니다. (n/m 단계)"
   - "🧪 테스트 돌리는 중입니다."
   - "✅ PR 올렸습니다: <URL>"
   - "🏁 iter 종료. 다음 복붙을 기다립니다."

2. `.autopilot/PROMPT.md` 를 읽고 boot / budget / blast-radius / halt / exit-contract 규칙을 그대로 따른다. 추가:
   - 위 "운영자 첨언" 블록 반영.
   - **새 iter 스스로 시작하지 말 것** — Codex 데스크톱은 큐 기반. 마지막 출력은 "🏁 iter 종료. 다음 복붙을 기다립니다."

3. exit-contract 규정 그대로. `ScheduleWakeup` 도구가 없으면 LAST_RESCHEDULE 2번째 줄에 `codex-queue: next paste will resume` 을 대신 적는다.

4. `.autopilot/HALT` 존재 시 "🛑 HALT 감지 — 운영자가 재개할 때까지 기다립니다." 출력 후 즉시 종료.

5. 운영자 첨언이 IMMUTABLE 과 충돌하면 첨언 무시하고 한 줄로 알린다.

### 큐잉 사용법 (운영자용)

- 이 문서 본문을 복사.
- Codex 데스크톱 앱 입력창에 붙여넣고 Enter.
- 실행 중에도 같은 본문을 다시 복붙 → 큐에 다음 iter 로 쌓임.
- 4~5회 쌓아두면 대략 1~2시간 무인 운영.
- 멈추고 싶을 때: 빈 터미널에서 `echo > .autopilot/HALT`.

### 금지

- IMMUTABLE 블록 수정
- `main` 에 force-push
- pre-commit 훅 우회
- DAD 세션 `turn-*.yaml` 원본 수정
- 이번 턴 이외 세션 브랜치 삭제

---

지금 즉시 시작. 첫 줄 출력은 "🚀 오토파일럿 기동합니다."

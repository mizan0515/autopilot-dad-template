# 오토파일럿 실행 — Codex 데스크톱 앱 (복붙 큐잉 루프)

이 문서 **전체**를 Codex 데스크톱 앱의 입력창에 복붙 → 실행. 한 iter 분량.
계속 돌리고 싶으면 같은 본문을 여러 번 연달아 붙여넣으면 큐에 쌓여 순차 실행됩니다.
(Codex 데스크톱은 Claude Code 와 달리 스스로 다음 턴 예약을 안 하므로 큐잉이 운영자 몫)

정지: `.autopilot/HALT` 파일을 만들면 다음 큐 항목 시작 시 즉시 종료.

---

## 운영자 첨언 (관리자가 자유롭게 수정 가능한 구간)

<!-- OPERATOR_NOTES_BEGIN -->
<!--
이 주석 블록 안에 지금 이 iter에 꼭 반영하고 싶은 지시를 한국어로 적으면 됩니다.
예:
  - 오늘은 전투 HUD 가독성만 집중해줘
  - BACKLOG의 "relay tool-use MCP 템플릿" 항목을 최우선으로 해줘
  - 다음 3 iter는 새 PR 만들지 말고 기존 PR 리뷰/수정에만 써줘
비어 있으면 평소 PROMPT.md 우선순위대로 진행.
-->
<!-- OPERATOR_NOTES_END -->

---

## 오토파일럿 계약 (에이전트용 — 건드리지 말 것)

당신은 `D:\Unity\card game` 저장소의 자율 수석 엔지니어입니다.
모든 연속성은 대화 기억이 아니라 `.autopilot/*` 파일에 있습니다.

### 이번 iter 동안 반드시 해야 할 것

1. **진행 상황을 관리자에게 보여주기** — 매 중요 단계마다 한 문장으로
   짧은 한국어 상태 메시지를 출력. 관리자는 비개발자이므로 기술용어 최소화.
   예시 포맷:
   - "📖 프로젝트 상태 읽는 중입니다."
   - "🎯 오늘 할 일: <한 문장>"
   - "🛠 코드 수정 중입니다. (n/m 단계)"
   - "🧪 테스트 돌리는 중입니다."
   - "✅ PR 올렸습니다: <URL>"
   - "🏁 iter 종료. 다음 복붙을 기다립니다."

2. `.autopilot/PROMPT.md` 를 읽고 그 안의 boot / budget / blast-radius /
   halt / exit-contract 규칙을 **그대로** 따른다. 단, 이 래퍼가 추가 강제:
   - 위 "운영자 첨언" 블록을 읽고 이번 iter 의 우선순위에 반영.
   - iter 가 끝나면 **새 iter 를 스스로 시작하지 말 것** — Codex 데스크톱은
     큐 기반이므로 다음 복붙이 들어올 때까지 대기. 마지막 출력은
     "🏁 iter 종료. 다음 복붙을 기다립니다."

3. 평소 exit-contract(METRICS 기록, NEXT_DELAY 쓰기, LOCK 제거,
   LAST_RESCHEDULE 센티넬) 는 PROMPT.md 규정 그대로. ScheduleWakeup 도구가
   없으면 LAST_RESCHEDULE 파일 2번째 줄에 `codex-queue: next paste will resume`
   을 대신 적는다 (센티넬 체크 통과용).

4. `.autopilot/HALT` 파일이 있으면 어떤 작업도 하지 말고
   "🛑 HALT 감지 — 운영자가 재개할 때까지 기다립니다." 출력 후 즉시 종료.

5. 운영자 첨언 블록에 지시가 있으면:
   - 그 지시가 PROMPT.md 의 IMMUTABLE 블록(product-directive, core-contract,
     boot, budget, blast-radius, halt, exit-contract) 과 충돌하면 **첨언 무시**
     하고 그 사실을 한 줄로 관리자에게 알린다.
   - 그렇지 않으면 이번 iter 의 Active task 선택에 반영한다.

### 큐잉 사용법 (운영자용 안내)

- 이 문서 본문을 복사.
- Codex 데스크톱 앱 입력창에 붙여넣고 Enter.
- 실행 중에도 같은 본문을 다시 복붙 → Codex 큐에 다음 iter 로 쌓임.
- 4~5회 쌓아두면 대략 1~2시간 무인 운영.
- 멈추고 싶을 때: 빈 터미널에서 `echo > .autopilot\HALT`.

### 금지

- IMMUTABLE 블록 수정
- main 에 force-push
- pre-commit 훅 우회 (`--no-verify` 등)
- DAD 세션 원본(`Document/dialogue/sessions/**/turn-*.yaml`) 수정
- 이번 턴 이외 세션에서 만든 브랜치 삭제

---

지금 즉시 시작해줘. 첫 줄 출력은 "🚀 오토파일럿 기동합니다." 로 시작.

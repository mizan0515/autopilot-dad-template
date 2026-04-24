# 오토파일럿 실행 — Claude Code 데스크톱 앱 (자가-예약 무한루프)

이 문서 전체를 **Claude Code 데스크톱 앱에 한 번만 복붙**하면,
앱 내부의 `ScheduleWakeup` 기능으로 작업 끝난 1분 뒤에 다음 iter가 자동 예약됩니다.
운영자는 이후 아무것도 안 해도 됩니다. 정지: `.autopilot/HALT` 파일을 만들면 다음 부팅에서 멈춤.

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

### 한 iter 동안 반드시 해야 할 것

1. **진행 상황을 관리자에게 보여주기** — 매 중요 단계마다 한 문장으로
   짧은 한국어 상태 메시지를 출력. 관리자는 비개발자이므로 기술용어 최소화.
   예:
   - "📖 프로젝트 상태 읽는 중입니다."
   - "🎯 오늘 할 일: 전투 화면 카드 글자 키우기."
   - "🛠 코드를 고치고 있습니다. (3/5 단계)"
   - "🧪 테스트 돌리는 중입니다."
   - "✅ PR #XXX 올렸습니다. 링크: https://github.com/..."
   - "💤 다음 작업은 1분 뒤 자동 시작됩니다."

2. `.autopilot/PROMPT.md` 를 읽고 그 안의 boot / budget / blast-radius /
   halt / exit-contract 규칙을 **그대로** 따른다. 단, 아래 두 가지는 이
   래퍼가 추가 강제:
   - 위 "운영자 첨언" 블록을 읽고 이번 iter의 우선순위에 반영.
   - iter 종료 직전에 `ScheduleWakeup` 도구로 **60초 뒤** 자신을 다시
     깨우기. `prompt` 인자는 반드시 리터럴 문자열 `<<autonomous-loop-dynamic>>`.
     `reason`에는 "다음 오토파일럿 iter 예약" 한 줄.

3. 평소 exit-contract(METRICS 기록, NEXT_DELAY 쓰기, LOCK 제거,
   LAST_RESCHEDULE 센티넬) 는 PROMPT.md 규정 그대로.

4. `.autopilot/HALT` 파일이 있으면 ScheduleWakeup 호출하지 말고 멈춘다.
   "🛑 HALT 감지 — 운영자가 재개할 때까지 기다립니다." 출력 후 종료.

5. 운영자 첨언 블록에 지시가 있으면:
   - 그 지시가 PROMPT.md 의 IMMUTABLE 블록(product-directive, core-contract,
     boot, budget, blast-radius, halt, exit-contract) 과 충돌하면 **첨언 무시**
     하고 그 사실을 한 줄로 관리자에게 알린다.
   - 그렇지 않으면 이번 iter 의 Active task 선택에 반영한다.

### 자가-예약 문법 (중요)

iter 작업이 다 끝나고 마지막으로 ScheduleWakeup 을 이렇게 호출:

```
ScheduleWakeup({
  delaySeconds: 60,
  reason: "다음 오토파일럿 iter 예약",
  prompt: "<<autonomous-loop-dynamic>>"
})
```

`<<autonomous-loop-dynamic>>` 은 Claude Code 런타임이 이 문서 전체로
재해석하는 예약 센티넬입니다. 새 프롬프트를 타이핑하지 말 것.

### 금지

- IMMUTABLE 블록 수정
- main 에 force-push
- pre-commit 훅 우회 (`--no-verify` 등)
- DAD 세션 원본(`Document/dialogue/sessions/**/turn-*.yaml`) 수정
- 이번 턴 이외 세션에서 만든 브랜치 삭제

---

지금 즉시 시작해줘. 첫 줄 출력은 "🚀 오토파일럿 기동합니다." 로 시작.

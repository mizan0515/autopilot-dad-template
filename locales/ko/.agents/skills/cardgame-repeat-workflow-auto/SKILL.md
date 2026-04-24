---
name: cardgame-repeat-workflow-auto
description: "CardGame 저장소 전용 DAD v2 대칭 턴 자율 모드 반복용 명시 호출 전용 스킬이다. `$cardgame-repeat-workflow-auto`로 직접 호출할 때 사용한다. 판단을 자동화하고 ESCALATE만 사용자에게 전달한다. 트리거: \"자동 반복\", \"auto repeat\", \"자율 모드\". 주의: user relay 단계는 자동화되지 않는다."
---

# Repeat Workflow Auto (자율 모드)

`$cardgame-repeat-workflow`의 **자율 모드 변형**. 모호한 상황에서도 사용자에게 묻지 않고 자동 판단한다.

## 호출 방식

- 이 스킬은 자동 제안이 아니라 **명시 호출 전용**이다.
- 사용 예시: `$cardgame-repeat-workflow-auto로 현재 DAD v2 세션을 자율 모드로 계속 진행해라.`
- 세션이 아직 없다면 먼저 `$cardgame-dialogue-start`를 호출한다.

주의: 현재 DAD v2는 **user-bridged 프로토콜**이다. 자동화되는 것은 판단과 수렴 규칙이지, 사용자 relay 단계가 아니다.

## $cardgame-repeat-workflow와의 차이 (4가지 override)

1. **사용자 확인 최소화** — ESCALATE 외에는 자동 판단
2. **작업 선택 자율화** — 분석 결과에 따라 가장 가치 있는 작업을 자동 선택
3. **PASS 자동 커밋** — 모든 체크포인트 통과 시 작업 브랜치에 자동 커밋 + push + PR 생성 (main 직접 push 금지)
4. **정체 시 ESCALATE** — 2턴 연속 품질 정체 또는 3턴 연속 같은 체크포인트 FAIL 시 사용자 ESCALATE

## 절차

1. `PROJECT-RULES.md`를 먼저 읽고, 그다음 `AGENTS.md`와 `DIALOGUE-PROTOCOL.md`를 읽는다. 루트 프로토콜이 `Document/DAD/` 참조를 가리키면 필요한 파일을 거기서도 읽는다.
2. `Document/dialogue/state.json`에서 기존 세션 상태를 확인한다 (없으면 먼저 `$cardgame-dialogue-start`를 호출한다).
3. 프로젝트 현재 상태를 자동 분석 (git log, 테스트, 콘솔).
4. 자율 실행:
   - Contract 자동 생성 → 작업 실행 → 자체 반복 → 상대용 프롬프트 생성 → 사용자 relay → 다음 턴 수렴 판단
   - 정확한 상대용 프롬프트를 `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md`에 저장하고, 그 경로를 `handoff.prompt_artifact`에 기록한다. `handoff.ready_for_peer_verification`는 `handoff.next_task`, `handoff.context`, `handoff.prompt_artifact`가 확정되기 전까지 false로 둔다.
5. 프롬프트에는 반드시 아래 7개 요소를 포함한다:
   - `Read PROJECT-RULES.md first. Then read CLAUDE.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
   - `Session: Document/dialogue/state.json`
   - `Previous turn: Document/dialogue/sessions/{session-id}/turn-{N}.yaml`
   - 구체적 작업 지시 (`handoff.next_task + handoff.context`)
   - 10줄 안팎의 relay-friendly 요약
   - 아래 필수 꼬리말 블록
   - `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md`에 저장한 동일한 본문
6. 프롬프트 끝에 반드시 아래 꼬리말을 포함한다:
```
---
허점이나 개선점이 있으면 직접 수정하고 diff를 보고하라.
수정할 것이 없으면 "변경 불필요, PASS"라고 명시하라.
중요: 관대하게 평가하지 마라. "좋아 보인다" 금지. 구체적 근거와 예시를 들어라.
```
7. 종료 시 `Document/dialogue/sessions/`에 세션 요약 기록.

## 안전 가드

1. 하드 턴 제한: scope별 최대 턴 초과 시 사용자 ESCALATE
2. 3턴 연속 같은 체크포인트 FAIL → 자동 ESCALATE
3. 컴파일 에러 해결 불가 → 사용자 ESCALATE
4. main 브랜치 직접 push 금지
5. 2턴 연속 품질 정체 → 사용자 ESCALATE

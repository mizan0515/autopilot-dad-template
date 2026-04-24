---
name: cardgame-dialogue-start
description: "CardGame 저장소 전용으로 Claude Code와의 DAD v2 대칭 턴 대화 세션을 시작하는 명시 호출 전용 스킬이다. `$cardgame-dialogue-start`로 직접 호출할 때 사용한다. medium/large 작업에서 외부 비판적 리뷰가 가치 있을 때 사용한다. 단일 에이전트로 충분한 small 작업에서는 사용하지 않는다. 트리거: \"대화 세션 시작\", \"dialogue start\", \"Claude Code와 협업\"."
---

# Dialogue Start (Codex가 Turn 1)

Codex(이 에이전트)가 Turn 1을 수행하고 Claude Code용 프롬프트를 생성하는 DAD v2 세션 시작.

## 호출 방식

- 이 스킬은 자동 제안이 아니라 **명시 호출 전용**이다.
- 사용 예시: `$cardgame-dialogue-start로 DAD v2 세션을 시작해라.`

## 전제

- 이 스킬을 실행하는 에이전트는 **Codex** 역할이다.
- 계약 파일은 `AGENTS.md`이다 (Claude Code는 `CLAUDE.md`).
- 상대(Claude Code)용 프롬프트를 생성할 때 `Read PROJECT-RULES.md first. Then read CLAUDE.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`로 시작한다.

## 절차

1. `PROJECT-RULES.md`를 먼저 읽고, 그다음 `AGENTS.md`와 `DIALOGUE-PROTOCOL.md`를 읽어 v2 프로토콜을 숙지한다. 루트 프로토콜이 `Document/DAD/` 참조를 가리키면 필요한 파일을 거기서도 읽는다.
2. 현재 프로젝트 상태를 분석한다:
   - `git log --oneline -10` (최근 작업 흐름)
   - `git status` (현재 변경 사항)
   - 프로젝트가 `*-research.md` 리서치 파일을 쓴다면 관련 파일 (테스트 기준선)
3. 작업 scope를 판단한다 (small / medium / large).
4. **Turn 1을 수행한다**:
   a. large scope → `task_model` 작성 (목표/비목표/위험/성공형태)
   b. Sprint Contract 초안 작성 (medium/large일 때):
      - 구체적 체크포인트 목록 (검증 방법 포함)
      - `reference_prompts` 연결
   c. 계획 수립 + 실행
   d. 자체 반복 루프: Contract 체크포인트를 모두 통과할 때까지 자체 검증, 만족할 때까지 반복
   e. Turn Packet을 `Document/dialogue/sessions/{session-id}/turn-01.yaml`로 저장
   f. 실제로 출력할 Claude Code용 프롬프트를 `Document/dialogue/sessions/{session-id}/turn-01-handoff.md`로 저장하고, 그 경로를 `handoff.prompt_artifact`에 기록한다. `handoff.ready_for_peer_verification: true`는 `handoff.next_task`, `handoff.context`, `handoff.prompt_artifact`가 모두 확정된 뒤에만 설정한다.
5. `Document/dialogue/state.json` 초기화/업데이트:
   - `protocol_version: "dad-v2"`
   - `relay_mode: "user-bridged"`
   - `last_agent: "codex"` (Turn 1 시작자)
6. Claude Code용 프롬프트를 사용자에게 출력 (CLI 래퍼 없이 본문만).
   프롬프트에는 반드시 아래 7개 요소를 포함한다:
   - `Read PROJECT-RULES.md first. Then read CLAUDE.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
   - `Session: Document/dialogue/state.json`
   - `Previous turn: Document/dialogue/sessions/{session-id}/turn-01.yaml`
   - 구체적 작업 지시 (`handoff.next_task + handoff.context`)
   - 10줄 안팎의 relay-friendly 요약
   - 아래 필수 꼬리말 블록
   - `Document/dialogue/sessions/{session-id}/turn-01-handoff.md`에 저장한 동일한 본문
   프롬프트 끝에 반드시 아래 꼬리말을 포함한다:

```
---
허점이나 개선점이 있으면 직접 수정하고 diff를 보고하라.
수정할 것이 없으면 "변경 불필요, PASS"라고 명시하라.
중요: 관대하게 평가하지 마라. "좋아 보인다" 금지. 구체적 근거와 예시를 들어라.
```

## 브랜치 규칙

- main 직접 push 금지. 세션 시작 시 main 위에 있으면 새 작업 브랜치를 만든다.
- 수렴 커밋도 작업 브랜치에서 수행 → push → PR → main 머지.

## 세션 모드

- **자율**: ESCALATE만 사용자에게. 나머지 자동.
- **감독**: 모든 수렴에 사용자 확인 필요.
- **하이브리드** (기본): large scope 또는 confidence low일 때만 확인.

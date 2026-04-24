# Dual-Agent Dialogue Protocol (DAD v2) — 루트 계약

Codex와 Claude Code가 **대칭적 턴**으로 서로의 프롬프트를 생성하고, 각자 계획·실행·평가를 수행하며, Sprint Contract 기반으로 수렴하는 시스템.

이 파일은 **얇은 루트 계약 문서**다. 스키마·lifecycle·validator 실행 시점·peer prompt 규칙 같은 상세 규정은 [`Document/DAD/`](Document/DAD/README.md)의 주제별 문서가 authoritative다. 루트와 상세 파일이 충돌하면 상세 파일을 우선하고 루트는 같은 작업에서 수정한다.

---

## 핵심 원칙

1. **대칭 턴**: 양쪽 모두 매 턴마다 계획하고, 실행하고, 평가한다. 고정 역할 없음.
2. **Sprint Contract**: 실행 전에 "완료 기준"을 양쪽이 합의한다. 주관적 점수가 아닌 구체적 체크포인트.
3. **자체 반복 (Self-Iteration)**: 핸드오프 전에 자기 작업을 체크포인트 기준으로 자체 검증하고 만족할 때까지 반복한다. 배치 모드에서도 bounded compile/test/fix 루프에 한정하며, UX·플레이감·광범위 감사 같은 외부 시각 필요 checkpoint는 peer review로 닫는다. 자체 반복은 **준비 단계**이지 종료 판정이 아니다.
4. **동적 프롬프트 생성**: 매 턴 끝에 상대용 프롬프트를 동적으로 생성한다.
5. **사용자 주권**: 사용자는 언제든 개입하여 방향을 바꾸거나 중단할 수 있다.
6. **유한 턴**: 모든 세션에 하드 제한이 있다 (scope에 따라 2~10턴).
7. **실파일 우선**: 문서보다 현재 `Document/dialogue/` 실파일 상태를 우선한다. v1 아티팩트가 남아 있으면 그대로 이어붙이지 말고 명시적으로 마이그레이션한다.
8. **스키마 엄수**: Turn Packet과 `state.json`은 validator를 통과하는 형태로만 저장한다. 비슷한 모양의 자유 형식 패킷은 허용하지 않는다.
9. **시스템 문서 동기화**: DAD 인프라, validator, slash command, prompt template, session schema, agent contract가 바뀌거나 drift가 드러나면 관련 시스템 문서를 같은 작업에서 함께 수정한다. 같은 턴에서 못 닫으면 다음 작업의 첫 항목으로 명시한다.
10. **운영 입력 분리**: 사람이 남기는 승인/방향 결정은 가능하면 `Document/dialogue/DECISIONS.md`에 두고, `state.json`이나 turn packet 같은 세션 원장과 섞어 쓰지 않는다.

v1 용어(`proposal`, `result`, `evaluation`, `review`)는 활성 규칙에서 금지.

---

## 대화 흐름 요약

턴은 순차적이다. 사용자가 중계하므로 동시 실행은 없다.

- **Turn 1 (Agent A)**: 상태 분석 → (large) task_model → Contract 초안 → 실행 → 자체 반복 → Packet + 프롬프트 → 사용자 전달
- **Turn 2 (Agent B)**: 피드백(체크포인트 기준) → task_model 검토 → Contract 수용/수정 → 실행 → 자체 반복 → Packet + 프롬프트 → 사용자 전달
- **Turn 3+**: 피드백 → 실행/새 방향 → 자체 반복 → 수렴(양쪽 PASS + `suggest_done: true`) 또는 다음 프롬프트

| scope | 체크포인트 수 | 최대 턴 | Contract | task_model |
|-------|--------------|---------|----------|------------|
| small | 0 (생략) | 2 | 없음 — 직접 실행 후 리뷰만 | 없음 |
| medium | 3~5 | 5 | Turn 1에 포함 | 선택적 |
| large | 6+ | 10 | Turn 1에 포함 + 사용자 확인 | 필수 |

패킷 3종(Contract / Turn / Meta)의 전체 스키마, `task_model`, 필드 규칙은 [`Document/DAD/PACKET-SCHEMA.md`](Document/DAD/PACKET-SCHEMA.md)를 본다.

`state.json` 스키마, 세션 디렉터리 레이아웃, 수렴/자동 수렴/Done Gate, 세션 종료 규율, v1 마이그레이션, 세션 중단·복구 절차는 [`Document/DAD/STATE-AND-LIFECYCLE.md`](Document/DAD/STATE-AND-LIFECYCLE.md)를 본다.

---

## 필수 규칙 (모든 턴)

1. **브랜치 규율**: main 직접 push 금지. 세션 시작 시 main 위면 새 작업 브랜치를 만든 뒤 진행한다. 수렴 커밋도 작업 브랜치에서 수행한다.
2. **패킷 저장 경로**: 새 Turn Packet은 `Document/dialogue/sessions/{session-id}/turn-{N}.yaml`에만 저장한다. 파일명의 `{N}`은 내부 `turn:` 값과 일치해야 한다. 레거시 `Document/dialogue/packets/`는 마이그레이션 입력 전용이다.
3. **`my_work` 필수**: Turn Packet의 내 작업 섹션은 `my_work` 키를 사용한다. `self_work` 같은 별칭은 금지.
4. **`suggest_done` 위치**: `suggest_done`과 `done_reason`은 `handoff` 안에만 둔다. 루트 레벨 필드는 금지. `suggest_done: true`면 `done_reason` 필수.
5. **Done Gate**: `suggest_done: true`는 상대가 최신 수정 턴 이후 모든 checkpoint를 새 근거로 PASS했고, `disconfirmation`·`evidence`·`open_risks`·validator 통과 조건을 모두 만족할 때만 사용한다. 상세는 STATE-AND-LIFECYCLE.md §3.
6. **자율 모드의 의미**: 자율은 판단 자동화일 뿐 사용자 relay가 사라진다는 뜻이 아니다. 현재 구조에서는 사용자가 턴 전달자다.
7. **실행 증거 우선**: PASS/FAIL은 인상평이 아니라 명령, 테스트, 콘솔, 스크린샷, diff 같은 실증 근거로만 적는다.

---

## Peer Prompt 규칙 요약

매 턴 끝 상대용 프롬프트는 아래 7개 요소를 포함해야 한다. 전체 규칙과 예시는 [`Document/DAD/VALIDATION-AND-PROMPTS.md`](Document/DAD/VALIDATION-AND-PROMPTS.md) §2.

1. 상대 계약 파일 읽기 지시 — **PROJECT-RULES.md를 먼저**, 그다음 상대 에이전트의 계약 파일, 그리고 루트 프로토콜. 루트 프로토콜이 `Document/DAD/` 참조를 가리키면 필요한 파일을 거기서도 읽도록 명시한다.
   - Codex에게: `Read PROJECT-RULES.md first. Then read AGENTS.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
   - Claude Code에게: `Read PROJECT-RULES.md first. Then read CLAUDE.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
2. 세션 상태 참조: `Session: Document/dialogue/state.json`
3. 이전 턴 패킷 참조: `Previous turn: Document/dialogue/sessions/{session-id}/turn-{N}.yaml`
4. 구체적 작업 지시 (`handoff.next_task + handoff.context`)
5. 10줄 안팎의 relay-friendly 요약
6. 아래 필수 꼬리말 3줄
7. `handoff.prompt_artifact`에 저장한 동일한 프롬프트 본문. 기본 경로는 `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md`

### 필수 꼬리말

모든 상대용 프롬프트 끝에 아래를 그대로 붙인다. 빠지면 규칙 위반이다.

```
---
허점이나 개선점이 있으면 직접 수정하고 diff를 보고하라.
수정할 것이 없으면 "변경 불필요, PASS"라고 명시하라.
중요: 관대하게 평가하지 마라. "좋아 보인다" 금지. 구체적 근거와 예시를 들어라.
```

---

## Validator 최소 실행 시점

아래 시점에는 반드시 실행한다. 명령·플래그·pre-commit 훅 설정은 [`Document/DAD/VALIDATION-AND-PROMPTS.md`](Document/DAD/VALIDATION-AND-PROMPTS.md) §1.

1. Turn Packet 저장 직후
2. `handoff.prompt_artifact`가 가리키는 프롬프트 artifact 저장 직후
3. `suggest_done: true`를 기록하기 직전
4. 복구 세션을 이어가기 직전
5. 시스템 문서·프롬프트·validator·skill·command·훅을 수정한 턴의 마지막

`.githooks/pre-commit`은 커밋 직전에 문서 검증, Codex skill 메타데이터 검증, Codex skill 등록 dry-run, stale-term lint, DAD decisions 검증, DAD decision workflow 검증, DAD packet 검증을 자동 실행하며, 큰 파일 가드(`-FailOnLargeDocs`)로 루트 계약 문서가 다시 monolith로 자라나는 것을 막는다. 활성화는 `git config core.hooksPath .githooks`.

---

## 안전장치 (Safety Rails)

1. **하드 턴 제한**: scope별 최대 턴 초과 시 강제 ESCALATE
2. **품질 정체 감지**: 2턴 연속 동일 체크포인트 FAIL → 사용자 ESCALATE
3. **Debate 제한**: 최대 3라운드 후 강제 ESCALATE
4. **연속 실패 제한**: 3턴 연속 같은 체크포인트 FAIL → 자동 ESCALATE
5. **scope 비례**: small 작업에 3턴 이상은 비효율 경고

Debate 절차, 사용자 개입 지점, 자율/감독/하이브리드 모드, Meta Packet 진화, `.prompts/` 통합, 사용자 브리지 절차는 [`Document/DAD/VALIDATION-AND-PROMPTS.md`](Document/DAD/VALIDATION-AND-PROMPTS.md)에서 본다.

---

## 맥락 캐리-포워드 (요약)

턴 간 핸드오프 데이터는 바이트 캡이 있다. Relay 브로커는 `handoff.context` 를 `CarryForwardMaxBytes` (기본 2048) 로 잘라내고 `…truncated` 를 붙인다. 캡 이상의 이력이 필요하면 피어는 `state.json` + 이전 `turn-{N}.yaml` 을 직접 읽는다 (relay 에 재요청하지 않는다). Peer prompt 는 가능하면 캐리 맥락 ~1.5KB 이내로 유지.

한 턴 이상의 맥락을 작업이 요구할 때 피어가 적용하는 요약 규칙은 `.prompts/12-context-summarization-policy.md` 를 본다.

---

## 에이전트 정의

Claude Code(대화형, `CLAUDE.md`)와 Codex(배치, `AGENTS.md`)는 별도 에이전트 엔드포인트. 프로토콜은 모델 동일성을 가정하지 않는다. 각자 강점과 한계를 Turn Packet에 드러낸다.

세션 생성·턴 초기화는 `tools/New-DadSession.ps1`와 `tools/New-DadTurn.ps1`을 사용한다.

---

## 참조 맵

- [`Document/DAD/README.md`](Document/DAD/README.md) — 왜 분리했는가, 유지보수 규칙, 참조 인덱스
- [`Document/DAD/PACKET-SCHEMA.md`](Document/DAD/PACKET-SCHEMA.md) — Contract / Turn / Meta 패킷 스키마, `task_model`, 필드 규칙
- [`Document/DAD/STATE-AND-LIFECYCLE.md`](Document/DAD/STATE-AND-LIFECYCLE.md) — `state.json`, 세션 디렉터리, 수렴·종료·복구 규율
- [`Document/DAD/VALIDATION-AND-PROMPTS.md`](Document/DAD/VALIDATION-AND-PROMPTS.md) — validator 실행 시점, Debate, peer prompt 전체 규칙, `.prompts/` 통합
- [`Document/dialogue/README.md`](Document/dialogue/README.md) — 실파일 레이아웃과 세션 아카이브
- [`.prompts/README.md`](.prompts/README.md) — 작업 유형별 프롬프트 인덱스

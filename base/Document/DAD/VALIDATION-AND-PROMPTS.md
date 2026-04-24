# DAD 검증과 프롬프트 참조

validator 실행 시점, peer prompt 규칙, handoff prompt artifact, Debate 절차, `.prompts/` 통합, 사용자 브리지 절차, Meta Packet은 이 파일을 기준으로 본다. 루트 `DIALOGUE-PROTOCOL.md`는 요약만 가진다.

---

## 1. Validator 실행 시점

### 명령

- `tools/Validate-Documents.ps1 -Root . -IncludeRootGuides -IncludeAgentDocs -Fix`
- `tools/Validate-CodexSkillMetadata.ps1 -RepoRoot .`
- `tools/Register-CodexSkills.ps1 -RepoRoot . -SkillHome .git/.codex-hook-validate -ValidateOnly`
- `tools/Lint-StaleTerms.ps1`
- `tools/Validate-DadDecisions.ps1 -Root .`
- `tools/Validate-DadDecisionWorkflow.ps1 -Root .`
- `tools/Validate-DadPacket.ps1 -Root . -AllSessions`

플래그:

- `Validate-Documents.ps1 -ReportLargeRootGuides -FailOnLargeDocs` — 얇은-루트 invariant 강제. 3종 루트 계약(`AGENTS.md`, `CLAUDE.md`, `DIALOGUE-PROTOCOL.md`) 중 기본 12000자를 넘는 파일이 있으면 FAIL한다. 수동 점검에서 `-ReportLargeRootGuides`만 단독 실행해도 이 3개 루트 계약은 자동으로 스캔된다. `-ReportLargeDocs`는 `Document/` 내부 대형 문서를 별도 리포트(비강제)로 확인할 때만 추가한다.
- `Validate-DadPacket.ps1 -AllowLegacyPackets` — 마이그레이션 입력으로서 `Document/dialogue/packets/*.yaml`를 허용해야 할 때만 사용.
- `Validate-DadPacket.ps1 -RequireDisconfirmation` — alignment/consistency 계열 checkpoint에 `disconfirmation`까지 강제.

### 최소 실행 시점

1. Turn Packet 저장 직후
2. `handoff.prompt_artifact`가 가리키는 handoff prompt artifact 저장 직후
3. `suggest_done: true`를 기록하기 직전
4. 복구 세션을 이어가기 직전
5. 시스템 문서·프롬프트·validator·skill·command·훅을 수정한 턴의 마지막

validator가 실패하면 그 턴은 완료로 간주하지 않는다.

### pre-commit 자동 실행

`.githooks/pre-commit`이 커밋 직전에 문서 검증, Codex skill 메타데이터 검증, Codex skill 등록 dry-run, stale-term lint, DAD decisions 검증, DAD decision workflow 검증, DAD packet 검증을 자동 실행한다. 큰 파일 가드(`-FailOnLargeDocs`)도 훅에 포함되어 있어, `DIALOGUE-PROTOCOL.md` 같은 자주 읽히는 루트 파일이 다시 monolith로 자라나면 커밋 단계에서 즉시 FAIL한다. pre-commit은 `-ReportLargeDocs`를 넘기지 않으므로 `Document/` 내부 대형 문서 리포트는 자동 강제가 아니라 수동 진단용 옵션이다.

운영 규칙 추가:

- `Document/dialogue/DECISIONS.md`를 바꿀 때는 `main`/`master`가 아닌 작업 브랜치에서 수정하고 PR로 병합한다.
- `Validate-DadDecisionWorkflow.ps1`은 `DECISIONS.md`가 바뀐 상태에서 현재 브랜치가 `main`/`master`이면 FAIL한다.

활성화:

```powershell
git config core.hooksPath .githooks
```

---

## 2. Peer Prompt 규칙

모든 peer prompt는 아래 7개 요소를 포함해야 한다.

1. 상대 계약 파일 읽기 지시 — **PROJECT-RULES.md를 먼저 언급**하고, 그 다음 상대 에이전트의 계약 파일, 그리고 루트 프로토콜. 루트 프로토콜이 `Document/DAD/` 참조를 가리키면 필요한 파일을 거기서도 읽도록 명시한다.
   - Codex에게 넘길 때: `Read PROJECT-RULES.md first. Then read AGENTS.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
   - Claude Code에게 넘길 때: `Read PROJECT-RULES.md first. Then read CLAUDE.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
2. 세션 상태 참조: `Session: Document/dialogue/state.json`
3. 이전 턴 패킷 참조: `Previous turn: Document/dialogue/sessions/{session-id}/turn-{N}.yaml`
4. 구체적 작업 지시 (`handoff.next_task + handoff.context`)
5. 10줄 안팎의 relay-friendly 요약
6. 아래 필수 꼬리말 3줄
7. `handoff.prompt_artifact`에 저장된 동일한 프롬프트 본문. 기본 경로는 `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md`

### 필수 꼬리말

```
---
허점이나 개선점이 있으면 직접 수정하고 diff를 보고하라.
수정할 것이 없으면 "변경 불필요, PASS"라고 명시하라.
중요: 관대하게 평가하지 마라. "좋아 보인다" 금지. 구체적 근거와 예시를 들어라.
```

꼬리말 없이 프롬프트를 출력하면 규칙 위반이다. 이 꼬리말은 인상평 방지와 매 턴 비판적 리뷰 강제를 위한 것이다.

### 하위 호환

기존 프롬프트가 아직 `If that file points to Document/DAD references, read the needed files there too.` 문장을 달고 있지 않더라도, 첫 3개 지시(읽기/세션/이전 턴) + 필수 꼬리말이 있으면 유효하다. 단, 새로 생성하는 peer prompt는 위 7개 요소를 모두 포함해야 한다.

과거 live session의 Turn Packet에는 `handoff.prompt_artifact`가 없을 수 있다. validator는 legacy packet을 위해 이 필드의 완전 부재는 허용하지만, 새 skeleton이 포함하는 `prompt_artifact` 필드가 존재할 때 `ready_for_peer_verification: true`와 함께 비어 있으면 FAIL한다.

---

## 3. Debate 절차

한쪽이 PASS, 다른 쪽이 FAIL일 때:

```
Round 1: 각자 입장 + 근거 제시 (코드, 테스트, 문서 인용)
Round 2: 상대 근거에 대한 반론 또는 수용
Round 3: 합의 시도 → 합의 실패 시 → 사용자에게 ESCALATE
```

- 부분 합의는 유효하다. 합의된 체크포인트는 PASS, 미합의만 ESCALATE.
- Debate는 Turn Packet의 `peer_review`에서 자연스럽게 발생한다.

---

## 4. 사용자 개입 지점

| 시점 | 트리거 | 사용자 옵션 |
|------|--------|-------------|
| 세션 시작 | `/dialogue-start` | 작업 방향, scope, 모드 선택 |
| Contract 확인 | large scope Turn 1 | 체크포인트 승인/수정/추가 |
| 턴 중계 | 매 턴 끝 | 프롬프트 전달 + 자기 의견 추가 가능 |
| 의견 교착 | Debate 3라운드 후 합의 실패 | 한쪽 선택, 제3의 방향, 보류 |
| 수렴 확인 | 양쪽 done (선택적) | 승인, 추가 요청, 거부 |
| Meta 변경 | Meta Packet의 프롬프트 개선 | 승인, 수정, 거부 |
| 언제든 | 사용자 자발적 개입 | 방향 전환, 중단, 새 작업 지시 |

### 자율/감독/하이브리드

- **자율**: 턴 중계만. ESCALATE만 사용자에게.
- **감독**: 모든 수렴에 사용자 확인. Contract도 확인.
- **하이브리드** (기본): large scope 또는 confidence low일 때만 확인.

사용자 브리지 절차: Agent A 작업 → 프롬프트 출력 → 사용자가 Agent B에 붙여넣기 → 반복. 자기 의견은 프롬프트 뒤에 `사용자 메모:`로 추가한다. **자율 모드라도 relay 단계는 사라지지 않는다.** 판단 자동화일 뿐이다.

운영 메모:

- 사람이 세션 운영 방향을 남길 때는 `Document/dialogue/DECISIONS.md`를 기본 입력면으로 사용한다.
- `state.json` 직접 편집은 예외 복구를 제외하면 기본 경로가 아니다.

---

## 5. 무한루프 방지 (Safety Rails)

1. **하드 턴 제한**: scope별 최대 턴 초과 시 강제 ESCALATE
2. **품질 정체 감지**: 2턴 연속 동일 체크포인트 FAIL → 사용자 ESCALATE
3. **Debate 제한**: 최대 3라운드 후 강제 ESCALATE
4. **연속 실패 제한**: 3턴 연속 같은 체크포인트 FAIL → 자동 ESCALATE
5. **scope 비례**: small 작업에 3턴 이상은 비효율 경고

---

## 6. .prompts/ 통합

`.prompts/` 파일은 **작업 유형별 체크리스트와 절차**다. Contract 작성 시 참조한다.

| 작업 유형 | 기본 참조 프롬프트 |
|-----------|--------------------|
| Contract 체크포인트 작성 | `03-도메인-감사-체크리스트.md` |
| 품질 평가 기준 | `06-품질-일관성-보강.md` |
| 기획 검증 | `07-기획-검증-수정.md` |
| 플레이테스트 | `08-플레이테스트-절차.md` |
| 비상 세션 복구 | `09-비상-세션-복구.md` |
| 시스템 문서 정합성 동기화 | `10-시스템-문서-정합성-동기화.md` |
| DAD 시스템 운영 감사 | `11-DAD-시스템-운영-감사.md` |

Contract에 `reference_prompts` 필드로 어떤 프롬프트를 참조했는지 기록한다.

- 시스템 문서/프로토콜/validator 변경 시에는 `10-`을 기본 참조에 포함한다.
- DAD 시스템 자체 감사를 할 때는 `11-`을 기본 참조에 포함하고, 수정이 동반되면 `10-`을 함께 묶는다.
- 시스템 문서 drift를 같은 턴에서 닫지 못했다면, `handoff.next_task`의 첫 항목은 반드시 그 drift를 닫는 동기화 작업이어야 한다.

전체 목록과 사용 규칙은 `../../.prompts/README.md`를 본다.

---

## 7. Meta 프롬프트 진화

Turn 흐름과 독립적. **반복 패턴이 최소 2회 이상 관찰**되고 summary 메모로는 재발 방지가 안 된다고 판단될 때만 발동한다.

흐름:

1. 에이전트가 반복 패턴(같은 유형의 버그, 비효율)을 관찰
2. Meta Packet 작성 → 상대에게 전달
3. 상대가 수용/거부/수정
4. 수용 시 → `AGENTS.md` 또는 `CLAUDE.md`에 반영
5. 구조적 변경은 사용자 승인 필요

---

## 8. 큰 참조 문서 읽기 규칙

- 필요한 참조 문서가 한 번에 읽기엔 너무 크면, 먼저 section index를 보고 필요한 부분만 chunk 단위로 읽는다.
- monolithic read가 한 번 실패했다고 작업을 중단하지 않는다.
- fallback 문구를 계속 늘리기보다, 큰 참조 문서는 미리 분할하는 쪽을 우선한다. `Validate-Documents.ps1 -FailOnLargeDocs`가 이 invariant를 강제한다.

---

## 관련 파일

- `PACKET-SCHEMA.md` — 패킷 스키마와 필드 규칙
- `STATE-AND-LIFECYCLE.md` — state.json, 수렴/종료 규율, 복구
- `../../DIALOGUE-PROTOCOL.md` — 얇은 루트 계약 문서
- `../../.prompts/README.md` — 프롬프트 인덱스
- `../DAD 스킬 운영 가이드.md` — 운영 매뉴얼

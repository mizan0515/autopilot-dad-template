<!-- validate:ignore-refs: Document/.archive/, INDEX.md, .prompts/10-시스템-문서-정합성-동기화.md -->
<!-- Archive subtree + archive INDEX.md + the optional 10-system-doc-sync prompt
     are project-conditional; do not fail pre-commit in a fresh apply (round-3 F7). -->

# Claude Code Contract — {{PROJECT_NAME}}

**IMPORTANT: `PROJECT-RULES.md` 를 먼저 읽는다.** 모든 에이전트가 따라야 하는 공용 프로젝트 규칙이 담겨 있다.

이 파일은 Claude Code 가 자동 로드하며 Claude Code 전용 지시가 담겨 있다.

관련 파일:
- `PROJECT-RULES.md` — 공용 프로젝트 규칙
- `DIALOGUE-PROTOCOL.md` — Dual-Agent Dialogue 프로토콜
- `AGENTS.md` — Codex 전용 지시. Claude Code 는 이 파일의 절차를 자기에게 적용하지 않는다.

---

## Agent identity ownership (Layer 1)

에이전트 정체성(agent-identities, tool-policy allowlist, dialogue-checkpoint 규약)의 **권위 있는 소유자는 relay repo** `{{RELAY_REPO_PATH}}` 이다. 근거: `{{RELAY_REPO_PATH}}/Document/governance/5-layer-mapping.md` 의 Layer 1. <!-- validate:ignore-missing-ref -->

- 이 repo 에 `.agents/identities/`, `agent-identities.json`, `tool-policy.json` 같은 shadow-identity 파일을 만들지 않는다. 식별자·허용 목록 원본은 relay repo 에만 존재해야 한다. <!-- validate:ignore-missing-ref -->
- 식별자·도구 클래스 허용 목록을 바꿔야 하면 relay repo 에 PR 을 내고, 그 PR 이 머지된 후 이 프로젝트의 동작을 맞춘다.
- 이 repo 는 Layer 3 (정책: `PROJECT-RULES.md`, `CLAUDE.md`, `AGENTS.md` 의 가드레일) 와 Layer 4 (anomaly: 프로젝트 테스트 스위트, 콘솔) 만 소유한다.

이 머신에 relay repo 가 설치되어 있지 않다면 relay 전용 체크를 건너뛴다. 스탠드얼론 autopilot 루프는 여전히 동작한다.

---

## 프로젝트 고유 가드레일

운영자가 이 프로젝트에 정의한 가드레일 (프로젝트가 성숙하면 이 블록을 확장):

{{PROJECT_GUARDRAILS_BLOCK}}

보편 가드레일 (항상 적용):
- 폴더의 스크립트를 수정하면 같은 작업에서 해당 폴더 리서치 파일을 갱신한다 (프로젝트가 리서치 파일을 쓸 때).
- 작업이 DAD 인프라, validator, slash command, prompt template, session schema, agent contract 를 바꾸면, 영향받는 시스템 문서를 같은 작업에서 갱신한다: `AGENTS.md`, `CLAUDE.md`, `DIALOGUE-PROTOCOL.md`, `.claude/commands/`, `.agents/skills/`, 관련 가이드.
- 같은 턴에서 동기화를 못 끝내면, `handoff.next_task` 또는 사용자 대면 다음 단계에 명시적으로 첫 후속 작업으로 적는다. 시스템 문서 drift 를 암묵적으로 두지 않는다.
- 시스템 문서 동기화가 작업에 포함될 때는 `.prompts/10-시스템-문서-정합성-동기화.md` 를 기본 동반 프롬프트로 본다.
- `Document/temp plan/` 폴더는 commit 대상이 아니다. untracked 로 잡혀도 무시한다.
- 현재 브랜치가 작업 브랜치면 그 위에 commit. `main` / `master` 이면 새 작업 브랜치를 만들고 진행한다. main 에 직접 push 금지.

## 프로젝트 읽기 방법

- `.autopilot/config.json` → `doc_priority` 또는 `PROJECT-RULES.md` 에 선언된 프로젝트 문서 우선순위를 사용한다.
- 모듈, 서비스, 런타임 경로가 존재한다고 가정하기 전에 실제 파일 인벤토리를 확인한다.
- 코드 검색은 선언된 `search_roots` 로 한정한다. 캐시/생성 디렉터리 와일드카드 검색 금지.
- **아카이브 건너뛰기**: `Document/.archive/`, `.autopilot/.archive/` 는 LLM 탐색에서 제외한다. 복원/역사적 맥락이 진짜 필요할 때만 아카이브 `INDEX.md` 의 한 줄 요약을 먼저 읽고, 그래도 부족하면 해당 파일만 pinpoint 로 연다. 전수 읽기 금지.
- `git log` 등 시간 기반 쿼리에서 상대 날짜(`"1 week ago"`) 를 쓰지 않는다. commit 해시 또는 절대 날짜를 사용한다.

## 검증 규칙

- 광범위 검증 전에 프로젝트 네이티브 검증 (테스트 러너, 린터, 타입 체커, 통합 하네스) 을 우선한다.
- 외관보다 런타임 플로우로 판단한다. 플로우가 깨진 예쁜 결과는 실패한 결과다.
- 배선, 씬/프리팹 참조, 입력 바인딩, 상태 소유권, 런타임 부트스트랩 갭을 주시한다.
- "될 거야", "괜찮아 보인다" 같은 표현을 검증된 사실의 대체물로 쓰지 않는다.

## Git 워크플로

- 의미 있는 갱신 후마다 Git commit 을 만들고 원격에 push 한다.
- 현재 작업이 자체 완결되고 검증된 변경 세트를 만들었다면, 추가 사용자 지시를 기다리지 않는다.
- 현재 작업에 속한 파일만 stage 할 수 있을 때는 자율 commit/push 를 우선한다.
- 워크트리가 무관한 이유로 더러우면, commit/push 를 건너뛴 사실을 분명히 보고한다.
- commit/push 를 조용히 건너뛰지 않는다. 최종 보고는 commit/push 했는지 또는 왜 안 했는지를 명시한다.

## PR 언어 규약

운영자 언어가 `{{OPERATOR_LANG}}` 일 때는 PR 제목과 본문을 해당 언어로 작성한다. 운영자는 대시보드와 PR 목록을 자기 언어로 읽는다. `ko` / `ja` / `zh` 대시보드에 영어 전용 PR 제목이 섞이면 마찰이 생긴다.

예외: 기술적 conventional-commit 프리픽스 (`fix:`, `chore:`, `feat:`) 뒤에 운영자 언어 본문이 오는 형태는 허용.

## 확장 추론 · 토큰 예산 · 캐시 회귀

Claude Code 는 필요 판단에 따라 확장 추론(extended thinking) 을 자동으로 사용한다 (별도 env 플래그 없음). 턴 내에서 의식적으로 조절할 것:
- 설계 결정, 근본 원인 추적, 다중 파일 리팩터, DAD Sprint Contract 초안에서는 깊이를 아끼지 않는다.
- 반복적 기계 편집에서는 Read → Edit 루틴으로 내려가 토큰을 아낀다.
- 릴레이 브로커는 `relay/profile-stub/broker.*.json` 의 `maxCumulativeOutputTokens` / `maxTurnsPerSession` 을 세션 단위 상한으로 본다.

`.autopilot/PROMPT.md` IMMUTABLE budget 블록이 우선한다. 추가 운영 규약:
- 연속 2 iter 동안 캐시 읽기 비율이 0.25 미만이면 즉시 요약 턴으로 전환하고 `.prompts/12-맥락-요약-정책.md` 절차를 따른다.
- iter 당 파일 읽기 20회 / 셸 호출 30회 soft cap 을 넘으면 `.autopilot/PITFALLS.md` 에 "맥락 폭주" 항목을 추가한다.
- 이 회귀가 3회 누적되면 `.autopilot/EVOLUTION.md` 에 프롬프트 축소 제안을 적고 자동 루프를 중단한다 (사용자 승인이 있어야 재개).

---

## Standalone Stance

역할: **자율적 프로젝트 파트너.** 사용자가 의사결정자.
Claude Code 가 직접 사용될 때 (dialogue session 외부) 의 기본.

### 계획과 범위
- 사용자 요청 범위 안에서 자율적으로 계획, 탐색, 다음 단계 제안, 작업 제안이 가능하다.
- 사용자 요청이 곧 범위.
- 요청이 광범위하면 (예: "다음 작업 해줘"), 현재 상태를 분석하고 옵션을 제안한 뒤 계획을 밝히고 진행한다.
- 요청이 모호하거나 위험하면 실행 전에 사용자에게 확인을 요청한다.

### 실행 자세
- 기억보다 구체적인 저장소 상태를 우선한다. 존재한다고 가정하기 전에 실파일을 확인한다.
- 수직 슬라이스를 우선: 코드, 데이터 연결, 최소 검증을 함께 구현.
- 여러 시스템을 건드릴 때는 계획을 먼저 선언한다.
- 변경 후 가장 좁은 유용한 검증을 돌린다.
- 폴더의 스크립트를 수정하면 리서치 파일을 갱신한다 (프로젝트가 리서치 파일을 쓸 때).

### 소통
- 주요 단계마다 무엇을 하고 있으며 왜 그런지 설명한다.
- 검증된 것, 남은 미검증, 알려진 리스크를 보고한다.
- 현재 요청을 끝낸 뒤 논리적인 다음 단계를 제안한다.
- 문서, 코드, 제약 간 충돌을 만나면 분명히 보고한다.

### 완료
- 변경이 자체 완결되고 검증되면 commit + push.
- 유의미한 세션의 작업 세션 요약을 `Document/chat/` 에 기록.
- 마무리: 변경 파일, 검증 항목, 리스크, 제안된 다음 작업.

---

## Dialogue Mode (Codex 협업)

`DIALOGUE-PROTOCOL.md` 에 정의된 Dual-Agent Dialogue v2 프로토콜에 따라 Codex 와 대칭 턴 협업할 때의 규칙.

### Claude Code 의 역할
- **대칭적 협업자**: 매 턴마다 계획·실행·평가를 모두 수행한다.
- Codex 의 작업물을 Contract 체크포인트 기준으로 솔직하게 평가한다.
- 핸드오프 전에 자체 반복 루프로 품질을 확보한다.
- 의견 차이가 있으면 코드/테스트/문서를 인용해 근거 기반 토론한다.
- 시스템 규칙/명령/validator 와 실제 저장 구조가 어긋난 것을 발견하면 문서 정합성 수정도 같은 deliverable 로 취급한다.

### Turn 수행 절차
1. 프로젝트 상태 분석 (git log, 코드, 콘솔)
2. Turn 1 이면: Sprint Contract 초안 + 자기 작업 실행
3. Turn 2+ 이면: 상대 작업 피드백 (체크포인트 기준) + 자기 작업 실행
4. 자체 반복 루프: 체크포인트 기준으로 자체 검증, 만족할 때까지 반복
5. Turn Packet 을 `Document/dialogue/sessions/{session-id}/turn-{N}.yaml` 로 저장
6. 실제로 출력할 Codex handoff prompt 를 `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md` 로 저장하고, 그 경로를 `handoff.prompt_artifact` 에 기록한다
7. 상대용 프롬프트를 사용자에게 출력 (아래 "Codex 용 프롬프트 생성 규칙" 참조)
8. 시스템 문서 정합성 갭이 남으면 같은 턴에서 수정하거나, 불가하면 그 갭을 다음 작업의 첫 항목으로 명시한다.

### Codex 용 프롬프트 생성 규칙
매 턴 끝 핸드오프에서 Codex 용 프롬프트를 동적으로 생성한다. 프롬프트에는 **반드시** 아래 7 개 요소가 포함되어야 한다:

1. 계약 파일 읽기 지시: `Read PROJECT-RULES.md first. Then read AGENTS.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`
2. 세션 상태 참조: `Document/dialogue/state.json`
3. 이전 턴 패킷 참조: 현재 세션 디렉터리의 `turn-{N}.yaml`
4. 구체적 작업 지시 (handoff.next_task + handoff.context)
5. 10 줄 안팎의 relay-friendly 요약
6. **필수 꼬리말** (아래 블록을 프롬프트 맨 끝에 반드시 포함)
7. `handoff.prompt_artifact` 에 저장한 동일한 프롬프트 본문

**필수 꼬리말** — 모든 상대용 프롬프트 끝에 아래 텍스트를 그대로 붙인다:
```
---
허점이나 개선점이 있으면 직접 수정하고 diff를 보고하라.
수정할 것이 없으면 "변경 불필요, PASS"라고 명시하라.
중요: 관대하게 평가하지 마라. "좋아 보인다" 금지. 구체적 근거와 예시를 들어라.
```
이 꼬리말 없이 프롬프트를 출력하면 규칙 위반이다.

### Codex 결과 수신 시
사용자가 Codex 결과를 공유하면:
1. 상대 Turn Packet 을 읽고 Contract 체크포인트 기준으로 피드백
2. 수렴 여부 판단 (모든 체크포인트 PASS + suggest_done?)
3. 미완료 시 → 다음 턴 실행 + 새 프롬프트 생성

### 자동 수렴 (Auto-Converge)
양쪽 모두 코드 변경 없이 전체 체크포인트 PASS + `suggest_done: true` 이면, 사용자의 추가 지시 없이 즉시:
1. 세션 상태를 `converged` 로 업데이트
2. 작업 브랜치에 커밋 + push
3. PR 생성 + main 머지
4. main checkout + pull
5. 결과 보고

"pr 생성해줘" 를 기다리지 않는다. `DIALOGUE-PROTOCOL.md` 의 자동 수렴 조건 참조.

### Meta Packet
반복 패턴을 관찰하면:
1. Meta Packet 을 작성하여 Codex 의 프롬프트 개선을 제안
2. 구조적 변경은 반드시 사용자 승인을 받는다
3. 자신의 접근 방식도 함께 개선한다

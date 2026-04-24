# DAD 상태와 세션 라이프사이클

공유 상태, 세션 디렉터리 레이아웃, session_status 전이, 종료 규율, 복구 절차는 이 파일을 기준으로 본다. 루트 `DIALOGUE-PROTOCOL.md`는 요약만 가진다.

---

## 1. 공유 상태

### 상태 파일

- 루트: `Document/dialogue/state.json` — 현재 활성 세션만 추적한다.
- 세션 스냅샷: `Document/dialogue/sessions/{session-id}/state.json` — 각 세션의 독립 스냅샷.

새 세션이 생성되면 루트 state는 덮어쓴다. 이전 세션 상태는 `sessions/{session-id}/state.json`에 남기고, 필요하면 `session_status`를 `superseded`로 바꾼다.

### 세션별 예상 산출물

- `turn-{N}.yaml`
- 턴 종료 시 실제로 출력한 peer prompt를 저장한 `turn-{N}-handoff.md`
- `state.json`
- 세션 범위 summary인 `summary.md`
- 닫힌 세션용 named summary인 `YYYY-MM-DD-{session-id}-summary.md` (루트 `Document/dialogue/sessions/` 또는 세션 디렉터리 안)

### 운영 선호 규칙

- 목표, 검증 표면, 작업 소유 범위가 크게 바뀌면 하나의 긴 umbrella session보다 짧은 session-scoped slice를 우선한다.
- 새 세션이 현재 세션을 대체하면 이전 세션을 `superseded` 또는 다른 종료 상태로 명시적으로 닫는다.
- 닫힌 세션도 `summary.md`와 named closed-session summary를 남긴다.
- 과거 세션에 `turn-{N}-handoff.md`가 없더라도 역사 보존을 위해 즉시 무효 처리하지 않는다. 새로 생성하거나 수정하는 턴부터는 handoff prompt artifact를 함께 남긴다.

---

## 2. state.json 스키마

`state.json`(루트·세션 공용)은 아래 필드를 포함한다.

| Field | Required | Values |
|-------|----------|--------|
| `protocol_version` | always | `"dad-v2"` |
| `session_id` | always | string |
| `session_status` | always | `active` / `converged` / `superseded` / `abandoned` |
| `relay_mode` | always | `"user-bridged"` |
| `mode` | always | `autonomous` / `hybrid` / `supervised` |
| `scope` | always | `small` / `medium` / `large` |
| `current_turn` | always | integer (0 before first turn) |
| `max_turns` | always | integer |
| `last_agent` | after first turn | `codex` / `claude-code` |
| `contract_status` | always | `proposed` / `accepted` / `amended` |
| `contract_checkpoints` | optional | `{ C1: PASS, ... }` |
| `packets` | always | session-scoped `turn-{N}.yaml` 상대경로 배열 |
| `decisions` | optional | 사용자가 내린 결정 기록 |
| `meta_improvements` | optional | 적용된 프롬프트 개선 사항 |
| `closed_reason` | when status != `active` | string |
| `superseded_by` | when status == `superseded` | session-id string |

### 저장 경로 규칙

- `packets`는 session-scoped `turn-{N}.yaml` 경로만 authoritative하게 가리켜야 한다.
- 레거시 `Document/dialogue/packets/` 경로는 마이그레이션 입력으로만 취급한다. 새 v2 세션의 활성 저장 경로로 쓰지 않는다.
- validator/migration 도구는 레거시 `packets/`를 읽을 수 있지만, 새 산출물은 session-scoped 경로에만 저장한다.

---

## 3. 수렴 규칙

### 정상 수렴

1. 양쪽 모두 모든 체크포인트 PASS 판정
2. 양쪽 모두 `suggest_done: true`
3. → 작업 브랜치에 커밋 + push → PR 생성 → main 머지

**main 직접 push 금지.** 수렴 커밋도 작업 브랜치에서 수행한다. 세션 시작 시 main 위에 있으면 새 브랜치를 만든 뒤 진행한다.

### 자동 수렴 (Auto-Converge)

**양쪽 모두 "전체 PASS — 변경 불필요"일 때 자동으로 PR 생성 + main 머지.**

조건: 마지막 코드 수정 턴 이후, 상대가 모든 체크포인트를 PASS 판정하고 코드 변경 없이 `suggest_done: true`를 기록했으며, 그 이전 턴 역시 변경 불필요 PASS였을 때.

구체적으로:

1. Agent A가 Turn N에서 구현 + 자체 검증 후 `suggest_done: false`로 핸드오프
2. Agent B가 Turn N+1에서 **코드 변경 없이** 모든 체크포인트 PASS → `suggest_done: true`
3. Agent A가 Turn N+2에서 **코드 변경 없이** 모든 체크포인트 PASS → `suggest_done: true`
4. **또는** Agent A가 Turn N에서 이미 `suggest_done: true`이고, Agent B가 Turn N+1에서 코드 변경 없이 전체 PASS + `suggest_done: true`

위 조건이 충족되면 **마지막 턴을 수행한 에이전트가 사용자의 추가 지시 없이 즉시**:

1. 세션 상태를 `converged`로 업데이트
2. 작업 브랜치에 커밋 + push
3. PR 생성
4. main에 머지
5. main checkout + pull

### 의견 차이 시 (Debate)

한쪽이 PASS, 다른 쪽이 FAIL일 때의 절차는 `VALIDATION-AND-PROMPTS.md`의 Debate 섹션을 본다. 부분 합의는 유효하며, 합의 실패는 사용자에게 ESCALATE.

### Done Gate

`suggest_done: true`는 아래 조건을 모두 만족할 때만 사용한다.

1. 최신 코드 수정 턴 이후 상대 에이전트가 모든 checkpoint를 다시 PASS 판정
2. 각 PASS에 재현 가능한 `evidence`가 포함됨
3. 판정형 checkpoint는 필요한 `disconfirmation` 근거를 포함함
4. `open_risks`가 비어 있거나 사용자 승인으로 명시적으로 수용됨
5. 최신 `state.json`과 Turn Packet이 validator를 통과함

### small scope 수렴

Contract 없이 진행. 한쪽이 실행하면 상대가 리뷰하고 PASS/FAIL. 1~2턴에 수렴.

---

## 4. 세션 종료 규율

세션을 닫을 때는 아래 중 하나를 반드시 선택한다.

- `converged` — 양쪽 done gate 충족
- `superseded` — 새 세션이 같은 작업 흐름을 더 정확히 대체
- `abandoned` — 중단/포기/외부 blocker/범위 재정의로 종료

종료 턴에 함께 남기는 3가지:

1. 루트 `Document/dialogue/state.json`과 세션 `state.json`의 `session_status`, `closed_reason`, 필요 시 `superseded_by`
2. 종료 Turn Packet
3. 세션 범위 `summary.md` + 필요 시 named closed-session summary

---

## 5. v1 아티팩트와 마이그레이션

v1 세션 흔적(`round-*-proposal.yaml` 등)은 **참고용 아카이브**다. v2는 이어붙이지 않고 새 `turn-{N}.yaml` 시리즈를 만든다.

- `state.json`이 v1 스키마면 재초기화한다.
- v1 금지어는 `tools/Lint-StaleTerms.ps1`로 자동 검출한다.
- 경로 이관은 `tools/Migrate-DadSession.ps1`을 쓴다. 비표준 packet filename(`turn-01-suffix.yaml` 등)도 이 도구로 canonical `turn-{N}.yaml`로 정규화한다.

---

## 6. 세션 중단 및 복구

### 컨텍스트 오버플로

에이전트의 컨텍스트 창이 세션 도중 가득 차면:

1. 현재 작업을 partial turn packet으로 저장한다.
2. `confidence: low`와 `open_risks`에 오버플로 사실을 남긴다.
3. 새 컨텍스트를 열고 복구 절차로 안전하게 재개한다.

### 복구 절차

1. `state.json`으로 마지막 turn/agent 확인 → 2. 마지막 packet 확인 → 3. 상대 턴부터 재개
- `superseded`/`abandoned`면 새 세션으로 시작한다.
- 복구 전 `tools/Validate-DadPacket.ps1`을 실행한다.
- 정상 복구가 불가능하면 `.prompts/09-비상-세션-복구.md` 절차를 적용한다.

---

## 관련 파일

- `PACKET-SCHEMA.md` — Turn/Contract/Meta 패킷 세부
- `VALIDATION-AND-PROMPTS.md` — validator 실행 시점과 peer prompt 규칙
- `../../DIALOGUE-PROTOCOL.md` — 얇은 루트 계약 문서
- `../DAD 스킬 운영 가이드.md` — 운영 매뉴얼(스킬/커맨드/훅)

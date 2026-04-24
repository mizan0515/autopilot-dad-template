# DAD 패킷 스키마

DAD v2 패킷(Contract / Turn / Meta)의 전체 형식과 필드 규칙은 이 파일을 기준으로 본다. 루트 `DIALOGUE-PROTOCOL.md`는 요약만 가진다.

---

## 1. Contract Packet

Turn 1 패킷에 포함되거나, large scope에서 별도로 사용자에게 확인 요청 시 사용.

```yaml
type: contract
task: "한줄 요약"
scope: "small | medium | large"
checkpoints:
  - id: C1
    description: "무엇이 달라져야 하는가"
    verification: "어떻게 검증하는가"
  - id: C2
    description: "..."
    verification: "..."
done_when: "모든 체크포인트 PASS"
reference_prompts: [".prompts/04-버그수정.md"]   # 선택적
```

### Contract 규모 (scope 적응)

| scope | 체크포인트 수 | 최대 턴 | Contract | task_model |
|-------|--------------|---------|----------|------------|
| small | 0 (생략) | 2 | 없음 — 직접 실행 후 리뷰만 | 없음 |
| medium | 3~5 | 5 | Turn 1에 포함 | 선택적 |
| large | 6+ | 10 | Turn 1에 포함 + 사용자 확인 | 필수 |

### task_model (planner-lite)

large scope에서는 Turn 1 Contract 초안 **전에** 목표를 구조화한다. 짧은 요청을 그대로 체크포인트로 바꾸면 under-scoping이 발생하기 쉽다.

```yaml
task_model:
  user_goal: "사용자가 원하는 최종 상태 한줄"
  out_of_scope:
    - "이번 작업에서 하지 않는 것"
  success_shape:
    - "완료 시 어떤 결과물이 존재하는가"
  major_risks:
    - "실패하거나 복잡해질 수 있는 지점"
```

- large scope Turn 1에서 `my_work.task_model`에 포함한다.
- medium scope에서는 아래 중 하나라도 해당하면 사용을 권장한다:
  - 사용자 요청이 짧거나 모호해서 성공 기준이 바로 체크포인트로 내려오지 않을 때
  - 코드 외에도 문서/도구/검증 산출물이 함께 필요한 작업일 때
  - 두 개 이상 서브시스템 또는 두 종류 이상 deliverable이 걸린 작업일 때
  - 감사/리뷰/리서치처럼 "무엇을 끝냈는가"가 구현 diff만으로 닫히지 않을 때
- Contract를 만들 때의 매핑 규칙:
  - `success_shape`의 각 항목은 적어도 하나의 checkpoint로 이어져야 한다.
  - `major_risks`의 각 항목은 mitigation checkpoint 또는 `open_risks` 추적으로 이어져야 한다.
  - `out_of_scope` 항목은 checkpoint에 다시 등장하면 안 된다. 필요하면 Turn 2에서 amended 처리한다.
- Turn 2 에이전트는 task_model을 검토하고 Contract 수용/수정 시 반영한다:
  - checkpoint가 `success_shape`를 충분히 덮는지 확인
  - task 범위가 `out_of_scope`를 침범했는지 확인
  - `major_risks`가 Contract나 handoff에 반영되었는지 확인
  - 필요하면 task_model 자체를 `amended` 또는 `superseded`로 선언

---

## 2. Turn Packet

매 턴마다 생성. 상대 피드백 + 내 작업 + 핸드오프를 하나로 통합. 저장 경로는 `Document/dialogue/sessions/{session-id}/turn-{N}.yaml`이며, 파일명의 `{N}`은 내부 `turn:` 값과 일치해야 한다.

```yaml
type: turn
from: [codex | claude-code]
turn: 1
session_id: "2026-04-12-001"

# Sprint Contract (Turn 1에서 초안, Turn 2에서 수용/수정)
contract:
  status: "proposed | accepted | amended"
  checkpoints: [...]   # Contract Packet 형식
  amendments: []       # 수정 시 변경 사항

# 상대 작업 피드백 (Turn 1에서는 project_analysis로 대체)
peer_review:
  # Turn 1일 때:
  project_analysis: "프로젝트 현재 상태 분석"
  # Turn 2+ 일 때:
  task_model_review:
    status: "aligned | amended | superseded"
    coverage_gaps: ["success_shape 누락 또는 under-scope"]
    scope_creep: ["out_of_scope 침범"]
    risk_followups: ["major_risks 후속 조치"]
    amendments: ["task_model 수정 사항"]
  checkpoint_results:
    C1:
      status: "PASS | FAIL | FAIL-then-FIXED | FAIL-then-PASS"
      note: "구체적 근거"
      evidence:
        independent: ["내가 이번 턴에 직접 재실행/재확인한 근거"]
        inherited: ["상대 이전 턴에서 받아들인 근거"]
      disconfirmation:
        attempted: true
        method: "반례 탐색 방법"
        result: "남은 반례가 없다고 본 이유"
    C2:
      status: "PASS | FAIL | FAIL-then-FIXED | FAIL-then-PASS"
      note: "..."
      evidence:
        independent: ["..."]
        inherited: ["..."]
  issues_found: ["발견된 문제"]
  fixes_applied: ["내가 직접 수정한 것"]

# 내 작업
my_work:
  task_model: {}   # large scope Turn 1에서 필수. medium scope는 위 기준 충족 시 사용
  plan: "이번 턴에 무엇을 했고 왜"
  changes:
    files_modified: ["파일 목록"]
    files_created: ["파일 목록"]
    summary: "변경 요약"
  self_iterations: 3
  evidence:
    commands: ["실행한 명령"]
    artifacts: ["생성/확인한 로그, 테스트 결과, 스크린샷 경로"]
  verification: "자체 검증 결과 (테스트, 콘솔 등)"
  open_risks: ["아직 닫히지 않은 위험"]
  confidence: "high | medium | low"

# 핸드오프
handoff:
  next_task: "상대가 이어서 할 작업 제안"
  context: "상대가 알아야 할 맥락"
  questions: ["상대에게 묻는 질문"]
  prompt_artifact: "Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md"
  ready_for_peer_verification: false
  suggest_done: false        # true면 수렴 제안
  done_reason: "수렴 제안 근거. suggest_done=true일 때 필수"
```

### Turn Packet 필드 규칙

- `my_work`는 필수 필드다. `self_work` 같은 별칭은 금지한다.
- `suggest_done`과 `done_reason`은 `handoff` 안에만 둔다. 루트 레벨 필드는 금지한다.
- 새로 생성하는 Turn Packet에서 `handoff.ready_for_peer_verification: true`를 올리기 전에는 `handoff.next_task`, `handoff.context`, `handoff.prompt_artifact`를 모두 채워야 한다.
- `handoff.prompt_artifact`는 해당 턴에서 실제로 출력한 peer prompt 본문을 가리켜야 하며, 기본 경로는 `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md`다.
- `suggest_done: true`면 `done_reason`이 필수다.
- `disconfirmation`은 모든 checkpoint에 강제되지 않는다. 단, 정합성·일관성·문서-코드 alignment·UX 밀도 같은 판정형 checkpoint에는 기본으로 포함한다.
- `evidence.independent`는 내가 이번 턴에 직접 재검증한 근거다. `evidence.inherited`는 상대의 이전 근거를 읽고 수용한 흔적이다.
- 파일명 `turn-{N}.yaml`의 `{N}`은 내부 `turn:` 값과 일치해야 한다. 비표준 이름(예: `turn-01-suffix.yaml`)은 `tools/Validate-DadPacket.ps1`가 FAIL로 처리하며, `tools/Migrate-DadSession.ps1`로 정규화한다.
- 기존 live 세션의 과거 Turn Packet에는 `handoff.prompt_artifact`가 없을 수 있다. 새로 만드는 턴부터는 필드를 유지하고, legacy packet은 점진적으로 보강한다.

---

## 3. Meta Packet (프롬프트 개선용)

Turn 흐름과 독립적. **같은 실패 패턴이 최소 2회 이상 반복되고**, summary 수준 메모로는 재발 방지가 안 된다고 판단될 때만 발동한다.

```yaml
type: meta
from: [codex | claude-code]
observation: "반복 패턴 관찰"
pattern: "어떤 종류의 실수/비효율이 반복되는가"
prompt_improvement: "상대의 프롬프트에 추가/수정 제안"
self_improvement: "자신의 접근 방식 개선 사항"
```

구조적 변경은 사용자 승인을 받는다. 수용 시 `AGENTS.md` 또는 `CLAUDE.md`에 반영한다.

---

## 관련 파일

- `STATE-AND-LIFECYCLE.md` — `state.json`과 session_status, 세션 종료 규율
- `VALIDATION-AND-PROMPTS.md` — packet/state 검증 명령과 peer prompt 형식
- `../../DIALOGUE-PROTOCOL.md` — 얇은 루트 계약 문서

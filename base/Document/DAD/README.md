# DAD 상세 참조 문서

`DIALOGUE-PROTOCOL.md`는 얇은 루트 계약 문서다. 상세 스키마·lifecycle·validation·프롬프트 규칙은 이 폴더로 분리한다.

## 왜 분리하는가

- 에이전트 하네스와 파일 읽기 도구는 큰 Markdown 파일에서 token/file-size 제한에 걸릴 수 있다.
- `DIALOGUE-PROTOCOL.md`는 매 턴 가장 먼저 읽히는 계약 문서이므로, 한 번에 읽을 수 있는 크기로 유지해야 한다.
- 스키마 표, validator 체크리스트, prompt reference 목록을 분리하면 drift가 생겨도 파일 단위로 관리하기 쉽다.
- 큰 문서가 한 번 읽기 실패했다고 작업이 멈추면 안 된다 — 그러나 이를 **chunked read fallback만으로 방어하기보다, 애초에 파일을 얇게 유지**하는 편이 비용과 재현성 양쪽에서 낫다.

## 유지보수 규칙

- 루트 계약 문서(`DIALOGUE-PROTOCOL.md`)는 얇고 authoritative하게 유지한다.
- 상세 스키마, lifecycle, validation 규칙은 이 폴더의 주제별 문서로 이동한다.
- 이 폴더의 상세 문서 중 하나가 다시 너무 커지면(12000자 이상 등) 또 주제별로 나누고, 다시 monolith로 키우지 않는다.
- `tools/Validate-Documents.ps1`는 `-ReportLargeRootGuides -FailOnLargeDocs`로 3종 루트 계약(`AGENTS.md`, `CLAUDE.md`, `DIALOGUE-PROTOCOL.md`)이 다시 monolith로 자라는 것을 강제로 차단한다. `Document/` 내부 대형 문서는 `-ReportLargeDocs`로 리포트만 받고(비강제) 필요 시 개별로 쪼갠다. 기본 threshold는 12000자다.
- pre-commit 훅(`.githooks/pre-commit`)은 위 flag를 포함해 실행되므로 이 invariant가 작업 흐름에서 자동으로 걸린다.

## 참조 맵

- [`PACKET-SCHEMA.md`](PACKET-SCHEMA.md) — Contract / Turn / Meta 패킷 전체 스키마와 필드 규칙, `task_model` 세부
- [`STATE-AND-LIFECYCLE.md`](STATE-AND-LIFECYCLE.md) — `state.json` 스키마, 세션 디렉터리 레이아웃, session_status 전이, 수렴/종료 규율, v1 아티팩트 처리, 복구 절차
- [`VALIDATION-AND-PROMPTS.md`](VALIDATION-AND-PROMPTS.md) — validator 실행 시점, Debate, peer prompt 전체 규칙, `.prompts/` 통합, Meta Packet, 사용자 브리지

## 루트와의 관계

루트 `DIALOGUE-PROTOCOL.md`는 이 폴더의 문서들을 **링크로만 참조**한다. 상세 규칙을 루트에 다시 복사하지 않는다. 루트와 상세 파일이 충돌하면 상세 파일(이 폴더)을 우선으로 보고 루트를 같은 작업에서 수정한다.

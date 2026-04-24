<!-- validate:ignore-refs: Document/.archive/harness-v1/, 00-공통-보충규칙.md, 01-정합성-감사수정.md, 02-전체-코드문서-감사.md, 03-도메인-감사-체크리스트.md, 04-버그수정.md, 05-데이터스키마-검증.md, 06-품질-일관성-보강.md, 07-기획-검증-수정.md, 08-플레이테스트-절차.md, 09-비상-세션-복구.md, 10-시스템-문서-정합성-동기화.md, 11-DAD-시스템-운영-감사.md -->
<!-- The numbered split-prompt files (00-...11-) are optional companion prompts
     a project may or may not author; ship a generic README that names them as
     possibilities without demanding their existence (round-3 F7). -->

# .prompts/ — Dual-Agent Dialogue v2 프롬프트

## 개요

이 폴더는 Codex와 Claude Code 간 **대칭 턴 협업 (DAD v2)** 시스템의 프롬프트를 포함한다.
모든 프롬프트는 **에이전트 중립** — Codex든 Claude Code든 동일하게 읽고 실행할 수 있다.

이 저장소의 프롬프트 팩은 `D:\dad-v2-system-template\ko`의 범용 DAD 템플릿에서 출발했지만,
현재 게임 저장소 운영에 맞춰 **프로젝트별 실행/감사 프롬프트로 의도적으로 diverge**했다.
즉 템플릿의 일반 세션 운영 프롬프트 일부는 여기서 게임 도메인용 00-08 시리즈로 대체되었고,
시스템 운영용 10-11만 공통 기반을 유지한다.

### 시스템 파일 (루트)
- `DIALOGUE-PROTOCOL.md` — v2 대칭 턴 프로토콜 thin-root 계약. 상세 스키마/수렴/validator 규칙은 `Document/DAD/`의 주제별 문서에 있다 (`Document/DAD/PACKET-SCHEMA.md`, `Document/DAD/STATE-AND-LIFECYCLE.md`, `Document/DAD/VALIDATION-AND-PROMPTS.md`).
- `AGENTS.md` — Codex 계약
- `CLAUDE.md` — Claude Code 계약
- `PROJECT-RULES.md` — 공유 프로젝트 규칙

### 이전 시스템 아카이브
- `Document/.archive/harness-v1/` — v1 하네스 전체 백업

---

## 프롬프트 목록

| 번호 | 파일 | 용도 | 분류 |
|------|------|------|------|
| 00 | `00-공통-보충규칙.md` | PROJECT-RULES.md 보충 규칙, 수치 참조, AI 빈번 실수 패턴 | 참조 |
| 01 | `01-정합성-감사수정.md` | 기획-구현 정합성 감사 및 수정 | 감사 |
| 02 | `02-전체-코드문서-감사.md` | 8개 도메인 전체 코드/문서 감사 | 감사 |
| 03 | `03-도메인-감사-체크리스트.md` | 도메인별 체크포인트 참조표 | 참조 |
| 04 | `04-버그수정.md` | 버그 재현/추적/수정/검증 절차 | 실행 |
| 05 | `05-데이터스키마-검증.md` | 데이터 자산/스키마 검증 | 감사 |
| 06 | `06-품질-일관성-보강.md` | 네이밍/용어/수치 일관성 보강 | 품질 |
| 07 | `07-기획-검증-수정.md` | 게임 기획 논리/재미 검증 | 기획 |
| 08 | `08-플레이테스트-절차.md` | Play 모드 QA 절차 (Slice 3 상세) | QA |
| 09 | `09-비상-세션-복구.md` | DAD 세션/state.json 비상 복구 및 force-close 절차 | 시스템 |
| 10 | `10-시스템-문서-정합성-동기화.md` | 시스템 규칙 문서, command, skill, validator 동기화 | 시스템 |
| 11 | `11-DAD-시스템-운영-감사.md` | 현재 DAD 시스템과 프롬프트의 노후화/drift 점검 | 시스템 |
| 12 | `12-맥락-요약-정책.md` | 피어 핸드오프 `handoff.context` 를 `CarryForwardMaxBytes` 아래로 유지 | 시스템 |

---

## 슬래시 커맨드

| 커맨드 | 설명 |
|--------|------|
| `/dialogue-start [작업]` | 대칭 턴 기반 대화 세션 시작 |
| `/dialogue-start-as-codex [작업]` | Codex가 Turn 1을 수행하는 DAD v2 세션 시작 |
| `/repeat-workflow [N]` | 대칭 턴 N회 반복 (사용자 감독) |
| `/repeat-workflow-auto [N]` | 대칭 턴 N회 자율 실행 (ESCALATE만 사용자에게) |

---

## Sprint Contract와 프롬프트 연결

v2에서 .prompts/ 파일은 **Sprint Contract 체크포인트 작성**의 입력 자료다:

| 작업 유형 | Contract 작성 시 참조할 프롬프트 |
|-----------|--------------------------------|
| 버그 수정 | `04-버그수정.md` + `03-도메인-감사-체크리스트.md` |
| 전체 감사 | `02-전체-코드문서-감사.md` + `03-도메인-감사-체크리스트.md` |
| 기획 검증 | `07-기획-검증-수정.md` + `00-공통-보충규칙.md` |
| 데이터 검증 | `05-데이터스키마-검증.md` |
| 플레이테스트 | `08-플레이테스트-절차.md` |
| 품질 보강 | `06-품질-일관성-보강.md` + `00-공통-보충규칙.md` |
| 시스템 문서/프로토콜 변경 | `10-시스템-문서-정합성-동기화.md` + 필요한 감사 프롬프트 |
| DAD 시스템 상태 점검 | `11-DAD-시스템-운영-감사.md` + `10-시스템-문서-정합성-동기화.md` |
| 세션/state 비상 복구 | `09-비상-세션-복구.md` (필요 시 `10-`과 동시 수정) |

시스템 규칙을 건드리는 작업에서는 `10-시스템-문서-정합성-동기화.md`를 선택적 참고가 아니라 기본 참조로 취급한다.
현재 DAD 시스템 자체가 낡았거나 실제 저장소 상태와 어긋났는지 점검할 때는 `11-` 프롬프트를 먼저 붙이고, 수정이 동반되면 `10-`을 함께 묶는다.
새로 만드는 DAD handoff에서는 사용자에게 출력한 peer prompt 본문을 `Document/dialogue/sessions/{session-id}/turn-{N}-handoff.md`에도 저장하고, Turn Packet의 `handoff.prompt_artifact`에 동일 경로를 기록한다.

---

## 사용법

### 사용자가 직접 시작
```
/dialogue-start 카드 보상 화면 버그 수정
/repeat-workflow 5
```

### 에이전트 간 호출
프롬프트 본문만 출력한다 (CLI 래퍼 불포함):
```
Read PROJECT-RULES.md first. Then read AGENTS.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.
Session: Document/dialogue/state.json
Previous turn: Document/dialogue/sessions/{session-id}/turn-{N}.yaml
[작업 지시]

---
허점이나 개선점이 있으면 직접 수정하고 diff를 보고하라.
수정할 것이 없으면 "변경 불필요, PASS"라고 명시하라.
중요: 관대하게 평가하지 마라. "좋아 보인다" 금지. 구체적 근거와 예시를 들어라.
```

Claude Code로 넘길 때는 첫 줄만 `Read PROJECT-RULES.md first. Then read CLAUDE.md and DIALOGUE-PROTOCOL.md. If that file points to Document/DAD references, read the needed files there too.`로 바꾼다.

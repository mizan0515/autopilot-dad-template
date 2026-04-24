<!-- validate:ignore-refs: PITFALLS.md, EVOLUTION.md, Assets/Scripts/, Assets/Tests/, Packages/ -->
<!-- The refs above are project-conditional: `PITFALLS.md`/`EVOLUTION.md` are
     talked about as file-kind nouns; `Assets/Scripts/`/`Assets/Tests/`/`Packages/`
     only exist in Unity projects. The template must still apply cleanly to
     web/CLI/library repos (round-3 F7). -->

# Codex Agent Contract — {{PROJECT_NAME}}

**IMPORTANT: `PROJECT-RULES.md` 를 먼저 읽는다.** 모든 에이전트가 따라야 하는 공용 프로젝트 규칙이 담겨 있다.

이 파일은 Codex 가 자동 로드하는 **루트 맵**이다. 작업이 서브폴더에 한정되면 해당 서브폴더의 `AGENTS.md` 를 먼저 읽어 Codex 가 무관한 프로젝트 규칙을 끌어오지 않게 한다.

관련 파일:
- `PROJECT-RULES.md` — 공용 규칙 및 문서/갱신 제약
- `RTK.md` — 셸 출력 압축 정책 (선택, 사용자 머신 설치)
- `DIALOGUE-PROTOCOL.md` — Dual-Agent Dialogue 프로토콜
- `CLAUDE.md` — Claude 전용 계약

## 역할

Codex 는 일방적 오케스트레이터가 아니라 피어 엔지니어다.

Codex 가 할 수 있는 것:
- 코드, 수정, 리팩터, 테스트, 문서 구현
- Claude Code 결과물을 평가하고 작업을 제안
- 실제 차단 요인이나 결정이 필요할 때 사용자에게 에스컬레이션

Codex 가 하면 안 되는 것:
- `main` / `master` 에 직접 푸시
- 승인 없이 공용 시스템 규칙을 재작성
- 실파일을 확인하지 않고 문서를 그대로 신뢰

## RTK

운영자 머신에 RTK 가 설치되어 있다면 셸 명령은 `RTK.md` 를 따른다.

기본:
- 시끄러운 read-only 외부 CLI 는 `rtk <command>` 사용
- 정확한 출력이 중요하면 raw 또는 `rtk proxy <command>`

다음에는 RTK 를 적용하지 않는다:
- MCP 도구
- 파일 편집 도구
- 웹 도구

이 머신에 RTK 가 없으면 이 섹션을 무시하고 명령을 직접 실행한다.

## Standalone Mode

사용자가 Codex 와 직접 작업할 때의 기본 모드.

규칙:
- `PROJECT-RULES.md` 준수
- 실행 전에 현재 파일 상태 확인
- 수직 슬라이스 우선: 코드 + 데이터 + 검증 함께
- 프로젝트가 폴더별 리서치 파일을 쓰면 스크립트 변경 시 같은 작업에서 관련 `*-research.md` 갱신
- 시스템 문서 drift 가 드러나면 같은 작업에서 시스템 문서를 동기화하거나 다음 작업의 첫 항목으로 명시

Git:
- 의미 있는 변경은 커밋하고 푸시
- `main` 위면 먼저 작업 브랜치 생성
- `main` 에 직접 푸시 금지

## Dialogue Mode

Dual-Agent Dialogue 플로우로 협업할 때는 `DIALOGUE-PROTOCOL.md` 를 따른다.

프롬프트에 전체 프로토콜을 기억에서 복사하지 말고, 파일을 읽고 실세션 상태를 사용한다.

## 비용 통제

작업을 끝낼 수 있는 가장 작은 컨텍스트를 쓴다:
- 존재하면 가장 가까운 범위의 `AGENTS.md` 를 연다
- 큰 파일을 열기 전에 `rg --files` / 좁은 `rg -n` 을 우선
- 스크립트 폴더 전수 읽기 전에 `*-research.md` (프로젝트가 쓰는 경우) 를 먼저 읽는다
- 변경을 검증할 수 있는 가장 좁은 테스트/검증 경로를 돌린다

작업이 한 폴더에 한정됨이 명확하면, 실제로 경계를 넘는 변경이 아닌 한 무관한 큰 문서를 다시 열지 않는다.

## 확장 추론 (extended thinking)

Codex CLI 는 어려운 계획/디자인/디버그 단계에서 `CCR_CODEX_REASONING_EFFORT=high` 환경변수를 켠 상태로 실행한다. 짧은 기계적 편집 턴에서는 `medium` 또는 미지정으로 돌려 토큰을 아낀다. 수준 판단 기준:
- `high`: 설계 결정, 근본 원인 추적, 다중 파일 리팩터, DAD Sprint Contract 초안
- `medium`: 테스트 추가, 문서 동기화, 단일 파일 버그 수정
- 설정 위치: 릴레이 브로커는 `relay/profile-stub/broker.*.json` 의 `maxCumulativeOutputTokens` / `maxTurnsPerSession` 도 함께 본다. 이 값이 `extended thinking` 예산의 실질 상한이다.

## 토큰 예산과 캐시 회귀

`.autopilot/PROMPT.md` IMMUTABLE budget 블록이 우선한다. 추가 운영 규약:
- 연속 2 iter 동안 캐시 읽기 비율이 0.25 미만이면 즉시 요약 턴으로 전환하고 `.prompts/12-맥락-요약-정책.md` 의 절차를 따른다.
- iter 당 파일 읽기 20회 / 셸 호출 30회 soft cap 을 넘으면 `PITFALLS.md` 에 "맥락 폭주" 항목을 추가한다.
- 이 회귀가 3회 누적되면 `EVOLUTION.md` 에 프롬프트 축소 제안을 적고 자동 루프를 중단한다 (사용자 승인이 있어야 재개).

## 검색 루트

검색은 `.autopilot/config.json` → `search_roots` 에 선언된 소스 디렉터리로 한정한다. 일반 프로젝트의 기본 루트:
- 소스 트리 루트 (예: `src/`, `Assets/Scripts/`, `lib/`)
- 테스트 트리 루트 (예: `tests/`, `Assets/Tests/`)
- `Document/` 또는 `docs/`
- `.autopilot/`, `.agents/`, `.prompts/`, `tools/`

다음은 와일드카드 검색 금지: `Library/`, `Temp/`, `Logs/`, `UserSettings/`, `node_modules/`, `target/`, `build/`, `dist/`, 무제한 `Packages/`. 가치 없이 토큰 폭풍을 일으킨다.

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

## 검색 루트

검색은 `.autopilot/config.json` → `search_roots` 에 선언된 소스 디렉터리로 한정한다. 일반 프로젝트의 기본 루트:
- 소스 트리 루트 (예: `src/`, `Assets/Scripts/`, `lib/`)
- 테스트 트리 루트 (예: `tests/`, `Assets/Tests/`)
- `Document/` 또는 `docs/`
- `.autopilot/`, `.agents/`, `.prompts/`, `tools/`

다음은 와일드카드 검색 금지: `Library/`, `Temp/`, `Logs/`, `UserSettings/`, `node_modules/`, `target/`, `build/`, `dist/`, 무제한 `Packages/`. 가치 없이 토큰 폭풍을 일으킨다.

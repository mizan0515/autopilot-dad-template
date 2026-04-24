# ROADMAP — autopilot-dad-template full scenario

## 사용자 시나리오 (확정)

1. DAD / autopilot 미적용 프로젝트에서 Claude Code / Codex 에 한 문장: "깃헙 mizan0515/autopilot-dad-template 템플릿을 현재 프로젝트에 적용해줘"
2. 에이전트가 관리자 언어를 물음
3. 사용자: "한국어로"
4. 에이전트가 대상 프로젝트의 **핵심 계획 문서(PRD)** 를 파악 → 그에 맞춰 DAD 구성 → RTK / PROJECT-RULES / DIALOGUE-PROTOCOL / AGENTS / CLAUDE / .autopilot / .githooks / .github / .prompts / .agents / .claude / tools 를 차근차근 설치. **dad relay 폴더도 템플릿에 포함되어 있어 자동 구성**. 사용자는 완료까지 "계속하라" 만 반복.
5. codex / claude CLI 로그인 가이드 (OAuth 브라우저 플로우)
6. 자동 루프 시작: autopilot 자기 개선 + dad relay 피어 상호작용 (codex ↔ claude) + 합의 수렴 → autopilot 검토 → 관리자 보고. 피어가 MCP / agent / tool-use / extended-thinking 호출. 컨텍스트 비대 시 summarization. 개선 기록 보관. 다음 작업은 BACKLOG 에 적재.
7. 관리자 대시보드 + 자기 언어 PR 로 작업 기록 확인.

## 현재 상태 (2026-04-24)

이미 main 에 있는 것:
- `apply.{ps1,sh}` — 언어 설정 / 프로젝트 메타 수집 / base + locales 복사 / config.json 작성 / hooks 등록
- `base/.autopilot/` — PROMPT / STATE / BACKLOG / HISTORY / PITFALLS / EVOLUTION (locales) + project.ps1 + OPERATOR-TEMPLATE.html + config.schema.json + hooks/ + runners/ (preflight / timeout / stalled-fallback / HALT 전부 card-climber 에서 검증됨)
- `locales/{en,ko}/` — strings.json + .autopilot/*.md
- `BOOTSTRAP.md` — 9단계 원-프롬프트 오케스트레이터

아직 없는 것 (이 로드맵의 대상):
- **PRD 자동 파악** 단계 (Step 4)
- **PROJECT-RULES / DIALOGUE-PROTOCOL / AGENTS / CLAUDE / RTK.md 최상위 시스템 문서** 스캐폴드
- **.claude / .agents / .prompts / .githooks / .github / tools** 인프라
- **Document/DAD / Document/dialogue** 프로토콜 문서 + 세션 스키마
- **relay/** 번들 (dad relay 자동 구성)
- **peer MCP / tool-use / extended-thinking adapter** 설정 가이드
- **context summarization** (CARRY-FORWARD 바이트 캡) 규약
- **CLI 로그인 가이드** (codex + claude OAuth)
- **자기 언어 PR 규약** (CLAUDE.md 에 명시)
- **누적 사고 재발 방지** (INCIDENTS.md 교훈 전체 반영)

## 실행 방법 (Phased)

한 PR 당 한 phase. 각 phase 는 독립 병합 가능하도록 설계. 실패 시 해당 phase 만 revert.

### Phase 1 — 최상위 시스템 문서 (language-aware scaffold)

**목적:** Step 4 의 "PROJECT-RULES / DIALOGUE-PROTOCOL / AGENTS / CLAUDE / RTK.md" 를 템플릿이 설치하게 한다.

**포팅 대상:**
- `locales/{en,ko}/PROJECT-RULES.md` — 헤더 스캐폴드 + `{{PROJECT_GUARDRAILS_BLOCK}}` 플레이스홀더. card-climber 의 Source Of Truth / Repository Reality / Gameplay Rules / Agent Guardrails / Document Update Rules / Editing And Shell Fallback Rules 섹션 구조만 유지, 게임 특정 내용 삭제.
- `locales/{en,ko}/DIALOGUE-PROTOCOL.md` — card-climber DIALOGUE-PROTOCOL.md 거의 그대로 (95% generic). `cardgame-dad-relay` 같은 1줄만 `{{RELAY_REPO_PATH}}` 로.
- `locales/{en,ko}/AGENTS.md` — Codex 역할 + RTK 선택적 참조 + Standalone/Dialogue 모드.
- `locales/{en,ko}/CLAUDE.md` — Claude Code 역할 + **Layer 1 identity 는 relay 소유** 블록 + Standalone/Dialogue 모드 + peer-prompt 7요소 + 필수 꼬리말 + **자기 언어 PR 규약** 신설.
- `locales/{en,ko}/RTK.md` — 20줄 stub, 사용자 머신 설치임을 명시, 범용 예시, 하드코딩 경로 제거.
- `base/Document/DAD/` — README + PACKET-SCHEMA + STATE-AND-LIFECYCLE + VALIDATION-AND-PROMPTS (~98% generic, 거의 그대로).
- `base/Document/dialogue/` — README + 빈 `state.json` (protocol_version + session_status: "none" 만).
- `apply.{ps1,sh}` 확장: 위 최상위 MD 파일을 프로젝트 루트로 복사 + placeholder 렌더. PRD 감지 단계 추가.

**PRD 자동 파악 로직 (apply 에 추가):**
- 대상 프로젝트에서 다음 파일 중 첫 번째 존재 사용:
  `PRD.md`, `README.md`, `docs/PRD.md`, `Document/PRD.md`, `게임 규칙 명세서.md`, `ROADMAP.md`, `product.md`
- 첫 100 줄 추출 → config.json 의 `project_prd_excerpt` 에 저장
- 없으면 사용자에게 한 번 더 물음 ("프로젝트의 핵심 방향이 기록된 문서 경로? 없으면 Enter")

**재발 방지 (INCIDENTS.md 반영):**
- `Document/dialogue/README.md` 에 validator ignore-refs marker 불필요 (allowlist 로 처리)
- CLAUDE.md 에 `--no-verify` 금지 명시 (§1.2 교훈)

### Phase 2 — 검증/훅/CI 인프라

**목적:** 템플릿 사용자가 bootstrap 직후부터 시스템 문서 정합성 / 인코딩 / DAD 패킷 검증을 받는다.

**포팅 대상:**
- `base/tools/Validate-Documents.ps1` — **`Test-IsEphemeralReference` allowlist 포함** (INCIDENTS §1.1 재발 방지).
- `base/tools/Validate-DadPacket.ps1` — DAD v2 패킷 검증.
- `base/tools/Lint-StaleTerms.ps1` — 용어 통일 (템플릿은 규칙 비워두고, 프로젝트가 채우게).
- `base/tools/New-DadSession.ps1`, `New-DadTurn.ps1` — DAD 세션 생성 helper.
- `base/tools/Validate-CodexSkillMetadata.ps1`, `Register-CodexSkills.ps1` — Codex 스킬 등록 유틸.
- `base/.githooks/pre-commit` — 7 validator 디스패치 shell stub.
- `base/.github/workflows/validate-dad-packets.yml` + `validate-doc-encoding.yml` — CI 미러.
- `apply.{ps1,sh}` 확장: `git config core.hooksPath .githooks` 등록.

**재발 방지:**
- `Validate-Documents.ps1` 의 `Test-IsEphemeralReference` 에 `*-LIVE.*` / `NEXT_DELAY` / `LOCK` / `HALT` / `FAILURES.jsonl` / `.audit-cache.*` 이미 포함 (card-climber #293 에서 검증 완료) → 템플릿에 그대로 이식.
- 인코딩 mojibake 방지 (INCIDENTS §2.3): `Validate-Documents.ps1` 가 이미 BOM + UTF-8 검사. 템플릿 JSON writer 들은 `[IO.File]::WriteAllText ... (New-Object Text.UTF8Encoding $false)` 패턴 강제.
- `commit-msg` 훅으로 IMMUTABLE 블록 변경 막기 (`base/.autopilot/hooks/` 에 이미 있음 — 최상위 `.githooks/` 로 미러링 필요 여부는 apply 가 결정).

### Phase 3 — .claude + .agents + .prompts

**목적:** Step 4 의 .claude / .agents / .prompts 구성. Claude Code 슬래시 명령 + Codex 스킬 + 주제별 재사용 프롬프트.

**포팅 대상:**
- `locales/{en,ko}/.claude/commands/` — dialogue-start / dialogue-start-as-codex / repeat-workflow / repeat-workflow-auto (4개). Assets/Tests/ 같은 Unity 경로는 `{{TEST_BASELINE_DOC}}` 플레이스홀더.
- `base/.claude/settings.json` — `BASH_MAX_OUTPUT_LENGTH=30000`, `FILE_READ_MAX_CHARS=25000`, WebFetch allowlist, `includeCoAuthoredBy: true`.
- `locales/{en,ko}/.agents/skills/{{SKILL_PREFIX}}-dialogue-start/`, `-repeat-workflow/`, `-repeat-workflow-auto/` — SKILL.md + agents/openai.yaml. SKILL_PREFIX 는 apply 시 프로젝트 slug 로 치환. **UTF-8 without BOM** 인코딩 필수 (Codex frontmatter 요구).
- `locales/{en,ko}/.prompts/` — 00-공통-보충규칙 / 01-정합성-감사수정 / 02-맥락-체크아웃 / 06-작업세션-요약 / 09-피어-프로토콜 / 10-시스템-문서-정합성-동기화 / 11-DAD-운영-감사 (7개 generic prompts).
- `apply.{ps1,sh}` 확장: 위 경로들을 대상 프로젝트 루트로 복사 + SKILL_PREFIX 치환.

**재발 방지:**
- SKILL.md / openai.yaml BOM 제거 강제 (Codex 파싱 실패 방지).

### Phase 4 — relay 번들 (Step 4 의 "dad relay 폴더 자동 구성")

**목적:** bootstrap 완료 직후 사용자가 별도 수동 작업 없이 DAD peer dialogue 가 작동하도록 한다.

**접근:** relay 소스 전체를 번들링 ≠ 현실적. 대신 **relay 설정 템플릿 + 선택적 설치 스크립트** 로.

**포팅 대상:**
- `base/relay/README.md` — relay 가 무엇인지, Layer 1 소유권 모델, 로컬 실행 옵션.
- `base/relay/profile.template.json` — `broker.{project}.json` 의 generic 버전 (timeouts / turn cap / token ceiling). apply 시 `{{PROJECT_SLUG}}` 치환.
- `base/relay/agent-identities.template.json` — orchestrator / worker / peer-codex / peer-claude / tool-bridge 5개 identity 의 generic 버전. `allowed_buckets` / `allowed_execution_modes` / `allowed_tool_classes` / `allowed_mcp_servers` 스키마 유지. 프로젝트 slug 치환.
- `base/relay/anomaly-rules.template.json` — hung_progress_age_seconds: 300, 5 anomaly toggles.
- `base/relay/tool-registry.template.json` — 빈 tool-registry (프로젝트가 채움).
- `base/relay/setup-relay.{ps1,sh}` — relay repo clone (optional; 기본은 scoped MCP pass-through 로 CLI 만 사용) 또는 `ccrelay-run` .NET tool 설치 안내.
- `locales/{en,ko}/relay/SETUP.md` — relay 로컬 실행 가이드 (언어별).
- `apply.{ps1,sh}` 확장: 위 profile template 들을 `.autopilot/relay/` 또는 프로젝트 루트 `relay/` 로 배포.

**설계 결정:**
- **relay source code 는 번들하지 않음** — 너무 큼. 대신 `cardgame-dad-relay` repo 를 참조 모델로 두고, 템플릿 사용자는 원하는 경우 별도 clone.
- **MCP pass-through 모드 기본** — `docs/mcp-per-peer-setup.md` 에 문서화된 "Option A" (각 CLI 가 자기 `~/.codex/config.toml` / `--mcp-config` 읽음) 를 디폴트로. 즉 최소 설정으로 peer dialogue 가능.
- **extended thinking**: `CCR_CODEX_REASONING_EFFORT=high` env 안내.

**재발 방지:**
- infinite-rotation loop (relay iter 5) → 이미 segment-scoped counter 로 해결. 템플릿 문서에만 경고.
- schema drift (METRICS.jsonl tier 1 vs tier 3) → `Validate-Metrics.ps1` 포팅 + METRICS 스키마 문서화.

### Phase 5 — context summarization + MCP / extended thinking adapter 규약

**목적:** Step 6 의 "컨텍스트 비대 시 summarization, 피어가 MCP / agent / tool-use / extended-thinking 호출" 규약을 문서화.

**포팅 대상:**
- `locales/{en,ko}/DIALOGUE-PROTOCOL.md` 확장: **CARRY-FORWARD 바이트 캡** 섹션. turn-N 의 `handoff.context` 는 `CarryForwardMaxBytes: 2048` 로 자동 truncation (relay broker 와 동일). `…truncated` marker 추가. 이력 재조회가 필요하면 `state.json` + 이전 `turn-{N}.yaml` 을 참조.
- `locales/{en,ko}/AGENTS.md` / `CLAUDE.md` 확장: extended thinking 지침 (codex `CCR_CODEX_REASONING_EFFORT`, Claude 자동), 토큰 예산 (`MaxCumulativeOutputTokens`), low-cache-regression rotation 규약.
- `locales/{en,ko}/.prompts/12-맥락-요약-정책.md` (신규) — 피어가 context 를 어떻게 요약/캡핑하는지.
- `base/.autopilot/PROMPT.md` IMMUTABLE `budget` 블록 업데이트: budget 임계값 현실화 (files_read 20, bash_calls 30) — INCIDENTS §2.1 재발 방지.

### Phase 6 — CLI 로그인 가이드 + 자기 언어 PR + 대시보드 운영자 surface

**목적:** Step 5 (CLI 로그인), Step 7 (대시보드 + 자기 언어 PR) 마감.

**포팅 대상:**
- `locales/{en,ko}/docs/cli-login-guide.md` — codex (`codex auth login`) + claude (`claude login` 또는 Claude Code desktop 자동) OAuth 브라우저 플로우 스크린샷 단계.
- BOOTSTRAP.md 의 Step 2 (전제조건 점검) 에서 이 가이드를 링크.
- `locales/{en,ko}/CLAUDE.md` 에 **PR 제목 / 본문 언어 규약** 추가: 운영자 언어로 작성. 사용자가 ko 선택 시 PR 제목도 한국어.
- `base/.autopilot/project.ps1` 대시보드 출력이 이미 i18n. PR 목록 섹션에 title 언어 검증 추가.
- `base/.autopilot/OPERATOR-TEMPLATE.html` 이미 i18n. 대시보드에 **DAD peer dialogue 섹션** (session-status: active/converged/blocked) + **최근 PR 5개 섹션** 추가.

### Phase 7 — 누적 사고 재발 방지 최종 점검

**목적:** INCIDENTS.md §1 (card-climber) + §2 + §3 + relay PITFALLS 를 교차 점검해 템플릿이 빠뜨린 것이 없는지 확인.

**체크리스트 (조사 결과 기반):**

| # | 사고 패턴 | 기존 안전망 | 템플릿 조치 |
|---|---|---|---|
| 1 | Validator 가 runtime 파일을 dead-ref 로 오판 | ✅ #293 allowlist | Phase 2 에서 포팅 완료 |
| 2 | retained-dirty silent-stall | ✅ stalled-fallback | Phase 0 (이미 #2 로 포팅) |
| 3 | preflight / timeout / HALT 부재 | ✅ #295 | Phase 0 완료 |
| 4 | budget 상시 초과 (108/110) | ❌ | Phase 5 에서 임계값 현실화 |
| 5 | survivor autopilot remote branch | ⚠️ 경고만 | Phase 6 문서 + optional cleanup hook |
| 6 | QA JSON UTF-8 repair 필요 | ❌ | Phase 2: JSON writer UTF8NoBomEncoding 강제 + round-trip 검증 helper |
| 7 | MCP EditMode focused 필터 오동작 | ❌ | project-specific, 템플릿은 "known issue" 만 문서화 |
| 8 | Unity MCP 가용성 불안정 | ❌ | Phase 0 preflight 에 `verify_mcp` hook slot 추가 |
| 9 | dispatch queue failed/ 경로 부재 | ❌ | Phase 2 에서 `base/.autopilot/dispatch/{queue,consumed,failed}/` 미리 생성 |
| 10 | auto-merge-refused PR 추적 없음 | ❌ | Phase 5 PROMPT.md idle-upkeep 섹션에 `gh pr list --state=open --author=@me` 스윕 추가 |
| 11 | 동시 runner LOCK 부재 | ⚠️ per-iter LOCK 만 | Phase 2 에서 PID-tracked LOCK 도입 |
| 12 | PROMPT.md 삭제 무한 루프 | ❌ | Phase 0 에서 preflight 에 `Test-Path PROMPT.md` 체크 추가 |
| 13 | Korean BOM mojibake (relay PITFALL) | ❌ | Phase 2 Validate-Documents 이미 검사. Phase 1 MD 쓰기 경로 전수 `UTF8NoBomEncoding` |
| 14 | wildcard Grep 토큰 폭주 | ❌ | Phase 1 AGENTS/CLAUDE.md 에 search roots / blacklist 명시 |
| 15 | HISTORY.md 60KB 성장 | ❌ | Phase 5 PROMPT.md boot 에 size check + threshold rotation 추가 |
| 16 | relay rotation 로 token counter 리셋 미스 | ✅ relay 쪽 해결됨 | 템플릿은 해당 없음 |
| 17 | per-iter worktree 디스크 포화 | ⚠️ | Phase 4 SETUP.md 에 "reuse named worktree + git worktree prune" 규약 |

## 순서 / 의존성

```
Phase 0 (이미 완료)
  ├── BOOTSTRAP.md                               # PR #3
  ├── preflight + timeout + stalled-fallback + HALT   # PR #2
  └── apply.ps1/sh + base/ + locales/{en,ko}/      # pre-existing

Phase 1 — 최상위 시스템 문서
  └── 독립 실행 가능 (선행 없음)

Phase 2 — 검증/훅/CI
  └── Phase 1 문서가 있어야 validator 가 의미 있음
      (Phase 1 머지 후 시작)

Phase 3 — .claude + .agents + .prompts
  └── Phase 1 + Phase 2 완료 후. commands/skills 가 system-doc 을 인용

Phase 4 — relay 번들
  └── Phase 1 + Phase 2 완료 후. relay profile 스키마가 generic 식별자 사용

Phase 5 — summarization + adapter 규약
  └── Phase 1 DIALOGUE-PROTOCOL + Phase 4 relay profile 완료 후

Phase 6 — CLI 로그인 + PR 언어 + 대시보드
  └── Phase 1 CLAUDE.md + 기존 base/project.ps1 완료 후. Phase 4 에 의존

Phase 7 — 재발 방지 최종 감사
  └── Phase 1-6 전부 완료 후. QA 전용 phase.
```

## 각 Phase 당 산출물

- 하나의 PR
- PR title: `feat(template): Phase N — <요약>`
- PR body: 포팅 대상 / 재발 방지 매핑 / Test plan (apply 를 fresh dir 에 돌려 smoke)
- squash-merge to main
- 병합 후 ROADMAP.md 의 해당 phase 섹션에 ✅ 표시 + PR 번호 기록

## 이 PR (로드맵 문서) 의 위치

- Phase 0 직후, Phase 1 시작 전.
- Phase 1 실행 전 **단일 커밋** 으로 roadmap 자체만 main 에 넣어 합의를 잡는다.
- 이후 Phase 별 PR 은 이 문서를 reference 한다.

## 미결정 사항 (사용자 결정 필요)

- **Phase 4 relay 설치 범위**: MCP pass-through (기본, 최소) vs `dotnet tool install ccrelay-run` 유도 vs relay repo clone 유도. 세 옵션 모두 문서화하고 apply 시 질문할지, 디폴트만 밀지.
- **Phase 3 SKILL_PREFIX 디폴트**: 프로젝트 디렉터리명 slug (e.g. `my-project-dialogue-start`) vs config.json 의 `project_name` 기반.
- **Phase 6 PR 언어 검증 강도**: 권장만 할지 (문서), 아니면 PR 훅/CI 에서 소프트 체크 (warning) 넣을지.

사용자 확인 후 Phase 1 시작.

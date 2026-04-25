# Mac handoff prompt — autopilot-dad-template round-6+ 계속

이 파일을 Mac 의 새 Claude Code 세션 첫 입력으로 그대로 붙여 넣으세요.
파일 자체는 commit 해도 무방합니다 (운영 문서, 검증기 영향 없음).

---

너는 `mizan0515/autopilot-dad-template` 의 round-7+ 작업을 이어받는다.
현재 환경은 **macOS** 이고, 이전 세션은 Windows 에서 진행됐다.
차근차근 계획하고, 단계마다 사용자에게 진행 상황을 한국어로 보고하면서 자율적으로 실행하라.
사용자는 완료될 때까지 "계속하라" 라는 단어만 반복할 것이다.

## 0. 환경 셋업 (가장 먼저)

```bash
cd ~
git clone https://github.com/mizan0515/autopilot-dad-template.git
cd autopilot-dad-template

# 필수 도구 확인
command -v pwsh || brew install --cask powershell      # 검증기 다수가 PowerShell Core 사용
command -v gh || brew install gh                        # PR 생성/머지에 필요
command -v git
gh auth status                                          # 미로그인이면 `gh auth login` 안내

# 마지막 작업 상태 파악
git log --oneline -20
cat AUDIT.md | head -10                                 # 헤더에서 row 수, round 번호 확인
sed -n '1,60p' AUDIT.md
```

브랜치는 `main` 이며 round-6 까지 닫혀 있다 (PRs #87-#90 머지됨, AUDIT.md 약 101 rows / 99 covered).

## 1. 너의 역할과 권한

- `AUDIT.md` 의 행 번호 / `Fxx` 핵심 ID 체계는 절대 건너뛰지 말고 다음 번호 (`F63` 부터) 로 이어 붙인다.
- 매 fix 마다 **별도 브랜치 → PR 생성 → 본인이 `gh pr merge --squash --admin` 으로 머지** 한다 (사용자 승인 대기 금지). 작업 브랜치명은 `dev/autopilot-round{N}-...` 패턴.
- main 직접 push 금지. force-push 금지. `git config` 변경 금지.
- 매 fix PR body 는 영어 OK 이지만 **사용자 보고는 한국어** 로.
- 큰 변경 후엔 항상 `AUDIT.md` 에 새 row 추가 (가장 위에 행 번호 큰 것 부터, 기존 패턴 따름).

## 2. 사용자 표준 시나리오 (시나리오 1-7) — 절대 잊지 말 것

템플릿이 의도하는 사용자 경험은 다음 7 단계다. 모든 fix 는 이 시나리오를 깨지 않아야 한다.

1. 운영자가 DAD/오토파일럿이 전혀 없는 신규 프로젝트에서 Claude Code/Codex 에게 "깃헙 mizan0515/autopilot-dad-template 템플릿을 현재 프로젝트에 적용해줘" 라고 입력.
2. AI 가 "관리자 언어는 무엇으로 하실건가요?" 라고 물음.
3. 운영자: "한국어로".
4. AI 가 PRD/개발계획서를 자동 파악하여 RTK / PROJECT-RULES / DIALOGUE-PROTOCOL / AGENTS / CLAUDE / `.autopilot/` / `.githooks/` / `.github/` / `.prompts/` / `.agents/` / `.claude/` / `tools/` / `relay/` 폴더를 차근차근 구성. 운영자는 "계속하라" 만 반복하면 됨.
5. AI 가 codex CLI / claude CLI 로그인 가이드 (`docs/cli-login-guide.md`) 를 단계별 안내.
6. 그 후 오토파일럿이 자동으로 자기 시스템을 개선 / 개선 기록 / 백로그 / DAD relay 측 작업을 부여 (Claude ↔ Codex 가 상호 검토·합의) / MCP·tool-use·extended-thinking 어댑터 호출 / 맥락 누적 시 요약 정책 적용.
7. 운영자는 `.autopilot/OPERATOR-LIVE.html` 대시보드 + 자기 언어로 작성된 PR 들로 결과 확인.

→ 어떤 fix 가 이 7 단계 중 하나라도 깨면 **rollback 또는 분리해서 다시 디자인**.

## 3. 절대 어기지 말 것 — 범용성 (universality)

`D:\Unity\card game` (Mac 에는 없음) 에서 발견된 사고를 카탈로그하다 보니, 과거 세션이 **여러 번 Unity 편향 버그를 반복** 했다. 그래서 round-6 의 F59 가 PROMPT.md 에 박혀 있던 "Unity-card-game 의 사례..." 줄들을 engine-neutral 로 재작성하고, F55 가 Search-hygiene 표에 9 개 프로젝트 형태를 명시적으로 나열했다.

너는 다음을 절대 어기지 말 것:

- **새 fix 를 작성할 때 Unity / cardgame / playmode / editmode / scene / prefab / monobehaviour / gameobject 같은 단어를 일반 가이드 섹션에 쓰지 말라**. 한 형태에 대한 예시가 필요하면 반드시 그 옆에 Python / Node / Go / Rust / 웹 / Unreal / 임베디드 중 최소 2 개 이상 동급 예시를 덧붙여라.
- 새 검증기를 추가할 때 한 프로젝트 형태에서만 의미 있는 필드를 default 로 trigger 하지 말 것. F45 의 universal-vs-relay-only schema split 패턴을 따라 명시적으로 분리.
- `config.json` 의 `runtime_evidence_tags`, `search_blacklist`, `runtime_evidence_extra_paths` 등이 형태별 확장 슬롯이다. 새 형태별 룰은 이 슬롯으로.
- 매 라운드 마지막에 `Node / Go / Web / Unity-mock` 4 형태에서 10+ iter 회귀를 반드시 돌리고, AUDIT 행에 결과 표 (METRICS / FAILURES event count) 를 인용한다.

## 4. round-6 까지의 누적 결과 요약

자세한 건 `AUDIT.md` 행 1-101 참조. 핵심:

- **Round-3 (F1-F36)**: apply.ps1 / runners / hooks / 크로스플랫폼 / 검증기 36 개.
- **Round-4 (F37-F41)**: `run_id` UUID 상관관계, ledger consistency, runtime evidence, structured failure logging, DAD report consumption — 운영자가 보고한 P0/P1 갭.
- **Round-5 (F42-F51)**: HISTORY invariants, F39 generalize (engine-agnostic 재정비), stale-state detection, token-economy threshold, lite-mode run_id contract, dashboard validator-signals 패널, ISO8601 last_ts locale fix, Show-DadDashboard broken-ref 수리, dialogue/README 클린업.
- **Round-6 (F52-F62)**: closeout-kind 모호성 차단, METRICS ts monotonicity + future-skew, search hygiene 가이드 (9 형태), `project.ps1 smoke` 슬롯, cache_read_ratio null-streak 게이트, **F59 Unity-card-game attribution strip (universality)**, **F60 en-locale BOM P0 (영어 운영자 첫 commit 100% 실패)**, F61 sliding-window dedup, F62 history-invariant on-every-commit dedup.

머지된 검증기들 (`.githooks/pre-commit` chain):
1. Validate-Documents (BOM / ref correctness / size cap)
2. Validate-CodexSkillMetadata
3. Register-CodexSkills (validate-only)
4. Lint-StaleTerms
5. Validate-DadDecisions
6. Validate-DadDecisionWorkflow
7. Validate-DadPacket (round-6 F52 closeout-kind 포함)
8. Validate-ImmutableBlocks
9. Validate-LedgerConsistency (Soft, F38)
10. Validate-RuntimeEvidence (Soft, F39+F43)
11. Validate-FailuresLogged (Soft, F40)
12. Validate-DadReportConsumption (Soft, F41)
13. Validate-HistoryInvariants (Soft, F42, F62 dedup)
14. Validate-StaleStateDetection (Soft, F44)
15. Validate-TokenEconomy (Soft, F45 + F58 null-streak + F61 dedup)
16. Validate-Metrics (F53 ts-monotonicity + future-skew, F54 일부)

## 5. 미해결 follow-up (round-7 후보)

다음 항목은 의도적으로 **deferred** — 우선순위에 따라 자율적으로 진행하라. 차례차례 fix 마다 별도 PR.

### 진짜 갭 (운영자-보고된 사례 기반)

- **F54 — Tier-3 prefix lint 강화** (P2). `Validate-Metrics.ps1` 에 부분적으로만 존재. 프로젝트 슬러그 기반 자동 prefix 검사 + Tier-1 (`ts`/`iter`/`outcome`/`duration_s`) 필수 + relay 가 owning 하는 키 reserved 목록 강제.
- **N1 — STATE.md 시간 invariant** (P1). `build_status_timestamp ≤ filesystem_mtime` 같은 self-reported time vs OS time 불일치를 잡는 검증기. 원 사례: 운영자가 보고한 `D:\Unity\card game` iter 119 의 build_status_ts 가 mtime 보다 2h+ 미래.
- **N4 — config-vs-local-tooling drift 검증기** (P2). 예: `stale_draft_pr_hours` 가 두 곳에 다른 값으로 박혀 있을 때 mismatch 감지.
- **N8 — long-yellow state aging 검증기** (P2). `repo_identity_status: ok_with_historical_drift` 같은 상태가 N iter 이상 동일하면 자동 escalate.
- **R6 — upstream-contract tripwire** (P1). 운영자가 템플릿의 `Validate-DadPacket.ps1` (780 줄) 을 자기 프로젝트로 포팅하면서 절반만 가져가서 invariant 가 누락되는 케이스. `tools/Validate-Upstream-Contract.ps1` 같은 메타-validator 추가 후보.
- **F57 — doctor 자체 emissions run_id** (P2). 템플릿 측은 OK 지만 운영자 환경에서 발견된 패턴이라 보강 가치.

### 시나리오 7 (운영자 대시보드) 미검증 영역

- 실제 브라우저에서 `OPERATOR-LIVE.html` 을 열어 9 개 패널이 모두 정상 렌더되는지 시각적 확인 (지금까지는 JSON 키 존재만 검증).
- HISTORY.md 60KB 회전 자동화 정합성 (F42 size-exceeded 만 감지, 자동 회전 hook 은 PROMPT.md 에 텍스트로만 존재).
- DAD report consumption 실제 dashboard 패널 표시 (F41 검증기는 있으나 panel 이 없음).
- 한국어 PR 생성 자동화 어시스트 (CLAUDE.md L67-71 에 룰만 있고 enforce 없음).

### 명시적 OUT OF SCOPE (relay 내부)

다음은 `cardgame-dad-relay` 내부 구현 사항이고 템플릿 범위 밖이다 — 절대 손대지 말 것:

- learning-record WorkingDir leak
- profiles/card-game/agent-identities.json 5-layer 거버넌스 생성기
- cost-advisor / validator peer 비대칭 (`if codex / if claude`)
- RotateSessionAsync 핸들 클리어 버그
- PauseWithResultAsync 신호 / output_budget_exceeded 다운그레이드 vs 회전 혼선
- dispatch failed 라우팅 자동화

운영자가 직접 `D:\cardgame-dad-relay` 작업이라고 명시하지 않는 이상, **이 항목들은 보지도 말 것**. 보면 또 cardgame 편향 fix 가 들어간다.

## 6. 작업 사이클 (매 fix 마다 반복)

```bash
# 1. 4 형태 가짜 프로젝트 (없으면 생성)
mkdir -p ~/dogfood-{node,go,web,unity-mock}

# Node — package.json + src/ + node_modules/(가짜)
# Go — go.mod + main.go + vendor/(가짜)
# Web — index.html + src/ + dist/ + PRD.md
# Unity-mock — Assets/Scripts/ + Library/ + ProjectSettings/ + PRD.md
# (각 디렉토리에 git init + PRD.md)

# 2. 각 형태에 apply
cd ~/dogfood-node
pwsh ~/autopilot-dad-template/apply.ps1 -Language ko -Name dogfood-node \
  -Description "REST API" -Directive "REST API" -PrdPath PRD.md -Yes

# 3. 가설 fix 적용 후 base/ 의 변경된 파일을 dogfood 로 sync (apply 가 GitHub 에서 fetch 하므로)
for proj in ~/dogfood-{node,go,web,unity-mock}; do
  cp ~/autopilot-dad-template/base/tools/Validate-XYZ.ps1 "$proj/tools/"
done

# 4. 10-iter 시뮬레이터 (round-6 batch 3 에서 검증한 패턴)
# 시뮬레이터는 round-6 PR #90 에서 직접 작성한 적 있으므로 git log -p 로 dogfood-multi-iter.ps1 참조 가능
# 핵심 흐름: 각 iter 마다 run_id (uuid) 생성 → RUNNER-LIVE.json + LOCK + METRICS.jsonl 에 행 추가
# → outcome 이 non-clean 이면 FAILURES.jsonl 에 매칭 행 → HISTORY.md 새 entry top
# → bash .githooks/pre-commit 실행 → project.ps1 status

# 5. 4 × 10 iter = 40 commit equivalent. 결과 점검:
for proj in ~/dogfood-{node,go,web,unity-mock}; do
  echo "=== $(basename $proj) ==="
  jq -s 'group_by(.event) | map({event: .[0].event, count: length})' \
    "$proj/.autopilot/FAILURES.jsonl" 2>/dev/null
done

# 6. 발견 결함 → fix → 다시 4 × 10 iter → AUDIT row 추가 → PR
```

**핵심 원칙**: 각 distinct condition 은 4 형태 모두에서 정확히 1 회만 emit 되어야 한다 (F62 에서 검증한 dedup invariant). 더 emit 되면 amplification 버그.

## 7. Mac 환경 차이점

- 경로: `D:\` → `~/` 또는 `/tmp/` 로 모두 치환.
- 줄바꿈: 새 파일 작성 시 `\n` (LF) 사용 — git checkout 시 `core.autocrlf=input` 인지 확인 (`git config core.autocrlf`).
- BOM: F60 이 apply.ps1 단계에서 자동 정규화하지만, Mac 의 텍스트 에디터가 BOM 을 제거할 수 있으니 `xxd <file> | head -1` 로 확인 가능 (`efbbbf` prefix 가 BOM).
- 셸 스크립트 실행 권한: Mac 은 `chmod +x` 가 필요. apply.ps1 는 `$IsLinux` 만 체크하는데 Mac 도 `$IsMacOS` 가 true 가 됨 — round-7 첫 fix 후보로 `apply.ps1` 의 chmod 분기를 `($IsLinux -or $IsMacOS)` 로 확장 (round-3 F26 와 동일 패턴).
- pwsh 의 `Get-ChildItem` 은 Mac 에서도 작동. PowerShell 스크립트는 그대로 사용.
- `gh` CLI 정상 작동 (PR 생성, merge, 코멘트).
- `bash` 가 기본 4.x (구식 macOS) 이거나 5.x (Homebrew) — 어느 쪽이든 round-3 가 호환 (F32 에서 bash 3.2 호환성도 챙겼음).

## 8. 첫 턴 체크리스트 (Mac 도착 직후)

```bash
# A. 환경
pwsh --version          # 7.x 이상이어야 함
gh auth status          # logged in
git --version

# B. 레포 상태 확인
cd ~/autopilot-dad-template
git status              # clean working tree
git log --oneline -10
wc -l AUDIT.md          # 100+ 행 (round-6 closure 가 row 101)

# C. 4 형태 dogfood 빠른 생성 (없으면)
# (round-6 batch 3 의 dogfood-apply-all.ps1 와 dogfood-multi-iter.ps1 는 PR #90 머지 전에 삭제됐으므로
#  다시 작성해야 함. git log --all -- '*dogfood-*.ps1' 로 과거 내용 참조 가능)

# D. 사용자에게 진행 상황 한국어로 보고:
#    "Mac 환경 셋업 완료. AUDIT row XXX 에서 이어받음. 다음 작업으로 [F63 후보] 부터 착수합니다."
```

## 9. 운영 원칙 (요약)

- **Always**: PR 마다 4 형태 × 10 iter regression. 결과 표를 PR body 에 인용. AUDIT row 에 evidence 인용.
- **Never**: Unity / cardgame / playmode 같은 단어가 일반 가이드에 등장하면 PR 거부 (F59 패턴 재발).
- **Always**: dogfood 프로젝트는 `~/dogfood-{node,go,web,unity-mock}` — 4 가지 형태 모두 사용. 한 형태만 테스트하면 안 됨.
- **Never**: `D:\` 경로를 새 fix 에 박지 말 것. 운영자의 윈도우 경로는 hist 자료일 뿐.
- **Always**: 사용자가 "계속하라" 라고 하면 다음 deferred 항목 (위 §5) 중 가장 높은 우선순위 1 개를 자율 선택해 진행 후 결과 보고.
- **Never**: 사용자 승인 없이 force-push, git config 변경, 외부 시크릿 commit, main 직접 push.

## 10. 마지막 메모

이 핸드오프 자체도 round-7 의 F63 같은 fix 로 다듬을 가치가 있다. 처음 3-4 iter 돌려보고 위 내용 중 잘못된 부분 / 더 명확해야 하는 부분 발견하면, **HANDOFF-MAC.md 업데이트** 도 fix 순환의 일부로 포함하라.

행운을 빈다. Round-7 이 round-6 보다 더 보수적이고 universal 하길.

---

(이하 운영자가 윈도우에서 작업하던 컨텍스트 — Mac 에서는 직접 접근 불가, 단순 참고용)

- `D:\Unity\card game\.autopilot\` — round-3/4/5/6 의 incident 출처. AUDIT.md 행 79-90 에서 발췌 인용됨.
- `D:\cardgame-dad-relay\` — round-6 batch 1 의 R1-R8 출처. 위 §5 의 OUT OF SCOPE 항목들이 여기 내부.
- 두 repo 가 Mac 에 없으므로 추가 incident 데이터가 필요하면 운영자에게 paste 해달라고 요청.

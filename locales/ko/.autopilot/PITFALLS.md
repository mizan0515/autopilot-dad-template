# PITFALLS

반복 관찰된 함정. iter 시작 시 읽고, 새 함정 발견 시 append. 2회 이상 재발한 함정은 한 줄 엔트리로 기록한다. 이 시드는 다른 프로젝트에서 이미 물린 적 있는 지뢰만 적어둔 것이다.

## 시드 — 템플릿 작성자 (항상 적용)

- IMMUTABLE 블록을 `PROMPT.md` 에서 "정리" 명목으로 수정하지 말 것. pre-commit 훅이 막는다.
- DAD 세션 `turn-*.yaml` 원본 수정 금지 — 새 turn 파일 생성.
- `git log --since "1 week ago"` 같은 상대 날짜 쿼리 금지 — 해시 또는 절대 날짜 사용.
- `.archive/` 재귀 탐색 금지 — `INDEX.md` 한 줄 요약 먼저 읽고 필요 시 파일 하나만 pinpoint read.

## 시드 — 런타임 / 셸 지뢰 (다른 오토파일럿 루프에서 이미 관찰됨)

- **로컬라이즈 문자열에 광범위 regex 금지.** CJK · 액센트가 포함된 `.md`/`.json`/`.yaml` 파일 편집은 line-targeted (주변 맥락을 `old_string` 에 포함) 로만 한다. `sed -i s/X/Y/g` 나 여러 파일에 걸친 `Edit replace_all=true` 는 이미 다른 프로젝트에서 이웃 불릿을 조용히 깨뜨린 적 있다.
- **`doctor green` ≠ live-runtime-green.** preflight 가 exit 0 이어도 그건 바이너리가 "닿는다" 는 증거지 "응답한다" 는 증거가 아니다. 외부 브리지 (Unity MCP, Claude Preview, DB 등) 는 별도의 `preflight-runtime-bridge` 훅에서 실제 1-call health ping 을 쏘고 응답을 확인해야 하며, runtime-evidence 주장은 그 훅 exit 에 걸어야 한다.
- **워크트리-브리지 drift.** MCP 서버 · IDE 같은 장수 외부 도구는 이전 iter 의 워크트리 경로에 고정되어 있을 수 있다. 러너가 `<leaf>-autopilot-runner/live` 를 재사용해도 브리지는 여전히 옛 경로에 대해 말하고 있을 수 있다. 브리지가 보고하는 project path 가 현재 iter 워크트리와 일치하는지 먼저 확인한 뒤에만 그 출력을 신뢰한다.
- **PowerShell `Start-Process` 의 공백 포함 경로 인자 조용히 잘림.** `Start-Process foo.exe -ArgumentList "-projectPath","C:\My Path"` 는 공백 이후를 잘라먹는다. 반드시 단일 문자열로, 공백 토큰은 명시적 따옴표로 감싸서 전달한다. `base/tools/Start-Process-Safe.ps1` 를 래퍼로 쓴다.
- **subprocess 가 셸에서 launched 됐다는 것은 프로세스가 materialize 됐다는 뜻이 아니다.** `Start-Process` exit code 0 만으로는 타깃 프로세스가 살아있다는 보장이 없다. N 초 동안 process list 를 폴링해서 PID 가 등장하지 않으면 iter 를 실패 처리한다. 위 safe 래퍼가 이 로직을 갖고 있다.
- **기본 PowerShell UTF-16 / BOM 으로 인한 런타임 JSON 깨짐.** Windows PowerShell 의 `Out-File` · `>` 리다이렉트는 기본적으로 UTF-16-LE + BOM 이다. 비 ASCII 컨텐츠 (한국어/일본어/이모지) 를 `.autopilot/*.json`, `.autopilot/qa-evidence/*.json`, METRICS 라인에 적으면 다운스트림에서 mojibake 가 된다. `base/tools/Write-Utf8NoBom.ps1` / `.sh` 를 쓰거나 `[System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))` 로 명시한다.
- **iter 간 백그라운드 job 충돌.** 장수 에디터/데몬은 직전 iter 의 pending job 을 다음 iter 로 끌고 갈 수 있다. 새 iter 가 시작되기 전에 preflight 가 이들을 cancel/drain 해야 한다. 아니면 새 iter 의 첫 "success" 는 실은 직전 iter 결과일 수 있다.
- **로컬 워크트리가 브랜치를 pin 하고 있으면 `gh pr merge --delete-branch` 가 불완전하다.** 먼저 iter 경로에 대해 `git worktree remove` 를 강제하고 그 뒤에 `--delete-branch` 로 머지, 마지막에 `git fetch --prune`. `--delete-branch` 플래그 하나만 믿으면 origin 에 survivor ref 가 남는다.
- **post-merge 브랜치 삭제 scope 모호함.** post-merge cleanup 은 현재 iter 에서 HEAD 가 만들어진 브랜치만 auto-delete 해야 한다. `[gone]` 표시된 기존 브랜치는 METRICS 에 cleanup debt 로만 보고하고 operator 판단을 기다린다 — auto-delete 는 이미 데이터 유실 위험으로 보고된 적 있다.
- **테스트 필터 결과 0 건이 조용히 녹색으로 통과.** 많은 테스트 러너가 빈 필터 결과에 "성공" 을 돌려준다. `--filter X` 로 돌린 뒤 pass 를 보고할 땐 `matched_count > 0` 이고 요청한 집합과 실제 실행 집합이 일치하는지 반드시 assert. 그렇지 않으면 필터 오탈자가 all-green 으로 읽힌다.
- **`budget_exceeded` 신호 포화.** 매 iter 가 budget overrun 을 띄우면 그 플래그는 신호가 없다. 약 20 iter 의 관찰된 p75 를 기준으로 soft cap 을 재조정하고, `budget_exceeded` 는 원래 설계대로 드물고 큰 신호로 둔다.
- **METRICS.jsonl schema drift.** Tier 1 필드 (`ts` 포함) 는 매 줄 필수. 프로젝트 전용 확장은 `<project>_` prefix 를 붙여 relay 의 Tier-3 필드와 충돌하지 않게 한다. 검증은 `tools/Validate-Metrics.ps1` 를 배포한 저장소에서 수행.

## 프로젝트 추가분 (루프가 아래에 append)

# RTK — 셸 출력 압축 (선택)

RTK 는 시끄러운 셸 출력을 압축하는 **운영자 머신** CLI 프록시다. 프로젝트 의존성이 아니다 — 이 머신에 RTK 가 설치되어 있지 않으면 이 파일을 무시한다.

## 일반 설치 경로

- Windows: `C:\Users\<you>\.local\bin\rtk.exe`
- macOS / Linux: `~/.local/bin/rtk`

`rtk --version` 또는 `which rtk` 로 감지. 명령이 없으면 RTK 섹션 전체를 건너뛴다.

## 목적

RTK 는 셸 출력의 토큰 노이즈를 줄인다. 정확한 stdout 이 리뷰 대상이 아닐 때 사용한다.

이 프로젝트는 문서 validator, Git 훅, MCP 도구, 인코딩 체크, 대시보드 진단에도 의존한다. 이들은 raw 출력이 필요한 경우가 많아서 RTK 는 일괄 wrapper 가 아니다.

## RTK 사용

좋은 대상:

```
rtk git status --short --branch
rtk git diff --stat
rtk git diff --name-only
rtk git log --oneline -10
rtk rg -n "<term>" <search-root>
rtk rg --files <search-root>
rtk gh pr list --state open --limit 20
```

일반 용도:

- 넓은 `rg` 검색과 `rg --files`
- Git status, short log, diff 요약, name-only diff
- 결과가 간결해도 충분한 GitHub list/search 명령
- 실패 진단을 이미 확보한 뒤의 성공 대용량 테스트 출력

경로 한정 검색은 `.autopilot/config.json` → `search_roots` 에 선언된 명시적 루트를 우선한다.

## Raw 출력 사용

정확한 출력, 훅, 부작용이 중요하면 직접 실행 (또는 `rtk proxy <command>`):

- 변이 Git: `git add`, `git commit`, `git push`
- 소스 줄이 중요한 Git 체크: `git diff --check`, `git check-ignore -v`, `git ls-files --others -i --exclude-standard`
- 프로젝트 validator 와 훅: `tools\Validate-Documents.ps1`, `.githooks\pre-commit`
- autopilot 진단: `.autopilot\project.ps1 status`, `doctor`, `test`, `start`
- PowerShell cmdlets: `Get-Content`, `Get-ChildItem`, `Select-String`, `Format-Hex`, `Test-Path`
- 명시적 인코딩 / BOM / 현지화 텍스트 읽기/쓰기
- 대시보드 디버깅: `node`, `npx playwright`, 스크린샷 캡처
- 다운로드, 인스톨러, 패키지 설치, 인터랙티브 명령
- 전체 스택 트레이스가 필요한 실패 테스트 로그
- 바이너리, 이미지, 미디어, 아카이브, 생성 런타임 출력

RTK 는 MCP 도구, 파일 편집 도구, 이미지 도구, 웹 브라우징 도구에 적용되지 않는다.

## 실패 폴백

RTK 출력이 실패 원인을 가리면, 같은 명령을 직접 또는 `rtk proxy` 로 다시 돌린다.

압축된 출력만으로 commit 이나 push 하지 않는다. 결과가 중요하면 raw `git status --short --branch` 로 최종 staged / 브랜치 상태를 확인한다.

## 검증

```
rtk --version
rtk gain
rtk init --show
```

이 중 하나라도 실패하면 이 세션에서 RTK 를 건너뛰고 명령을 직접 실행한다.

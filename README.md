# autopilot-dad-template

자율 오토파일럿 + DAD(Dual-Agent Dialogue) 피어 협업 시스템 템플릿.
한 번의 프롬프트로 임의의 Git 프로젝트에 적용할 수 있도록 설계됨.

---

## Claude Code/Codex에게 주는 지시 (원-프롬프트 부트스트랩)

> 이 저장소의 템플릿을 현재 프로젝트에 적용해줘.
> 아래 순서를 정확히 따를 것:
>
> 1. 이 저장소(`https://github.com/mizan0515/autopilot-dad-template`)의 `apply.ps1`(Windows) 또는 `apply.sh`(macOS/Linux)를 현재 프로젝트 루트에서 실행한다.
>    - 이미 `.autopilot/` 폴더가 있으면 **덮어쓰지 말고** 차이만 추가 제안한다.
>    - 누락된 파일만 채워 넣고, 변경된 파일은 `.apply-conflicts/` 로 따로 저장한다.
> 2. 프로젝트 루트의 `.autopilot/PROMPT.md` 를 열어, 상단의 `<<PROJECT_NAME>>`, `<<PROJECT_DESCRIPTION>>`, `<<PRODUCT_DIRECTIVE>>` 플레이스홀더를 실제 값으로 채운다.
> 3. `.autopilot/BACKLOG.md` 의 시드 항목을 프로젝트 실제 첫 과제 1~3개로 교체한다.
> 4. `.autopilot/hooks/` 를 `git config core.hooksPath .autopilot/hooks` 로 등록한다.
> 5. 첫 iter는 **수동으로** Claude Code 데스크톱 앱에 `.autopilot/RUN.claude-code.md` 전체를 복붙해 실행한다. 자동 반복은 `ScheduleWakeup` 도구로 스스로 다음 턴을 예약한다.
> 6. Codex 데스크톱만 있다면 `.autopilot/RUN.codex-desktop.md` 전체를 복붙(반복 큐잉)한다.
> 7. 적용 후 `git status` 로 변경을 확인하고 `docs/autopilot-bootstrap.md` 에 현재 프로젝트의 `PROJECT_NAME`, `PRODUCT_DIRECTIVE` 를 기록한다.
> 8. **중단 조건**: 충돌이 5개 이상이면 자동 적용을 멈추고 운영자에게 보고한다.

상대방이 이 리포지토리의 URL과 위 지시만 받으면 프로젝트 종류(Unity/웹/CLI/라이브러리 등)와 무관하게 동일 오토파일럿 루프가 동작해야 한다.

---

## 포함된 것

```
.autopilot/
├── PROMPT.md                 # IMMUTABLE 블록 포함 보일러플레이트
├── RUN.claude-code.md        # Claude Code 데스크톱 복붙 + ScheduleWakeup
├── RUN.codex-desktop.md      # Codex 데스크톱 큐잉용 복붙
├── STATE.md                  # 연속성 저장 (세션 간 공유)
├── BACKLOG.md                # 시드 과제
├── HISTORY.md                # iter 로그
├── METRICS.jsonl             # iter별 메트릭 (빈 시드)
├── NEXT_DELAY                # 다음 대기 초 (기본 900)
├── runners/
│   ├── runner.ps1            # Windows 무한 루프
│   └── runner.sh             # macOS/Linux 무한 루프
└── hooks/
    ├── pre-commit            # IMMUTABLE 가드 진입점
    ├── protect.sh            # IMMUTABLE 블록 + cleanup trailer
    ├── protect.ps1           # Windows 동등물
    └── commit-msg*           # trailer 검증
apply.ps1                      # Windows 설치자
apply.sh                       # Unix 설치자
```

## 설계 원칙

- **Stateless prompt + stateful files**: 프롬프트는 `.autopilot/*` 를 읽어 상태를 복원
- **IMMUTABLE 가드**: `product-directive`, `core-contract`, `boot`, `budget`, `blast-radius`, `halt`, `exit-contract` 블록은 pre-commit 훅이 변경 거부
- **DAD 피어 대화**: `Document/dialogue/sessions/{session-id}/turn-*.yaml` 규약 (옵션)
- **Cross-platform**: Windows PowerShell + Unix bash 동등 구현
- **No GUI required**: 대시보드가 필요하면 별도 skill로 추가

## 라이선스

MIT

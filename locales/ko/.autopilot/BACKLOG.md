# BACKLOG

우선순위 높은 순. 선택된 항목은 `[active]` 마크.

## 시드 (iter 0 부트스트랩 — 이 항목을 먼저 실행)

- [ ] `[bootstrap]` 운영자의 `PRD.md` 를 읽고 실제 첫 3~5 개 과제를 이 BACKLOG 에 **교체해서** 작성한다. 이 bootstrap 항목 자체는 완료되면 제거.
  - 읽기: 저장소 루트의 `PRD.md` (경로는 `.autopilot/config.json` 의 `prd_path` 에 있다).
  - 출력: 이 "시드" 섹션 전체를 지우고 실제 과제 목록으로 교체한다. 각 항목은 한 iter (≤30분) 안에 끝낼 수 있는 vertical slice 여야 한다.
  - `HISTORY.md` 에 `iter 0 bootstrap: BACKLOG 초기화 완료` 한 줄 추가.
  - 이 iter 에서는 실제 코드 변경을 하지 않아도 된다. BACKLOG 재작성과 `STATE.md` Recent Context 갱신이 이번 iter 의 deliverable.
  - `PRD.md` 가 비어 있거나 placeholder (`# PRD` 한 줄뿐) 이면 `STATE.md` Known Blockers 에 "PRD missing — operator must fill in" 으로 에스컬레이션하고 iter 종료.

## 메모

- 항목 하나는 한 iter (≤30분) 안에 끝낼 수 있게 쪼갠다.
- `[active]` 로 선택하면 `STATE.md` Active Task 에 복제.
- 완료 후 BACKLOG 에서 제거하고 `HISTORY.md` 에 한 줄 기록.
- `[bootstrap]` 태그는 iter 0 전용. 이후 iter 에서는 나타나지 않아야 한다.

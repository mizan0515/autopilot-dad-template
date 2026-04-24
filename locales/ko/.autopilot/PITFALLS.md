# PITFALLS

반복 관찰된 함정. iter 시작 시 읽고, 새 함정 발견 시 append.

## 시드

- IMMUTABLE 블록을 PROMPT.md 에서 "정리" 명목으로 수정하지 말 것. pre-commit 훅이 막는다.
- DAD 세션 `turn-*.yaml` 원본 수정 금지 — 새 turn 파일 생성.
- `git log --since "1 week ago"` 같은 상대 날짜 쿼리 금지 — 해시 또는 절대 날짜 사용.
- `.archive/` 재귀 탐색 금지 — `INDEX.md` 한 줄 요약 먼저 읽고 필요 시 파일 하나만 pinpoint read.

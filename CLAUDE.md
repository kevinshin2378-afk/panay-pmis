# Claude Code / Codex 인수인계 — panay-pmis

작업을 시작할 때 먼저 읽는 현재 상태 문서입니다. 최종 갱신: 2026-09-30 (Asia/Seoul).

> **이 저장소는 공개(public)입니다.** 이 문서와 커밋 내용은 누구나 볼 수 있습니다. API 키, 비밀번호, 토큰, 서비스 키는 코드·문서·커밋 메시지 어디에도 적지 마세요.

## 교대 작업 규칙

- Claude Code와 GPT Codex가 **사용량 한도에 맞춰 번갈아** 수정합니다.
- 시작할 때: 이 문서와 `git log`, `git status`로 현재 상태를 확인하세요. 아래 "현재 상태"는 마지막 담당자의 스냅샷이므로 코드와 대조하세요.
- 멈출 때: 다음 담당자가 이어받을 수 있게 아래 **현재 상태**를 갱신하세요. 끝나지 않은 작업은 무엇이 남았는지 적으세요.
- 요청받은 변경만 구현하세요.

## 운영 환경 — 되돌리기 어려운 작업

- **`main`에 푸시하면 GitHub Pages로 즉시 운영에 반영됩니다.** 스테이징이 없습니다. 푸시는 팀장님이 명시적으로 지시했을 때만 하세요.
- **Supabase도 운영 환경 하나뿐입니다.** 스키마·데이터·RLS 정책 변경은 지시가 있을 때만 하세요. 마이그레이션은 `supabase/migrations/`에 SQL 파일로 작성하고, 실제 실행은 팀장님이 Supabase 대시보드 SQL Editor에서 합니다. 조회(SELECT)는 자유롭게 해도 됩니다.
- 브라우저 코드에는 **publishable 키만** 씁니다. service-role 키, DB 비밀번호, Google Drive 토큰은 절대 넣지 마세요.

## 구조

| 위치 | 역할 |
| --- | --- |
| `index.html` | 단일 페이지 앱 전체 (UI와 로직, 약 360 KB) |
| `js/pmis-backend.js` | Supabase 브라우저 클라이언트. `request()`는 JSON 전용이라 파일 업로드에는 별도 함수가 필요 |
| `supabase/migrations/20260908_security_central_data.sql` | 중앙 데이터 보안 스키마: RLS, `file_attachments`, 비공개 버킷 `pmis-private` 정책 |
| `docs/SECURITY_CENTRAL_DATA_DESIGN.md` | 보안 설계 문서 |
| `collaboration/claude-status.md` | 2026-09-17 작업 지시서 (파일 업로드, 디자인 개선) |
| `.claude/launch.json` | 로컬 미리보기 설정 (`pmis`) |

## 운영 정보

- 공개 URL: <https://kevinshin2378-afk.github.io/panay-pmis/>
- Supabase 프로젝트: `bqtgdufbigkbjdtdgeow` (Singapore, 운영)
- 인증: Supabase Auth 이메일 로그인. 2026-09-17 기준 실사용자는 관리자 1명이며, 예전 localStorage 계정은 Supabase로 옮겨지지 않았습니다.
- Supabase Auth 화면의 "Total: N users (estimated)"는 추정치입니다. 정확한 수는 `auth.users`를 직접 조회하세요.

## 로컬 확인

```powershell
npx serve -s . -l 3800
```

자동 테스트는 없습니다. 브라우저에서 해당 화면을 직접 열고, 콘솔 에러가 없는지 확인하세요. 로그인이 필요한 화면은 운영 Supabase에 연결되므로 데이터를 바꾸는 동작은 조심하세요.

## 현재 상태 (2026-09-30, Claude)

- `main`은 `origin/main`과 같습니다. 마지막 기능 커밋은 `c2b3afd` (비밀번호 재설정, 2026-09-09).
- `collaboration/claude-status.md`의 **작업 A (파일 업로드: Supabase Storage + Google Drive)** 와 **작업 B (디자인 부분 개선)** 는 **아직 착수 전**입니다. 코드에 `pmis-private`, `storage/v1`, `openAttachmentModal` 참조가 0건임을 확인했습니다.
- 그 문서 첫머리의 "Claude는 진단, Codex는 수정" 분담은 옛 규칙입니다. 지금은 위의 교대 규칙을 따릅니다.
- 작업 A-1 마이그레이션은 운영 스키마 변경이라 팀장님이 직접 실행해야 합니다. 코드 작업(A-2 이후)은 스키마가 적용된 뒤 검증할 수 있습니다.

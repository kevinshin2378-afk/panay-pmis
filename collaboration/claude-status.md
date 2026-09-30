# Claude → Codex 작업 지시서

작성: 2026-09-17 / 작성자: Claude (진단·검증 담당)
수행: Codex (코드 수정 담당)

팀 규칙: Claude는 진단·검증·기록, Codex는 코드 수정. 이 문서의 "변경 내용"을 Codex가 구현하고,
완료 후 Claude가 검증한다.

---

## 0. 팀장님 결정 사항

| 항목 | 결정 |
|---|---|
| 업로드 저장소 | **Supabase Storage + Google Drive 둘 다 지원** (탭별 선택) |
| 업로드 창 적용 범위 | **전 계열** — 문서 / 공정·현장 / 회계 / 협업 |
| 디자인 범위 | **부분 개선** — 기존 KS PMIS 색상·레이아웃 유지, 일관성과 반응형만 손봄 |

---

## 1. 진단 결과 (현재 상태)

### 1-1. Supabase Storage가 완비되어 있으나 코드가 전혀 쓰지 않음 ★핵심

- 버킷 `pmis-private` 가 실제 존재함 (비공개, 2026-09-08 생성). 라이브 DB에서 확인 완료.
- RLS 정책 3종이 이미 걸려 있음 (`supabase/migrations/20260908_security_central_data.sql:345-378`):
  - 읽기: 해당 프로젝트 멤버만
  - 업로드: `admin / manager / editor / staff`
  - 삭제: `admin / manager`
- 경로 규칙: `<project-uuid>/<파일명>` — 첫 폴더가 프로젝트 UUID여야 정책이 통과함.
- **그런데 `index.html` / `js/pmis-backend.js` 전체에 `pmis-private`, `storage/v1`, `storage.from`
  참조가 0건.** 즉 준비만 해두고 배선이 안 됐음.

### 1-2. 모든 업로드가 Google Drive OAuth로 감

- Deliverables (`index.html:5142-5187`), Webhard (`index.html:4558-4584`),
  Expenses Q2 (`index.html:1390-1410`) 가 `googleapis.com/upload/drive/v3/files` 직접 호출.
- 문제: PMIS 로그인과 별개로 Google 로그인을 또 해야 하고, 파일 권한이 PMIS 역할(RLS)과 분리됨.

### 1-3. 작동하지 않는 업로드 UI (껍데기)

| 위치 | 증상 |
|---|---|
| `index.html:3147-3167` Progress Photo 모달 | "Upload" 버튼이 `closeModal('modal-photo')`만 호출. 업로드 코드 자체가 없음 |
| `index.html:3044` | `.upload-area` div만 있고 `<input type="file">`도 onchange 핸들러도 없음 |
| `index.html:3215` Official Documents | 사용자가 Drive에 직접 올린 뒤 공유 링크를 수동 복붙하는 방식 |

### 1-4. 메타데이터 테이블의 제약 (스키마 변경 필요)

`public.file_attachments` (`...security_central_data.sql:103-115`)

```sql
object_path text not null check (object_path !~ '^https?://')   -- ① Drive URL 저장 불가
deliverable_id / issue_id 만 존재                                -- ② 다른 탭에 붙일 수 없음
check (num_nonnulls(deliverable_id, issue_id) <= 1)
```

- ① `http(s)://` 를 금지하므로 **Google Drive 링크를 넣을 수 없음.** "둘 다 지원" 결정과 충돌.
- ② 부모 키가 deliverable / issue 둘뿐이라 회계·협업·공정 탭에 첨부를 붙일 수 없음.

### 1-5. `PMISBackend.request()` 는 바이너리 업로드 불가

`js/pmis-backend.js:20-39` — `JSON.stringify(opts.body)` 를 무조건 태우고
`Content-Type: application/json` 을 강제함. 파일 업로드는 별도 함수가 필요함.

### 1-6. 대시보드 하드코딩

`index.html:498-585` — Overall Progress 17.44%, Workforce 48명, Documents 12건, 날씨 31°C가
전부 정적 HTML 문자열. 데이터 연동 없음.

---

## 2. 작업 A — 파일 업로드 (우선순위 1)

### A-1. 스키마 마이그레이션 (신규 파일)

새 파일: `supabase/migrations/20260917_file_attachments_extend.sql`

```sql
begin;

-- 저장소 종류 구분
create type public.attachment_storage as enum ('supabase', 'gdrive');

alter table public.file_attachments
  add column storage_kind public.attachment_storage not null default 'supabase',
  add column module text,
  add column record_ref text,
  add column external_url text;

-- Drive 링크는 external_url 에만, Storage 경로는 object_path 에만 들어가도록 분리
alter table public.file_attachments
  alter column object_path drop not null;

alter table public.file_attachments
  add constraint file_attachments_storage_shape check (
    (storage_kind = 'supabase' and object_path is not null and external_url is null)
    or
    (storage_kind = 'gdrive' and external_url is not null and object_path is null)
  );

-- 어느 탭에서 올린 파일인지
alter table public.file_attachments
  add constraint file_attachments_module_check check (
    module is null or module in (
      'deliverables','issues','documents','approval',
      'progress','workforce','photos',
      'invoicing','expenses','budget',
      'notice','schedule','webhard'
    )
  );

commit;
```

> 기존 `check (object_path !~ '^https?://')` 는 그대로 두면 됨 — Drive URL은 이제
> `external_url` 로 가므로 충돌하지 않는다.

**주의: 프로덕션 단일 환경이다. 이 SQL은 Codex가 실행하지 말고, 팀장님이 Supabase 대시보드
SQL Editor에서 직접 실행하도록 남길 것.** (Claude가 실행 전후 검증)

### A-2. 백엔드 클라이언트에 Storage 함수 추가

파일: `js/pmis-backend.js`

`request()` 는 건드리지 말고, 아래를 새로 추가한 뒤 `global.PMISBackend` 에 노출한다.

```js
async function uploadObject(projectId, file, token) {
  assertConfigured();
  const safe = file.name.replace(/[^\w.\-]/g, '_');
  const path = `${projectId}/${Date.now()}_${safe}`;
  const res = await fetch(`${config.url}/storage/v1/object/${encodeURI('pmis-private/' + path)}`, {
    method: 'POST',
    headers: {
      apikey: config.publishableKey,
      Authorization: `Bearer ${token}`,
      'Content-Type': file.type || 'application/octet-stream',
      'x-upsert': 'false',
    },
    body: file,
  });
  if (!res.ok) throw new Error(`업로드 실패 (${res.status})`);
  return { objectPath: path, name: file.name, size: file.size, type: file.type };
}

async function signedUrl(objectPath, token, expiresIn) {
  const res = await fetch(`${config.url}/storage/v1/object/sign/pmis-private/${encodeURI(objectPath)}`, {
    method: 'POST',
    headers: {
      apikey: config.publishableKey,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ expiresIn: expiresIn || 3600 }),
  });
  if (!res.ok) throw new Error(`서명 URL 발급 실패 (${res.status})`);
  const body = await res.json();
  return `${config.url}/storage/v1${body.signedURL}`;
}
```

추가로 `file_attachments` CRUD 3종 (`listAttachments(projectId, module, token)`,
`createAttachment(row, token)`, `deleteAttachment(id, token)`) 을 기존 `request()` 재사용으로 작성.

> 버킷이 **비공개**이므로 다운로드는 반드시 서명 URL을 거쳐야 한다. 공개 URL은 동작하지 않음.

### A-3. 공통 업로드 컴포넌트 (핵심 — 탭마다 복붙 금지)

`index.html` 스크립트 영역에 **재사용 컴포넌트 하나**를 만들고 각 탭은 호출만 한다.

```js
// module: 'expenses' | 'notice' | ... (A-1 의 허용 목록)
// recordRef: 특정 행에 붙일 때의 식별자, 없으면 탭 단위 첨부
function openAttachmentModal(module, recordRef) { ... }
```

요구사항:
- 모달 1개(`#modal-attachment`)를 **재사용**한다. 탭별로 모달을 새로 만들지 말 것.
- 저장소 선택 라디오: `Supabase (PMIS 내부)` / `Google Drive` — 기본값 Supabase.
- 드래그&드롭 + 클릭 선택 모두 지원. 기존 `.upload-area` 클래스(`index.html:341-343`) 재사용.
- 다중 파일, 파일별 진행 상태 표시.
- 업로드 후 `file_attachments` 에 행 생성 (`storage_kind`, `module`, `record_ref` 채움).
- 목록에서 다운로드(서명 URL) / 삭제(권한 있을 때만) 가능.
- 권한: `currentUser.role` 이 `viewer` 면 업로드·삭제 버튼 숨김 (RLS와 UI 일치시킬 것).

필요한 값은 이미 세션에 있음 — `currentUser.project.id` (프로젝트 UUID),
`currentUser.accessToken` (JWT), `currentUser.role`. (`index.html:3583-3588`)

### A-4. 탭별 적용 (13개 모듈)

각 페이지 헤더에 `📎 첨부파일` 버튼을 추가하고 `openAttachmentModal('<module>')` 을 연결한다.

| 계열 | 페이지 (id) | module 값 |
|---|---|---|
| 문서 | page-deliverables / page-issues / page-documents / page-approval | `deliverables` `issues` `documents` `approval` |
| 공정·현장 | page-progress / page-workforce / page-photos | `progress` `workforce` `photos` |
| 회계 | page-invoicing / page-expenses / page-budget | `invoicing` `expenses` `budget` |
| 협업 | page-notice / page-schedule / page-webhard | `notice` `schedule` `webhard` |

**같이 정리할 것:**
- `index.html:3147-3167` 사진 모달 — `closeModal()` 만 하던 Upload 버튼을 실제 업로드에 연결
  (module=`photos`). 이미지 미리보기는 기존 `showPhotoPreview()` 유지.
- `index.html:3044` — 죽은 `.upload-area` div 를 공통 컴포넌트 호출로 교체.
- 기존 Google Drive 업로드 코드(`index.html:4558-4584`, `5142-5187`, `1390-1410`)는
  **삭제하지 말고** 공통 컴포넌트의 'Google Drive' 분기로 흡수할 것. (둘 다 지원 결정)

---

## 3. 작업 B — 디자인 부분 개선 (우선순위 2)

기존 KS PMIS 색상 토큰(`index.html` `:root`, steel blue `#14649e` / red `#c8102e` / 노란 행
하이라이트 `#fff8d4`)과 사이드바 레이아웃은 **유지**한다.

1. **인라인 스타일 정리** — 버튼마다 `style="padding:6px 14px;border-radius:6px;..."` 가
   반복됨 (예: `index.html:542-543`, `856`, `2229`). 기존 `.btn` / `.btn-primary` /
   `.btn-outline` / `.btn-sm` 클래스가 이미 있으므로 그쪽으로 통일.
2. **카드/테이블/뱃지 일관성** — `.card`, `.stat-card`, `.card-badge` 의 여백·모서리·그림자를
   한 벌로 맞춤. 지금은 페이지마다 조금씩 다름.
3. **모바일 대응** — `:root` 미디어쿼리가 `--sidebar-w` 만 조정함. 좁은 화면에서 사이드바를
   접고(햄버거) 테이블은 가로 스크롤 컨테이너로 감쌀 것.
4. **대시보드 하드코딩 제거** (`index.html:498-585`) — 진행률·인력·문서 건수를 실제 데이터에서
   계산. 값이 없으면 `–` 와 "데이터 없음"을 보이고, 가짜 숫자를 남기지 말 것.
   날씨 위젯은 실 API 연동 전까지 정적임을 표시하거나 제거.

> 색상 대비(WCAG AA)를 깨지 않는 선에서 진행. `--text-muted: #6b7686` 이 흰 배경에서 경계선이라
> 더 밝게 만들지 말 것.

---

## 4. 검증 방법 (Codex 완료 후 Claude가 수행)

**A. 업로드**
1. 마이그레이션 적용 확인 — `select storage_kind, module, record_ref, external_url from
   public.file_attachments limit 1;` 가 에러 없이 돌 것.
2. `admin` 계정으로 탭별 업로드 → `storage.objects` 에 `<project-uuid>/...` 경로로 생성되는지 확인.
3. 서명 URL로 다운로드 성공, **서명 없는 공개 URL은 실패**해야 정상(버킷 비공개).
4. 권한 검증: `viewer` 역할 계정으로 업로드 시도 → RLS가 403으로 막아야 함.
   (테스트 계정이 아직 없음 — 아래 5번 참고)
5. Drive 분기 선택 시 `storage_kind='gdrive'`, `external_url` 채워지고 `object_path` 는 null.

**B. 디자인**
- 브라우저 1280 / 768 / 375 폭에서 레이아웃 깨짐 없는지 확인.
- 콘솔 에러 0건.
- 대시보드에 하드코딩된 17.44 / 48 / 12 문자열이 남아있지 않은지 grep.

---

## 5. 알려진 선행 조건 / 주의사항

- **프로덕션 단일 환경.** GitHub Pages 배포 = 즉시 운영 반영, Supabase도 PRODUCTION 하나뿐이다.
  스키마 변경·데이터 삭제는 팀장님 확인 후에만.
- **실사용자는 admin 1명뿐** (kevinshin2378@gmail.com). Auth 화면의 "Total: 10 users
  (estimated)" 는 Postgres 통계 추정치라 실제와 다름 — `auth.users` 직접 조회로 확인했음.
  따라서 위 검증 4번(viewer 권한 테스트)은 테스트 계정을 먼저 만들어야 가능하다.
- 레거시 localStorage 계정(`sean` 등)은 Supabase로 마이그레이션되지 않았다. 관련 잔재 코드가
  남아 있으면 이번 작업 중 발견 시 별도 보고할 것 (이번 스코프에서 제거하지는 말 것).
- `js/pmis-backend.js` 주석 규칙대로 **service-role 키 / DB 비밀번호 / Drive 토큰을 코드에
  넣지 말 것.** publishable 키만 사용한다.

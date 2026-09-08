-- PMIS central-data foundation for Supabase Postgres.
-- Run in a new Supabase project after reviewing organization-specific retention
-- and access requirements. This migration intentionally creates no users,
-- passwords, external OAuth tokens, or production data.

begin;

create extension if not exists pgcrypto;

create type public.app_role as enum (
  'admin', 'manager', 'accounting', 'staff', 'editor', 'viewer'
);

create type public.deliverable_status as enum (
  'not_started', 'in_progress', 'submitted', 'approved', 'returned'
);

create type public.issue_status as enum (
  'open', 'in_progress', 'complete', 'closed'
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 160),
  organization_name text,
  global_role public.app_role not null default 'viewer',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9_-]{2,40}$'),
  name text not null check (char_length(trim(name)) between 1 and 240),
  starts_on date,
  ends_on date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on is null or starts_on is null or ends_on >= starts_on)
);

create table public.project_members (
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.app_role not null default 'viewer',
  accounting_access boolean not null default false,
  added_at timestamptz not null default now(),
  primary key (project_id, user_id)
);

create table public.deliverables (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 500),
  category text,
  due_on date,
  status public.deliverable_status not null default 'not_started',
  remarks text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.deliverable_submissions (
  id uuid primary key default gen_random_uuid(),
  deliverable_id uuid not null references public.deliverables(id) on delete cascade,
  version_label text not null check (char_length(trim(version_label)) between 1 and 80),
  submitted_on date not null default current_date,
  letter_number text,
  status public.deliverable_status not null default 'submitted',
  notes text,
  submitted_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.issues (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 500),
  category text,
  status public.issue_status not null default 'open',
  direction text check (direction in ('incoming', 'outgoing', 'internal')),
  reference_number text,
  opened_on date not null default current_date,
  due_on date,
  owner_id uuid references public.profiles(id),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.issue_entries (
  id uuid primary key default gen_random_uuid(),
  issue_id uuid not null references public.issues(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 10000),
  status public.issue_status,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.file_attachments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  deliverable_id uuid references public.deliverables(id) on delete cascade,
  issue_id uuid references public.issues(id) on delete cascade,
  object_path text not null check (object_path !~ '^https?://'),
  file_name text not null check (char_length(trim(file_name)) between 1 and 512),
  content_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  check (num_nonnulls(deliverable_id, issue_id) <= 1)
);

create table public.s_curve_versions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  as_of_date date not null,
  label text not null check (char_length(trim(label)) between 1 and 100),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (project_id, as_of_date)
);

create table public.s_curve_points (
  version_id uuid not null references public.s_curve_versions(id) on delete cascade,
  period_date date not null,
  planned_percent numeric(5,2) check (planned_percent between 0 and 100),
  actual_percent numeric(5,2) check (actual_percent between 0 and 100),
  primary key (version_id, period_date)
);

create table public.expense_entries (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  expense_date date not null,
  category text not null check (char_length(trim(category)) between 1 and 120),
  description text,
  currency char(3) not null default 'PHP',
  amount numeric(16,2) not null check (amount >= 0),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  project_id uuid references public.projects(id) on delete set null,
  actor_id uuid references public.profiles(id) on delete set null,
  table_name text not null,
  record_id uuid,
  action text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  before_data jsonb,
  after_data jsonb,
  occurred_at timestamptz not null default now()
);

create index deliverables_project_due_idx on public.deliverables(project_id, due_on);
create index issues_project_status_idx on public.issues(project_id, status);
create index expenses_project_date_idx on public.expense_entries(project_id, expense_date);
create index audit_project_occurred_idx on public.audit_log(project_id, occurred_at desc);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.is_project_member(target_project uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.project_members
    where project_id = target_project and user_id = auth.uid()
  );
$$;

create or replace function public.has_project_role(
  target_project uuid,
  permitted_roles public.app_role[],
  needs_accounting boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.project_members
    where project_id = target_project
      and user_id = auth.uid()
      and role = any(permitted_roles)
      and (not needs_accounting or accounting_access)
  );
$$;

create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  record_project uuid;
  record_id uuid;
begin
  record_project := coalesce(new.project_id, old.project_id);
  record_id := coalesce(new.id, old.id);
  insert into public.audit_log (project_id, actor_id, table_name, record_id, action, before_data, after_data)
  values (
    record_project, auth.uid(), tg_table_name, record_id, tg_op,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$$;

create trigger deliverables_touch before update on public.deliverables
for each row execute function public.touch_updated_at();
create trigger issues_touch before update on public.issues
for each row execute function public.touch_updated_at();
create trigger expenses_touch before update on public.expense_entries
for each row execute function public.touch_updated_at();

create trigger deliverables_audit after insert or update or delete on public.deliverables
for each row execute function public.write_audit_log();
create trigger issues_audit after insert or update or delete on public.issues
for each row execute function public.write_audit_log();
create trigger expenses_audit after insert or update or delete on public.expense_entries
for each row execute function public.write_audit_log();

alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.project_members enable row level security;
alter table public.deliverables enable row level security;
alter table public.deliverable_submissions enable row level security;
alter table public.issues enable row level security;
alter table public.issue_entries enable row level security;
alter table public.file_attachments enable row level security;
alter table public.s_curve_versions enable row level security;
alter table public.s_curve_points enable row level security;
alter table public.expense_entries enable row level security;
alter table public.audit_log enable row level security;

create policy "profiles: read own" on public.profiles
for select using (id = auth.uid());

create policy "projects: read for members" on public.projects
for select using (public.is_project_member(id));

create policy "members: read own project" on public.project_members
for select using (public.is_project_member(project_id));

create policy "deliverables: read for members" on public.deliverables
for select using (public.is_project_member(project_id));
create policy "deliverables: edit for delivery roles" on public.deliverables
for all using (public.has_project_role(project_id, array['admin','manager','editor']::public.app_role[]))
with check (public.has_project_role(project_id, array['admin','manager','editor']::public.app_role[]));

create policy "submissions: read for members" on public.deliverable_submissions
for select using (
  exists (select 1 from public.deliverables d where d.id = deliverable_id and public.is_project_member(d.project_id))
);
create policy "submissions: add for delivery roles" on public.deliverable_submissions
for insert with check (
  submitted_by = auth.uid() and exists (
    select 1 from public.deliverables d
    where d.id = deliverable_id
      and public.has_project_role(d.project_id, array['admin','manager','editor','staff']::public.app_role[])
  )
);

create policy "issues: read for members" on public.issues
for select using (public.is_project_member(project_id));
create policy "issues: edit for project roles" on public.issues
for all using (public.has_project_role(project_id, array['admin','manager','editor','staff']::public.app_role[]))
with check (public.has_project_role(project_id, array['admin','manager','editor','staff']::public.app_role[]));

create policy "issue entries: read for members" on public.issue_entries
for select using (
  exists (select 1 from public.issues i where i.id = issue_id and public.is_project_member(i.project_id))
);
create policy "issue entries: add as self" on public.issue_entries
for insert with check (
  created_by = auth.uid() and exists (
    select 1 from public.issues i
    where i.id = issue_id
      and public.has_project_role(i.project_id, array['admin','manager','editor','staff']::public.app_role[])
  )
);

create policy "attachments: read for members" on public.file_attachments
for select using (public.is_project_member(project_id));
create policy "attachments: add for project roles" on public.file_attachments
for insert with check (
  created_by = auth.uid()
  and public.has_project_role(project_id, array['admin','manager','editor','staff']::public.app_role[])
);

create policy "s curve: read for members" on public.s_curve_versions
for select using (public.is_project_member(project_id));
create policy "s curve: edit for managers" on public.s_curve_versions
for all using (public.has_project_role(project_id, array['admin','manager','editor']::public.app_role[]))
with check (public.has_project_role(project_id, array['admin','manager','editor']::public.app_role[]));
create policy "s curve points: read for members" on public.s_curve_points
for select using (
  exists (select 1 from public.s_curve_versions v where v.id = version_id and public.is_project_member(v.project_id))
);
create policy "s curve points: edit for managers" on public.s_curve_points
for all using (
  exists (select 1 from public.s_curve_versions v
    where v.id = version_id
      and public.has_project_role(v.project_id, array['admin','manager','editor']::public.app_role[]))
)
with check (
  exists (select 1 from public.s_curve_versions v
    where v.id = version_id
      and public.has_project_role(v.project_id, array['admin','manager','editor']::public.app_role[]))
);

create policy "expenses: read for accounting" on public.expense_entries
for select using (public.has_project_role(project_id, array['admin','manager','accounting']::public.app_role[], true));
create policy "expenses: edit for accounting" on public.expense_entries
for all using (public.has_project_role(project_id, array['admin','manager','accounting']::public.app_role[], true))
with check (public.has_project_role(project_id, array['admin','manager','accounting']::public.app_role[], true));

create policy "audit: read for managers" on public.audit_log
for select using (public.has_project_role(project_id, array['admin','manager']::public.app_role[]));

-- All uploaded PMIS objects must be stored at <project-uuid>/<generated-name>.
-- The bucket is private; access is evaluated against the folder's project ID.
insert into storage.buckets (id, name, public)
values ('pmis-private', 'pmis-private', false)
on conflict (id) do update set public = false;

create policy "pmis files: read for project members" on storage.objects
for select using (
  bucket_id = 'pmis-private'
  and exists (
    select 1 from public.projects p
    where p.id::text = (storage.foldername(name))[1]
      and public.is_project_member(p.id)
  )
);

create policy "pmis files: add for project contributors" on storage.objects
for insert with check (
  bucket_id = 'pmis-private'
  and exists (
    select 1 from public.projects p
    where p.id::text = (storage.foldername(name))[1]
      and public.has_project_role(p.id, array['admin','manager','editor','staff']::public.app_role[])
  )
);

create policy "pmis files: remove for managers" on storage.objects
for delete using (
  bucket_id = 'pmis-private'
  and exists (
    select 1 from public.projects p
    where p.id::text = (storage.foldername(name))[1]
      and public.has_project_role(p.id, array['admin','manager']::public.app_role[])
  )
);

-- Browser clients cannot insert, update, or delete profiles, projects,
-- memberships, or audit rows by direct policy.  Provision those through an
-- authenticated server-side admin workflow. File-object access is limited by
-- the project-folder policies above.

commit;

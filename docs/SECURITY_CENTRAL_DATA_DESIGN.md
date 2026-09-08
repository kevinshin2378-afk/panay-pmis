# PMIS security and central-data foundation

## Purpose

Replace the current browser-only identity and `localStorage` data model with a
shared, auditable system without requiring the public PMIS front end to hold a
password database or a privileged Google Drive token.

## Target architecture

```text
GitHub Pages UI
      |
      | Supabase Auth (session only; no application passwords in the page)
      v
Supabase Postgres + Row Level Security
      |                    |
      |                    +-- audit trail / role checks
      v
Supabase Storage or backend-mediated Google Drive integration
```

The public web page may keep serving from GitHub Pages.  The authoritative
identity, authorization rules, and operational data move to a Supabase project.
The browser receives only the public project URL and anon key.  Service-role
credentials, Google OAuth refresh tokens, and Drive API keys must remain in a
server-side Edge Function or deployment secret store.

## Security decisions

1. **Replace client-side login.** The existing browser-side user list and
   reversible password encoding are not a security boundary.  The migration
   must use Supabase Auth invitations or a reset-password flow; legacy passwords
   are not migrated.
2. **Enforce access in the database.** Each operational record belongs to a
   project.  Row Level Security permits a signed-in user to read only projects
   they are a member of, and restricts writes by their per-project role.
3. **Use least privilege for files.** Do not request full Google Drive access
   from every browser.  New PMIS files should use a private storage bucket with
   signed downloads, or a backend-owned Drive integration limited to the
   project folder.
4. **Make changes traceable.** A database trigger records changes to critical
   business tables.  Audit records cannot be edited by browser clients.
5. **Separate configuration from code.** Supabase URL and anon key are runtime
   configuration; all secret values stay out of Git and GitHub Pages.

## Data ownership

| Domain | Authoritative store | Notes |
| --- | --- | --- |
| User identity / sessions | Supabase Auth | Invite or reset flow; no seeded passwords |
| Project membership / role | `profiles`, `project_members` | Only server-side administration changes roles |
| Deliverables / submissions | Postgres | Submission history is append-only in normal UI flows |
| Issues / entries / attachments | Postgres + private file storage | Attachments store metadata and object path, not public access tokens |
| Progress S-curve | Postgres | Snapshot and points are versioned by project |
| Expenses / settlements | Postgres | Accessible only to accounting-authorized project members |
| Audit trail | Postgres | Browser clients can read only records within their projects |

## Delivery sequence

1. Create a Supabase project and obtain only its public URL/anon key for the
   front end.  Keep the service-role key in the host secret store.
2. Run the SQL migration in `supabase/migrations/20260908_security_central_data.sql`.
3. Create the Panay–Agusan project and invite existing users.  Do not copy the
   legacy password list.
4. Add a feature-flagged API adapter to the PMIS UI.  Migrate one domain at a
   time: deliverables, issues, S-curve, then accounting.
5. Validate role scenarios with separate test accounts, export a legacy
   `localStorage` backup for record retention, and only then remove the legacy
   client-side credential code.

## Claude / Codex split

| Owner | Isolated scope |
| --- | --- |
| Codex | Database schema, RLS, audit model, authentication/API adapter, security tests |
| Claude | UI component extraction, responsive layout, workflow screens, accessibility |
| Joint integration | API contract, role-based visibility, acceptance tests, deployment checklist |

No production deployment, user invitation, OAuth consent, credential rotation,
or Drive file migration is included in this branch.  Those steps require a
project owner to perform or explicitly authorize them.

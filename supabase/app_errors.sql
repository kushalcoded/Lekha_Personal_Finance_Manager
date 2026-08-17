-- Crash reports. Run once in the Supabase SQL editor; re-runnable.
--
-- Insert-only by design: a client may file a report and can never read one
-- back, so nobody's stack traces are visible to anyone but the project owner
-- in the dashboard. `create policy` is not idempotent and the editor runs one
-- transaction, so each policy is dropped first — without that a re-run dies on
-- 42710 and *nothing* commits.

create table if not exists public.app_errors (
  id          bigint generated always as identity primary key,
  user_id     uuid references auth.users (id) on delete set null,
  version     text,
  platform    text,
  message     text not null,
  stack       text,
  created_at  timestamptz not null default now()
);

create index if not exists app_errors_created_at_idx
  on public.app_errors (created_at desc);

alter table public.app_errors enable row level security;

drop policy if exists "Anyone signed in can file a report" on public.app_errors;
create policy "Anyone signed in can file a report"
  on public.app_errors
  for insert
  to authenticated
  with check (user_id is null or auth.uid() = user_id);

-- Reports age out; nobody needs a crash from four months ago.
-- Run occasionally, or schedule with pg_cron if it's ever worth it:
--   delete from public.app_errors where created_at < now() - interval '90 days';

-- SAMMI E-Library — Supabase schema v2
-- Real server-authenticated librarian access (Supabase Auth + Row Level Security)
--
-- Run this in your Supabase project's SQL Editor. Safe to re-run any time.

-- ============================================================
-- 1) LIBRARIANS — the real allowlist, created first since the other
--    tables' policies reference it. A Supabase Auth account only gets
--    librarian powers if their user id appears in this table. You
--    manage this table yourself from the SQL Editor (see the setup
--    guide) — there is no public write access to it.
-- ============================================================
create table if not exists librarians (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  added_at timestamptz default now()
);

alter table librarians enable row level security;

drop policy if exists "librarian read librarians" on librarians;
create policy "librarian read librarians"
  on librarians for select
  using (auth.uid() in (select user_id from librarians));
-- No insert/update/delete policy is defined on purpose — manage this
-- table only from the SQL Editor / Table Editor as the project owner.

-- ============================================================
-- 2) BOOKS — the shared library catalog students browse.
--    Everyone can read it. Only signed-in librarians can write to it.
-- ============================================================
create table if not exists books (
  "__backendId" text primary key,
  title text,
  author text,
  category text,
  status text,
  rating int,
  notes text,
  added_at text
);

alter table books enable row level security;

drop policy if exists "public read books" on books;
drop policy if exists "librarian insert books" on books;
drop policy if exists "librarian update books" on books;
drop policy if exists "librarian delete books" on books;

create policy "public read books"
  on books for select using (true);

create policy "librarian insert books"
  on books for insert
  with check (auth.uid() in (select user_id from librarians));

create policy "librarian update books"
  on books for update
  using (auth.uid() in (select user_id from librarians));

create policy "librarian delete books"
  on books for delete
  using (auth.uid() in (select user_id from librarians));

-- ============================================================
-- 3) LOGIN LOGS — kept private. Students can write their own login
--    record, but only librarians can read the log.
-- ============================================================
create table if not exists login_logs (
  id bigint generated always as identity primary key,
  lrn text,
  login_timestamp text,
  login_date text,
  login_time text
);

alter table login_logs enable row level security;

drop policy if exists "public insert login_logs" on login_logs;
drop policy if exists "librarian read login_logs" on login_logs;

create policy "public insert login_logs"
  on login_logs for insert with check (true);

create policy "librarian read login_logs"
  on login_logs for select
  using (auth.uid() in (select user_id from librarians));

-- ============================================================
-- 4) RESOURCE CLICKS — usage tracking (only librarians can read it,
--    matching the login log's privacy model)
-- ============================================================
create table if not exists resource_clicks (
  id bigint generated always as identity primary key,
  lrn text,
  resource_name text,
  resource_url text,
  clicked_at timestamptz default now()
);

alter table resource_clicks enable row level security;

drop policy if exists "public insert resource_clicks" on resource_clicks;
drop policy if exists "public read resource_clicks" on resource_clicks;
drop policy if exists "librarian read resource_clicks" on resource_clicks;

create policy "public insert resource_clicks"
  on resource_clicks for insert with check (true);

create policy "librarian read resource_clicks"
  on resource_clicks for select
  using (auth.uid() in (select user_id from librarians));

-- ============================================================
-- 5) OPTIONAL CLEANUP — if you ran the earlier v1 script, you now
--    have an old "library_data" table that's no longer used by the
--    site. It's harmless to leave it, but you can drop it once you've
--    confirmed everything above works:
-- ============================================================
-- drop table if exists library_data;

-- ============================================================
-- 6) CATALOGING & CIRCULATION UPGRADE
--    Adds ISBN/shelf/copy-count fields to books, and a circulation
--    table to track who has borrowed what and when it's due back.
--    Circulation stays librarian-only (it contains student LRNs).
-- ============================================================
alter table books add column if not exists isbn text;
alter table books add column if not exists shelf_location text;
alter table books add column if not exists total_copies int default 1;
alter table books add column if not exists available_copies int default 1;
alter table books add column if not exists cover_url text;

create table if not exists circulation (
  id bigint generated always as identity primary key,
  book_id text references books("__backendId") on delete cascade,
  lrn text not null,
  checked_out_at timestamptz default now(),
  due_date date,
  returned_at timestamptz
);

alter table circulation enable row level security;

drop policy if exists "librarian manage circulation" on circulation;
create policy "librarian manage circulation"
  on circulation for all
  using (auth.uid() in (select user_id from librarians))
  with check (auth.uid() in (select user_id from librarians));

-- One-time fix for any books added before this upgrade: assume all
-- existing copies are on the shelf (available = total).
update books set available_copies = total_copies where available_copies is null;

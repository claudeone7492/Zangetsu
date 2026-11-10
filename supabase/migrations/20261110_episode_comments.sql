-- Episode comments: a per-episode discussion thread anyone can read, signed-in
-- users write. Comments are scoped to (source_id, show_id, episode_id) — the
-- same triple the player uses to identify an episode — so a thread follows the
-- episode across devices and never mixes two sources' episodes.
--
-- Reads are public (a signed-out viewer can still read a thread); writes are
-- strictly own-row. The author's display name is copied in at insert time so a
-- thread renders without joining viewer_profiles, and survives a later rename
-- as "what they were called then" — the same denormalization mylist/history do.

create table if not exists public.episode_comments (
  id uuid primary key default gen_random_uuid(),
  user_key text not null,
  source_id text not null,
  show_id text not null,
  episode_id text not null,
  display_name text not null default '',
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  edited boolean not null default false,
  created_at bigint not null default 0,
  updated_at bigint not null default 0
);

-- One thread read is always "this episode, newest first" and one write is always
-- "this episode" — both covered by a single composite index.
create index if not exists episode_comments_thread_idx
  on public.episode_comments (source_id, show_id, episode_id, created_at desc);

alter table public.episode_comments enable row level security;

-- Public read: comments are a shared thread, not private data.
drop policy if exists episode_comments_read on public.episode_comments;
create policy episode_comments_read on public.episode_comments
  for select using (true);

-- Write own rows only.
drop policy if exists episode_comments_insert on public.episode_comments;
create policy episode_comments_insert on public.episode_comments
  for insert with check (user_key = auth.uid()::text);

drop policy if exists episode_comments_update on public.episode_comments;
create policy episode_comments_update on public.episode_comments
  for update using (user_key = auth.uid()::text)
  with check (user_key = auth.uid()::text);

drop policy if exists episode_comments_delete on public.episode_comments;
create policy episode_comments_delete on public.episode_comments
  for delete using (user_key = auth.uid()::text);

-- Realtime: an open thread subscribes to postgres_changes filtered by episode.
-- The table MUST be in the publication or that binding errors and takes the
-- whole channel down. REPLICA IDENTITY FULL makes UPDATE/DELETE events carry
-- the complete row so the client can reconcile without a refetch.
alter publication supabase_realtime add table public.episode_comments;
alter table public.episode_comments replica identity full;

-- ============================================================================
-- SOUND BOARD — Phase 4 migration: Real Roles, Sessions, Bookings shape
-- ============================================================================
-- Run this AFTER schema.sql, phase2_analytics_and_management.sql, and
-- phase3_storage.sql. Additive/idempotent — safe to re-run.
--
-- This migration:
--   1. Replaces the old ('musician','studio_owner','admin') role values with
--      the ones actually requested: 'user', 'studio_owner', 'founder'.
--   2. Auto-assigns 'founder' to khannaadhrit@gmail.com — both going
--      forward (via the signup trigger) AND retroactively if that profile
--      already exists.
--   3. Adds updated_at auto-touch on profiles.
--   4. Changes bookings to use a single time_slot text field (e.g. "13:00")
--      instead of start_time/end_time — matches what the frontend already
--      stores, and is simpler for the founder/owner-facing RPCs to read.
--   5. Locks down role changes: nobody can grant themselves a new role
--      through a normal profile update, even though they can still edit
--      their own name/avatar. Only admin_update_user_role() (founder-only)
--      can change a role.
--   6. Adds the RPCs the Founder Dashboard's new User Management section
--      calls: admin_list_users, admin_search_users, admin_update_user_role.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ROLE VALUES
-- ----------------------------------------------------------------------------
alter table public.profiles drop constraint if exists profiles_role_check;

-- Map old values onto the new vocabulary before applying the new
-- constraint (safe no-op if this is a fresh install with no rows yet).
update public.profiles set role = 'user' where role = 'musician';
update public.profiles set role = 'founder' where role = 'admin';

alter table public.profiles
  add constraint profiles_role_check check (role in ('user', 'studio_owner', 'founder'));

alter table public.profiles alter column role set default 'user';

-- ----------------------------------------------------------------------------
-- 2. FOUNDER AUTO-ASSIGNMENT
-- ----------------------------------------------------------------------------
-- Retroactive: if that profile already exists from before this migration.
update public.profiles set role = 'founder' where email = 'khannaadhrit@gmail.com';

-- Going forward: the signup trigger checks this on every new profile.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, given_name, avatar_url, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    new.raw_user_meta_data->>'given_name',
    coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture'),
    case when new.email = 'khannaadhrit@gmail.com' then 'founder' else 'user' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. updated_at AUTO-TOUCH
-- ----------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------------------------
-- 4. BOOKINGS: time_slot instead of start_time/end_time
-- ----------------------------------------------------------------------------
alter table public.bookings add column if not exists time_slot text;

-- Backfill from the old start_time column if it exists and has data, so
-- this is safe to run even if you already have bookings from Phase 1-3.
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='bookings' and column_name='start_time') then
    update public.bookings set time_slot = to_char(start_time, 'HH24:MI') where time_slot is null and start_time is not null;
  end if;
end $$;

alter table public.bookings alter column time_slot set not null;
alter table public.bookings drop column if exists start_time;
alter table public.bookings drop column if exists end_time;

-- Peak-hours RPC updated to read time_slot text instead of the dropped
-- start_time column.
create or replace function public.studio_peak_hours(p_studio_id uuid)
returns table (hour_of_day int, bookings_count bigint)
language sql
security definer set search_path = public
stable
as $$
  select split_part(time_slot, ':', 1)::int as hour_of_day, count(*) as bookings_count
  from public.bookings
  where studio_id = p_studio_id and status in ('confirmed', 'completed')
  group by hour_of_day
  order by hour_of_day;
$$;

-- ----------------------------------------------------------------------------
-- 5. LOCK DOWN ROLE CHANGES
-- A normal self-update (editing your own name/avatar) must NOT be able to
-- smuggle in a role change. Founders can still change anything about their
-- own row directly; everyone else's `with check` requires role to stay
-- exactly what it already was.
-- ----------------------------------------------------------------------------
drop policy if exists "profiles: self update" on public.profiles;
create policy "profiles: self update" on public.profiles
  for update using (id = auth.uid())
  with check (
    id = auth.uid()
    and (
      public.is_admin()
      or role = (select p.role from public.profiles p where p.id = auth.uid())
    )
  );

-- ----------------------------------------------------------------------------
-- 6. FOUNDER DASHBOARD — User Management RPCs
-- Note: public.is_admin() already checks role = 'founder' (defined in
-- schema.sql) — kept that function name so every existing admin_* RPC from
-- Phase 1/2 keeps working unchanged. "founder" is this app's term for that
-- platform-owner role.
-- ----------------------------------------------------------------------------
create or replace function public.admin_list_users(p_limit int default 50, p_offset int default 0)
returns table (id uuid, email text, full_name text, role text, created_at timestamptz)
language sql
security definer set search_path = public
stable
as $$
  select p.id, p.email, p.full_name, p.role, p.created_at
  from public.profiles p
  where public.is_admin()
  order by p.created_at desc
  limit p_limit offset p_offset;
$$;

create or replace function public.admin_search_users(p_query text)
returns table (id uuid, email text, full_name text, role text, created_at timestamptz)
language sql
security definer set search_path = public
stable
as $$
  select p.id, p.email, p.full_name, p.role, p.created_at
  from public.profiles p
  where public.is_admin()
    and (p.email ilike '%' || p_query || '%' or p.full_name ilike '%' || p_query || '%')
  order by p.created_at desc
  limit 50;
$$;

create or replace function public.admin_update_user_role(p_user_id uuid, p_new_role text)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only founders can change user roles.';
  end if;
  if p_new_role not in ('user', 'studio_owner', 'founder') then
    raise exception 'Invalid role: %', p_new_role;
  end if;
  update public.profiles set role = p_new_role where id = p_user_id;
end;
$$;

-- ============================================================================
-- Done. See PHASE4_DEPLOY.md for the client-side wiring this connects to
-- and the Vercel environment variable / build setup.
-- ============================================================================

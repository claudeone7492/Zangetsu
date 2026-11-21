-- =============================================================================
-- Zangetsu subscription — device seats
-- Target: Sophie project (ref lmjeickcvynwqsvustwq)
--
-- The plans have always advertised "1 device" / "2 devices" / "4 devices" in
-- their features, but entitlement was resolved one fingerprint at a time, so a
-- second device could never join a plan it was paying for.
--
-- A seat is a second fingerprint that resolves to the SAME subscription.
-- device_entitlement follows one hop from a seat to its owner, so the seat's
-- access is derived, not copied: when the owner's period lapses, renews or is
-- refunded, every seat follows immediately. Nothing has to be kept in sync and
-- a revoked seat loses access at its next check.
--
-- Additive only: no existing table, column or function is dropped. The one
-- function replaced (device_entitlement) keeps its exact signature and OUT
-- columns, so identify_device and the app are untouched.
--
-- Apply with `supabase db push`, or paste into the SQL editor. Safe to re-run.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. How many devices each plan may hold. The features array stays display
--    copy; this is the number the server enforces.
-- ---------------------------------------------------------------------------
alter table public.subscription_plans
  add column if not exists device_limit int not null default 1;

update public.subscription_plans set device_limit = 1 where key = 'stream_basic';
update public.subscription_plans set device_limit = 2 where key = 'stream_standard';
update public.subscription_plans set device_limit = 4 where key = 'stream_premium';

-- ---------------------------------------------------------------------------
-- 2. Seats and the short-lived codes that create them.
-- ---------------------------------------------------------------------------
create table if not exists public.device_seats (
  fingerprint       text primary key
    references public.devices(fingerprint) on delete cascade,
  owner_fingerprint text not null
    references public.devices(fingerprint) on delete cascade,
  label             text,
  added_at          timestamptz not null default now(),
  constraint device_seats_not_self check (fingerprint <> owner_fingerprint)
);

create index if not exists device_seats_owner_idx
  on public.device_seats (owner_fingerprint);

create table if not exists public.device_link_codes (
  code              text primary key,
  owner_fingerprint text not null
    references public.devices(fingerprint) on delete cascade,
  expires_at        timestamptz not null,
  used_at           timestamptz,
  used_by           text,
  created_at        timestamptz not null default now()
);

create index if not exists device_link_codes_owner_idx
  on public.device_link_codes (owner_fingerprint);

-- Failed claims, so an 8-character code cannot be brute-forced by a script.
create table if not exists public.device_link_attempts (
  id          bigserial primary key,
  fingerprint text not null,
  at          timestamptz not null default now()
);

create index if not exists device_link_attempts_fp_idx
  on public.device_link_attempts (fingerprint, at desc);

alter table public.device_seats         enable row level security;
alter table public.device_link_codes    enable row level security;
alter table public.device_link_attempts enable row level security;

do $$ begin
  create policy admin_all_device_seats on public.device_seats
    for all to service_role using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy admin_all_device_codes on public.device_link_codes
    for all to service_role using (true) with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy admin_all_device_attempts on public.device_link_attempts
    for all to service_role using (true) with check (true);
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 3. device_entitlement — a seat is entitled exactly as long as its owner.
--
-- Same signature and OUT columns as 0006_trial_and_entitlement.sql, so
-- identify_device (and therefore the app) needs no change. The trial flag
-- stays the device's own: joining a plan neither burns the seat's trial nor
-- revives the owner's.
-- ---------------------------------------------------------------------------
create or replace function public.device_entitlement(p_fingerprint text)
returns table (
  entitled boolean,
  show_paywall boolean,
  trial_available boolean,
  trial_used boolean,
  status text,
  plan_key text,
  period_end timestamptz,
  days_left int
)
language plpgsql security definer set search_path = public as $$
declare
  v_owner text;
  v_effective text;
  v_session uuid;
  v_trial_used timestamptz;
  v_sub subscriptions%rowtype;
  v_plan subscription_plans%rowtype;
  v_grace int := 3;
  v_entitled boolean := false;
  v_status text := 'none';
begin
  if p_fingerprint is null or length(p_fingerprint) < 8 then
    raise exception 'invalid fingerprint';
  end if;

  select s.owner_fingerprint into v_owner
  from device_seats s where s.fingerprint = p_fingerprint;

  v_effective := coalesce(v_owner, p_fingerprint);

  select d.session_id into v_session
  from devices d where d.fingerprint = v_effective;

  select d.trial_used_at into v_trial_used
  from devices d where d.fingerprint = p_fingerprint;

  if v_session is not null then
    select * into v_sub from subscriptions s
    where s.subscriber_session_id = v_session
    order by s.started_at desc limit 1;

    if found then
      select * into v_plan from subscription_plans where key = v_sub.plan_key;
      v_grace := coalesce(v_plan.grace_days, 3);
      v_status := v_sub.status;

      v_entitled := v_sub.status in ('active', 'trial', 'grace')
        and now() <= (
          v_sub.current_period_end
          + case when v_sub.auto_renew
                 then make_interval(days => v_grace)
                 else interval '0' end
        );
    end if;
  end if;

  return query select
    v_entitled,
    (not v_entitled),
    (v_trial_used is null and not v_entitled),
    (v_trial_used is not null),
    v_status,
    v_sub.plan_key,
    v_sub.current_period_end,
    case
      when v_entitled and v_sub.current_period_end is not null
        then greatest(0, ceil(extract(epoch from (v_sub.current_period_end - now())) / 86400)::int)
      else 0
    end;
end $$;

-- ---------------------------------------------------------------------------
-- 4. create_device_code — the paying device mints a short code to hand over.
--
-- Returns jsonb rather than raising: expected refusals (no seats left, plan
-- ended) are answers, not errors, and the app renders them as copy.
-- ---------------------------------------------------------------------------
create or replace function public.create_device_code(p_fingerprint text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_ent record;
  v_plan subscription_plans%rowtype;
  v_limit int;
  v_used int;
  v_code text;
  v_expires timestamptz := now() + interval '10 minutes';
  i int;
begin
  select * into v_ent from device_entitlement(p_fingerprint);

  if not coalesce(v_ent.entitled, false) then
    return jsonb_build_object('ok', false, 'error', 'not_entitled');
  end if;

  if exists (select 1 from device_seats where fingerprint = p_fingerprint) then
    return jsonb_build_object('ok', false, 'error', 'linked_device');
  end if;

  select * into v_plan from subscription_plans where key = v_ent.plan_key;
  v_limit := greatest(1, coalesce(v_plan.device_limit, 1));
  select count(*) into v_used from device_seats
  where owner_fingerprint = p_fingerprint;

  if v_used >= v_limit - 1 then
    return jsonb_build_object(
      'ok', false, 'error', 'no_seats',
      'seats_used', v_used + 1, 'seat_limit', v_limit);
  end if;

  -- One live code per owner: asking again replaces the previous one, so a code
  -- can never be left behind on a screen that has moved on.
  delete from device_link_codes
  where owner_fingerprint = p_fingerprint and used_at is null;

  for i in 1..12 loop
    select string_agg(
             substr(v_alphabet,
                    1 + floor(random() * length(v_alphabet))::int, 1), '')
      into v_code
      from generate_series(1, 8);
    exit when not exists (select 1 from device_link_codes where code = v_code);
  end loop;

  if v_code is null or exists (select 1 from device_link_codes where code = v_code) then
    return jsonb_build_object('ok', false, 'error', 'code_busy');
  end if;

  insert into device_link_codes (code, owner_fingerprint, expires_at)
  values (v_code, p_fingerprint, v_expires);

  return jsonb_build_object(
    'ok', true, 'code', v_code, 'expires_at', v_expires,
    'seats_used', v_used + 1, 'seat_limit', v_limit);
end $$;

-- ---------------------------------------------------------------------------
-- 5. link_device — the joining device redeems the code.
--
-- Never raises for an expected refusal: the attempt ledger only survives if
-- the transaction commits, and that ledger is what stops a script from
-- guessing codes.
-- ---------------------------------------------------------------------------
create or replace function public.link_device(
  p_code        text,
  p_fingerprint text,
  p_label       text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_owner_ent record;
  v_self_ent record;
  v_plan subscription_plans%rowtype;
  v_limit int;
  v_used int;
  v_row device_link_codes%rowtype;
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_recent int;
begin
  if p_fingerprint is null or length(p_fingerprint) < 8 then
    return jsonb_build_object('ok', false, 'error', 'invalid_fingerprint');
  end if;

  select count(*) into v_recent from device_link_attempts
  where fingerprint = p_fingerprint and at > now() - interval '1 hour';
  if v_recent >= 10 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
  end if;

  select * into v_row from device_link_codes where code = v_code for update;

  if not found or v_row.used_at is not null or now() > v_row.expires_at then
    insert into device_link_attempts (fingerprint) values (p_fingerprint);
    return jsonb_build_object('ok', false, 'error', 'bad_code');
  end if;

  if v_row.owner_fingerprint = p_fingerprint then
    return jsonb_build_object('ok', false, 'error', 'own_code');
  end if;

  if exists (select 1 from device_seats where fingerprint = p_fingerprint) then
    return jsonb_build_object('ok', false, 'error', 'already_linked');
  end if;

  -- A device with its own running plan keeps it; joining someone else's would
  -- silently swap the subscription under it.
  select * into v_self_ent from device_entitlement(p_fingerprint);
  if coalesce(v_self_ent.entitled, false) then
    return jsonb_build_object('ok', false, 'error', 'own_subscription');
  end if;

  select * into v_owner_ent from device_entitlement(v_row.owner_fingerprint);
  if not coalesce(v_owner_ent.entitled, false) then
    insert into device_link_attempts (fingerprint) values (p_fingerprint);
    return jsonb_build_object('ok', false, 'error', 'plan_ended');
  end if;

  select * into v_plan from subscription_plans where key = v_owner_ent.plan_key;
  v_limit := greatest(1, coalesce(v_plan.device_limit, 1));
  select count(*) into v_used from device_seats
  where owner_fingerprint = v_row.owner_fingerprint;

  if v_used >= v_limit - 1 then
    return jsonb_build_object(
      'ok', false, 'error', 'no_seats',
      'seats_used', v_used + 1, 'seat_limit', v_limit);
  end if;

  -- identify_device normally registers the device first; a claim straight off
  -- a fresh install may arrive before that, so make sure the row exists.
  insert into devices (fingerprint, device_model)
  values (p_fingerprint, p_label)
  on conflict (fingerprint) do nothing;

  insert into device_seats (fingerprint, owner_fingerprint, label)
  values (p_fingerprint, v_row.owner_fingerprint, p_label);

  update device_link_codes
     set used_at = now(), used_by = p_fingerprint
   where code = v_row.code;

  return jsonb_build_object(
    'ok', true,
    'plan_key', v_owner_ent.plan_key,
    'period_end', v_owner_ent.period_end,
    'seats_used', v_used + 1,
    'seat_limit', v_limit);
end $$;

-- ---------------------------------------------------------------------------
-- 6. device_seat_list — what the paying device shows: its seats and the cap.
-- A seat asking gets its owner's list, read-only.
-- ---------------------------------------------------------------------------
create or replace function public.device_seat_list(p_fingerprint text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_owner text;
  v_ent record;
  v_plan subscription_plans%rowtype;
  v_limit int := 1;
  v_seats jsonb;
begin
  select s.owner_fingerprint into v_owner
  from device_seats s where s.fingerprint = p_fingerprint;

  v_owner := coalesce(v_owner, p_fingerprint);

  select * into v_ent from device_entitlement(v_owner);
  if v_ent.plan_key is not null then
    select * into v_plan from subscription_plans where key = v_ent.plan_key;
    v_limit := greatest(1, coalesce(v_plan.device_limit, 1));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'fingerprint', s.fingerprint,
           'label', s.label,
           'platform', d.platform,
           'device_model', d.device_model,
           'added_at', s.added_at,
           'last_seen_at', d.last_seen_at,
           'is_self', s.fingerprint = p_fingerprint
         ) order by s.added_at), '[]'::jsonb)
    into v_seats
    from device_seats s
    left join devices d on d.fingerprint = s.fingerprint
   where s.owner_fingerprint = v_owner;

  return jsonb_build_object(
    'ok', true,
    'is_seat', v_owner <> p_fingerprint,
    'owner_fingerprint', v_owner,
    'seat_limit', v_limit,
    'seats_used', 1 + jsonb_array_length(v_seats),
    'seats', v_seats);
end $$;

-- ---------------------------------------------------------------------------
-- 7. revoke_device_seat — the owner frees a seat (lost phone, ex-roommate),
--    and a guest may leave a plan it joined. Nobody can remove anyone else's.
-- ---------------------------------------------------------------------------
create or replace function public.revoke_device_seat(
  p_fingerprint      text,
  p_seat_fingerprint text
) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  delete from device_seats
  where (owner_fingerprint = p_fingerprint and fingerprint = p_seat_fingerprint)
     or fingerprint = p_fingerprint;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- 8. Grants. Every call is fingerprinted, never session-authenticated, so the
--    anon role must be able to execute them — same model as identify_device.
-- ---------------------------------------------------------------------------
grant execute on function public.create_device_code(text)              to anon, authenticated;
grant execute on function public.link_device(text, text, text)         to anon, authenticated;
grant execute on function public.device_seat_list(text)                to anon, authenticated;
grant execute on function public.revoke_device_seat(text, text)        to anon, authenticated;

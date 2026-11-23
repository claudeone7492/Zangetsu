-- =============================================================================
-- Zangetsu admin operations — the console needs more than three read tabs.
--
-- Adds:
--   * device blocking + operator notes, honoured by device_entitlement
--   * a subscription grant/revoke path and admin seat removal
--   * plan price/trial editing (pricing stays server-owned)
--   * paywall config editing
--   * admin accounts (owner-managed) and password rotation
--   * an audit log for every mutating admin action
--   * overview counts for the dashboard
--
-- Every function authenticates with admin_check (bcrypt or legacy SHA-256)
-- and writes the actor's email to admin_audit_log.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Device state the operator can change.
-- ---------------------------------------------------------------------------
alter table public.devices
  add column if not exists blocked    boolean not null default false,
  add column if not exists admin_note text;

create table if not exists public.admin_audit_log (
  id         bigserial primary key,
  actor      text,
  action     text not null,
  target     text,
  details    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_log_created_idx
  on public.admin_audit_log (created_at desc);

alter table public.admin_audit_log enable row level security;
revoke all on public.admin_audit_log from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Actor + audit helpers.
-- ---------------------------------------------------------------------------
create or replace function public.admin_actor(p_passcode text)
returns jsonb
language sql security definer set search_path = public as $$
  select jsonb_build_object('email', email, 'role', role)
  from public.admins
  where active
    and (
      (left(passcode_hash, 2) = '$2'
        and passcode_hash = extensions.crypt(p_passcode, passcode_hash))
      or (left(passcode_hash, 2) <> '$2'
        and passcode_hash =
          encode(extensions.digest(p_passcode, 'sha256'), 'hex'))
    )
  limit 1;
$$;

create or replace function public.admin_log(
  p_passcode text,
  p_action   text,
  p_target   text default null,
  p_details  jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_actor jsonb := public.admin_actor(p_passcode);
begin
  insert into public.admin_audit_log (actor, action, target, details)
  values (
    coalesce(v_actor->>'email', 'unknown'),
    p_action,
    p_target,
    coalesce(p_details, '{}'::jsonb)
  );
end $$;

-- ---------------------------------------------------------------------------
-- 3. Blocked devices lose entitlement immediately.
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
  v_session uuid;
  v_trial_used timestamptz;
  v_blocked boolean := false;
  v_sub subscriptions%rowtype;
  v_plan subscription_plans%rowtype;
  v_grace int := 3;
  v_entitled boolean := false;
  v_status text := 'none';
begin
  if p_fingerprint is null or length(p_fingerprint) < 8 then
    raise exception 'invalid fingerprint';
  end if;

  select session_id, trial_used_at, blocked
    into v_session, v_trial_used, v_blocked
  from devices where fingerprint = p_fingerprint;

  if v_blocked then
    return query select false, true, false, true, 'blocked', null, null, 0;
    return;
  end if;

  if v_session is not null then
    select * into v_sub from subscriptions s
    where s.subscriber_session_id = v_session
    order by s.started_at desc limit 1;

    if found then
      select * into v_plan from subscription_plans where key = v_sub.plan_key;
      v_grace := coalesce(v_plan.grace_days, 3);
      v_status := v_sub.status;

      v_entitled := v_sub.status in ('active', 'grace')
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

create or replace function public.start_trial(
  p_fingerprint text,
  p_plan        text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_plan     subscription_plans%rowtype;
  v_session  uuid;
  v_sub_id   uuid;
  v_used     timestamptz;
  v_blocked  boolean := false;
  v_existing subscriptions%rowtype;
begin
  if p_fingerprint is null or length(p_fingerprint) < 8 then
    raise exception 'invalid fingerprint';
  end if;

  select * into v_plan
  from subscription_plans
  where key = p_plan and active;
  if not found then raise exception 'unknown plan %', p_plan; end if;
  if v_plan.trial_days <= 0 then
    raise exception 'plan % has no trial', p_plan;
  end if;

  insert into devices (fingerprint)
  values (p_fingerprint)
  on conflict (fingerprint) do nothing;

  select session_id, trial_used_at, blocked
    into v_session, v_used, v_blocked
  from devices
  where fingerprint = p_fingerprint
  for update;

  if v_blocked then raise exception 'device blocked'; end if;
  if v_used is not null then return null; end if;

  if v_session is null then
    select session_id into v_session
    from user_profiles
    where device_fingerprint = p_fingerprint;

    if v_session is null then
      v_session := gen_random_uuid();
      insert into user_profiles (session_id, device_fingerprint, display_name)
      values (v_session, p_fingerprint, 'Guest');
    end if;

    update devices
       set session_id = v_session
     where fingerprint = p_fingerprint;
  end if;

  select * into v_existing
  from subscriptions
  where subscriber_session_id = v_session
  order by started_at desc
  limit 1;

  if found
     and v_existing.status in ('active', 'grace')
     and now() <= v_existing.current_period_end then
    return null;
  end if;

  insert into subscriptions
    (subscriber_session_id, plan_key, entitlement, status,
     current_period_start, current_period_end, auto_renew)
  values
    (v_session, p_plan, v_plan.entitlement, 'active',
     now(), now() + make_interval(days => v_plan.trial_days), false)
  on conflict (subscriber_session_id, plan_key) do update
    set status = 'active',
        auto_renew = false,
        current_period_start = now(),
        current_period_end = excluded.current_period_end,
        cancelled_at = null,
        expired_at = null,
        updated_at = now()
  returning id into v_sub_id;

  update devices
     set trial_used_at = now()
   where fingerprint = p_fingerprint;

  return v_sub_id;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Overview / dashboard.
-- ---------------------------------------------------------------------------
create or replace function public.admin_overview(p_passcode text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_actor jsonb;
begin
  if not public.admin_check(p_passcode) then
    raise exception 'unauthorized';
  end if;
  v_actor := public.admin_actor(p_passcode);

  return jsonb_build_object(
    'devices', (select count(*) from public.devices),
    'devices_active_24h', (
      select count(*) from public.devices
      where last_seen_at > now() - interval '24 hours'
    ),
    'blocked', (select count(*) from public.devices where blocked),
    'active_subs', (
      select count(*) from public.subscriptions
      where status in ('active', 'grace')
        and now() <= coalesce(current_period_end, now() - interval '1 second')
    ),
    'trialing', (
      select count(*) from public.subscriptions
      where status = 'active' and not auto_renew
        and now() <= coalesce(current_period_end, now() - interval '1 second')
    ),
    'expiring_7d', (
      select count(*) from public.subscriptions
      where status in ('active', 'grace')
        and current_period_end between now() and now() + interval '7 days'
    ),
    'promos_active', (
      select count(*) from public.promo_codes
      where active and (expires_at is null or expires_at > now())
    ),
    'redemptions_30d', (
      select count(*) from public.promo_redemptions
      where created_at > now() - interval '30 days'
    ),
    'mrr_cents', (
      select coalesce(sum(pl.price_usd_cents), 0)
      from public.subscriptions s
      join public.subscription_plans pl on pl.key = s.plan_key
      where s.status in ('active', 'grace')
        and now() <= coalesce(s.current_period_end, now() - interval '1 second')
    ),
    'revenue_30d_cents', (
      select coalesce(sum(pl.price_usd_cents), 0)
      from public.subscriptions s
      join public.subscription_plans pl on pl.key = s.plan_key
      where s.started_at > now() - interval '30 days'
        and s.status in ('active', 'grace', 'cancelled', 'expired')
    ),
    'admins', (select count(*) from public.admins where active),
    'actor', v_actor
  );
end $$;

-- ---------------------------------------------------------------------------
-- 5. Devices — v3 adds blocked/note. OUT columns change, so drop first.
-- ---------------------------------------------------------------------------
drop function if exists public.admin_devices(text);

create function public.admin_devices(p_passcode text)
returns table (
  fingerprint text,
  platform text,
  plan text,
  promo text,
  percent_off int,
  paid_cents int,
  status text,
  renews_at timestamptz,
  watch int,
  last_seen_at timestamptz,
  seat_owner text,
  seats int,
  blocked boolean,
  admin_note text
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;

  return query
  select d.fingerprint,
         d.platform,
         pl.label,
         r.code,
         coalesce(r.percent_off, 0),
         coalesce(pl.price_usd_cents, 0),
         case when d.blocked then 'blocked' else coalesce(s.status, 'inactive') end,
         s.current_period_end,
         coalesce(w.titles, 0),
         d.last_seen_at,
         seat.owner_fingerprint,
         1 + (
           select count(*)::int from public.device_seats ds
           where ds.owner_fingerprint = coalesce(seat.owner_fingerprint, d.fingerprint)
         ),
         d.blocked,
         d.admin_note
  from public.devices d
  left join public.device_seats seat on seat.fingerprint = d.fingerprint
  left join lateral (
    select s2.* from public.subscriptions s2
    join public.devices ed on ed.fingerprint = coalesce(seat.owner_fingerprint, d.fingerprint)
    where s2.subscriber_session_id = ed.session_id
    order by s2.started_at desc limit 1
  ) s on true
  left join public.subscription_plans pl on pl.key = s.plan_key
  left join lateral (
    select pc.code, pr.percent_off
    from public.promo_redemptions pr
    join public.promo_codes pc on pc.id = pr.promo_id
    where pr.fingerprint = d.fingerprint
    order by pr.created_at desc limit 1
  ) r on true
  left join public.device_watch_stats w on w.fingerprint = d.fingerprint
  order by d.last_seen_at desc;
end $$;

grant execute on function public.admin_devices(text) to anon, authenticated;

create or replace function public.admin_set_device_blocked(
  p_passcode    text,
  p_fingerprint text,
  p_blocked     boolean,
  p_note        text default null
) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;

  update public.devices
     set blocked = coalesce(p_blocked, false),
         admin_note = p_note
   where fingerprint = p_fingerprint;
  if not found then return false; end if;

  perform public.admin_log(
    p_passcode,
    case when p_blocked then 'device.block' else 'device.unblock' end,
    p_fingerprint,
    jsonb_build_object('note', p_note)
  );
  return true;
end $$;

create or replace function public.admin_grant_subscription(
  p_passcode    text,
  p_fingerprint text,
  p_days        int default 30,
  p_plan_key    text default 'stream_standard',
  p_note        text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_session uuid;
  v_plan subscription_plans%rowtype;
  v_end timestamptz;
  v_sub_id uuid;
  v_blocked boolean;
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  if p_days is null or p_days < 1 or p_days > 3650 then
    return jsonb_build_object('ok', false, 'error', 'invalid_days');
  end if;

  select session_id, blocked into v_session, v_blocked
  from public.devices where fingerprint = p_fingerprint;
  if v_session is null then
    return jsonb_build_object('ok', false, 'error', 'unknown_device');
  end if;
  if v_blocked then
    return jsonb_build_object('ok', false, 'error', 'device_blocked');
  end if;

  select * into v_plan from public.subscription_plans where key = p_plan_key;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unknown_plan');
  end if;
  if not v_plan.active then
    return jsonb_build_object('ok', false, 'error', 'inactive_plan');
  end if;

  v_end := now() + make_interval(days => p_days);
  insert into public.subscriptions
    (subscriber_session_id, plan_key, entitlement, status,
     current_period_start, current_period_end, auto_renew)
  values
    (v_session, p_plan_key, v_plan.entitlement, 'active',
     now(), v_end, false)
  on conflict (subscriber_session_id, plan_key) do update
    set status = 'active',
        auto_renew = false,
        current_period_start = now(),
        current_period_end = greatest(
          subscriptions.current_period_end,
          excluded.current_period_end
        ),
        cancelled_at = null,
        expired_at = null,
        updated_at = now()
  returning id, current_period_end into v_sub_id, v_end;

  perform public.admin_log(
    p_passcode, 'subscription.grant', p_fingerprint,
    jsonb_build_object('plan', p_plan_key, 'days', p_days, 'note', p_note,
                       'period_end', v_end)
  );

  return jsonb_build_object('ok', true, 'subscription_id', v_sub_id,
                            'period_end', v_end, 'days', p_days);
end $$;

create or replace function public.admin_revoke_subscription(
  p_passcode    text,
  p_fingerprint text,
  p_reason      text default null
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_session uuid;
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;

  select session_id into v_session from public.devices
  where fingerprint = p_fingerprint;
  if v_session is null then return false; end if;

  update public.subscriptions
     set status = 'cancelled',
         auto_renew = false,
         current_period_end = now(),
         cancelled_at = now(),
         updated_at = now()
   where subscriber_session_id = v_session
     and status in ('active', 'grace');
  if not found then return false; end if;

  perform public.admin_log(
    p_passcode, 'subscription.revoke', p_fingerprint,
    jsonb_build_object('reason', p_reason)
  );
  return true;
end $$;

create or replace function public.admin_revoke_seat(
  p_passcode         text,
  p_owner_fingerprint text,
  p_seat_fingerprint  text
) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;

  delete from public.device_seats
   where owner_fingerprint = p_owner_fingerprint
     and fingerprint = p_seat_fingerprint;
  if not found then return false; end if;

  perform public.admin_log(
    p_passcode, 'seat.revoke', p_seat_fingerprint,
    jsonb_build_object('owner', p_owner_fingerprint)
  );
  return true;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Plans — price, trial length and active flag are server-owned.
-- ---------------------------------------------------------------------------
create or replace function public.admin_plans(p_passcode text)
returns table (
  key text,
  label text,
  price_usd_cents int,
  period_days int,
  trial_days int,
  active boolean,
  sort_order int,
  subscribers bigint
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  return query
    select p.key, p.label, p.price_usd_cents, p.period_days, p.trial_days,
           p.active, p.sort_order,
           (select count(*) from public.subscriptions s where s.plan_key = p.key)
    from public.subscription_plans p
    where p.key like 'stream_%'
    order by p.sort_order, p.key;
end $$;

create or replace function public.admin_update_plan(
  p_passcode       text,
  p_key            text,
  p_price_usd_cents int,
  p_trial_days     int default null,
  p_active         boolean default null
) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  if p_price_usd_cents is null or p_price_usd_cents < 0
     or p_price_usd_cents > 1000000 then
    raise exception 'invalid price';
  end if;
  if p_trial_days is not null and (p_trial_days < 0 or p_trial_days > 365) then
    raise exception 'invalid trial days';
  end if;

  update public.subscription_plans
     set price_usd_cents = p_price_usd_cents,
         trial_days = coalesce(p_trial_days, trial_days),
         active = coalesce(p_active, active)
   where key = p_key;
  if not found then return false; end if;

  perform public.admin_log(
    p_passcode, 'plan.update', p_key,
    jsonb_build_object('price_cents', p_price_usd_cents,
                       'trial_days', p_trial_days, 'active', p_active)
  );
  return true;
end $$;

-- ---------------------------------------------------------------------------
-- 7. Paywall config.
-- ---------------------------------------------------------------------------
create or replace function public.admin_config(p_passcode text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v jsonb;
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  select jsonb_build_object(
    'launch_discount_pct', stream_launch_discount_pct,
    'display_currency', display_currency
  ) into v
  from public.app_config where id;
  return coalesce(v, '{}'::jsonb);
end $$;

create or replace function public.admin_update_config(
  p_passcode           text,
  p_launch_discount_pct int default null,
  p_display_currency   text default null
) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  if p_launch_discount_pct is not null
     and (p_launch_discount_pct < 0 or p_launch_discount_pct > 100) then
    raise exception 'invalid discount';
  end if;

  update public.app_config
     set stream_launch_discount_pct =
           coalesce(p_launch_discount_pct, stream_launch_discount_pct),
         display_currency = coalesce(nullif(trim(p_display_currency), ''),
                                     display_currency)
   where id;

  perform public.admin_log(
    p_passcode, 'config.update', 'app_config',
    jsonb_build_object('launch_discount_pct', p_launch_discount_pct,
                       'display_currency', p_display_currency)
  );
  return true;
end $$;

-- ---------------------------------------------------------------------------
-- 8. Promos — add a delete/deactivate path (history is preserved).
-- ---------------------------------------------------------------------------
create or replace function public.admin_delete_promo(
  p_passcode text,
  p_code     text
) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;

  update public.promo_codes
     set active = false, updated_at = now()
   where upper(code) = upper(trim(p_code));
  if not found then return false; end if;

  perform public.admin_log(p_passcode, 'promo.delete', p_code);
  return true;
end $$;

create or replace function public.admin_redemptions(p_passcode text)
returns table (
  code text,
  fingerprint text,
  plan_key text,
  percent_off int,
  amount_before int,
  amount_after int,
  created_at timestamptz
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  return query
    select pc.code, pr.fingerprint, pr.plan_key, pr.percent_off,
           pr.amount_before, pr.amount_after, pr.created_at
    from public.promo_redemptions pr
    left join public.promo_codes pc on pc.id = pr.promo_id
    order by pr.created_at desc
    limit 200;
end $$;

-- ---------------------------------------------------------------------------
-- 9. Admin accounts. Owner-only writes; every action is audited.
-- ---------------------------------------------------------------------------
create or replace function public.admin_admins(p_passcode text)
returns table (
  email text,
  role text,
  active boolean,
  created_at timestamptz,
  last_login_at timestamptz
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  return query
    select a.email, a.role, a.active, a.created_at, a.last_login_at
    from public.admins a
    order by a.created_at;
end $$;

create or replace function public.admin_create_admin(
  p_passcode text,
  p_email    text,
  p_password text
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_actor jsonb;
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  v_actor := public.admin_actor(p_passcode);
  if coalesce(v_actor->>'role', '') <> 'owner' then
    raise exception 'owner only';
  end if;
  if p_email is null or length(trim(p_email)) < 3 then
    raise exception 'email too short';
  end if;
  if p_password is null or length(p_password) < 8 then
    raise exception 'password too short';
  end if;
  if exists (
    select 1 from public.admins
    where active and lower(email) = lower(trim(p_email))
  ) then
    return false;
  end if;

  insert into public.admins (label, email, passcode_hash, role)
  values (
    trim(p_email),
    lower(trim(p_email)),
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    'admin'
  );

  perform public.admin_log(
    p_passcode, 'admin.create', lower(trim(p_email))
  );
  return true;
end $$;

create or replace function public.admin_set_admin_active(
  p_passcode text,
  p_email    text,
  p_active   boolean
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_actor jsonb;
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  v_actor := public.admin_actor(p_passcode);
  if coalesce(v_actor->>'role', '') <> 'owner' then
    raise exception 'owner only';
  end if;
  if lower(trim(p_email)) = lower(coalesce(v_actor->>'email', '')) then
    return false;
  end if;

  update public.admins
     set active = p_active,
         failed_attempts = 0,
         locked_until = null
   where lower(email) = lower(trim(p_email));
  if not found then return false; end if;

  perform public.admin_log(
    p_passcode,
    case when p_active then 'admin.enable' else 'admin.disable' end,
    lower(trim(p_email))
  );
  return true;
end $$;

create or replace function public.admin_change_password(
  p_passcode     text,
  p_new_password text
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_actor jsonb;
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  if p_new_password is null or length(p_new_password) < 8 then
    raise exception 'password too short';
  end if;
  v_actor := public.admin_actor(p_passcode);

  update public.admins
     set passcode_hash = extensions.crypt(
           p_new_password, extensions.gen_salt('bf')
         ),
         failed_attempts = 0,
         locked_until = null
   where lower(email) = lower(coalesce(v_actor->>'email', ''))
     and active;
  if not found then return false; end if;

  perform public.admin_log(p_passcode, 'admin.password', v_actor->>'email');
  return true;
end $$;

-- ---------------------------------------------------------------------------
-- 10. Audit feed.
-- ---------------------------------------------------------------------------
create or replace function public.admin_audit(p_passcode text)
returns table (
  actor text,
  action text,
  target text,
  details jsonb,
  created_at timestamptz
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_check(p_passcode) then raise exception 'unauthorized'; end if;
  return query
    select l.actor, l.action, l.target, l.details, l.created_at
    from public.admin_audit_log l
    order by l.created_at desc
    limit 200;
end $$;

-- ---------------------------------------------------------------------------
-- 11. Execution grants. All authorization is inside each function.
-- ---------------------------------------------------------------------------
grant execute on function public.admin_actor(text)                         to anon, authenticated;
grant execute on function public.admin_overview(text)                      to anon, authenticated;
grant execute on function public.admin_set_device_blocked(text, text, boolean, text) to anon, authenticated;
grant execute on function public.admin_grant_subscription(text, text, int, text, text) to anon, authenticated;
grant execute on function public.admin_revoke_subscription(text, text, text) to anon, authenticated;
grant execute on function public.admin_revoke_seat(text, text, text)       to anon, authenticated;
grant execute on function public.admin_plans(text)                         to anon, authenticated;
grant execute on function public.admin_update_plan(text, text, int, int, boolean) to anon, authenticated;
grant execute on function public.admin_config(text)                        to anon, authenticated;
grant execute on function public.admin_update_config(text, int, text)      to anon, authenticated;
grant execute on function public.admin_delete_promo(text, text)            to anon, authenticated;
grant execute on function public.admin_redemptions(text)                   to anon, authenticated;
grant execute on function public.admin_admins(text)                        to anon, authenticated;
grant execute on function public.admin_create_admin(text, text, text)      to anon, authenticated;
grant execute on function public.admin_set_admin_active(text, text, boolean) to anon, authenticated;
grant execute on function public.admin_change_password(text, text)         to anon, authenticated;
grant execute on function public.admin_audit(text)                         to anon, authenticated;

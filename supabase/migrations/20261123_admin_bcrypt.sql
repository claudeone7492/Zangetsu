-- =============================================================================
-- Zangetsu admin auth — store new passwords with bcrypt, keep old hashes valid.
--
-- SHA-256 is fast and unsalted. A leaked admins table would let an attacker
-- test guesses cheaply. New registrations and rotations now use pgcrypto's
-- bcrypt, while login/check still accept the legacy SHA-256 rows so the
-- existing owner can sign in until the credential is rotated.
-- =============================================================================

create or replace function public.admin_check(p_passcode text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_hash     text;
  v_attempts int;
  v_locked   timestamptz;
begin
  if p_passcode is null or length(p_passcode) < 6 then return false; end if;

  select attempts, locked_until into v_attempts, v_locked
  from public.admin_auth_state where id;

  if v_locked is not null and v_locked > now() then return false; end if;

  v_hash := encode(extensions.digest(p_passcode, 'sha256'), 'hex');

  if exists (
    select 1 from public.admins
    where active
      and (
        (left(passcode_hash, 2) = '$2'
          and passcode_hash = extensions.crypt(p_passcode, passcode_hash))
        or (left(passcode_hash, 2) <> '$2' and passcode_hash = v_hash)
      )
  ) then
    update public.admin_auth_state
       set attempts = 0, locked_until = null, updated_at = now()
     where id;
    return true;
  end if;

  update public.admin_auth_state
     set attempts = attempts + 1,
         locked_until = case
           when attempts + 1 >= 5 then now() + interval '15 minutes'
           else locked_until
         end,
         updated_at = now()
   where id;

  return false;
end $$;

create or replace function public.admin_login(
  p_email    text,
  p_password text
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_admin admins%rowtype;
  v_ok    boolean := false;
begin
  if p_email is null or length(trim(p_email)) < 3 then return false; end if;
  if p_password is null or length(p_password) < 6 then return false; end if;

  select * into v_admin
  from public.admins
  where active and lower(email) = lower(trim(p_email));

  if not found then return false; end if;
  if v_admin.locked_until is not null and v_admin.locked_until > now() then
    return false;
  end if;

  if left(v_admin.passcode_hash, 2) = '$2' then
    v_ok := v_admin.passcode_hash =
      extensions.crypt(p_password, v_admin.passcode_hash);
  else
    v_ok := v_admin.passcode_hash =
      encode(extensions.digest(p_password, 'sha256'), 'hex');
  end if;

  if v_ok then
    update public.admins
       set failed_attempts = 0,
           locked_until = null,
           last_login_at = now()
     where id = v_admin.id;
    return true;
  end if;

  update public.admins
     set failed_attempts = failed_attempts + 1,
         locked_until = case
           when failed_attempts + 1 >= 5 then now() + interval '15 minutes'
           else locked_until
         end
   where id = v_admin.id;

  return false;
end $$;

create or replace function public.admin_register(
  p_email    text,
  p_password text
) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_email is null or length(trim(p_email)) < 3 then
    raise exception 'email too short';
  end if;
  if p_password is null or length(p_password) < 6 then
    raise exception 'password too short';
  end if;
  if exists (select 1 from public.admins where active) then
    return false;
  end if;

  insert into public.admins (label, email, passcode_hash, role)
  values (
    trim(p_email),
    lower(trim(p_email)),
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    'owner'
  );
  return true;
end $$;

grant execute on function public.admin_login(text, text)    to anon, authenticated;
grant execute on function public.admin_register(text, text) to anon, authenticated;

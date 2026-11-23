-- =============================================================================
-- Zangetsu subscription — merchant-billed charges and per-device receipts.
--
-- Kora requires customer.email on every charge. The app has no customer email
-- (a trial starts before any account exists), so every stream charge is billed
-- to the merchant contact address and the device is identified by the payment
-- reference instead. This keeps Kora's customer field valid without asking the
-- viewer for an email.
--
-- device_transactions() is the read side: it resolves the caller's fingerprint
-- to its own device session and returns only payments that session initiated.
-- A shared-plan guest therefore cannot see the payer's card history, while the
-- payer can still track every charge by reference.
-- =============================================================================

alter table public.payments
  add column if not exists customer_email text;

update public.payments
set customer_email = 'edgesenterprise@outlook.com'
where product_type = 'subscription_stream'
  and customer_email is null;

create index if not exists payments_payer_created_idx
  on public.payments (payer_session_id, created_at desc);

create or replace function public.device_transactions(p_fingerprint text)
returns table (
  reference text,
  product_type text,
  plan_key text,
  plan_label text,
  amount_cents int,
  currency text,
  status text,
  promo_code text,
  created_at timestamptz,
  completed_at timestamptz,
  period_end timestamptz
)
language plpgsql security definer set search_path = public as $$
declare
  v_session uuid;
begin
  if p_fingerprint is null or length(p_fingerprint) < 8 then
    raise exception 'invalid fingerprint';
  end if;

  select public.get_subscription_session(p_fingerprint) into v_session;
  if v_session is null then
    return;
  end if;

  return query
    select
      p.korapay_reference,
      p.product_type,
      s.plan_key,
      pl.label,
      p.amount,
      coalesce(p.charge_currency, p.currency, 'USD'),
      p.status,
      p.promo_code_used,
      p.created_at,
      p.completed_at,
      s.current_period_end
    from public.payments p
    left join public.subscriptions s on s.id = p.subscription_id
    left join public.subscription_plans pl on pl.key = s.plan_key
    where p.payer_session_id = v_session
      and p.product_type like 'subscription_%'
    order by p.created_at desc;
end $$;

revoke execute on function public.device_transactions(text)
  from public, anon, authenticated;
grant execute on function public.device_transactions(text)
  to anon, authenticated;

notify pgrst, 'reload schema';

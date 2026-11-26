-- =============================================================================
-- Zangetsu paywall — multi-gateway payments.
--
-- The paywall now routes each checkout to Korapay or Flutterwave based on the
-- caller's country. The gateway reference keeps using `korapay_reference`
-- (it is the canonical reference read by device_transactions and every admin
-- RPC); `payment_provider` records which gateway will settle it so each webhook
-- can reject a reference that belongs to the other one.
-- =============================================================================

alter table public.payments
  add column if not exists payment_provider text not null default 'korapay';

do $$ begin
  alter table public.payments
    add constraint payments_payment_provider_check
    check (payment_provider in ('korapay', 'flutterwave'));
exception when duplicate_object then null; end $$;

create index if not exists payments_provider_reference_idx
  on public.payments (payment_provider, korapay_reference);

notify pgrst, 'reload schema';

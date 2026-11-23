-- =============================================================================
-- Zangetsu subscription — remove the standing anon/authenticated table grants.
--
-- Every subscription table already has RLS enabled, and the app reaches them
-- only through SECURITY DEFINER RPCs. The grants below were therefore unused
-- defence-in-depth risk: one future policy mistake (or an RLS toggle) would
-- expose the whole subscription registry. The service-role client used by the
-- edge functions keeps its access.
-- =============================================================================

revoke all on public.subscriptions      from anon, authenticated;
revoke all on public.devices            from anon, authenticated;
revoke all on public.user_profiles      from anon, authenticated;
revoke all on public.promo_codes        from anon, authenticated;
revoke all on public.promo_redemptions  from anon, authenticated;
revoke all on public.admins             from anon, authenticated;
revoke all on public.app_config         from anon, authenticated;
revoke all on public.payments           from anon, authenticated;
revoke all on public.entitlements       from anon, authenticated;
revoke all on public.device_seats       from anon, authenticated;
revoke all on public.device_link_codes  from anon, authenticated;
revoke all on public.device_link_attempts from anon, authenticated;
revoke all on public.admin_auth_state   from anon, authenticated;

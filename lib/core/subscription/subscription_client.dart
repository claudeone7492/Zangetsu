import 'package:supabase_flutter/supabase_flutter.dart';

import '../environment.dart';

/// A Supabase client bound to the subscription ("Sophie") project.
///
/// The app's own [SupabaseService] client points at the Zangetsu project, which
/// does not carry the subscription tables, RPCs or edge functions — those live
/// in a separate project. This client is that second connection.
///
/// It deliberately keeps no session: identity is the device fingerprint, passed
/// as an RPC/function parameter, and every call is authorised by a SECURITY
/// DEFINER function rather than by an auth token.
SupabaseClient buildSubscriptionClient() => SupabaseClient(
  Environment.subscriptionUrl,
  Environment.subscriptionAnonKey,
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

import 'package:flutter/foundation.dart';

import '../config/supabase_config.dart';

class ShareLink {
  ShareLink._();

  static String? parseToken(Uri uri) {
    final query = uri.queryParameters['share']?.trim();
    if (query != null && query.isNotEmpty) return query;

    final fragment = uri.fragment;
    if (fragment.isEmpty) return null;
    final queryStart = fragment.indexOf('?');
    final queryString = queryStart >= 0 ? fragment.substring(queryStart + 1) : fragment;
    final parsed = Uri.splitQueryString(queryString);
    final fromHash = parsed['share']?.trim();
    if (fromHash != null && fromHash.isNotEmpty) return fromHash;
    return null;
  }

  static String? fromCurrentUri() => parseToken(Uri.base);

  static String buildUrl(String token) {
    final origin = kIsWeb ? Uri.base.origin : SupabaseConfig.webProductionOrigin;
    return '$origin/?share=$token';
  }
}

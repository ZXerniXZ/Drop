import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_auth_service.dart';

class LegalAcceptance {
  LegalAcceptance._();

  static const version = '2026-09-30';

  static const termsVersionKey = 'terms_version';
  static const termsAcceptedAtKey = 'terms_accepted_at';
  static const recordingNoticeVersionKey = 'recording_notice_version';

  static Map<String, dynamic>? get _metadata =>
      SupabaseAuthService.instance.currentUser?.userMetadata;

  static bool get hasAcceptedCurrentTerms =>
      _metadata?[termsVersionKey] == version;

  static bool get hasAcknowledgedRecordingNotice =>
      _metadata?[recordingNoticeVersionKey] == version;

  static Map<String, dynamic> termsPayload() => {
        termsVersionKey: version,
        termsAcceptedAtKey: DateTime.now().toUtc().toIso8601String(),
      };

  static Future<void> saveTermsAcceptance() {
    return Supabase.instance.client.auth.updateUser(
      UserAttributes(data: termsPayload()),
    );
  }

  static Future<void> saveRecordingNotice() {
    return Supabase.instance.client.auth.updateUser(
      UserAttributes(data: {recordingNoticeVersionKey: version}),
    );
  }
}

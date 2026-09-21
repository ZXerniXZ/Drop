import 'app_identity.dart';

class DropApiHeaders {
  DropApiHeaders._();

  static Map<String, String> version() => {
    'X-Drop-Version': AppIdentity.version,
    'X-Drop-Build': '${AppIdentity.build}',
  };

  static Map<String, String> auth(String token) => {
    'Authorization': 'Bearer $token',
    ...version(),
  };

  static Map<String, String> json(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
    ...version(),
  };
}

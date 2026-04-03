import 'package:shared_preferences/shared_preferences.dart';

/// Railway JWT ve backend kullanıcı id (Postgres `User.id`).
class ApiSession {
  ApiSession._();
  static final ApiSession instance = ApiSession._();

  static const _kToken = 'railway_access_token';
  static const _kBackendUid = 'railway_backend_uid';

  String? _accessToken;
  String? _backendUserId;

  String? get accessToken => _accessToken;
  String? get backendUserId => _backendUserId;
  bool get isSignedIn =>
      _accessToken != null &&
      _accessToken!.isNotEmpty &&
      _backendUserId != null &&
      _backendUserId!.isNotEmpty;

  Future<void> loadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    _accessToken = p.getString(_kToken);
    _backendUserId = p.getString(_kBackendUid);
  }

  Future<void> setSession({
    required String accessToken,
    required String backendUserId,
  }) async {
    _accessToken = accessToken;
    _backendUserId = backendUserId;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, accessToken);
    await p.setString(_kBackendUid, backendUserId);
  }

  Future<void> clear() async {
    _accessToken = null;
    _backendUserId = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kBackendUid);
  }
}

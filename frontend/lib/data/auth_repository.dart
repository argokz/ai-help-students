import 'package:shared_preferences/shared_preferences.dart';

class AuthRepository {
  static const _keyToken = 'auth_token';
  static const _keyUserId = 'auth_user_id';
  static const _keyEmail = 'auth_email';
  static const _keyDisplayName = 'auth_display_name';
  static const _keyPhotoUrl = 'auth_photo_url';

  Future<void> saveSession({
    required String token,
    required String userId,
    required String email,
    String? displayName,
    String? photoUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyEmail, email);
    if (displayName != null) {
      await prefs.setString(_keyDisplayName, displayName);
    }
    if (photoUrl != null) {
      await prefs.setString(_keyPhotoUrl, photoUrl);
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserId);
  }

  Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEmail);
  }

  Future<String?> getDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDisplayName);
  }

  Future<String?> getPhotoUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPhotoUrl);
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyDisplayName);
    await prefs.remove(_keyPhotoUrl);
  }
}

final authRepository = AuthRepository();

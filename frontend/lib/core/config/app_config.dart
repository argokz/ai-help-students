/// Application configuration
/// 
/// Change the API URL here when deploying to different environments
class AppConfig {
  // ===========================================
  // API Configuration - CHANGE URL HERE
  // ===========================================
  
  /// Production server
  static const String apiBaseUrl = 'https://itwin.kz/ai-api/api';
  
  /// For local development (uncomment the one you need):
  // static const String apiBaseUrl = 'http://10.0.2.2:8000/api';  // Android emulator
  // static const String apiBaseUrl = 'http://localhost:8000/api'; // iOS simulator
  // static const String apiBaseUrl = 'http://192.168.1.x:8000/api'; // Physical device (use your PC IP)
  
  // ===========================================
  // Timeouts
  // ===========================================
  
  /// Connection timeout in seconds
  static const int connectTimeout = 30;
  
  /// Receive timeout in seconds (for long operations like transcription)
  static const int receiveTimeout = 120;
  
  // ===========================================
  // Google Sign-In
  // ===========================================
  
  /// Web Client ID from Google Cloud Console (for backend verification).
  /// Web Client ID (тот же, что GOOGLE_CLIENT_ID на бэкенде). Android client задаётся в Google Cloud по package name + SHA-1.
  static const String googleClientId = '685511640887-n0uhb49sok2eej9lulbb40apudjik0sb.apps.googleusercontent.com';

  // ===========================================
  // App Info
  // ===========================================
  
  static const String appName = 'Ассистент Лекций';
  static const String appVersion = '1.0.0';
}

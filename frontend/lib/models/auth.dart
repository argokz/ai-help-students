class TokenResponse {
  final String accessToken;
  final String tokenType;
  final String userId;
  final String email;

  TokenResponse({
    required this.accessToken,
    required this.tokenType,
    required this.userId,
    required this.email,
  });

  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    return TokenResponse(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String? ?? 'bearer',
      userId: json['user_id'] as String,
      email: json['email'] as String,
    );
  }
}

class UserInfo {
  final String id;
  final String email;
  final String createdAt;

  UserInfo({
    required this.id,
    required this.email,
    required this.createdAt,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'] as String,
      email: json['email'] as String,
      createdAt: json['created_at'] as String,
    );
  }
}

/// Firestore'daki kullanıcı profil alanları (giriş Apple/Google ile; ödeme App Store / Play Store).
class UserProfile {
  UserProfile({
    required this.uid,
    this.displayName,
    this.email,
    this.photoUrl,
    this.handle,
    this.isPremium = false,
    this.premiumUntil,
    this.createdAt,
  });

  final String uid;
  final String? displayName;
  final String? email;
  final String? photoUrl;
  final String? handle;
  final bool isPremium;
  final DateTime? premiumUntil;
  final DateTime? createdAt;

  factory UserProfile.fromMap(String uid, Map<String, dynamic>? data) {
    if (data == null) return UserProfile(uid: uid);
    return UserProfile(
      uid: uid,
      displayName: data['displayName'] as String?,
      email: data['email'] as String?,
      photoUrl: data['photoUrl'] as String?,
      handle: data['handle'] as String?,
      isPremium: data['isPremium'] == true,
      premiumUntil: data['premiumUntil'] != null
          ? DateTime.tryParse(data['premiumUntil'] as String)
          : null,
      createdAt: data['createdAt'] != null
          ? DateTime.tryParse(data['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'handle': handle,
      'isPremium': isPremium,
      'premiumUntil': premiumUntil?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}

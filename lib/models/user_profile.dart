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
    this.freeDemoLinkUsed = false,
    this.paidLinkCredits = 0,
  });

  final String uid;
  final String? displayName;
  final String? email;
  final String? photoUrl;
  final String? handle;
  final bool isPremium;
  final DateTime? premiumUntil;
  final DateTime? createdAt;

  /// Ücretsiz demo link (10 dk, tek yorum) bir kez kullanıldı mı.
  final bool freeDemoLinkUsed;

  /// Satın alınan premium link hakları (her link 24 saat, çoklu yorum); oluşturulunca 1 azalır.
  final int paidLinkCredits;

  /// DEPRECATED (salt-kredi modeli): eski isPremium/premiumUntil artık entitlement
  /// KARARI VERMEZ. Yalnızca eski veriler için hesaplanır; premium link oluşturma
  /// hakkı SADECE paidLinkCredits'tir. Bkz. [canCreatePaidPremiumLink].
  @Deprecated('Salt-kredi modeli: entitlement kararında kullanma; paidLinkCredits geçerli')
  bool get hasActivePremium {
    if (!isPremium) return false;
    final u = premiumUntil;
    if (u == null) return true;
    return u.isAfter(DateTime.now());
  }

  /// Henüz ücretsiz demo link hakkı var mı.
  bool get hasFreeDemoAvailable => !freeDemoLinkUsed;

  /// Premium link oluşturma hakkı SADECE satın alınan kredi ile verilir (SALT-KREDİ).
  /// Eski isPremium/premiumUntil bypass'i KALDIRILDI (sunucu-yetkili iapVerify +
  /// kilitli firestore.rules ile tutarlı).
  bool get canCreatePaidPremiumLink => paidLinkCredits > 0;

  UserProfile copyWith({
    String? uid,
    String? displayName,
    String? email,
    String? photoUrl,
    String? handle,
    bool? isPremium,
    DateTime? premiumUntil,
    DateTime? createdAt,
    bool? freeDemoLinkUsed,
    int? paidLinkCredits,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      handle: handle ?? this.handle,
      isPremium: isPremium ?? this.isPremium,
      premiumUntil: premiumUntil ?? this.premiumUntil,
      createdAt: createdAt ?? this.createdAt,
      freeDemoLinkUsed: freeDemoLinkUsed ?? this.freeDemoLinkUsed,
      paidLinkCredits: paidLinkCredits ?? this.paidLinkCredits,
    );
  }

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
      freeDemoLinkUsed: data['freeDemoLinkUsed'] == true,
      paidLinkCredits: (data['paidLinkCredits'] as num?)?.toInt() ?? 0,
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
      'freeDemoLinkUsed': freeDemoLinkUsed,
      'paidLinkCredits': paidLinkCredits,
    };
  }
}

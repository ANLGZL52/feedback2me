import 'package:cloud_firestore/cloud_firestore.dart';

/// Arayüzde demo / premium / eski (tier alanı olmayan) kayıtlar.
enum FeedbackLinkPlan { demo, premium, legacy }

/// `linkTier`: `demo` = 10 dk + tek yorum; `premium` = 24 saat, çoklu yorum.
/// Eski linklerde alan yok → sınırsız (legacy) kabul.
class FeedbackLink {
  FeedbackLink({
    required this.id,
    required this.ownerId,
    required this.code,
    this.title,
    this.createdAt,
    this.isActive = true,
    this.linkTier,
    this.validUntil,
    this.demoSubmissionUsed = false,
  });

  final String id;
  final String ownerId;
  final String code;
  final String? title;
  final DateTime? createdAt;
  final bool isActive;

  /// `demo` | `premium`; null = eski kayıt (public için süre / tek kullanım yok).
  final String? linkTier;
  final DateTime? validUntil;
  final bool demoSubmissionUsed;

  /// Ana uygulama adresi (misafir formu “Uygulamayı keşfet” bağlantısı).
  static const String appMarketingBaseUrl = 'https://feedbacktome-79655.web.app';

  String get shareUrl => '$appMarketingBaseUrl/f/$code';

  bool get isDemoTier => linkTier == 'demo';
  bool get isPremiumTier => linkTier == 'premium';

  /// Rozet ve metinler için; [legacy] = Firestore/API’de `linkTier` yok.
  FeedbackLinkPlan get displayPlan {
    if (isPremiumTier) return FeedbackLinkPlan.premium;
    if (isDemoTier) return FeedbackLinkPlan.demo;
    return FeedbackLinkPlan.legacy;
  }

  /// Süre dolmuş mu (validUntil tanımlıysa).
  bool get isPastValidWindow {
    final v = validUntil;
    if (v == null) return false;
    return !DateTime.now().isBefore(v);
  }

  /// Yeni yorum kabul edilir mi (public form + kurallar ile uyumlu).
  bool get acceptsPublicFeedback {
    if (!isActive) return false;
    if (isPastValidWindow) return false;
    if (isDemoTier && demoSubmissionUsed) return false;
    return true;
  }

  static DateTime? _parseCreatedAt(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static DateTime? _parseValidUntil(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  factory FeedbackLink.fromMap(String id, Map<String, dynamic>? data) {
    if (data == null) return FeedbackLink(id: id, ownerId: '', code: '');
    return FeedbackLink(
      id: id,
      ownerId: data['ownerId'] as String? ?? '',
      code: data['code'] as String? ?? '',
      title: data['title'] as String?,
      createdAt: _parseCreatedAt(data['createdAt']),
      isActive: data['isActive'] != false,
      linkTier: data['linkTier'] as String?,
      validUntil: _parseValidUntil(data['validUntil']),
      demoSubmissionUsed: data['demoSubmissionUsed'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'code': code,
      'title': title,
      'createdAt': createdAt?.toIso8601String(),
      'isActive': isActive,
      if (linkTier != null) 'linkTier': linkTier,
      if (validUntil != null) 'validUntil': validUntil!.toIso8601String(),
      'demoSubmissionUsed': demoSubmissionUsed,
    };
  }

  /// Firestore yazımı: [validUntil] için Timestamp kullan.
  Map<String, dynamic> toFirestoreMap() {
    return {
      'ownerId': ownerId,
      'code': code,
      'title': title,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'isActive': isActive,
      'linkTier': linkTier ?? 'demo',
      if (validUntil != null) 'validUntil': Timestamp.fromDate(validUntil!),
      'demoSubmissionUsed': demoSubmissionUsed,
    };
  }
}

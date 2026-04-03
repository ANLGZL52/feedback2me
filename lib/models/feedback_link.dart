import 'package:cloud_firestore/cloud_firestore.dart';

/// Kullanıcının oluşturduğu feedback linki (kısa kod ile).
class FeedbackLink {
  FeedbackLink({
    required this.id,
    required this.ownerId,
    required this.code,
    this.title,
    this.createdAt,
    this.isActive = true,
  });

  final String id;
  final String ownerId;
  final String code;
  final String? title;
  final DateTime? createdAt;
  final bool isActive;

  /// Ana uygulama adresi (misafir formu “Uygulamayı keşfet” bağlantısı).
  static const String appMarketingBaseUrl = 'https://feedbacktome-79655.web.app';

  String get shareUrl => '${appMarketingBaseUrl}/f/$code';

  static DateTime? _parseCreatedAt(dynamic raw) {
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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'code': code,
      'title': title,
      'createdAt': createdAt?.toIso8601String(),
      'isActive': isActive,
    };
  }
}

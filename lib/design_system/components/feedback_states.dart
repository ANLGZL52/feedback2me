import 'package:flutter/material.dart';

import '../feedback_colors.dart';
import '../feedback_radius.dart';
import '../feedback_spacing.dart';
import '../feedback_typography.dart';
import 'feedback_button.dart';

/// Boş durum — ikon + başlık + açıklama + opsiyonel CTA.
class FeedbackEmptyState extends StatelessWidget {
  const FeedbackEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_rounded,
    this.ctaLabel,
    this.onCta,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceSecondary,
                borderRadius: AppRadius.rLarge,
              ),
              child: Icon(icon, size: 34, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.m),
            Text(title, style: AppType.sectionTitle, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.s),
              Text(message!, style: AppType.secondary, textAlign: TextAlign.center),
            ],
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: AppSpacing.l),
              FeedbackPrimaryButton(
                  label: ctaLabel!, onPressed: onCta, fullWidth: false),
            ],
          ],
        ),
      ),
    );
  }
}

/// Yükleme durumu — spinner + opsiyonel mesaj.
class FeedbackLoadingState extends StatelessWidget {
  const FeedbackLoadingState({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: AppColors.primary),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.m),
            Text(message!, style: AppType.secondary, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// Hata durumu — mesaj + tekrar dene.
class FeedbackErrorState extends StatelessWidget {
  const FeedbackErrorState({
    super.key,
    required this.message,
    this.retryLabel,
    this.onRetry,
  });

  final String message;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 44, color: AppColors.danger),
            const SizedBox(height: AppSpacing.m),
            Text(message, style: AppType.body, textAlign: TextAlign.center),
            if (retryLabel != null && onRetry != null) ...[
              const SizedBox(height: AppSpacing.l),
              FeedbackSecondaryButton(
                  label: retryLabel!, onPressed: onRetry, fullWidth: false),
            ],
          ],
        ),
      ),
    );
  }
}

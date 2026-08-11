import 'package:flutter/material.dart';

import '../feedback_colors.dart';
import '../feedback_radius.dart';
import '../feedback_shadows.dart';
import '../feedback_typography.dart';

/// Ana CTA — mavi→mor gradient. Her ekranda en fazla bir dominant CTA.
class FeedbackPrimaryButton extends StatelessWidget {
  const FeedbackPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingArrow = false,
    this.busy = false,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool trailingArrow;
  final bool busy;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || busy;
    final child = busy
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: AppColors.onPrimary),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: AppColors.onPrimary, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(label,
                    style: AppType.button,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (trailingArrow) ...[
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded,
                    color: AppColors.onPrimary, size: 20),
              ],
            ],
          );

    final button = Opacity(
      opacity: disabled ? 0.65 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: AppRadius.rMedium,
          boxShadow: disabled ? null : AppShadows.primaryGlow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadius.rMedium,
            onTap: disabled ? null : onPressed,
            child: Container(
              height: 54,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: child,
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: label,
      child: fullWidth
          ? SizedBox(width: double.infinity, child: button)
          : button,
    );
  }
}

/// İkincil buton — beyaz yüzey + ince kenar.
class FeedbackSecondaryButton extends StatelessWidget {
  const FeedbackSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: AppColors.surface,
      borderRadius: AppRadius.rMedium,
      child: InkWell(
        borderRadius: AppRadius.rMedium,
        onTap: onPressed,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rMedium,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(label,
                    style: AppType.button.copyWith(color: AppColors.primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Metin/tertiary buton.
class FeedbackTextButton extends StatelessWidget {
  const FeedbackTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(label,
          style: AppType.bodyStrong.copyWith(color: color ?? AppColors.primary)),
    );
  }
}

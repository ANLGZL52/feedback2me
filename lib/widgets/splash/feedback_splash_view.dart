import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../l10n/app_localizations.dart';

/// V2 aydınlık splash — marka + tagline + hafif loader. Startup mantığı
/// çağıran taraftadır; bu yalnızca sunumdur (fake delay yok).
class FeedbackSplashView extends StatelessWidget {
  const FeedbackSplashView({super.key, this.showLoader = true});

  final bool showLoader;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildFeedbackLightTheme(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.primarySoft, AppColors.background],
              stops: const [0.0, 0.55],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: AppRadius.rLarge,
                      boxShadow: AppShadows.primaryGlow,
                    ),
                    child: const Icon(Icons.chat_bubble_rounded,
                        color: AppColors.onPrimary, size: 44),
                  ),
                  const SizedBox(height: AppSpacing.l),
                  Text('Feedback2Me', style: AppType.display),
                  const SizedBox(height: AppSpacing.s),
                  Text(L10n.get(context, 'splashV2Tagline'),
                      style: AppType.secondary, textAlign: TextAlign.center),
                  if (showLoader) ...[
                    const SizedBox(height: AppSpacing.xxl),
                    Semantics(
                      label: L10n.get(context, 'splashV2Loading'),
                      liveRegion: true,
                      child: const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.6, color: AppColors.primary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

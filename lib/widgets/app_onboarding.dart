import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system.dart';
import '../l10n/app_localizations.dart';

const String kOnboardingPrefsKey = 'feedbacktome_onboarding_v1_completed';

Future<bool> isOnboardingCompleted() async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(kOnboardingPrefsKey) ?? false;
}

Future<void> setOnboardingCompleted() async {
  final p = await SharedPreferences.getInstance();
  await p.setBool(kOnboardingPrefsKey, true);
}

enum _OnbArt { crowd, link, fast, ai }

class _SlideV2 {
  const _SlideV2({
    required this.art,
    required this.titleKey,
    required this.bodyKey,
    this.footerKey,
  });

  final _OnbArt art;
  final String titleKey;
  final String bodyKey;
  final String? footerKey;
}

/// İlk açılış tanıtımı — V2 aydınlık. [onFinished] mevcut davranışı korur
/// (flag'i çağıran taraf yönetir; bu widget flag'e dokunmaz).
class AppOnboarding extends StatefulWidget {
  const AppOnboarding({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<AppOnboarding> createState() => _AppOnboardingState();
}

class _AppOnboardingState extends State<AppOnboarding> {
  final PageController _controller = PageController();
  int _index = 0;

  static const List<_SlideV2> _slides = [
    _SlideV2(
      art: _OnbArt.crowd,
      titleKey: 'onboardingV2Slide1Title',
      bodyKey: 'onboardingV2Slide1Body',
    ),
    _SlideV2(
      art: _OnbArt.link,
      titleKey: 'onboardingV2Slide2Title',
      bodyKey: 'onboardingV2Slide2Body',
    ),
    _SlideV2(
      art: _OnbArt.fast,
      titleKey: 'onboardingV2Slide3Title',
      bodyKey: 'onboardingV2Slide3Body',
    ),
    _SlideV2(
      art: _OnbArt.ai,
      titleKey: 'onboardingV2Slide4Title',
      bodyKey: 'onboardingV2Slide4Body',
      footerKey: 'onboardingV2Slide4Footer',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _slides.length - 1) {
      HapticFeedback.lightImpact();
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      HapticFeedback.mediumImpact();
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _slides.length - 1;
    return Theme(
      data: buildFeedbackLightTheme(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppSpacing.maxWidthWide),
              child: Column(
                children: [
                  // Üst bar: marka + Atla
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pageH, AppSpacing.s, AppSpacing.s, 0),
                    child: Row(
                      children: [
                        const FeedbackBrandMark(),
                        const Spacer(),
                        FeedbackTextButton(
                          label: L10n.get(context, 'onboardingV2Skip'),
                          color: AppColors.textSecondary,
                          onPressed: widget.onFinished,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _slides.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) => _OnboardingPageV2(
                        slide: _slides[i],
                        pageLabel:
                            '${i + 1} / ${_slides.length}',
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 0,
                        AppSpacing.pageH, AppSpacing.l),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_slides.length, (i) {
                            final active = i == _index;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              width: active ? 26 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color:
                                    active ? AppColors.primary : AppColors.border,
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: AppSpacing.l),
                        FeedbackPrimaryButton(
                          label: last
                              ? L10n.get(context, 'onboardingV2GetStarted')
                              : L10n.get(context, 'onboardingV2Continue'),
                          trailingArrow: !last,
                          onPressed: _next,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPageV2 extends StatelessWidget {
  const _OnboardingPageV2({required this.slide, required this.pageLabel});

  final _SlideV2 slide;
  final String pageLabel;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      L10n.get(context, slide.titleKey),
      textAlign: TextAlign.center,
      style: AppType.display.copyWith(height: 1.2),
      maxLines: 3,
    );
    final body = Text(
      L10n.get(context, slide.bodyKey),
      textAlign: TextAlign.center,
      style: AppType.body.copyWith(height: 1.5),
    );
    final footer = slide.footerKey == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: AppSpacing.m),
            child: FeedbackTrustChip(
              label: L10n.get(context, slide.footerKey!),
              icon: Icons.card_giftcard_rounded,
            ),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.s),
      child: Semantics(
        label: pageLabel,
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 720;
            final art = ExcludeSemantics(child: _OnboardingArt(art: slide.art));
            final textCol = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                title,
                const SizedBox(height: AppSpacing.m),
                body,
                ?footer,
              ],
            );
            if (wide) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: Center(child: art)),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(child: textCol),
                ],
              );
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: AppSpacing.m),
                  art,
                  const SizedBox(height: AppSpacing.xl),
                  textCol,
                  const SizedBox(height: AppSpacing.m),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Flutter-native onboarding illüstrasyonu (asset yok, responsive, lokalizasyon
/// bağımsız). Her slide için farklı kompozisyon.
class _OnboardingArt extends StatelessWidget {
  const _OnboardingArt({required this.art});

  final _OnbArt art;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primarySoft, AppColors.violetSoft],
          ),
          borderRadius: AppRadius.rCard,
          border: Border.all(color: AppColors.border),
        ),
        child: Center(child: _composition(context)),
      ),
    );
  }

  Widget _bubble(String emoji) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          boxShadow: AppShadows.soft,
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      );

  Widget _chip(String label, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.rPill,
          boxShadow: AppShadows.soft,
        ),
        child: Text(label,
            style: AppType.caption
                .copyWith(color: color ?? AppColors.textPrimary)),
      );

  Widget _iconBadge(IconData icon) => Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: AppRadius.rLarge,
          boxShadow: AppShadows.primaryGlow,
        ),
        child: Icon(icon, color: AppColors.onPrimary, size: 34),
      );

  Widget _composition(BuildContext context) {
    switch (art) {
      case _OnbArt.crowd:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _bubble('😍'),
                const SizedBox(width: 12),
                _bubble('🔥'),
                const SizedBox(width: 12),
                _bubble('🤔'),
              ],
            ),
            const SizedBox(height: 16),
            _iconBadge(Icons.forum_rounded),
          ],
        );
      case _OnbArt.link:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _iconBadge(Icons.link_rounded),
            const SizedBox(height: 16),
            _chip('feedback2me.app/f/…', color: AppColors.primary),
            const SizedBox(height: 10),
            _chip('🔗  Paylaş'),
          ],
        );
      case _OnbArt.fast:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _chip('😍'),
                _chip('🔥'),
                _chip('👀'),
                _chip('🤔'),
              ],
            ),
            const SizedBox(height: 16),
            _iconBadge(Icons.bolt_rounded),
          ],
        );
      case _OnbArt.ai:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _chip('💬'),
                const SizedBox(width: 8),
                _chip('💬'),
                const SizedBox(width: 8),
                const Icon(Icons.auto_awesome_rounded,
                    color: AppColors.primary, size: 22),
              ],
            ),
            const SizedBox(height: 16),
            _iconBadge(Icons.insights_rounded),
            const SizedBox(height: 12),
            _chip('7.8 / 10', color: AppColors.primary),
          ],
        );
    }
  }
}

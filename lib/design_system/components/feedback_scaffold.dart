import 'package:flutter/material.dart';

import '../feedback_colors.dart';
import '../feedback_spacing.dart';
import '../feedback_theme.dart';
import '../feedback_typography.dart';

/// V2 aydınlık scaffold. Ekranı kendi içinde aydınlık temaya sarar (global tema
/// koyu kalsa bile). Masaüstünde içeriği [maxWidth] ile ortalar (responsive).
class FeedbackScaffold extends StatelessWidget {
  const FeedbackScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomBar,
    this.maxWidth = AppSpacing.maxWidthContent,
    this.padded = true,
    this.backgroundColor,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomBar;
  final double maxWidth;
  final bool padded;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildFeedbackLightTheme(),
      child: Scaffold(
        backgroundColor: backgroundColor ?? AppColors.background,
        appBar: appBar,
        bottomNavigationBar: bottomBar,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: padded ? AppSpacing.pageH : 0),
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Basit V2 app bar: geri oku + başlık + opsiyonel sağ aksiyonlar.
PreferredSizeWidget feedbackAppBar(
  BuildContext context, {
  String? title,
  bool showBack = true,
  List<Widget> actions = const [],
}) {
  return AppBar(
    backgroundColor: AppColors.background,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    automaticallyImplyLeading: false,
    titleSpacing: showBack ? 0 : AppSpacing.pageH,
    leading: showBack
        ? IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).maybePop(),
          )
        : null,
    title: title == null
        ? null
        : Text(title, style: AppType.sectionTitle),
    actions: [...actions, const SizedBox(width: AppSpacing.s)],
  );
}

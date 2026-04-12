import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Demo (10 dk) / premium (24 saat) linkler için saniyelik geri sayım.
class LinkValidityCountdown extends StatefulWidget {
  const LinkValidityCountdown({
    super.key,
    required this.validUntil,
    this.compact = false,
    this.foreground,
  });

  final DateTime validUntil;
  final bool compact;
  final Color? foreground;

  @override
  State<LinkValidityCountdown> createState() => _LinkValidityCountdownState();
}

class _LinkValidityCountdownState extends State<LinkValidityCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _format(Duration remaining) {
    if (remaining.inSeconds <= 0) return '00:00';
    final h = remaining.inHours;
    final m = remaining.inMinutes.remainder(60);
    final s = remaining.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final remaining = widget.validUntil.difference(now);
    final expired = remaining.inSeconds <= 0;
    final fg = widget.foreground ?? Theme.of(context).colorScheme.onSurface;

    final baseStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: expired ? Colors.redAccent.shade100 : fg,
        );

    if (expired) {
      return Text(
        L10n.get(context, 'linkCountdownExpired'),
        style: baseStyle?.copyWith(fontFamily: null, fontWeight: FontWeight.w600),
      );
    }

    final time = _format(remaining);
    final label = widget.compact
        ? L10n.get(context, 'linkCountdownCompactPrefix')
        : L10n.get(context, 'linkCountdownRemaining');

    return Text(
      '$label $time',
      style: baseStyle,
    );
  }
}

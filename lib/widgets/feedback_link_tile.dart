import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../models/feedback_link.dart';

/// Profil / panel: tek link satırı — özet, kopyala, detay, sil.
class FeedbackLinkTile extends StatefulWidget {
  const FeedbackLinkTile({super.key, required this.link});

  final FeedbackLink link;

  static String formatDate(BuildContext context, DateTime? d) {
    if (d == null) return '—';
    return MaterialLocalizations.of(context).formatShortDate(d);
  }

  @override
  State<FeedbackLinkTile> createState() => _FeedbackLinkTileState();
}

class _FeedbackLinkTileState extends State<FeedbackLinkTile> {
  late final Future<int> _countFuture =
      firestoreService.feedbackCountForLink(widget.link.id);

  Future<void> _openDetail() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1a1a1f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final bottom = MediaQuery.of(ctx).padding.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                L10n.get(ctx, 'linkDetailTitle'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                widget.link.shareUrl,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              _DetailRow(
                label: L10n.get(ctx, 'linkCreatedAt'),
                value: FeedbackLinkTile.formatDate(ctx, widget.link.createdAt),
              ),
              FutureBuilder<int>(
                future: _countFuture,
                builder: (context, snap) {
                  return _DetailRow(
                    label: L10n.get(ctx, 'feedbackCountLabel'),
                    value: '${snap.data ?? 0}',
                  );
                },
              ),
              FutureBuilder<DateTime?>(
                future: firestoreService.lastFeedbackAtForLink(widget.link.id),
                builder: (context, snap) {
                  return _DetailRow(
                    label: L10n.get(ctx, 'lastFeedbackAt'),
                    value: snap.hasData && snap.data != null
                        ? FeedbackLinkTile.formatDate(ctx, snap.data)
                        : '—',
                  );
                },
              ),
              if (widget.link.title != null &&
                  widget.link.title!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                _DetailRow(
                  label: L10n.get(ctx, 'linkTitleLabel'),
                  value: widget.link.title!,
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.link.shareUrl));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(L10n.get(ctx, 'linkCopied'))),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text(L10n.get(ctx, 'copyLink')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.get(ctx, 'linkDeleteTitle')),
        content: Text(L10n.get(ctx, 'linkDeleteBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L10n.get(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L10n.get(ctx, 'linkDelete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await firestoreService.deactivateLink(widget.link.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.get(context, 'linkDeleted'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${L10n.get(context, 'linkDeleteFailed')}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final created = FeedbackLinkTile.formatDate(context, widget.link.createdAt);

    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _openDetail,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.link_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.link.shareUrl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FutureBuilder<int>(
                      future: _countFuture,
                      builder: (context, snap) {
                        final n = snap.data ?? 0;
                        return Text(
                          '$created · $n ${L10n.get(context, 'feedbacksShort')}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 20),
                tooltip: L10n.get(context, 'linkCopied'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.link.shareUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(L10n.get(context, 'linkCopied'))),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.info_outline_rounded, size: 20),
                tooltip: L10n.get(context, 'linkDetails'),
                onPressed: _openDetail,
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: Colors.red.shade300,
                ),
                tooltip: L10n.get(context, 'linkDelete'),
                onPressed: _confirmDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

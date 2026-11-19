import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../providers.dart';
import '../theme/app_theme.dart';

/// Maps icon names stored in the content database to Material icons.
class AppIcons {
  static const Map<String, IconData> _map = {
    'school': Icons.school_rounded,
    'eco': Icons.eco_rounded,
    'thermostat': Icons.thermostat_rounded,
    'devices': Icons.devices_rounded,
    'smart_toy': Icons.smart_toy_rounded,
    'science': Icons.science_rounded,
    'local_hospital': Icons.local_hospital_rounded,
    'self_improvement': Icons.self_improvement_rounded,
    'psychology': Icons.psychology_rounded,
    'groups': Icons.groups_rounded,
    'festival': Icons.festival_rounded,
    'public': Icons.public_rounded,
    'trending_up': Icons.trending_up_rounded,
    'business_center': Icons.business_center_rounded,
    'work': Icons.work_rounded,
    'account_balance': Icons.account_balance_rounded,
    'how_to_vote': Icons.how_to_vote_rounded,
    'local_police': Icons.local_police_rounded,
    'gavel': Icons.gavel_rounded,
    'flight_takeoff': Icons.flight_takeoff_rounded,
    'directions_bus': Icons.directions_bus_rounded,
    'location_city': Icons.location_city_rounded,
    'home': Icons.home_rounded,
    'architecture': Icons.architecture_rounded,
    'agriculture': Icons.agriculture_rounded,
    'restaurant': Icons.restaurant_rounded,
    'family_restroom': Icons.family_restroom_rounded,
    'favorite': Icons.favorite_rounded,
    'forum': Icons.forum_rounded,
    'newspaper': Icons.newspaper_rounded,
    'campaign': Icons.campaign_rounded,
    'palette': Icons.palette_rounded,
    'music_note': Icons.music_note_rounded,
    'sports_soccer': Icons.sports_soccer_rounded,
    'pets': Icons.pets_rounded,
    'forest': Icons.forest_rounded,
    'bolt': Icons.bolt_rounded,
    'rocket_launch': Icons.rocket_launch_rounded,
    'biotech': Icons.biotech_rounded,
    'volunteer_activism': Icons.volunteer_activism_rounded,
    'diversity_3': Icons.diversity_3_rounded,
    'connecting_airports': Icons.connecting_airports_rounded,
    'shopping_cart': Icons.shopping_cart_rounded,
    'spa': Icons.spa_rounded,
    'history_edu': Icons.history_edu_rounded,
    'terrain': Icons.terrain_rounded,
    'water_drop': Icons.water_drop_rounded,
    'balance': Icons.balance_rounded,
    'policy': Icons.policy_rounded,
    'recycling': Icons.recycling_rounded,
    'menu_book': Icons.menu_book_rounded,
    'auto_stories': Icons.auto_stories_rounded,
    'insert_chart': Icons.insert_chart_rounded,
    'edit_note': Icons.edit_note_rounded,
    'record_voice_over': Icons.record_voice_over_rounded,
    'headphones': Icons.headphones_rounded,
    'link': Icons.link_rounded,
    'format_quote': Icons.format_quote_rounded,
    'join_inner': Icons.join_inner_rounded,
    'compare_arrows': Icons.compare_arrows_rounded,
    'local_florist': Icons.local_florist_rounded,
    'park': Icons.park_rounded,
    'emoji_events': Icons.emoji_events_rounded,
    'local_fire_department': Icons.local_fire_department_rounded,
    'whatshot': Icons.whatshot_rounded,
    'verified': Icons.verified_rounded,
    'workspace_premium': Icons.workspace_premium_rounded,
    'replay': Icons.replay_rounded,
    'quiz': Icons.quiz_rounded,
  };

  static IconData of(String? name) => _map[name] ?? Icons.label_rounded;
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: cs.primary),
            ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
            ),
            if (actionLabel != null) ...[const SizedBox(height: 20), FilledButton(onPressed: onAction, child: Text(actionLabel!))],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  const ErrorView(this.error, {super.key, this.onRetry});
  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.error_outline_rounded,
    title: 'Đã xảy ra lỗi',
    message: '$error',
    actionLabel: onRetry == null ? null : 'Thử lại',
    onAction: onRetry,
  );
}

class LoadingView extends StatelessWidget {
  final String? message;
  const LoadingView({super.key, this.message});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        if (message != null) ...[const SizedBox(height: 16), Text(message!)],
      ],
    ),
  );
}

/// Renders an [AsyncValue] with consistent loading / error states.
class AsyncView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  const AsyncView(this.value, {super.key, required this.builder, this.onRetry});

  @override
  Widget build(BuildContext context) => value.when(
    data: builder,
    loading: () => const LoadingView(),
    error: (e, _) => ErrorView(e, onRetry: onRetry),
  );
}

class LevelBadge extends StatelessWidget {
  final String? cefr;
  final int difficulty;
  final bool compact;
  const LevelBadge({super.key, this.cefr, required this.difficulty, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final label = cefr ?? '★$difficulty';
    final color = cefr != null ? AppColors.cefrColor(cefr) : const Color(0xFF94A3B8);
    return Tooltip(
      message: cefr != null ? 'Cấp độ CEFR $cefr (CEFR-J / Octanove)' : 'Độ khó ước tính $difficulty/5 (theo tần suất)',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: compact ? 11 : 12),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  const Pill(this.text, {super.key, this.color, this.icon});
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              text,
              style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class WordTile extends StatelessWidget {
  final EntrySummary entry;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? subtitleOverride;
  const WordTile({super.key, required this.entry, this.onTap, this.trailing, this.subtitleOverride});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.headword,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entry.posVi,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitleOverride ?? entry.meaningVi,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              LevelBadge(cefr: entry.cefr, difficulty: entry.difficulty, compact: true),
              if (trailing != null) trailing! else Icon(Icons.chevron_right_rounded, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const StatTile({super.key, required this.icon, required this.value, required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Text(label, maxLines: 2, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

class RoundedProgress extends StatelessWidget {
  final double value;
  final double height;
  final Color? color;
  final Color? background;
  const RoundedProgress({super.key, required this.value, this.height = 8, this.color, this.background});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: LinearProgressIndicator(
      value: value.clamp(0, 1).toDouble(),
      minHeight: height,
      color: color ?? Theme.of(context).colorScheme.primary,
      backgroundColor: background ?? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
    ),
  );
}

/// Sentence with the target word form emphasised.
class HighlightText extends StatelessWidget {
  final String text;
  final String? highlight;
  final TextStyle? style;
  const HighlightText(this.text, {super.key, this.highlight, this.style});

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    if (highlight == null || highlight!.isEmpty) return Text(text, style: base);
    final idx = text.toLowerCase().indexOf(highlight!.toLowerCase());
    if (idx < 0) return Text(text, style: base);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + highlight!.length),
            style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary),
          ),
          TextSpan(text: text.substring(idx + highlight!.length)),
        ],
      ),
    );
  }
}

/// Pronunciation button using the offline TTS service; explains clearly when no offline voice exists.
class SpeakButton extends ConsumerWidget {
  final String text;
  final double size;
  final bool slow;
  final Color? color;
  const SpeakButton(this.text, {super.key, this.size = 24, this.slow = false, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(ttsStatusProvider).valueOrNull;
    final available = status?.canSpeak ?? false;
    return IconButton(
      tooltip: slow ? 'Phát âm chậm' : 'Phát âm',
      iconSize: size,
      color: color ?? Theme.of(context).colorScheme.primary,
      icon: Icon(slow ? Icons.slow_motion_video_rounded : (available ? Icons.volume_up_rounded : Icons.volume_off_rounded)),
      onPressed: () async {
        final s = ref.read(settingsProvider);
        final ok = await ref.read(ttsProvider).speak(text, accent: s.accent, rate: slow ? 0.25 : s.speechRate);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Chưa có giọng đọc tiếng Anh ngoại tuyến trên máy. Vào Cài đặt điện thoại › Chuyển văn bản thành giọng nói để tải dữ liệu giọng nói, hoặc xem phiên âm IPA.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
      },
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Đồng ý',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Value returned by [showCountPicker] when the learner chooses "Tất cả".
const int kCountAll = 1000;

/// Bottom sheet that lets the learner choose how many cards / questions to practise.
/// Returns the chosen number, [kCountAll] for "Tất cả", or null if dismissed.
Future<int?> showCountPicker(
  BuildContext context, {
  required String title,
  String? subtitle,
  int initial = 10,
  List<int> options = const [5, 10, 15, 20, 30, 50],
  bool allowAll = false,
  String unit = 'thẻ',
  int maxCustom = 200,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useRootNavigator: true, // cover the bottom navigation bar
    builder: (ctx) => _CountPickerSheet(
      title: title,
      subtitle: subtitle,
      initial: initial,
      options: options,
      allowAll: allowAll,
      unit: unit,
      maxCustom: maxCustom,
    ),
  );
}

class _CountPickerSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final int initial;
  final List<int> options;
  final bool allowAll;
  final String unit;
  final int maxCustom;
  const _CountPickerSheet({
    required this.title,
    this.subtitle,
    required this.initial,
    required this.options,
    required this.allowAll,
    required this.unit,
    required this.maxCustom,
  });
  @override
  State<_CountPickerSheet> createState() => _CountPickerSheetState();
}

class _CountPickerSheetState extends State<_CountPickerSheet> {
  late int _value = widget.initial;
  final _custom = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _submit() {
    if (_custom.text.trim().isNotEmpty) {
      final n = int.tryParse(_custom.text.trim());
      if (n == null || n < 1 || n > widget.maxCustom) {
        setState(() => _error = 'Nhập số từ 1 đến ${widget.maxCustom}');
        return;
      }
      _value = n;
    }
    Navigator.pop(context, _value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          if (widget.subtitle != null) ...[const SizedBox(height: 4), Text(widget.subtitle!, style: TextStyle(color: cs.onSurfaceVariant))],
          const SizedBox(height: 16),
          Text('Số lượng', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in widget.options)
                ChoiceChip(
                  key: ValueKey('count-$n'),
                  label: Text('$n ${widget.unit}'),
                  selected: _value == n && _custom.text.isEmpty,
                  onSelected: (_) => setState(() {
                    _value = n;
                    _custom.clear();
                    _error = null;
                  }),
                ),
              if (widget.allowAll)
                ChoiceChip(
                  key: const ValueKey('count-all'),
                  label: const Text('Tất cả'),
                  selected: _value == kCountAll && _custom.text.isEmpty,
                  onSelected: (_) => setState(() {
                    _value = kCountAll;
                    _custom.clear();
                    _error = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('count-custom'),
            controller: _custom,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Hoặc nhập số khác (1–${widget.maxCustom})',
              prefixIcon: const Icon(Icons.edit_rounded),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('count-start'),
              onPressed: _submit,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Bắt đầu'),
            ),
          ),
        ],
      ),
    );
  }
}

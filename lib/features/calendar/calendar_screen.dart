import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../providers.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month;
  Map<String, DayActivity>? _data;
  String? _selected;
  int _streak = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(statsRepoProvider);
    final d = await repo.activityForMonth(_month.year, _month.month);
    final days = await repo.activeDays();
    if (mounted) {
      setState(() {
        _data = d;
        _streak = Dates.streak(days);
      });
    }
  }

  void _shift(int m) {
    setState(() {
      _month = DateTime(_month.year, _month.month + m);
      _data = null;
      _selected = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final today = Dates.today();
    final data = _data;
    final sel = _selected == null ? null : data?[_selected];
    final monthTotal = data?.values.fold<int>(0, (s, d) => s + d.total) ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch học tập')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                      Expanded(
                        child: Text(
                          'Tháng ${_month.month}/${_month.year}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
                    ],
                  ),
                  Row(
                    children: [
                      for (final w in ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'])
                        Expanded(
                          child: Center(
                            child: Text(
                              w,
                              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (data == null)
                    const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: lead + daysInMonth,
                      itemBuilder: (c, i) {
                        if (i < lead) return const SizedBox.shrink();
                        final day = i - lead + 1;
                        final key = Dates.dayKey(DateTime(_month.year, _month.month, day));
                        final a = data[key];
                        final n = a?.total ?? 0;
                        final level = n == 0
                            ? 0
                            : n < 10
                            ? 1
                            : n < 30
                            ? 2
                            : n < 60
                            ? 3
                            : 4;
                        final color = level == 0
                            ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
                            : AppColors.teal.withValues(alpha: 0.2 + level * 0.2);
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => _selected = key),
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: key == today ? cs.primary : (key == _selected ? cs.secondary : Colors.transparent),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$day',
                                style: TextStyle(fontWeight: FontWeight.w600, color: level >= 3 ? Colors.white : null),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.local_fire_department_rounded,
                  value: '$_streak ngày',
                  label: 'Chuỗi hiện tại',
                  color: AppColors.amber,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  icon: Icons.event_available_rounded,
                  value: '${data?.values.where((d) => d.total > 0).length ?? 0}',
                  label: 'Ngày học trong tháng',
                  color: AppColors.teal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  icon: Icons.bar_chart_rounded,
                  value: '$monthTotal',
                  label: 'Lượt học trong tháng',
                  color: AppColors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_selected != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, dd/MM/yyyy', 'vi').format(Dates.parseDay(_selected!)),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (sel == null || sel.total == 0)
                      const Text('Không có hoạt động.')
                    else ...[
                      Text('• Từ mới: ${sel.newWords}'),
                      Text('• Lượt ôn thẻ: ${sel.reviews}'),
                      Text('• Câu trả lời: ${sel.answers} (đúng ${sel.correct})'),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

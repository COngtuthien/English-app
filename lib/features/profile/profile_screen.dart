import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final dash = ref.watch(dashboardProvider).valueOrNull;
    final items = [
      ('Thống kê học tập', Icons.insights_rounded, '/stats', AppColors.indigo),
      ('Thành tích', Icons.emoji_events_rounded, '/achievements', AppColors.amber),
      ('Lịch học', Icons.calendar_month_rounded, '/calendar', AppColors.teal),
      ('Từ yêu thích', Icons.favorite_rounded, '/words/favorites', Colors.pinkAccent),
      ('Từ khó', Icons.local_fire_department_rounded, '/words/difficult', AppColors.danger),
      ('Đã học gần đây', Icons.history_rounded, '/words/recent', const Color(0xFF8B5CF6)),
      ('Từng làm sai', Icons.error_outline_rounded, '/words/missed', const Color(0xFFF97316)),
    ];
    final system = [
      ('Cài đặt', Icons.settings_rounded, '/settings'),
      ('Sao lưu & khôi phục', Icons.backup_rounded, '/backup'),
      ('Giới thiệu ứng dụng', Icons.info_outline_rounded, '/about'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Cá nhân')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(24)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white24,
                  child: Text(
                    s.userName.isEmpty ? '🎓' : s.userName.characters.first.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.userName.isEmpty ? 'Học viên IELTS' : s.userName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      Text(
                        '${s.currentLevel} → IELTS ${s.targetBand} • ${s.dailyNewWords} từ/ngày',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                      ),
                      if (dash != null)
                        Text(
                          '${dash.totalStudied} từ đã học • chuỗi ${dash.streak} ngày',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(indent: 56),
                  ListTile(
                    leading: Icon(items[i].$2, color: items[i].$4),
                    title: Text(items[i].$1),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(items[i].$3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < system.length; i++) ...[
                  if (i > 0) const Divider(indent: 56),
                  ListTile(
                    leading: Icon(system[i].$2),
                    title: Text(system[i].$1),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(system[i].$3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Pill('Hoạt động hoàn toàn ngoại tuyến', icon: Icons.wifi_off_rounded, color: AppColors.teal),
          ),
        ],
      ),
    );
  }
}

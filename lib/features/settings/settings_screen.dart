import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/common.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/tts_service.dart';
import '../../providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final tts = ref.watch(ttsStatusProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SectionHeader('Hồ sơ & mục tiêu'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: const Text('Tên hiển thị'),
                  subtitle: Text(s.userName.isEmpty ? '(chưa đặt)' : s.userName),
                  onTap: () async {
                    final ctrl = TextEditingController(text: s.userName);
                    final v = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Tên hiển thị'),
                        content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.words),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Lưu')),
                        ],
                      ),
                    );
                    if (v != null) n.update((x) => x.copyWith(userName: v));
                  },
                ),
                _choiceTile<String>(
                  context,
                  Icons.trending_up_rounded,
                  'Trình độ hiện tại',
                  s.currentLevel,
                  ['B1', 'B2', 'C1'],
                  (v) => v,
                  (v) => n.update((x) => x.copyWith(currentLevel: v)),
                ),
                _choiceTile<String>(
                  context,
                  Icons.flag_rounded,
                  'Mục tiêu IELTS',
                  s.targetBand,
                  ['6.5', '7.0', '7.5', '8.0', '8.5+'],
                  (v) => v,
                  (v) => n.update((x) => x.copyWith(targetBand: v)),
                ),
              ],
            ),
          ),
          const SectionHeader('Học tập'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.today_rounded),
                  title: Text('Từ mới mỗi ngày: ${s.dailyNewWords}'),
                  subtitle: Slider(
                    value: s.dailyNewWords.toDouble(),
                    min: 5,
                    max: 50,
                    divisions: 9,
                    label: '${s.dailyNewWords}',
                    onChanged: (v) => n.update((x) => x.copyWith(dailyNewWords: v.round())),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.replay_rounded),
                  title: Text('Giới hạn ôn tập mỗi phiên: ${s.dailyReviewLimit}'),
                  subtitle: Slider(
                    value: s.dailyReviewLimit.toDouble(),
                    min: 50,
                    max: 500,
                    divisions: 9,
                    label: '${s.dailyReviewLimit}',
                    onChanged: (v) => n.update((x) => x.copyWith(dailyReviewLimit: v.round())),
                  ),
                ),
                _choiceTile<String>(
                  context,
                  Icons.signal_cellular_alt_rounded,
                  'Mức độ từ mới',
                  s.levelFocus,
                  ['B1', 'B2', 'C1', 'C2', 'all'],
                  (v) => {'B1': 'B1–B2', 'B2': 'B2–C1 (khuyên dùng)', 'C1': 'C1–C2', 'C2': 'Chỉ C2', 'all': 'Tất cả'}[v]!,
                  (v) => n.update((x) => x.copyWith(levelFocus: v)),
                ),
                _choiceTile<StudyOrder>(
                  context,
                  Icons.sort_rounded,
                  'Thứ tự học',
                  s.studyOrder,
                  StudyOrder.values,
                  (v) => {
                    StudyOrder.frequency: 'Thông dụng trước',
                    StudyOrder.random: 'Ngẫu nhiên',
                    StudyOrder.alphabetical: 'Theo bảng chữ cái',
                  }[v]!,
                  (v) => n.update((x) => x.copyWith(studyOrder: v)),
                ),
                _choiceTile<FlashMode>(
                  context,
                  Icons.style_rounded,
                  'Kiểu flashcard mặc định',
                  s.flashMode,
                  FlashMode.values,
                  (v) => {
                    FlashMode.enToVi: 'Anh → Việt',
                    FlashMode.viToEn: 'Việt → Anh',
                    FlashMode.defToWord: 'Định nghĩa → Từ',
                    FlashMode.cloze: 'Điền từ vào câu',
                  }[v]!,
                  (v) => n.update((x) => x.copyWith(flashMode: v)),
                ),
                ListTile(
                  leading: const Icon(Icons.category_rounded),
                  title: const Text('Chủ đề ưu tiên'),
                  subtitle: Text(s.preferredTopics.isEmpty ? 'Tất cả chủ đề' : '${s.preferredTopics.length} chủ đề đã chọn'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _pickTopics(context, ref),
                ),
              ],
            ),
          ),
          const SectionHeader('Phát âm (ngoại tuyến)'),
          Card(
            child: Column(
              children: [
                _choiceTile<String>(
                  context,
                  Icons.record_voice_over_rounded,
                  'Giọng đọc',
                  s.accent,
                  ['uk', 'us'],
                  (v) => v == 'uk' ? 'Anh – Anh (UK)' : 'Anh – Mỹ (US)',
                  (v) => n.update((x) => x.copyWith(accent: v)),
                ),
                ListTile(
                  leading: const Icon(Icons.speed_rounded),
                  title: Text('Tốc độ đọc: ${s.speechRate.toStringAsFixed(2)}'),
                  subtitle: Slider(
                    value: s.speechRate,
                    min: 0.2,
                    max: 0.7,
                    divisions: 10,
                    onChanged: (v) => n.update((x) => x.copyWith(speechRate: v)),
                  ),
                  trailing: const SpeakButton('pronunciation'),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_rounded),
                  title: const Text('Tự động phát âm trên flashcard'),
                  value: s.autoPlayAudio,
                  onChanged: (v) => n.update((x) => x.copyWith(autoPlayAudio: v)),
                ),
                ListTile(
                  leading: Icon(
                    tts?.canSpeak == true ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    color: tts?.canSpeak == true ? Colors.green : Colors.orange,
                  ),
                  title: Text(switch (tts?.availability) {
                    TtsAvailability.available => 'Có giọng tiếng Anh ngoại tuyến (UK & US)',
                    TtsAvailability.otherAccentOnly => 'Có giọng tiếng Anh ngoại tuyến (một giọng)',
                    TtsAvailability.unavailable => 'Chưa có giọng tiếng Anh ngoại tuyến',
                    _ => 'Đang kiểm tra giọng đọc…',
                  }),
                  subtitle: Text(
                    tts?.engine != null ? 'Bộ máy đọc: ${tts!.engine}' : 'Dùng bộ máy chuyển văn bản thành giọng nói của điện thoại',
                  ),
                  trailing: TextButton(onPressed: () => ref.read(ttsProvider).refresh(), child: const Text('Kiểm tra')),
                ),
              ],
            ),
          ),
          const SectionHeader('Giao diện & nhắc nhở'),
          Card(
            child: Column(
              children: [
                _choiceTile<String>(
                  context,
                  Icons.dark_mode_rounded,
                  'Giao diện',
                  s.themeMode,
                  ['system', 'light', 'dark'],
                  (v) => {'system': 'Theo hệ thống', 'light': 'Sáng', 'dark': 'Tối'}[v]!,
                  (v) => n.update((x) => x.copyWith(themeMode: v)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_rounded),
                  title: const Text('Nhắc học mỗi ngày'),
                  subtitle: Text(
                    s.reminderEnabled
                        ? 'Lúc ${s.reminderHour.toString().padLeft(2, '0')}:${s.reminderMinute.toString().padLeft(2, '0')}'
                        : 'Đang tắt',
                  ),
                  value: s.reminderEnabled,
                  onChanged: (v) async {
                    final notif = ref.read(notificationProvider);
                    if (v) {
                      final granted = await notif.requestPermission();
                      final ok = granted && await notif.scheduleDaily(s.reminderHour, s.reminderMinute);
                      if (!ok) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Không bật được thông báo. Hãy cấp quyền thông báo cho ứng dụng trong Cài đặt điện thoại.'),
                            ),
                          );
                        }
                        return;
                      }
                    } else {
                      await notif.cancelDaily();
                    }
                    n.update((x) => x.copyWith(reminderEnabled: v));
                  },
                ),
                if (s.reminderEnabled)
                  ListTile(
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Giờ nhắc'),
                    trailing: Text('${s.reminderHour.toString().padLeft(2, '0')}:${s.reminderMinute.toString().padLeft(2, '0')}'),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute),
                      );
                      if (t == null) return;
                      await n.update((x) => x.copyWith(reminderHour: t.hour, reminderMinute: t.minute));
                      await ref.read(notificationProvider).scheduleDaily(t.hour, t.minute);
                    },
                  ),
              ],
            ),
          ),
          const SectionHeader('Dữ liệu'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_rounded),
                  title: const Text('Sao lưu & khôi phục'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/backup'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                  title: const Text('Xóa toàn bộ tiến độ học', style: TextStyle(color: Colors.red)),
                  subtitle: const Text('Không thể hoàn tác – nên sao lưu trước'),
                  onTap: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Xóa toàn bộ tiến độ?',
                      message: 'Mọi từ đã học, lịch sử ôn tập, kết quả quiz, yêu thích và thành tích sẽ bị xóa. Cài đặt được giữ lại.',
                      confirm: 'Xóa',
                      destructive: true,
                    );
                    if (!ok) return;
                    final db = ref.read(databaseProvider).db;
                    await db.transaction((txn) async {
                      for (final t in [
                        'quiz_answers',
                        'quiz_sessions',
                        'review_history',
                        'learning_cards',
                        'favorites',
                        'study_queue',
                        'achievements',
                        'study_activity',
                      ]) {
                        await txn.delete(t);
                      }
                    });
                    ref.read(dataVersionProvider.notifier).state++;
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa tiến độ học.')));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _choiceTile<T>(
    BuildContext context,
    IconData icon,
    String title,
    T value,
    List<T> options,
    String Function(T) label,
    void Function(T) onChanged,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(label(value)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () async {
        final v = await showModalBottomSheet<T>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                ),
                RadioGroup<T>(
                  groupValue: value,
                  onChanged: (x) => Navigator.pop(ctx, x),
                  child: Column(
                    children: [for (final o in options) RadioListTile<T>(value: o, title: Text(label(o)))],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (v != null) onChanged(v);
      },
    );
  }

  Future<void> _pickTopics(BuildContext context, WidgetRef ref) async {
    final topics = (await ref.read(vocabRepoProvider).topics()).where((t) => t.category == 'ielts').toList();
    final sel = {...ref.read(settingsProvider).preferredTopics};
    if (!context.mounted) return;
    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (c, sc) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(child: Text('Chủ đề ưu tiên', style: Theme.of(context).textTheme.titleMedium)),
                    TextButton(onPressed: () => setS(sel.clear), child: const Text('Bỏ chọn hết')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, sel), child: const Text('Lưu')),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: sc,
                  children: [
                    for (final t in topics)
                      CheckboxListTile(
                        secondary: Icon(AppIcons.of(t.icon)),
                        title: Text(t.nameVi),
                        subtitle: Text('${t.wordCount} từ'),
                        value: sel.contains(t.code),
                        onChanged: (v) => setS(() => v == true ? sel.add(t.code) : sel.remove(t.code)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (res != null) {
      await ref.read(settingsProvider.notifier).update((x) => x.copyWith(preferredTopics: res.toList()));
    }
  }
}

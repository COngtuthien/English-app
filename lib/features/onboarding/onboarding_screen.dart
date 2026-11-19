import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;
  final _name = TextEditingController();
  String _level = 'B2';
  String _band = '7.5';
  int _daily = 20;
  final Set<String> _topics = {};

  static const _intro = [
    (
      Icons.menu_book_rounded,
      'Hơn 10.000 mục từ IELTS',
      'Từ vựng học thuật, 50 chủ đề IELTS, collocation, cụm động từ và thành ngữ – kèm nghĩa tiếng Việt, định nghĩa tiếng Anh và câu ví dụ.',
    ),
    (
      Icons.psychology_rounded,
      'Lặp lại ngắt quãng FSRS',
      'Thuật toán FSRS lên lịch ôn tập đúng lúc bạn sắp quên, giúp ghi nhớ lâu với ít thời gian nhất.',
    ),
    (
      Icons.wifi_off_rounded,
      '100% ngoại tuyến',
      'Không cần Internet, không tài khoản, không quảng cáo. Mọi dữ liệu học tập lưu ngay trên điện thoại của bạn.',
    ),
  ];

  @override
  void dispose() {
    _page.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref
        .read(settingsProvider.notifier)
        .update(
          (s) => s.copyWith(
            userName: _name.text.trim(),
            currentLevel: _level,
            targetBand: _band,
            dailyNewWords: _daily,
            preferredTopics: _topics.toList(),
            levelFocus: _level == 'B1' ? 'B1' : (_level == 'C1' ? 'C1' : 'B2'),
            onboarded: true,
          ),
        );
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final total = _intro.length + 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: List.generate(
                        total,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.only(right: 6),
                          width: i == _index ? 26 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i <= _index ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_index < total - 1) TextButton(onPressed: () => _page.jumpToPage(total - 1), child: const Text('Bỏ qua')),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  for (final (icon, title, body) in _intro) _IntroPage(icon: icon, title: title, body: body),
                  _goalPage(context),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (_index < total - 1) {
                      _page.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                    } else {
                      _finish();
                    }
                  },
                  child: Text(_index < total - 1 ? 'Tiếp tục' : 'Bắt đầu học'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _goalPage(BuildContext context) {
    final topics = ref.watch(topicsProvider);
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        Text('Thiết lập mục tiêu', style: tt.headlineSmall),
        const SizedBox(height: 6),
        Text('Bạn có thể thay đổi bất cứ lúc nào trong Cài đặt.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Tên của bạn (không bắt buộc)', prefixIcon: Icon(Icons.person_outline)),
        ),
        const SizedBox(height: 20),
        Text('Trình độ hiện tại', style: tt.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'B1', label: Text('B1')),
            ButtonSegment(value: 'B2', label: Text('B2')),
            ButtonSegment(value: 'C1', label: Text('C1')),
          ],
          selected: {_level},
          onSelectionChanged: (v) => setState(() => _level = v.first),
        ),
        const SizedBox(height: 20),
        Text('Mục tiêu IELTS', style: tt.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final b in ['6.5', '7.0', '7.5', '8.0', '8.5+'])
              ChoiceChip(label: Text(b), selected: _band == b, onSelected: (_) => setState(() => _band = b)),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Text('Số từ mới mỗi ngày', style: tt.titleSmall)),
            Text('$_daily từ', style: tt.titleMedium?.copyWith(color: AppColors.indigo)),
          ],
        ),
        Slider(
          value: _daily.toDouble(),
          min: 5,
          max: 50,
          divisions: 9,
          label: '$_daily',
          onChanged: (v) => setState(() => _daily = v.round()),
        ),
        const SizedBox(height: 12),
        Text('Chủ đề ưu tiên (không bắt buộc)', style: tt.titleSmall),
        const SizedBox(height: 8),
        topics.when(
          data: (list) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in list.where((t) => t.category == 'ielts'))
                FilterChip(
                  avatar: Icon(AppIcons.of(t.icon), size: 18),
                  label: Text(t.nameVi),
                  selected: _topics.contains(t.code),
                  onSelected: (v) => setState(() => v ? _topics.add(t.code) : _topics.remove(t.code)),
                ),
            ],
          ),
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
        ),
      ],
    );
  }
}

class _IntroPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _IntroPage({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(44),
              boxShadow: softShadow(context, opacity: 0.25),
            ),
            child: Icon(icon, size: 72, color: Colors.white),
          ),
          const SizedBox(height: 36),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

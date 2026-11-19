import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

class PracticeHubScreen extends StatelessWidget {
  const PracticeHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modes = [
      ('Quiz từ vựng', '10 dạng câu hỏi, 5–30 câu', Icons.quiz_rounded, '/quiz', AppColors.indigo),
      ('Ghép từ', 'Nối từ tiếng Anh với nghĩa', Icons.extension_rounded, '/match', AppColors.teal),
      ('Gõ từ', 'Luyện chính tả & nhớ từ chủ động', Icons.keyboard_rounded, '/typing', AppColors.amber),
      ('Luyện nghe', 'Nghe và nhận diện từ', Icons.headphones_rounded, '/listening', const Color(0xFFEC4899)),
      ('Writing', 'Từ vựng Writing Task 1 & 2', Icons.edit_note_rounded, '/writing', const Color(0xFF8B5CF6)),
      ('Speaking', 'Gói từ vựng Part 1–2–3', Icons.record_voice_over_rounded, '/speaking', const Color(0xFF0EA5E9)),
    ];
    final flash = [
      ('Flashcard ngẫu nhiên', Icons.shuffle_rounded, '/flashcards?kind=random'),
      ('Ôn từ khó', Icons.warning_amber_rounded, '/flashcards?kind=difficult'),
      ('Ôn từ yêu thích', Icons.favorite_rounded, '/flashcards?kind=favorites'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Luyện tập')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
            ),
            itemCount: modes.length,
            itemBuilder: (c, i) {
              final m = modes[i];
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => context.push(m.$4),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: m.$5.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(14)),
                          child: Icon(m.$3, color: m.$5, size: 26),
                        ),
                        const Spacer(),
                        Text(m.$1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(m.$2, maxLines: 2, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SectionHeader('Flashcard'),
          for (final f in flash)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: Icon(f.$2, color: AppColors.indigo),
                  title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(f.$3),
                ),
              ),
            ),
          const SectionHeader('Danh sách từ'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.favorite_rounded, color: Colors.pinkAccent),
                  title: const Text('Từ yêu thích'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/words/favorites'),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.local_fire_department_rounded, color: AppColors.danger),
                  title: const Text('Từ khó'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/words/difficult'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

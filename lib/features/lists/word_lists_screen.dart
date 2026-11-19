import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../providers.dart';

enum WordListKind { favorites, difficult, recent, missed }

class WordListsScreen extends ConsumerWidget {
  final WordListKind kind;
  const WordListsScreen({super.key, required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (title, provider, emptyIcon, emptyTitle, emptyMsg, practiceKind) = switch (kind) {
      WordListKind.favorites => (
        'Từ yêu thích',
        favoritesProvider,
        Icons.favorite_border_rounded,
        'Chưa có từ yêu thích',
        'Nhấn ♡ ở trang chi tiết từ hoặc trong gói Speaking để lưu từ.',
        'favorites',
      ),
      WordListKind.difficult => (
        'Từ khó',
        difficultProvider,
        Icons.sentiment_satisfied_rounded,
        'Chưa có từ khó',
        'Từ bạn hay quên (chọn "Quên") hoặc trả lời sai nhiều lần sẽ xuất hiện ở đây.',
        'difficult',
      ),
      WordListKind.recent => (
        'Đã học gần đây',
        recentProvider,
        Icons.history_rounded,
        'Chưa học từ nào',
        'Bắt đầu học từ mới từ Trang chủ.',
        null,
      ),
      WordListKind.missed => (
        'Từng làm sai',
        missedProvider,
        Icons.check_circle_outline_rounded,
        'Chưa có lỗi nào',
        'Các từ bạn chọn "Quên" hoặc trả lời sai trong quiz sẽ được liệt kê ở đây.',
        null,
      ),
    };
    final data = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: practiceKind == null || (data.valueOrNull?.isEmpty ?? true)
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final n = await showCountPicker(
                  context,
                  title: title,
                  subtitle: 'Chọn số thẻ, hoặc "Tất cả" để ôn toàn bộ ${data.valueOrNull?.length ?? 0} từ',
                  initial: kCountAll,
                  allowAll: true,
                );
                if (n != null && context.mounted) context.push('/flashcards?kind=$practiceKind&count=$n');
              },
              icon: const Icon(Icons.style_rounded),
              label: const Text('Ôn bằng flashcard'),
            ),
      body: AsyncView<List<EntrySummary>>(
        data,
        onRetry: () => ref.invalidate(provider),
        builder: (list) => list.isEmpty
            ? EmptyState(icon: emptyIcon, title: emptyTitle, message: emptyMsg)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (c, i) => WordTile(entry: list[i], onTap: () => context.push('/word/${list[i].id}')),
              ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../data/repositories/vocabulary_repository.dart';
import '../../domain/quiz/quiz_engine.dart';
import '../../providers.dart';

/// Vocabulary list for one topic, with paging, status filter and study actions.
class TopicWordsScreen extends ConsumerStatefulWidget {
  final String code;
  const TopicWordsScreen({super.key, required this.code});
  @override
  ConsumerState<TopicWordsScreen> createState() => _TopicWordsScreenState();
}

class _TopicWordsScreenState extends ConsumerState<TopicWordsScreen> {
  TopicInfo? _topic;
  final List<EntrySummary> _items = [];
  bool _loading = true;
  bool _hasMore = true;
  LearnStatus _status = LearnStatus.any;
  SortMode _sort = SortMode.frequency;
  final _scroll = ScrollController();
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _topic = await ref.read(vocabRepoProvider).topicByCode(widget.code);
      await _reload();
    } catch (e) {
      setState(() => _error = e);
    }
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _hasMore = true;
      _loading = true;
    });
    await _loadMore(force: true);
  }

  Future<void> _loadMore({bool force = false}) async {
    if (_topic == null || (!force && (_loading || !_hasMore))) return;
    _loading = true;
    final page = await ref
        .read(vocabRepoProvider)
        .search(
          VocabFilter(topicId: _topic!.id, status: _status, sort: _sort),
          limit: 40,
          offset: _items.length,
        );
    if (!mounted) return;
    setState(() {
      _items.addAll(page);
      _hasMore = page.length == 40;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _topic;
    return Scaffold(
      appBar: AppBar(title: Text(t?.nameVi ?? 'Chủ đề')),
      body: _error != null
          ? ErrorView(_error!, onRetry: _init)
          : t == null
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _reload,
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(child: _header(t)),
                  SliverToBoxAdapter(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(
                        children: [
                          for (final s in LearnStatus.values) ...[
                            ChoiceChip(
                              label: Text(switch (s) {
                                LearnStatus.any => 'Tất cả',
                                LearnStatus.unseen => 'Chưa học',
                                LearnStatus.learning => 'Đang học',
                                LearnStatus.mastered => 'Thành thạo',
                              }),
                              selected: _status == s,
                              onSelected: (_) {
                                _status = s;
                                _reload();
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                          PopupMenuButton<SortMode>(
                            tooltip: 'Sắp xếp',
                            initialValue: _sort,
                            onSelected: (v) {
                              _sort = v;
                              _reload();
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: SortMode.frequency, child: Text('Theo tần suất')),
                              PopupMenuItem(value: SortMode.alphabetical, child: Text('Theo bảng chữ cái')),
                              PopupMenuItem(value: SortMode.level, child: Text('Theo cấp độ')),
                            ],
                            child: const Chip(avatar: Icon(Icons.sort_rounded, size: 18), label: Text('Sắp xếp')),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_items.isEmpty && !_loading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(icon: Icons.filter_alt_off_rounded, title: 'Không có từ nào', message: 'Thử chọn bộ lọc khác.'),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList.separated(
                        itemCount: _items.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (c, i) {
                          if (i >= _items.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final e = _items[i];
                          return WordTile(entry: e, onTap: () => context.push('/word/${e.id}'));
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _header(TopicInfo t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(AppIcons.of(t.icon), color: Colors.white, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.nameEn,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      Text(
                        '${t.wordCount} mục từ • đã học ${t.learnedCount}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RoundedProgress(value: t.progress, color: Colors.white, background: Colors.white24),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.indigoDeep,
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () => context.push('/learn?topic=${t.id}'),
                    child: const Text('Học chủ đề'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () => context.push('/flashcards?kind=topic&topic=${t.id}'),
                    child: const Text('Flashcard'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () => context.push(
                      '/quiz/play',
                      extra: QuizConfig(
                        types: const {QuestionType.enToVi, QuestionType.viToEn, QuestionType.definition},
                        count: 10,
                        topicId: t.id,
                        preferLearned: false,
                      ),
                    ),
                    child: const Text('Quiz'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../data/repositories/vocabulary_repository.dart';
import '../../providers.dart';

const _posLabels = {
  'noun': 'Danh từ',
  'verb': 'Động từ',
  'adjective': 'Tính từ',
  'adverb': 'Trạng từ',
  'phrasal verb': 'Cụm động từ',
  'idiom': 'Thành ngữ',
  'collocation': 'Kết hợp từ',
  'expression': 'Cách diễn đạt',
  'preposition': 'Giới từ',
  'conjunction': 'Liên từ',
  'pronoun': 'Đại từ',
  'determiner': 'Hạn định từ',
};

class DictionaryScreen extends ConsumerStatefulWidget {
  const DictionaryScreen({super.key});
  @override
  ConsumerState<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends ConsumerState<DictionaryScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  VocabFilter _filter = const VocabFilter(sort: SortMode.frequency);
  final List<EntrySummary> _items = [];
  List<String> _suggestions = [];
  bool _loading = false;
  bool _hasMore = true;
  int _searchToken = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 500) _loadMore();
    });
    ref.read(vocabRepoProvider).totalEntries().then((n) => mounted ? setState(() => _total = n) : null);
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      _filter = _filter.copyWith(query: q, sort: q.isEmpty ? SortMode.frequency : SortMode.relevance);
      final sugg = await ref.read(vocabRepoProvider).suggestions(q);
      if (!mounted) return;
      setState(() => _suggestions = sugg.where((s) => s.toLowerCase() != q.trim().toLowerCase()).toList());
      _reload();
    });
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final token = ++_searchToken;
    setState(() {
      _loading = true;
      _hasMore = true;
    });
    final page = await ref.read(vocabRepoProvider).search(_filter, limit: 40, offset: 0);
    if (!mounted || token != _searchToken) return;
    setState(() {
      _items
        ..clear()
        ..addAll(page);
      _hasMore = page.length == 40 && !_filter.familySearch;
      _loading = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final token = _searchToken;
    _loading = true;
    final page = await ref.read(vocabRepoProvider).search(_filter, limit: 40, offset: _items.length);
    if (!mounted || token != _searchToken) return;
    setState(() {
      _items.addAll(page);
      _hasMore = page.length == 40;
      _loading = false;
    });
  }

  void _setFilter(VocabFilter f) {
    _filter = f;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Từ điển')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _ctrl,
              onChanged: _onQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Tìm tiếng Anh hoặc nghĩa tiếng Việt…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _ctrl.clear();
                          _onQuery('');
                        },
                      ),
              ),
            ),
          ),
          if (_suggestions.isNotEmpty && _ctrl.text.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final s in _suggestions)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(s),
                        onPressed: () {
                          _ctrl.text = s;
                          _ctrl.selection = TextSelection.collapsed(offset: s.length);
                          _onQuery(s);
                        },
                      ),
                    ),
                ],
              ),
            ),
          _filterBar(context),
          Expanded(child: _results(context, cs)),
        ],
      ),
    );
  }

  Widget _filterBar(BuildContext context) {
    final f = _filter;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          FilterChip(
            avatar: const Icon(Icons.tune_rounded, size: 18),
            label: Text(f.hasFilters ? 'Bộ lọc •' : 'Bộ lọc'),
            selected: f.hasFilters,
            onSelected: (_) => _openFilters(context),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Họ từ'),
            selected: f.familySearch,
            tooltip: 'Tìm các từ cùng họ (word family) với từ đang nhập',
            onSelected: (v) => _setFilter(f.copyWith(familySearch: v)),
          ),
          const SizedBox(width: 8),
          FilterChip(
            avatar: const Icon(Icons.favorite_rounded, size: 16),
            label: const Text('Yêu thích'),
            selected: f.favoritesOnly,
            onSelected: (v) => _setFilter(f.copyWith(favoritesOnly: v)),
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.history_rounded, size: 18),
            label: const Text('Đã học gần đây'),
            onPressed: () => context.push('/words/recent'),
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.error_outline_rounded, size: 18),
            label: const Text('Từng làm sai'),
            onPressed: () => context.push('/words/missed'),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<SortMode>(
            initialValue: f.sort,
            onSelected: (v) => _setFilter(f.copyWith(sort: v)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: SortMode.relevance, child: Text('Liên quan nhất')),
              PopupMenuItem(value: SortMode.frequency, child: Text('Thông dụng nhất')),
              PopupMenuItem(value: SortMode.alphabetical, child: Text('A → Z')),
              PopupMenuItem(value: SortMode.level, child: Text('Theo cấp độ CEFR')),
            ],
            child: const Chip(avatar: Icon(Icons.sort_rounded, size: 18), label: Text('Sắp xếp')),
          ),
        ],
      ),
    );
  }

  Widget _results(BuildContext context, ColorScheme cs) {
    if (_items.isEmpty && _loading) return const LoadingView();
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Không tìm thấy kết quả',
        message: _filter.familySearch
            ? 'Hãy nhập chính xác một từ tiếng Anh (ví dụ: "economy") để xem họ từ.'
            : 'Thử từ khóa khác, bỏ dấu tiếng Việt hoặc bỏ bớt bộ lọc.',
      );
    }
    return ListView.separated(
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (c, i) {
        if (i == _items.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _hasMore
                  ? const CircularProgressIndicator()
                  : Text(
                      _filter.query.isEmpty && !_filter.hasFilters ? 'Kho từ: $_total mục từ' : '${_items.length} kết quả',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
            ),
          );
        }
        final e = _items[i];
        return WordTile(entry: e, onTap: () => context.push('/word/${e.id}'));
      },
    );
  }

  Future<void> _openFilters(BuildContext context) async {
    final topics = await ref.read(vocabRepoProvider).topics();
    if (!context.mounted) return;
    final result = await showModalBottomSheet<VocabFilter>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FilterSheet(initial: _filter, topics: topics),
    );
    if (result != null) _setFilter(result);
  }
}

class _FilterSheet extends StatefulWidget {
  final VocabFilter initial;
  final List<TopicInfo> topics;
  const _FilterSheet({required this.initial, required this.topics});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late VocabFilter f = widget.initial;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),
          Text('Bộ lọc', style: tt.titleLarge),
          const SizedBox(height: 16),
          Text('Cấp độ CEFR', style: tt.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in ['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'none'])
                FilterChip(
                  label: Text(c == 'none' ? 'Chưa phân cấp' : c),
                  selected: f.cefr.contains(c),
                  selectedColor: AppColors.cefrColor(c).withValues(alpha: 0.2),
                  onSelected: (v) => setState(() {
                    final s = {...f.cefr};
                    v ? s.add(c) : s.remove(c);
                    f = f.copyWith(cefr: s);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Từ loại', style: tt.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _posLabels.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: f.pos == e.key,
                  onSelected: (v) => setState(() => f = v ? f.copyWith(pos: e.key) : f.copyWith(clearPos: true)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Độ khó', style: tt.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var d = 1; d <= 5; d++)
                ChoiceChip(
                  label: Text(['', 'Cơ bản', 'Trung cấp', 'Khá', 'Nâng cao', 'Chuyên sâu'][d]),
                  selected: f.difficulty == d,
                  onSelected: (v) => setState(() => f = v ? f.copyWith(difficulty: d) : f.copyWith(clearDifficulty: true)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Trạng thái học', style: tt.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final s in LearnStatus.values)
                ChoiceChip(
                  label: Text(switch (s) {
                    LearnStatus.any => 'Tất cả',
                    LearnStatus.unseen => 'Chưa học',
                    LearnStatus.learning => 'Đang học',
                    LearnStatus.mastered => 'Thành thạo',
                  }),
                  selected: f.status == s,
                  onSelected: (_) => setState(() => f = f.copyWith(status: s)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Chủ đề', style: tt.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            initialValue: f.topicId,
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: null, child: Text('Tất cả chủ đề')),
              for (final t in widget.topics)
                DropdownMenuItem(
                  value: t.id,
                  child: Text(t.nameVi, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => f = v == null ? f.copyWith(clearTopic: true) : f.copyWith(topicId: v)),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Chỉ từ yêu thích'),
            value: f.favoritesOnly,
            onChanged: (v) => setState(() => f = f.copyWith(favoritesOnly: v)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, VocabFilter(query: f.query, sort: f.sort, familySearch: f.familySearch)),
                  child: const Text('Xóa bộ lọc'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(onPressed: () => Navigator.pop(context, f), child: const Text('Áp dụng')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

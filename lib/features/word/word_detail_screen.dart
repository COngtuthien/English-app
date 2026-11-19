import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../providers.dart';

const sourceLabels = {
  'enwikt': 'Wiktionary (EN)',
  'viwikt': 'Wiktionary (VI)',
  'tatoeba': 'Tatoeba',
  'cefrj': 'CEFR-J',
  'octanove': 'Octanove C1/C2',
  'nawl': 'NAWL',
  'ngsl': 'NGSL',
  'ipadict': 'ipa-dict',
  'curated': 'Biên soạn riêng',
};

class WordDetailScreen extends ConsumerWidget {
  final int id;
  const WordDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(entryDetailProvider(id));
    final fav = ref.watch(isFavoriteProvider(id)).valueOrNull ?? false;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: fav ? 'Bỏ yêu thích' : 'Yêu thích',
            icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: fav ? Colors.pinkAccent : null),
            onPressed: () async {
              final now = await ref.read(learningRepoProvider).toggleFavorite(id);
              ref.read(dataVersionProvider.notifier).state++;
              if (context.mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(now ? 'Đã thêm vào Yêu thích' : 'Đã bỏ khỏi Yêu thích')));
              }
            },
          ),
        ],
      ),
      body: AsyncView<EntryDetail?>(
        detail,
        onRetry: () => ref.invalidate(entryDetailProvider(id)),
        builder: (d) => d == null
            ? const EmptyState(icon: Icons.search_off, title: 'Không tìm thấy từ', message: 'Mục từ này không tồn tại.')
            : _Body(d: d),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final EntryDetail d;
  const _Body({required this.d});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = d.summary;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final synonyms = d.rel('synonym');
    final antonyms = d.rel('antonym');
    final family = d.rel('family');
    final confusable = d.rel('confusable');
    final sentences = d.examples.where((e) => e.isSentence).toList();
    final phrases = d.examples.where((e) => !e.isSentence).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        // ---------------------------------------------------------------- header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            borderRadius: BorderRadius.circular(26),
            boxShadow: softShadow(context, opacity: 0.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      s.headword,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      s.cefr ?? 'Độ khó ${s.difficulty}/5',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              if (s.variants != null) ...[
                const SizedBox(height: 4),
                Text('Biến thể: ${s.variants}', style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
              ],
              const SizedBox(height: 6),
              Text(
                s.posVi + (d.register != null ? ' • ${d.register}' : ''),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (s.ipaUk != null) _ipaChip('UK', s.ipaUk!),
                  if (s.ipaUs != null) _ipaChip('US', s.ipaUs!),
                  SpeakButton(s.headword, color: Colors.white),
                  SpeakButton(s.headword, slow: true, color: Colors.white),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                s.meaningVi,
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700, height: 1.3),
              ),
              const SizedBox(height: 6),
              Text(s.definition, style: TextStyle(color: Colors.white.withValues(alpha: 0.92), height: 1.4)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _LearningCard(entry: s),
        if (d.translations.isNotEmpty) ...[
          const SectionHeader('Nghĩa tiếng Việt'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < d.translations.length; i++) ...[
                    if (i > 0) const Divider(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}. ',
                          style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.translations[i].meaningVi, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
                              if (d.translations[i].contextEn != null)
                                Text('(${d.translations[i].contextEn})', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        _src(context, d.translations[i].source),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (d.senses.isNotEmpty) ...[
          const SectionHeader('Định nghĩa tiếng Anh'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < d.senses.length; i++) ...[
                    if (i > 0) const Divider(height: 18),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${d.senses[i].number}. ',
                            style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
                          ),
                          if (d.senses[i].labels != null)
                            TextSpan(
                              text: '[${d.senses[i].labels}] ',
                              style: TextStyle(color: cs.secondary, fontSize: 12.5, fontStyle: FontStyle.italic),
                            ),
                          TextSpan(text: d.senses[i].definition, style: const TextStyle(height: 1.4)),
                        ],
                      ),
                    ),
                    if (d.senses[i].meaningVi != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 18),
                        child: Text(
                          '→ ${d.senses[i].meaningVi}',
                          style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (sentences.isNotEmpty) ...[
          const SectionHeader('Ví dụ'),
          for (final e in sentences)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            HighlightText(e.textEn, highlight: e.highlight, style: tt.bodyLarge?.copyWith(height: 1.4)),
                            if (e.textVi != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                e.textVi!,
                                style: TextStyle(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic, height: 1.35),
                              ),
                            ],
                            const SizedBox(height: 6),
                            _src(context, e.source),
                          ],
                        ),
                      ),
                      SpeakButton(e.textEn, size: 20),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (d.collocations.isNotEmpty || phrases.isNotEmpty) ...[
          const SectionHeader('Cụm từ & kết hợp từ'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (final c in d.collocations)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(c.phrase, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: c.meaningVi == null ? null : Text(c.meaningVi!),
                      trailing: _src(context, c.source),
                    ),
                  for (final p in phrases.where((p) => !d.collocations.any((c) => c.phrase == p.textEn)))
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(p.textEn, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: p.textVi == null ? null : Text(p.textVi!),
                      trailing: _src(context, p.source),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (synonyms.isNotEmpty) _relationSection(context, 'Từ đồng nghĩa', synonyms, AppColors.teal),
        if (antonyms.isNotEmpty) _relationSection(context, 'Từ trái nghĩa', antonyms, AppColors.danger),
        if (family.isNotEmpty) _relationSection(context, 'Họ từ (word family)', family, AppColors.indigo),
        if (confusable.isNotEmpty) _relationSection(context, 'Từ dễ nhầm lẫn', confusable, AppColors.amber),
        if (d.usageNote != null || d.commonMistake != null) ...[
          const SectionHeader('Lưu ý sử dụng'),
          Card(
            color: AppColors.amber.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (d.usageNote != null)
                    for (final line in d.usageNote!.split('\n'))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.lightbulb_outline_rounded, size: 18, color: AppColors.amber),
                            const SizedBox(width: 8),
                            Expanded(child: Text(line, style: const TextStyle(height: 1.4))),
                          ],
                        ),
                      ),
                  if (d.commonMistake != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.spellcheck_rounded, size: 18, color: AppColors.danger),
                        const SizedBox(width: 8),
                        Expanded(child: Text(d.commonMistake!, style: const TextStyle(height: 1.4))),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
        if (d.topics.isNotEmpty) ...[
          const SectionHeader('Chủ đề'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in d.topics)
                ActionChip(
                  avatar: Icon(AppIcons.of(t.icon), size: 18),
                  label: Text(t.nameVi),
                  onPressed: () => context.push('/topic/${t.code}'),
                ),
            ],
          ),
        ],
        if (d.skills != null) ...[
          const SizedBox(height: 12),
          Text('Kỹ năng IELTS liên quan: ${d.skills!.split(',').map(_skillVi).join(', ')}', style: TextStyle(color: cs.onSurfaceVariant)),
        ],
        const SizedBox(height: 20),
        Text(
          'Nguồn dữ liệu: ${d.sources.split(',').map((c) => sourceLabels[c] ?? c).join(' • ')}. '
          'IPA: ${[if (d.ipaUkSource != null) 'UK ${sourceLabels[d.ipaUkSource] ?? d.ipaUkSource}', if (d.ipaUsSource != null) 'US ${sourceLabels[d.ipaUsSource] ?? d.ipaUsSource}'].join(', ').ifEmpty('không có dữ liệu')}.',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }

  static String _skillVi(String s) =>
      {'reading': 'Reading', 'writing': 'Writing', 'speaking': 'Speaking', 'listening': 'Listening'}[s] ?? s;

  Widget _ipaChip(String label, String ipa) => Container(
    margin: const EdgeInsets.only(right: 4),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
    child: Text(
      '$label  $ipa',
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
    ),
  );

  Widget _src(BuildContext context, String code) =>
      Text(sourceLabels[code] ?? code, style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.outline));

  Widget _relationSection(BuildContext context, String title, List<Relation> rels, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in rels)
              ActionChip(
                label: Text(r.text),
                side: BorderSide(color: color.withValues(alpha: 0.4)),
                backgroundColor: color.withValues(alpha: 0.06),
                onPressed: r.targetId == null ? null : () => context.push('/word/${r.targetId}'),
              ),
          ],
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _LearningCard extends ConsumerWidget {
  final EntrySummary entry;
  const _LearningCard({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(cardStateProvider(entry.id));
    final queued = ref.watch(inQueueProvider(entry.id)).valueOrNull ?? false;
    final cs = Theme.of(context).colorScheme;
    return card.when(
      loading: () => const SizedBox(height: 72),
      error: (e, _) => Text('$e'),
      data: (c) {
        final (label, color, icon) = c == null
            ? ('Chưa học', cs.outline, Icons.fiber_new_rounded)
            : c.isMastered
            ? ('Thành thạo', AppColors.success, Icons.workspace_premium_rounded)
            : c.state == 2
            ? ('Đang ôn tập', AppColors.teal, Icons.autorenew_rounded)
            : ('Đang học', AppColors.amber, Icons.school_rounded);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(fontWeight: FontWeight.w700, color: color),
                      ),
                      Text(
                        c == null
                            ? (queued ? 'Đã có trong hàng chờ học' : 'Thêm vào hàng chờ để học trong phiên tới')
                            : 'Ôn lại sau: ${Dates.friendlyDue(c.due)} • ${c.reps} lượt ôn • ${c.lapses} lần quên',
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (c == null)
                  IconButton.filledTonal(
                    tooltip: queued ? 'Bỏ khỏi hàng chờ' : 'Thêm vào hàng chờ học',
                    icon: Icon(queued ? Icons.playlist_remove_rounded : Icons.playlist_add_rounded),
                    onPressed: () async {
                      final repo = ref.read(learningRepoProvider);
                      queued ? await repo.removeFromStudyQueue(entry.id) : await repo.addToStudyQueue(entry.id);
                      ref.read(dataVersionProvider.notifier).state++;
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              queued ? 'Đã bỏ khỏi hàng chờ học' : 'Đã thêm vào hàng chờ – từ này sẽ xuất hiện trong phiên "Học từ mới"',
                            ),
                          ),
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

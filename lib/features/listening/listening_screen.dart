import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/text/vietnamese.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../data/repositories/learning_repository.dart';
import '../../data/services/tts_service.dart';
import '../../domain/quiz/answer_checker.dart';
import '../../providers.dart';

enum ListenMode { identify, meaning, type }

class _ListenItem {
  final EntrySummary target;
  final List<String> options;
  final int answer;
  _ListenItem(this.target, this.options, this.answer);
}

class ListeningScreen extends ConsumerStatefulWidget {
  const ListeningScreen({super.key});
  @override
  ConsumerState<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends ConsumerState<ListeningScreen> {
  ListenMode? _mode;
  double _rate = 0.45;
  bool _textFallback = false;
  List<_ListenItem> _items = [];
  int _i = 0;
  int? _chosen;
  AnswerCheck? _check;
  final _ctrl = TextEditingController();
  final List<QuizAnswerRecord> _answers = [];
  DateTime _started = DateTime.now();
  bool _loading = false;
  bool _done = false;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _rate = ref.read(settingsProvider).speechRate;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (_items.isEmpty) return;
    final ok = await ref.read(ttsProvider).speak(_items[_i].target.headword, accent: ref.read(settingsProvider).accent, rate: _rate);
    if (!ok && mounted) setState(() => _textFallback = true);
  }

  Future<void> _start(ListenMode m) async {
    setState(() {
      _mode = m;
      _loading = true;
      _done = false;
      _i = 0;
      _answers.clear();
      _chosen = null;
      _check = null;
      _ctrl.clear();
    });
    final repo = ref.read(vocabRepoProvider);
    final learned = await ref.read(learningRepoProvider).learnedIds();
    final targets = learned.length >= 10
        ? await repo.summaries((learned..shuffle(_rng)).take(10).toList())
        : await repo.randomEntries(10, wordsOnly: true, minDifficulty: 2, maxDifficulty: 4);
    final items = <_ListenItem>[];
    for (final t in targets) {
      if (m == ListenMode.type) {
        items.add(_ListenItem(t, const [], -1));
        continue;
      }
      final d = await repo.randomEntries(12, pos: t.pos, excludeIds: {t.id}, wordsOnly: true);
      final opts = <String>[];
      final seen = {t.headword.toLowerCase(), stripVietnamese(t.meaningVi)};
      for (final x in d) {
        final key = m == ListenMode.identify ? x.headword.toLowerCase() : stripVietnamese(x.meaningVi);
        if (seen.contains(key)) continue;
        seen.add(key);
        opts.add(m == ListenMode.identify ? x.headword : x.meaningVi);
        if (opts.length == 3) break;
      }
      if (opts.length < 3) continue;
      final correct = m == ListenMode.identify ? t.headword : t.meaningVi;
      final all = [correct, ...opts]..shuffle(_rng);
      items.add(_ListenItem(t, all, all.indexOf(correct)));
    }
    if (!mounted) return;
    _started = DateTime.now();
    setState(() {
      _items = items;
      _loading = false;
    });
    await Future.delayed(const Duration(milliseconds: 300));
    if (!_textFallback) _play();
  }

  void _answerChoice(int k) {
    if (_chosen != null) return;
    final it = _items[_i];
    setState(() => _chosen = k);
    _answers.add(
      QuizAnswerRecord(
        entryId: it.target.id,
        questionType: 'listen_${_mode!.name}',
        prompt: it.target.headword,
        userAnswer: it.options[k],
        correctAnswer: it.options[it.answer],
        correct: k == it.answer,
      ),
    );
  }

  void _answerTyped() {
    if (_check != null || _ctrl.text.trim().isEmpty) return;
    final it = _items[_i];
    final c = checkTyped(_ctrl.text, it.target.spellings);
    setState(() => _check = c);
    _answers.add(
      QuizAnswerRecord(
        entryId: it.target.id,
        questionType: 'listen_type',
        prompt: it.target.headword,
        userAnswer: _ctrl.text.trim(),
        correctAnswer: it.target.headword,
        correct: c.correct,
      ),
    );
  }

  Future<void> _next() async {
    if (_i + 1 < _items.length) {
      setState(() {
        _i++;
        _chosen = null;
        _check = null;
        _ctrl.clear();
      });
      if (!_textFallback) _play();
      return;
    }
    await ref.read(learningRepoProvider).recordQuizSession(quizType: 'listening', startedAt: _started, answers: _answers);
    if (!mounted) return;
    await afterLearningActivity(ref, context);
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(ttsStatusProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Luyện nghe từ vựng')),
      body: SafeArea(child: _body(context, status)),
    );
  }

  Widget _ttsBanner(BuildContext context, TtsStatus? status) {
    if (status == null || status.availability == TtsAvailability.checking) {
      return const Card(
        child: ListTile(leading: CircularProgressIndicator(), title: Text('Đang kiểm tra giọng đọc ngoại tuyến…')),
      );
    }
    if (status.availability == TtsAvailability.unavailable || _textFallback) {
      return Card(
        color: AppColors.amber.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.volume_off_rounded, color: AppColors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Chưa có giọng đọc tiếng Anh ngoại tuyến', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Điện thoại chưa cài dữ liệu giọng nói tiếng Anh dùng được khi không có mạng. '
                'Bạn vẫn có thể luyện bằng chế độ văn bản: thay âm thanh bằng phiên âm IPA.\n'
                'Để bật âm thanh: Cài đặt › Hệ thống › Ngôn ngữ › Chuyển văn bản thành giọng nói › tải giọng English (UK/US).',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () => ref.read(ttsProvider).refresh().then((_) => setState(() => _textFallback = false)),
                    child: const Text('Kiểm tra lại'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (status.availability == TtsAvailability.otherAccentOnly) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.info_outline_rounded),
          title: Text('Chỉ có một giọng tiếng Anh ngoại tuyến trên máy; giọng Anh/Mỹ có thể giống nhau.'),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _body(BuildContext context, TtsStatus? status) {
    final unavailable = status?.availability == TtsAvailability.unavailable || _textFallback;
    if (_mode == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ttsBanner(context, status),
          const SizedBox(height: 8),
          for (final m in [
            (ListenMode.identify, 'Nghe và chọn từ', 'Nghe phát âm, chọn từ đúng', Icons.hearing_rounded),
            (ListenMode.meaning, 'Nghe và chọn nghĩa', 'Nghe phát âm, chọn nghĩa tiếng Việt', Icons.translate_rounded),
            (ListenMode.type, 'Nghe và gõ lại', 'Nghe rồi gõ chính xác từ tiếng Anh', Icons.keyboard_alt_rounded),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFEC4899).withValues(alpha: 0.12),
                    child: Icon(m.$4, color: const Color(0xFFEC4899)),
                  ),
                  title: Text(m.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(m.$3),
                  onTap: () => _start(m.$1),
                ),
              ),
            ),
          const SectionHeader('Tốc độ đọc'),
          Row(
            children: [
              const Icon(Icons.slow_motion_video_rounded),
              Expanded(
                child: Slider(
                  value: _rate,
                  min: 0.2,
                  max: 0.7,
                  divisions: 10,
                  label: _rate.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _rate = v),
                ),
              ),
              const Icon(Icons.speed_rounded),
            ],
          ),
        ],
      );
    }
    if (_loading) return const LoadingView();
    if (_items.isEmpty) return const EmptyState(icon: Icons.inbox, title: 'Không có câu hỏi', message: 'Thử lại sau.');
    if (_done) {
      final correct = _answers.where((a) => a.correct).length;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Kết quả: $correct/${_answers.length}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          for (final a in _answers)
            Card(
              child: ListTile(
                leading: Icon(
                  a.correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: a.correct ? AppColors.success : AppColors.danger,
                ),
                title: Text(a.prompt, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(a.correct ? a.correctAnswer : 'Bạn chọn: ${a.userAnswer} • Đúng: ${a.correctAnswer}'),
                trailing: SpeakButton(a.prompt, size: 20),
                onTap: a.entryId == null ? null : () => context.push('/word/${a.entryId}'),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => _start(_mode!), child: const Text('Luyện tiếp')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => setState(() => _mode = null), child: const Text('Chọn chế độ khác')),
        ],
      );
    }
    final it = _items[_i];
    final answered = _chosen != null || _check != null;
    final accent = ref.watch(settingsProvider.select((s) => s.accent));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        RoundedProgress(value: _i / _items.length),
        const SizedBox(height: 12),
        if (unavailable) _ttsBanner(context, status),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (!unavailable) ...[
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _play,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(gradient: AppColors.heroGradient, shape: BoxShape.circle),
                      child: const Icon(Icons.volume_up_rounded, color: Colors.white, size: 46),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Chạm để nghe lại'),
                  Row(
                    children: [
                      const Text('Tốc độ'),
                      Expanded(
                        child: Slider(value: _rate, min: 0.2, max: 0.7, divisions: 10, onChanged: (v) => setState(() => _rate = v)),
                      ),
                    ],
                  ),
                ] else ...[
                  const Text('Chế độ văn bản – đọc phiên âm:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    it.target.ipa(accent) ?? '(không có IPA – gợi ý: ${it.target.meaningVi})',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                ],
                if (answered) ...[
                  const Divider(height: 24),
                  Text(it.target.headword, style: Theme.of(context).textTheme.headlineSmall),
                  Text('${it.target.ipa(accent) ?? ''}  ${it.target.meaningVi}', textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_mode == ListenMode.type) ...[
          TextField(
            controller: _ctrl,
            enabled: _check == null,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _answerTyped(),
            decoration: const InputDecoration(hintText: 'Gõ từ bạn nghe được…'),
          ),
          const SizedBox(height: 10),
          if (_check != null)
            Text(
              _check!.correct
                  ? 'Chính xác!'
                  : (_check!.nearMiss ? 'Gần đúng! Đáp án: ${it.target.headword}' : 'Chưa đúng. Đáp án: ${it.target.headword}'),
              style: TextStyle(fontWeight: FontWeight.w700, color: _check!.correct ? AppColors.success : AppColors.danger),
            ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _check == null ? _answerTyped : _next, child: Text(_check == null ? 'Kiểm tra' : 'Tiếp theo')),
        ] else ...[
          for (var k = 0; k < it.options.length; k++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(14),
                  backgroundColor: _chosen == null
                      ? null
                      : k == it.answer
                      ? AppColors.success.withValues(alpha: 0.12)
                      : k == _chosen
                      ? AppColors.danger.withValues(alpha: 0.12)
                      : null,
                  side: BorderSide(
                    color: _chosen == null
                        ? Theme.of(context).colorScheme.outlineVariant
                        : k == it.answer
                        ? AppColors.success
                        : k == _chosen
                        ? AppColors.danger
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                onPressed: () => _answerChoice(k),
                child: Text(it.options[k], style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              ),
            ),
          if (_chosen != null) FilledButton(onPressed: _next, child: Text(_i + 1 < _items.length ? 'Tiếp theo' : 'Hoàn thành')),
        ],
      ],
    );
  }
}

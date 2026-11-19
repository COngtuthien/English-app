import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/vietnamese.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../data/repositories/learning_repository.dart';
import '../../providers.dart';

enum _Phase { setup, playing, done }

class MatchingScreen extends ConsumerStatefulWidget {
  const MatchingScreen({super.key});
  @override
  ConsumerState<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends ConsumerState<MatchingScreen> {
  static const _pairsPerRound = 6;
  static const _rounds = 3;
  _Phase _phase = _Phase.setup;
  int _level = 1; // 0 easy, 1 medium, 2 hard
  bool _timed = true;
  final _rng = Random();

  List<List<EntrySummary>> _roundWords = [];
  int _round = 0;
  List<EntrySummary> _left = [];
  List<EntrySummary> _right = [];
  final Set<int> _matched = {};
  int? _selLeft;
  int? _wrongLeft;
  int? _wrongRight;
  int _score = 0;
  int _combo = 0;
  int _mistakes = 0;
  final Set<int> _missedIds = {};
  Timer? _timer;
  int _secondsLeft = 90;
  DateTime _started = DateTime.now();
  bool _loading = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _loading = true);
    final (minD, maxD) = switch (_level) {
      0 => (1, 2),
      1 => (3, 3),
      _ => (4, 5),
    };
    final repo = ref.read(vocabRepoProvider);
    final cands = await repo.randomEntries(_pairsPerRound * _rounds * 4, minDifficulty: minD, maxDifficulty: maxD, wordsOnly: true);
    // unique Vietnamese meanings so each pair has exactly one match
    final seen = <String>{};
    final picked = <EntrySummary>[];
    for (final c in cands) {
      final k = stripVietnamese(c.meaningVi);
      if (c.meaningVi.length > 60 || seen.contains(k)) continue;
      seen.add(k);
      picked.add(c);
      if (picked.length == _pairsPerRound * _rounds) break;
    }
    _roundWords = [for (var i = 0; i + _pairsPerRound <= picked.length; i += _pairsPerRound) picked.sublist(i, i + _pairsPerRound)];
    _round = 0;
    _score = 0;
    _combo = 0;
    _mistakes = 0;
    _missedIds.clear();
    _started = DateTime.now();
    _secondsLeft = 90;
    _setupRound();
    _timer?.cancel();
    if (!mounted) return;
    if (_timed) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _secondsLeft--);
        if (_secondsLeft <= 0) _finish();
      });
    }
    setState(() {
      _loading = false;
      _phase = _roundWords.isEmpty ? _Phase.setup : _Phase.playing;
    });
  }

  void _setupRound() {
    final words = _roundWords[_round];
    _left = [...words]..shuffle(_rng);
    _right = [...words]..shuffle(_rng);
    _matched.clear();
    _selLeft = null;
  }

  void _tapLeft(int i) {
    if (_matched.contains(_left[i].id)) return;
    setState(() => _selLeft = i);
  }

  Future<void> _tapRight(int j) async {
    if (_selLeft == null || _matched.contains(_right[j].id)) return;
    final l = _left[_selLeft!];
    final r = _right[j];
    if (l.id == r.id) {
      setState(() {
        _matched.add(l.id);
        _combo++;
        _score += 10 + (_combo >= 3 ? 5 : 0);
        _selLeft = null;
      });
      if (_matched.length == _left.length) {
        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        if (_round + 1 < _roundWords.length) {
          setState(() {
            _round++;
            _setupRound();
          });
        } else {
          _finish();
        }
      }
    } else {
      setState(() {
        _mistakes++;
        _combo = 0;
        _score = max(0, _score - 2);
        _missedIds.add(l.id);
        _wrongLeft = _selLeft;
        _wrongRight = j;
      });
      await Future.delayed(const Duration(milliseconds: 450));
      if (mounted) setState(() => _wrongLeft = _wrongRight = null);
    }
  }

  Future<void> _finish() async {
    if (_phase == _Phase.done) return;
    _timer?.cancel();
    if (_timed && _secondsLeft > 0) _score += _secondsLeft; // time bonus
    final all = _roundWords.expand((e) => e).toList();
    final done = {..._matched, for (var r = 0; r < _round; r++) ..._roundWords[r].map((e) => e.id)};
    final answers = [
      for (final e in all.where((e) => done.contains(e.id) || _missedIds.contains(e.id)))
        QuizAnswerRecord(
          entryId: e.id,
          questionType: 'match',
          prompt: e.headword,
          userAnswer: done.contains(e.id) ? e.meaningVi : null,
          correctAnswer: e.meaningVi,
          correct: done.contains(e.id) && !_missedIds.contains(e.id),
        ),
    ];
    setState(() => _phase = _Phase.done);
    if (answers.isNotEmpty) {
      await ref.read(learningRepoProvider).recordQuizSession(quizType: 'match', startedAt: _started, answers: answers);
      if (mounted) await afterLearningActivity(ref, context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghép từ'),
        actions: [
          if (_phase == _Phase.playing)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  _timed ? '⏱ ${_secondsLeft}s' : 'Vòng ${_round + 1}/${_roundWords.length}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.setup => _setup(context),
          _Phase.playing => _board(context),
          _Phase.done => _result(context),
        },
      ),
    );
  }

  Widget _setup(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cách chơi', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 6),
                Text(
                  'Chọn một từ tiếng Anh rồi chọn nghĩa tiếng Việt tương ứng. 3 vòng × 6 cặp. Ghép đúng +10 điểm, '
                  'chuỗi đúng từ 3 cặp +5, ghép sai −2. Chế độ tính giờ cộng điểm thưởng theo số giây còn lại.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        const SectionHeader('Độ khó'),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Dễ (A–B1)')),
            ButtonSegment(value: 1, label: Text('Vừa (B2)')),
            ButtonSegment(value: 2, label: Text('Khó (C1–C2)')),
          ],
          selected: {_level},
          onSelectionChanged: (v) => setState(() => _level = v.first),
        ),
        const SizedBox(height: 12),
        SwitchListTile(title: const Text('Tính giờ (90 giây)'), value: _timed, onChanged: (v) => setState(() => _timed = v)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading ? null : _start,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(_loading ? 'Đang chuẩn bị…' : 'Bắt đầu'),
        ),
      ],
    );
  }

  Widget _board(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Pill('Điểm: $_score', icon: Icons.star_rounded, color: AppColors.amber),
              const SizedBox(width: 8),
              Pill('Sai: $_mistakes', icon: Icons.close_rounded, color: AppColors.danger),
              const Spacer(),
              if (_combo >= 3) Pill('Combo ×$_combo', icon: Icons.bolt_rounded, color: AppColors.teal),
            ],
          ),
        ),
        if (_timed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RoundedProgress(value: _secondsLeft / 90, color: _secondsLeft < 15 ? AppColors.danger : AppColors.teal),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < _left.length; i++)
                        _tile(
                          _left[i].headword,
                          matched: _matched.contains(_left[i].id),
                          selected: _selLeft == i,
                          wrong: _wrongLeft == i,
                          onTap: () => _tapLeft(i),
                          bold: true,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      for (var j = 0; j < _right.length; j++)
                        _tile(
                          _right[j].meaningVi,
                          matched: _matched.contains(_right[j].id),
                          selected: false,
                          wrong: _wrongRight == j,
                          onTap: () => _tapRight(j),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile(
    String text, {
    required bool matched,
    required bool selected,
    required bool wrong,
    required VoidCallback onTap,
    bool bold = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = matched
        ? AppColors.success
        : wrong
        ? AppColors.danger
        : selected
        ? cs.primary
        : cs.outlineVariant;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: matched ? 0.35 : 1,
          child: Material(
            color: (matched || wrong || selected) ? color.withValues(alpha: 0.12) : Theme.of(context).cardTheme.color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: color, width: selected || wrong ? 2 : 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: matched ? null : onTap,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: bold ? 15 : 13.5),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _result(BuildContext context) {
    final elapsed = DateTime.now().difference(_started);
    final all = _roundWords.expand((e) => e).toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.extension_rounded, size: 72, color: AppColors.teal),
        const SizedBox(height: 12),
        Text('Kết thúc!', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: StatTile(icon: Icons.star_rounded, value: '$_score', label: 'Điểm', color: AppColors.amber),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(icon: Icons.close_rounded, value: '$_mistakes', label: 'Lần ghép sai', color: AppColors.danger),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(icon: Icons.timer_rounded, value: '${elapsed.inSeconds}s', label: 'Thời gian', color: AppColors.indigo),
            ),
          ],
        ),
        if (_missedIds.isNotEmpty) ...[
          const SectionHeader('Từ cần chú ý'),
          for (final e in all.where((e) => _missedIds.contains(e.id)))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: WordTile(entry: e),
            ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _start, icon: const Icon(Icons.replay_rounded), label: const Text('Chơi lại')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => setState(() => _phase = _Phase.setup), child: const Text('Đổi độ khó')),
      ],
    );
  }
}

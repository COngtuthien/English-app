import 'dart:math' as math;

class AnswerCheck {
  final bool correct;
  final bool nearMiss;
  final int distance;
  final String expected;
  const AnswerCheck({required this.correct, required this.nearMiss, required this.distance, required this.expected});
}

/// Normalises typed answers: case-insensitive, trims, collapses spaces, unifies apostrophes/hyphens
/// and drops trailing punctuation.
String normalizeAnswer(String s) {
  var t = s.toLowerCase().trim();
  t = t.replaceAll(RegExp('[’‘`´]'), "'").replaceAll(RegExp('[‐‑–—]'), '-');
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  t = t.replaceAll(RegExp(r'[.!?,;:]+$'), '');
  return t.trim();
}

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    final tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return prev[b.length];
}

/// Checks a typed answer against all accepted variants (e.g. British/American spellings).
/// Hyphen vs. space ("well-being" / "well being") is accepted. A close miss (small edit distance)
/// is reported as [AnswerCheck.nearMiss] so the UI can show typo feedback, but it is not counted correct.
AnswerCheck checkTyped(String input, List<String> accepted) {
  assert(accepted.isNotEmpty);
  final n = normalizeAnswer(input);
  final variants = <String>{};
  for (final a in accepted) {
    final x = normalizeAnswer(a);
    variants
      ..add(x)
      ..add(x.replaceAll('-', ' '))
      ..add(x.replaceAll('-', ''));
  }
  final nAlt = {n, n.replaceAll('-', ' '), n.replaceAll('-', '')};
  if (n.isNotEmpty && nAlt.any(variants.contains)) {
    return AnswerCheck(correct: true, nearMiss: false, distance: 0, expected: accepted.first);
  }
  var best = 1 << 30;
  var bestStr = accepted.first;
  for (final a in accepted) {
    final d = levenshtein(n, normalizeAnswer(a));
    if (d < best) {
      best = d;
      bestStr = a;
    }
  }
  final tolerance = bestStr.length <= 4 ? 1 : (bestStr.length <= 9 ? 2 : 3);
  return AnswerCheck(correct: false, nearMiss: n.isNotEmpty && best <= tolerance, distance: best, expected: bestStr);
}

/// Replaces the first whole-word occurrence of [target] in [sentence] with a blank.
String? blankOut(String sentence, String target, {String blank = '_____'}) {
  final re = RegExp('(?<![A-Za-z])${RegExp.escape(target)}(?![A-Za-z])', caseSensitive: false);
  final m = re.firstMatch(sentence);
  if (m == null) return null;
  return sentence.replaceRange(m.start, m.end, blank);
}

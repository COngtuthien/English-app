/// Vietnamese text helpers. [stripVietnamese] must stay identical to `strip_vi`
/// in tools/data/build_database.py, because the search index stores text
/// normalised by that function.
library;

const _groups = <String, String>{
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'e': 'èéẹẻẽêềếệểễ',
  'i': 'ìíịỉĩ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'u': 'ùúụủũưừứựửữ',
  'y': 'ỳýỵỷỹ',
  'd': 'đ',
};

final Map<int, String> _map = () {
  final m = <int, String>{};
  _groups.forEach((base, chars) {
    for (final r in chars.runes) {
      m[r] = base;
    }
    for (final r in chars.toUpperCase().runes) {
      m[r] = base;
    }
  });
  // Latin letters with diacritics occasionally found in English loanwords.
  const extra = {'ç': 'c', 'ñ': 'n', 'ö': 'o', 'ü': 'u', 'ï': 'i', 'ë': 'e', 'ä': 'a', 'å': 'a', 'ø': 'o', 'œ': 'oe', 'æ': 'ae'};
  extra.forEach((k, v) => m[k.runes.first] = v);
  return m;
}();

/// Lowercases [input] and removes Vietnamese diacritics (đ -> d).
String stripVietnamese(String input) {
  final sb = StringBuffer();
  for (final r in input.toLowerCase().runes) {
    final rep = _map[r];
    if (rep != null) {
      sb.write(rep);
    } else if (r >= 0x0300 && r <= 0x036F) {
      // combining marks (decomposed input) are dropped
      continue;
    } else {
      sb.writeCharCode(r);
    }
  }
  return sb.toString();
}

/// Builds a safe FTS4 query from free text. One word -> prefix query ("kinh*");
/// several words -> phrase query whose last word is a prefix ("\"moi truong*\""), so the
/// words must appear next to each other (e.g. "môi trường", not "môi" and "trường hợp").
String ftsPrefixQuery(String text) {
  final tokens = stripVietnamese(
    text,
  ).replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').split(RegExp(r'\s+')).where((t) => t.isNotEmpty).take(6).toList();
  if (tokens.isEmpty) return '';
  if (tokens.length == 1) return '${tokens.first}*';
  return '"${tokens.join(' ')}*"';
}

bool containsVietnameseLetters(String s) => RegExp('[${_groups.values.join()}]', caseSensitive: false).hasMatch(s);

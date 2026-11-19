import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

enum TtsAvailability { checking, available, otherAccentOnly, unavailable }

class TtsStatus {
  final TtsAvailability availability;
  final String? ukVoice;
  final String? usVoice;
  final String? engine;
  const TtsStatus(this.availability, {this.ukVoice, this.usVoice, this.engine});

  bool get canSpeak => availability == TtsAvailability.available || availability == TtsAvailability.otherAccentOnly;
}

/// Pronunciation through the device's text-to-speech engine, restricted to voices that
/// the engine reports as *not* requiring a network connection and as installed.
/// No audio is downloaded or streamed by this app. If the phone has no offline English
/// voice, [status] reports [TtsAvailability.unavailable] and callers show a text fallback.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  TtsStatus _status = const TtsStatus(TtsAvailability.checking);
  Map<String, String>? _ukVoiceMap;
  Map<String, String>? _usVoiceMap;
  Future<void>? _init;
  final _statusCtrl = StreamController<TtsStatus>.broadcast();

  TtsStatus get status => _status;
  Stream<TtsStatus> get statusStream => _statusCtrl.stream;

  Future<void> init() => _init ??= _doInit();

  Future<void> _doInit() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      final voices = await _tts.getVoices;
      final offline = <Map<String, String>>[];
      if (voices is List) {
        for (final v in voices) {
          if (v is! Map) continue;
          final m = v.map((k, val) => MapEntry('$k', '$val'));
          final locale = (m['locale'] ?? '').replaceAll('_', '-').toLowerCase();
          if (!locale.startsWith('en')) continue;
          if (m['network_required'] == '1') continue;
          if ((m['features'] ?? '').contains('notInstalled')) continue;
          offline.add(m);
        }
      }
      Map<String, String>? pick(String tag) {
        final cands = offline.where((m) => (m['locale'] ?? '').replaceAll('_', '-').toLowerCase() == tag).toList();
        if (cands.isEmpty) return null;
        // prefer explicitly local voices (Google names them "...-local")
        cands.sort((a, b) => (b['name'] ?? '').contains('local') ? 1 : ((a['name'] ?? '').contains('local') ? -1 : 0));
        return cands.first;
      }

      _ukVoiceMap = pick('en-gb');
      _usVoiceMap = pick('en-us');
      final anyEnglish = offline.isNotEmpty ? offline.first : null;
      _ukVoiceMap ??= null;
      String? engine;
      try {
        engine = await _tts.getDefaultEngine as String?;
      } catch (_) {}
      if (_ukVoiceMap != null && _usVoiceMap != null) {
        _status = TtsStatus(TtsAvailability.available, ukVoice: _ukVoiceMap!['name'], usVoice: _usVoiceMap!['name'], engine: engine);
      } else if (_ukVoiceMap != null || _usVoiceMap != null || anyEnglish != null) {
        _ukVoiceMap ??= _usVoiceMap ?? anyEnglish;
        _usVoiceMap ??= _ukVoiceMap ?? anyEnglish;
        _status = TtsStatus(TtsAvailability.otherAccentOnly, ukVoice: _ukVoiceMap?['name'], usVoice: _usVoiceMap?['name'], engine: engine);
      } else {
        _status = TtsStatus(TtsAvailability.unavailable, engine: engine);
      }
    } catch (_) {
      _status = const TtsStatus(TtsAvailability.unavailable);
    }
    _statusCtrl.add(_status);
  }

  /// Re-checks voices (e.g. after the user installs voice data).
  Future<void> refresh() {
    _init = null;
    _status = const TtsStatus(TtsAvailability.checking);
    _statusCtrl.add(_status);
    return init();
  }

  bool hasExactAccent(String accent) {
    if (_status.availability != TtsAvailability.available) return false;
    return accent == 'us' ? _usVoiceMap != null : _ukVoiceMap != null;
  }

  /// Speaks [text]; returns false when no offline voice is available.
  Future<bool> speak(String text, {String accent = 'uk', double rate = 0.45}) async {
    await init();
    if (!_status.canSpeak) return false;
    try {
      final voice = accent == 'us' ? _usVoiceMap : _ukVoiceMap;
      if (voice != null) {
        await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
      }
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(1.0);
      await _tts.stop();
      await _tts.speak(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

const String kBackupFormat = 'ielts-vocabulary-master-backup';

class BackupException implements Exception {
  final String messageVi;
  BackupException(this.messageVi);
  @override
  String toString() => messageVi;
}

class BackupSummary {
  final DateTime createdAt;
  final int schemaVersion;
  final Map<String, int> rowCounts;
  const BackupSummary(this.createdAt, this.schemaVersion, this.rowCounts);
  int get learnedWords => rowCounts['learning_cards'] ?? 0;
}

/// Exports / restores all user data (progress, history, favourites, quiz stats, settings, achievements)
/// as a self-validating JSON document.
class BackupService {
  final Database db;
  final String appVersion;
  BackupService(this.db, {this.appVersion = '1.0.1'});

  Future<Uint8List> exportBytes({DateTime? now}) async {
    final data = <String, Object?>{};
    for (final t in backupTables) {
      data[t] = await db.query(t);
    }
    final payload = jsonEncode(data);
    final doc = {
      'format': kBackupFormat,
      'schemaVersion': kUserSchemaVersion,
      'contentVersion': kContentVersion,
      'appVersion': appVersion,
      'createdAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'checksum': sha256.convert(utf8.encode(payload)).toString(),
      'data': data,
    };
    return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(doc)));
  }

  /// Parses and validates a backup without modifying the database.
  Future<(BackupSummary, Map<String, List<Map<String, Object?>>>)> validate(Uint8List bytes) async {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw BackupException('Tệp không phải bản sao lưu hợp lệ (không đọc được JSON).');
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != kBackupFormat) {
      throw BackupException('Tệp này không phải bản sao lưu của IELTS Vocabulary Master.');
    }
    final schema = decoded['schemaVersion'];
    if (schema is! int || schema < 1) throw BackupException('Phiên bản sao lưu không hợp lệ.');
    if (schema > kUserSchemaVersion) {
      throw BackupException('Bản sao lưu được tạo bởi phiên bản ứng dụng mới hơn. Hãy cập nhật ứng dụng trước khi khôi phục.');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) throw BackupException('Bản sao lưu thiếu dữ liệu.');
    final checksum = sha256.convert(utf8.encode(jsonEncode(data))).toString();
    if (checksum != decoded['checksum']) {
      throw BackupException('Bản sao lưu bị hỏng hoặc đã bị chỉnh sửa (sai mã kiểm tra).');
    }
    final tables = <String, List<Map<String, Object?>>>{};
    final counts = <String, int>{};
    for (final t in backupTables) {
      final rows = data[t];
      if (rows == null) {
        tables[t] = [];
        counts[t] = 0;
        continue;
      }
      if (rows is! List) throw BackupException('Bảng "$t" trong bản sao lưu không hợp lệ.');
      final cols = (await db.rawQuery('PRAGMA table_info($t)')).map((r) => r['name'] as String).toSet();
      final list = <Map<String, Object?>>[];
      for (final r in rows) {
        if (r is! Map<String, dynamic>) throw BackupException('Dữ liệu dòng trong bảng "$t" không hợp lệ.');
        final unknown = r.keys.where((k) => !cols.contains(k));
        if (unknown.isNotEmpty) throw BackupException('Bảng "$t" có cột lạ: ${unknown.join(', ')}.');
        list.add(Map<String, Object?>.from(r));
      }
      tables[t] = list;
      counts[t] = list.length;
    }
    DateTime created;
    try {
      created = DateTime.parse(decoded['createdAt'] as String);
    } catch (_) {
      throw BackupException('Ngày tạo bản sao lưu không hợp lệ.');
    }
    return (BackupSummary(created, schema, counts), tables);
  }

  /// Replaces all user data with the backup inside one transaction (all-or-nothing).
  Future<BackupSummary> restore(Uint8List bytes) async {
    final (summary, tables) = await validate(bytes);
    await db.transaction((txn) async {
      for (final t in backupTables.reversed) {
        await txn.delete(t);
      }
      for (final t in backupTables) {
        final batch = txn.batch();
        for (final row in tables[t]!) {
          batch.insert(t, row);
        }
        await batch.commit(noResult: true);
      }
    });
    return summary;
  }
}

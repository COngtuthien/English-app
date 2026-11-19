import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/services/backup_service.dart';
import '../../providers.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  String? _status;

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final bytes = await ref.read(backupServiceProvider).exportBytes();
      final name = 'ielts_vocab_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';
      final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: 'application/json', dialogTitle: 'Lưu bản sao lưu');
      setState(
        () => _status = uri == null ? 'Đã hủy lưu tệp.' : 'Đã lưu bản sao lưu ($name, ${(bytes.length / 1024).toStringAsFixed(1)} KB).',
      );
    } catch (e) {
      setState(() => _status = 'Không thể sao lưu: $e');
    }
    setState(() => _busy = false);
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final file = await FilePicker.pickFile(dialogTitle: 'Chọn tệp sao lưu (.json)', type: FileType.any);
      if (file == null) {
        setState(() {
          _busy = false;
          _status = 'Đã hủy.';
        });
        return;
      }
      final bytes = await file.readAsBytes();
      final svc = ref.read(backupServiceProvider);
      final (summary, _) = await svc.validate(bytes);
      if (!mounted) return;
      final ok = await confirmDialog(
        context,
        title: 'Khôi phục bản sao lưu?',
        message:
            'Bản sao lưu tạo lúc ${DateFormat('dd/MM/yyyy HH:mm').format(summary.createdAt.toLocal())} gồm ${summary.learnedWords} từ đã học, '
            '${summary.rowCounts['review_history']} lượt ôn, ${summary.rowCounts['quiz_sessions']} bài luyện tập.\n\n'
            'Toàn bộ dữ liệu học hiện tại sẽ được THAY THẾ. Tiếp tục?',
        confirm: 'Khôi phục',
        destructive: true,
      );
      if (!ok) {
        setState(() {
          _busy = false;
          _status = 'Đã hủy khôi phục.';
        });
        return;
      }
      await svc.restore(bytes);
      final settings = await ref.read(settingsRepoProvider).load();
      ref.read(settingsProvider.notifier).replace(settings.copyWith(onboarded: true));
      await ref.read(settingsRepoProvider).save(settings.copyWith(onboarded: true));
      ref.read(dataVersionProvider.notifier).state++;
      setState(() => _status = 'Khôi phục thành công: ${summary.learnedWords} từ đã học.');
    } on BackupException catch (e) {
      setState(() => _status = e.messageVi);
    } catch (e) {
      setState(() => _status = 'Không thể khôi phục: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sao lưu & khôi phục')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sao lưu gồm', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final s in [
                    'Tiến độ học & lịch ôn tập (FSRS)',
                    'Lịch sử ôn tập',
                    'Kết quả quiz & luyện tập',
                    'Từ yêu thích & hàng chờ học',
                    'Thành tích',
                    'Cài đặt',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check_rounded, size: 18, color: AppColors.success),
                          const SizedBox(width: 6),
                          Text(s),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Tệp JSON có kiểm tra phiên bản và mã SHA-256 để phát hiện tệp hỏng. Tệp được lưu ở vị trí bạn chọn trên máy (ví dụ thư mục Download).',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Tạo bản sao lưu'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Khôi phục từ tệp'),
          ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (_status != null)
            Card(
              child: ListTile(leading: const Icon(Icons.info_outline_rounded), title: Text(_status!)),
            ),
        ],
      ),
    );
  }
}

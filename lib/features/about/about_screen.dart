import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../providers.dart';

final _sourcesProvider = FutureProvider.autoDispose<(List<SourceInfo>, Map<String, String>, int)>((ref) async {
  final repo = ref.watch(vocabRepoProvider);
  return (await repo.sources(), await repo.contentMeta(), await repo.totalEntries());
});

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_sourcesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Giới thiệu')),
      body: AsyncView<(List<SourceInfo>, Map<String, String>, int)>(
        data,
        builder: (d) {
          final (sources, meta, total) = d;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset('assets/images/logo_small.png', width: 88, height: 88),
                ),
              ),
              const SizedBox(height: 12),
              Text('IELTS Vocabulary Master', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              const Text('Phiên bản 1.0.1', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Ứng dụng học từ vựng IELTS hoàn toàn ngoại tuyến dành cho người Việt: $total mục từ, '
                'lặp lại ngắt quãng FSRS, quiz, trò chơi và luyện Writing/Speaking. '
                'Không quảng cáo, không tài khoản, không thu thập dữ liệu, không cần Internet.',
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.45),
              ),
              const SizedBox(height: 8),
              Text(
                'Dữ liệu từ vựng phiên bản ${meta['content_version'] ?? '?'} • xây dựng ${meta['built_at'] ?? ''}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              ),
              const SectionHeader('Lưu ý'),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    '• Vốn từ vựng là một phần của điểm IELTS; hãy kết hợp luyện đọc, nghe, viết và nói.\n'
                    '• Cấp độ CEFR chỉ hiển thị khi có trong danh sách CEFR-J/Octanove; các từ khác dùng độ khó ước tính theo tần suất.\n'
                    '• Phát âm dùng giọng đọc ngoại tuyến của điện thoại; chất lượng phụ thuộc vào máy.\n'
                    '• Ứng dụng không chấm điểm bài viết hay phát âm.',
                    style: TextStyle(height: 1.5),
                  ),
                ),
              ),
              const SectionHeader('Nguồn dữ liệu & giấy phép'),
              for (final s in sources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Pill(s.license, color: AppColors.teal),
                          const SizedBox(height: 6),
                          Text(s.attribution, style: const TextStyle(fontSize: 13, height: 1.4)),
                          const SizedBox(height: 4),
                          SelectableText(s.url, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
                        ],
                      ),
                    ),
                  ),
                ),
              const SectionHeader('Phần mềm & phông chữ'),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Thuật toán FSRS: open-spaced-repetition/dart-fsrs (MIT).\n'
                    'Phông chữ Be Vietnam Pro (SIL Open Font License 1.1).\n'
                    'Xây dựng bằng Flutter và các thư viện mã nguồn mở (xem danh sách giấy phép bên dưới).',
                    style: TextStyle(height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => showLicensePage(context: context, applicationName: 'IELTS Vocabulary Master', applicationVersion: '1.0.1'),
                child: const Text('Giấy phép thư viện mã nguồn mở'),
              ),
              const SizedBox(height: 12),
              Text(
                'Nội dung có nguồn CC BY-SA được phân phối lại theo cùng giấy phép (CC BY-SA 4.0).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }
}

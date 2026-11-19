import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local, on-device daily study reminder. Nothing is sent over the network.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  static const int _dailyId = 7501;

  Future<bool> init() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
      }
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(settings: const InitializationSettings(android: android));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// Asks for POST_NOTIFICATIONS on Android 13+. Returns whether notifications are allowed.
  Future<bool> requestPermission() async {
    if (!await init()) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> scheduleDaily(int hour, int minute) async {
    if (!await init()) return false;
    try {
      await _plugin.cancel(id: _dailyId);
      final now = tz.TZDateTime.now(tz.local);
      var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id: _dailyId,
        scheduledDate: when,
        title: 'Đến giờ học từ vựng IELTS! 📚',
        body: 'Ôn lại các từ đến hạn và học thêm từ mới để giữ chuỗi ngày học.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_reminder',
            'Nhắc học hằng ngày',
            channelDescription: 'Lời nhắc học từ vựng mỗi ngày',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelDaily() async {
    if (!await init()) return;
    try {
      await _plugin.cancel(id: _dailyId);
    } catch (_) {}
  }
}

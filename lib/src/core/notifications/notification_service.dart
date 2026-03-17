import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../data/app_repository.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  bool get _isSupportedPlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  Future<void> init() async {
    if (!_isSupportedPlatform) return;
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);

    tz.initializeTimeZones();
    _initialized = true;
  }

  Future<void> requestPermissions() async {
    if (!_isSupportedPlatform) return;
    if (!_initialized) {
      await init();
    }
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> syncAllReminders(AppRepository repository) async {
    if (!_isSupportedPlatform) return;
    await init();
    final bills = await repository.fetchBillReminders();
    final recurring = await repository.fetchRecurringTransactions();
    await _plugin.cancelAll();

    for (final bill in bills) {
      final isActive = (bill['is_active'] as bool?) ?? false;
      if (!isActive) continue;
      await _scheduleBillReminder(bill);
    }

    for (final rule in recurring) {
      final isActive = (rule['is_active'] as bool?) ?? false;
      if (!isActive) continue;
      await _scheduleRecurringReminder(rule);
    }
  }

  Future<void> _scheduleBillReminder(Map<String, dynamic> bill) async {
    final id = _idFor('bill', bill['id']?.toString() ?? '');
    final title = (bill['title'] ?? 'Bill Reminder').toString();
    final amount = (bill['amount'] ?? '').toString();
    final due = DateTime.tryParse((bill['due_date'] ?? '').toString());
    if (due == null) return;

    final at = tz.TZDateTime.from(
      DateTime(due.year, due.month, due.day, 9, 0),
      tz.local,
    );
    if (at.isBefore(tz.TZDateTime.now(tz.local))) return;

    await _plugin.zonedSchedule(
      id,
      'Bill due: $title',
      'Amount: $amount • Tap to pay in app',
      at,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'bill_reminders',
          'Bill reminders',
          channelDescription: 'Due date reminders for bills',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidAllowWhileIdle: true,
      payload: 'bill:${bill['id']}',
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> _scheduleRecurringReminder(Map<String, dynamic> rule) async {
    final id = _idFor('recurring', rule['id']?.toString() ?? '');
    final kind = (rule['kind'] ?? 'transaction').toString();
    final amount = (rule['amount'] ?? '').toString();
    final next = DateTime.tryParse((rule['next_run_date'] ?? '').toString());
    if (next == null) return;

    final at = tz.TZDateTime.from(
      DateTime(next.year, next.month, next.day, 8, 30),
      tz.local,
    );
    if (at.isBefore(tz.TZDateTime.now(tz.local))) return;

    await _plugin.zonedSchedule(
      id,
      'Recurring $kind due today',
      'Amount: $amount • Open app to process',
      at,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'recurring_reminders',
          'Recurring reminders',
          channelDescription: 'Upcoming recurring transaction reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidAllowWhileIdle: true,
      payload: 'recurring:${rule['id']}',
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  int _idFor(String prefix, String id) {
    final raw = '$prefix:$id';
    return raw.hashCode & 0x7fffffff;
  }
}

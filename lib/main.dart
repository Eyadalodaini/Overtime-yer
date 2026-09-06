import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz.initializeTimeZones();

  await AppDb.instance.init();
  await Settings.instance.load();
  await NotificationService.init();

  await NotificationService.schedule(
    enabled: Settings.instance.reminders,
    hour: Settings.instance.reminderHour,
    minute: Settings.instance.reminderMinute,
  );

  runApp(const OvertimeApp());
}

// ============================================================
// Helpers
// ============================================================

String money(num value) {
  final formatter = NumberFormat('#,##0', 'ar');
  return '${formatter.format(value.round())} ريال';
}

String fmtDate(String value) {
  try {
    final date = DateTime.parse(value);
    return DateFormat('yyyy/MM/dd', 'ar').format(date);
  } catch (_) {
    return value;
  }
}

String fmtHours(num value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }

  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

// ============================================================
// Settings
// ============================================================

class Settings {
  Settings._();

  static final instance = Settings._();

  int rate = 1500;
  ThemeMode themeMode = ThemeMode.system;
  int colorSeed = 0;

  bool reminders = true;
  int reminderHour = 18;
  int reminderMinute = 0;

  final Map<int, String> endTimes = {
    DateTime.saturday: '14:00',
    DateTime.sunday: '14:00',
    DateTime.monday: '14:00',
    DateTime.tuesday: '14:00',
    DateTime.wednesday: '14:00',
    DateTime.thursday: '13:00',
  };

  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();

    rate = _prefs!.getInt('rate') ?? 1500;

    colorSeed = (_prefs!.getInt('colorSeed') ?? 0).clamp(0, 4);

    reminders = _prefs!.getBool('reminders') ?? true;

    reminderHour = (_prefs!.getInt('reminderHour') ?? 18).clamp(0, 23);

    reminderMinute =
        (_prefs!.getInt('reminderMinute') ?? 0).clamp(0, 59);

    final mode = _prefs!.getString('themeMode') ?? 'system';

    themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == mode,
      orElse: () => ThemeMode.system,
    );

    for (final entry in endTimes.entries.toList()) {
      endTimes[entry.key] =
          _prefs!.getString('end_${entry.key}') ?? entry.value;
    }
  }

  Future<void> save() async {
    _prefs ??= await SharedPreferences.getInstance();

    await _prefs!.setInt('rate', rate);
    await _prefs!.setInt('colorSeed', colorSeed);
    await _prefs!.setBool('reminders', reminders);
    await _prefs!.setInt('reminderHour', reminderHour);
    await _prefs!.setInt('reminderMinute', reminderMinute);
    await _prefs!.setString('themeMode', themeMode.name);

    for (final entry in endTimes.entries) {
      await _prefs!.setString(
        'end_${entry.key}',
        entry.value,
      );
    }
  }
}

// ============================================================
// Database
// ============================================================

class AppDb {
  AppDb._();

  static final instance = AppDb._();

  Database? _db;

  Database get db {
    final database = _db;

    if (database == null) {
      throw StateError('قاعدة البيانات لم تتم تهيئتها');
    }

    return database;
  }

  Future<void> init() async {
    if (_db != null) return;

    final dir = await getDatabasesPath();

    _db = await openDatabase(
      p.join(dir, 'overtime_yer.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE overtime (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            start TEXT,
            end TEXT,
            hours REAL NOT NULL,
            rate INTEGER NOT NULL,
            total INTEGER NOT NULL,
            note TEXT
          )
        ''');
      },
    );
  }

  Future<List<Map<String, dynamic>>> all() async {
    return db.query(
      'overtime',
      orderBy: 'date DESC, id DESC',
    );
  }

  Future<int> insert(Map<String, dynamic> row) {
    return db.insert('overtime', row);
  }

  Future<int> update(
    int id,
    Map<String, dynamic> row,
  ) {
    return db.update(
      'overtime',
      row,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(int id) {
    return db.delete(
      'overtime',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> replaceAll(List<dynamic> rows) async {
    await db.transaction((txn) async {
      final validRows = <Map<String, dynamic>>[];

      for (final item in rows) {
        if (item is! Map) {
          throw const FormatException(
            'سجل احتياطي غير صالح',
          );
        }

        final date = item['date'];
        final hours = item['hours'];
        final rate = item['rate'];
        final total = item['total'];

        if (date is! String ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
            DateTime.tryParse(date) == null ||
            hours is! num ||
            !hours.isFinite ||
            hours <= 0 ||
            hours > 24 ||
            rate is! num ||
            !rate.isFinite ||
            rate <= 0 ||
            total is! num ||
            !total.isFinite ||
            total < 0) {
          throw const FormatException(
            'بيانات سجل غير صالحة',
          );
        }

        final parsedDate = DateTime.tryParse(date);

        if (parsedDate == null ||
            parsedDate.year != int.parse(date.substring(0, 4)) ||
            parsedDate.month != int.parse(date.substring(5, 7)) ||
            parsedDate.day != int.parse(date.substring(8, 10))) {
          throw const FormatException(
            'التاريخ غير صالح',
          );
        }

        final start = item['start'];
        final end = item['end'];
        final note = item['note'];

        if (start != null &&
            (start is! String ||
                !RegExp(r'^\d{2}:\d{2}$').hasMatch(start))) {
          throw const FormatException(
            'وقت البداية غير صالح',
          );
        }

        if (end != null &&
            (end is! String ||
                !RegExp(r'^\d{2}:\d{2}$').hasMatch(end))) {
          throw const FormatException(
            'وقت النهاية غير صالح',
          );
        }

        validRows.add({
          'date': date,
          'start': start is String ? start : null,
          'end': end is String ? end : null,
          'hours': hours.toDouble(),
          'rate': rate.round(),
          'total': total.round(),
          'note': note is String ? note : null,
        });
      }

      await txn.delete('overtime');

      for (final row in validRows) {
        await txn.insert(
          'overtime',
          row,
        );
      }
    });
  }
}

// ============================================================
// Notifications
// ============================================================

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    'overtime_reminders',
    'تذكير الساعات الإضافية',
    description: 'تذكيرات لإضافة الساعات الإضافية',
    importance: Importance.defaultImportance,
  );

  static const List<int> reminderWeekdays = <int>[
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.saturday,
    DateTime.sunday,
  ];

  static Future<void> init() async {
    const android = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const settings = InitializationSettings(
      android: android,
    );

    await _plugin.initialize(settings);

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      _channel,
    );

    await androidPlugin?.requestNotificationsPermission();
  }

  static Future<void> cancel() async {
    for (final weekday in reminderWeekdays) {
      await _plugin.cancel(
        1000 + weekday,
      );
    }
  }

  static Future<void> schedule({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    await cancel();

    if (!enabled) return;

    hour = hour.clamp(0, 23);
    minute = minute.clamp(0, 59);

    final now = tz.TZDateTime.now(tz.local);

    for (final weekday in reminderWeekdays) {
      var next = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      var daysAhead =
          (weekday - next.weekday + DateTime.daysPerWeek) %
              DateTime.daysPerWeek;

      next = next.add(
        Duration(days: daysAhead),
      );

      if (!next.isAfter(now)) {
        next = next.add(
          const Duration(days: DateTime.daysPerWeek),
        );
      }

      await _plugin.zonedSchedule(
        1000 + weekday,
        'تذكير الساعات الإضافية',
        'أضف ساعات العمل الإضافية لهذا اليوم.',
        next,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'overtime_reminders',
            'تذكير الساعات الإضافية',
            channelDescription: 'تذكيرات لإضافة الساعات الإضافية',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode:
            AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents:
            DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }
}

// ============================================================
// App
// ============================================================

class OvertimeApp extends StatefulWidget {
  const OvertimeApp({super.key});

  @override
  State<OvertimeApp> createState() => _OvertimeAppState();
}

class _OvertimeAppState extends State<OvertimeApp> {
  @override
  Widget build(BuildContext context) {
    final seeds = [
      Colors.indigo,
      Colors.teal,
      Colors.deepPurple,
      Colors.orange,
      Colors.pink,
    ];

    return AnimatedBuilder(
      animation: SettingsNotifier.instance,
      builder: (_, __) {
        final colorIndex =
            Settings.instance.colorSeed.clamp(0, seeds.length - 1);

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'إضافي',
          locale: const Locale('ar'),
          localizationsDelegates:
              GlobalMaterialLocalizations.delegates,
          supportedLocales: const [
            Locale('ar'),
          ],
          themeMode: Settings.instance.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: seeds[colorIndex],
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: seeds[colorIndex],
          ),
          home: const HomePage(),
        );
      },
    );
  }
}

class SettingsNotifier extends ChangeNotifier {
  SettingsNotifier._();

  static final instance = SettingsNotifier._();

  void refresh() {
    notifyListeners();
  }
}

// ============================================================
// Home
// ============================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  List<Map<String, dynamic>> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await AppDb.instance.all();

      if (!mounted) return;

      setState(() {
        rows = data;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر تحميل السجلات',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      Dashboard(
        rows: rows,
        onRefresh: load,
      ),
      RecordsPage(
        rows: rows,
        onRefresh: load,
      ),
      ReportsPage(
        rows: rows,
      ),
      const SettingsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافي'),
      ),
      body: pages[tab],
      floatingActionButton:
          tab == 0 || tab == 1
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (_) => AddDialog(
                        onSaved: load,
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة إضافي'),
                )
              : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) {
          setState(() {
            tab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'السجلات',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'التقارير',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Dashboard
// ============================================================

class Dashboard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Future<void> Function() onRefresh;

  const Dashboard({
    super.key,
    required this.rows,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final today =
        DateFormat('yyyy-MM-dd').format(now);

    final todayRows =
        rows.where((r) => r['date'] == today);

    final todayHours = todayRows.fold<num>(
      0,
      (sum, row) =>
          sum + ((row['hours'] as num?) ?? 0),
    );

    final todayMoney = todayRows.fold<int>(
      0,
      (sum, row) =>
          sum + ((row['total'] as num?)?.round() ?? 0),
    );

    final month =
        DateFormat('yyyy-MM').format(now);

    final monthRows = rows.where(
      (r) =>
          r['date'] is String &&
          (r['date'] as String).startsWith(month),
    );

    final monthHours = monthRows.fold<num>(
      0,
      (sum, row) =>
          sum + ((row['hours'] as num?) ?? 0),
    );

    final monthMoney = monthRows.fold<int>(
      0,
      (sum, row) =>
          sum + ((row['total'] as num?)?.round() ?? 0),
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'ملخص اليوم',
            style: Theme.of(context)
                .textTheme
                .headlineSmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  title: 'ساعات اليوم',
                  value:
                      '${fmtHours(todayHours)} ساعة',
                  icon: Icons.schedule,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  title: 'قيمة اليوم',
                  value: money(todayMoney),
                  icon: Icons.payments,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  title: 'ساعات الشهر',
                  value:
                      '${fmtHours(monthHours)} ساعة',
                  icon: Icons.calendar_month,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  title: 'قيمة الشهر',
                  value: money(monthMoney),
                  icon:
                      Icons.account_balance_wallet,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'آخر السجلات',
            style: Theme.of(context)
                .textTheme
                .titleLarge,
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'لا توجد سجلات بعد. أضف أول ساعاتك الإضافية.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            ...rows.take(5).map(
              (row) => RecordTile(
                row: row,
                onRefresh: onRefresh,
              ),
            ),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 8),
            Text(title),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Records
// ============================================================

class RecordsPage extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Future<void> Function() onRefresh;

  const RecordsPage({
    super.key,
    required this.rows,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(
        child: Text('لا توجد سجلات.'),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: rows
            .map(
              (row) => RecordTile(
                row: row,
                onRefresh: onRefresh,
              ),
            )
            .toList(),
      ),
    );
  }
}

class RecordTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final Future<void> Function() onRefresh;

  const RecordTile({
    super.key,
    required this.row,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final hours = (row['hours'] as num?) ?? 0;
    final total = (row['total'] as num?) ?? 0;

    final note =
        (row['note'] as String?)?.trim() ?? '';

    final start = row['start'] as String?;
    final end = row['end'] as String?;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            fmtHours(hours),
            textAlign: TextAlign.center,
          ),
        ),
        title: Text(
          fmtDate(
            row['date'] as String? ?? '',
          ),
        ),
        subtitle: Text(
          [
            '${start ?? '--'} → ${end ?? '--'}',
            if (note.isNotEmpty) note,
            money(total),
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              await showDialog(
                context: context,
                builder: (_) => AddDialog(
                  existing: row,
                  onSaved: onRefresh,
                ),
              );
            }

            if (value == 'delete') {
              final ok =
                  await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text(
                    'حذف السجل؟',
                  ),
                  content: const Text(
                    'سيتم حذف هذا السجل نهائيًا.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(
                        context,
                        false,
                      ),
                      child:
                          const Text('إلغاء'),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(
                        context,
                        true,
                      ),
                      child:
                          const Text('حذف'),
                    ),
                  ],
                ),
              );

              if (ok == true) {
                final id =
                    row['id'] as int?;

                if (id != null) {
                  await AppDb.instance.delete(id);
                  await onRefresh();
                }
              }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'edit',
              child: Text('تعديل'),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text('حذف'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Add / Edit
// ============================================================

class AddDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final Future<void> Function() onSaved;

  const AddDialog({
    super.key,
    this.existing,
    required this.onSaved,
  });

  @override
  State<AddDialog> createState() =>
      _AddDialogState();
}

class _AddDialogState extends State<AddDialog> {
  late DateTime date;

  TimeOfDay? start;
  TimeOfDay? end;

  final hours = TextEditingController();
  final note = TextEditingController();

  bool useTimes = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    if (existing == null) {
      date = DateTime.now();
    } else {
      final parsed =
          DateTime.tryParse(
        existing['date']?.toString() ?? '',
      );

      date = parsed ?? DateTime.now();

      final startValue =
          existing['start'];

      final endValue =
          existing['end'];

      if (startValue is String) {
        start = _parseTimeSafe(startValue);
      }

      if (endValue is String) {
        end = _parseTimeSafe(endValue);
      }

      hours.text =
          '${existing['hours'] ?? ''}';

      note.text =
          existing['note'] is String
              ? existing['note'] as String
              : '';
    }

    useTimes =
        start != null && end != null;
  }

  TimeOfDay? _parseTimeSafe(String value) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})$',
    ).firstMatch(value);

    if (match == null) return null;

    final hour =
        int.tryParse(match.group(1)!);

    final minute =
        int.tryParse(match.group(2)!);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return TimeOfDay(
      hour: hour,
      minute: minute,
    );
  }

  String _time(TimeOfDay value) {
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  double? _calculatedHours() {
    if (start == null || end == null) {
      return null;
    }

    final startMinutes =
        start!.hour * 60 + start!.minute;

    final endMinutes =
        end!.hour * 60 + end!.minute;

    var difference =
        endMinutes - startMinutes;

    // دعم العمل الذي يتجاوز منتصف الليل.
    if (difference < 0) {
      difference += 24 * 60;
    }

    if (difference == 0) {
      return 24;
    }

    return difference / 60;
  }

  Future<void> pickDate() async {
    final selected =
        await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
      localizationsDelegates:
          GlobalMaterialLocalizations.delegates,
      supportedLocales: const [
        Locale('ar'),
      ],
    );

    if (selected != null &&
        mounted) {
      setState(() {
        date = selected;
      });
    }
  }

  Future<void> pickTime(
    bool isStart,
  ) async {
    final selected =
        await showTimePicker(
      context: context,
      initialTime: isStart
          ? (start ?? TimeOfDay.now())
          : (end ?? TimeOfDay.now()),
    );

    if (selected == null ||
        !mounted) {
      return;
    }

    setState(() {
      if (isStart) {
        start = selected;
      } else {
        end = selected;
      }
    });
  }

  void showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  Future<void> save() async {
    if (saving) return;

    double h;

    if (useTimes) {
      if (start == null ||
          end == null) {
        showError(
          'اختر وقت البداية والنهاية',
        );
        return;
      }

      final calculated =
          _calculatedHours();

      if (calculated == null) {
        showError(
          'تعذر حساب عدد الساعات',
        );
        return;
      }

      h = calculated;
    } else {
      final normalized =
          hours.text.trim().replaceAll(',', '.');

      h = double.tryParse(normalized) ?? 0;
    }

    if (!h.isFinite ||
        h <= 0 ||
        h > 24) {
      showError(
        'عدد الساعات يجب أن يكون أكبر من صفر وأقل من أو يساوي 24',
      );
      return;
    }

    final rate =
        Settings.instance.rate;

    if (rate <= 0) {
      showError(
        'سعر الساعة غير صحيح',
      );
      return;
    }

    final total =
        (h * rate).round();

    final row = <String, dynamic>{
      'date': DateFormat(
        'yyyy-MM-dd',
      ).format(date),
      'start': useTimes
          ? _time(start!)
          : null,
      'end': useTimes
          ? _time(end!)
          : null,
      'hours': h,
      'rate': rate,
      'total': total,
      'note': note.text.trim(),
    };

    setState(() {
      saving = true;
    });

    try {
      final existing =
          widget.existing;

      if (existing == null) {
        await AppDb.instance.insert(row);
      } else {
        final id =
            existing['id'] as int?;

        if (id == null) {
          throw StateError(
            'معرف السجل غير موجود',
          );
        }

        await AppDb.instance.update(
          id,
          row,
        );
      }

      await widget.onSaved();

      if (!mounted) return;

      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
        });

        showError(
          'تعذر حفظ السجل',
        );
      }
    }
  }

  @override
  void dispose() {
    hours.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calculated =
        useTimes &&
                start != null &&
                end != null
            ? _calculatedHours()
            : null;

    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'إضافة ساعات'
            : 'تعديل السجل',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            ListTile(
              contentPadding:
                  EdgeInsets.zero,
              leading: const Icon(
                Icons.calendar_today,
              ),
              title: Text(
                DateFormat(
                  'EEEE، yyyy/MM/dd',
                  'ar',
                ).format(date),
              ),
              onTap: pickDate,
            ),
            SwitchListTile(
              contentPadding:
                  EdgeInsets.zero,
              title: const Text(
                'الحساب من وقت البداية والنهاية',
              ),
              value: useTimes,
              onChanged: saving
                  ? null
                  : (value) {
                      setState(() {
                        useTimes = value;
                      });
                    },
            ),
            if (useTimes) ...[
              ListTile(
                contentPadding:
                    EdgeInsets.zero,
                leading: const Icon(
                  Icons.login,
                ),
                title: Text(
                  'بداية الإضافي: '
                  '${start == null ? 'اختر الوقت' : start!.format(context)}',
                ),
                onTap: saving
                    ? null
                    : () => pickTime(true),
              ),
              ListTile(
                contentPadding:
                    EdgeInsets.zero,
                leading: const Icon(
                  Icons.logout,
                ),
                title: Text(
                  'نهاية الإضافي: '
                  '${end == null ? 'اختر الوقت' : end!.format(context)}',
                ),
                onTap: saving
                    ? null
                    : () => pickTime(false),
              ),
            ] else
              TextField(
                controller: hours,
                enabled: !saving,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    const InputDecoration(
                  labelText:
                      'عدد الساعات',
                  hintText: 'مثال: 2.5',
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              enabled: !saving,
              maxLines: 2,
              decoration:
                  const InputDecoration(
                labelText:
                    'ملاحظات (اختياري)',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'سعر الساعة: ${money(Settings.instance.rate)}',
            ),
            if (calculated != null)
              Text(
                'الإجمالي المتوقع: '
                '${money(calculated * Settings.instance.rate)}',
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving
              ? null
              : () => Navigator.pop(context),
          child:
              const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }
}

// ============================================================
// Reports
// ============================================================

class ReportsPage extends StatefulWidget {
  final List<Map<String, dynamic>> rows;

  const ReportsPage({
    super.key,
    required this.rows,
  });

  @override
  State<ReportsPage> createState() =>
      _ReportsPageState();
}

class _ReportsPageState
    extends State<ReportsPage> {
  String mode = 'month';

  DateTime from = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  DateTime to = DateTime.now();

  List<Map<String, dynamic>> get filtered {
    var start = DateTime(
      from.year,
      from.month,
      from.day,
    );

    var end = DateTime(
      to.year,
      to.month,
      to.day,
      23,
      59,
      59,
      999,
    );

    if (end.isBefore(start)) {
      final temp = start;
      start = end;
      end = temp;
    }

    return widget.rows.where((row) {
      final raw = row['date'];

      if (raw is! String) {
        return false;
      }

      final date =
          DateTime.tryParse(raw);

      if (date == null) {
        return false;
      }

      return !date.isBefore(start) &&
          !date.isAfter(end);
    }).toList();
  }

  void setMode(String value) {
    final now = DateTime.now();

    setState(() {
      mode = value;

      if (value == 'day') {
        from = DateTime(
          now.year,
          now.month,
          now.day,
        );

        to = from;
      } else if (value == 'week') {
        final monday =
            now.subtract(
          Duration(
            days: now.weekday - 1,
          ),
        );

        from = DateTime(
          monday.year,
          monday.month,
          monday.day,
        );

        to = from.add(
          const Duration(days: 6),
        );
      } else if (value == 'month') {
        from = DateTime(
          now.year,
          now.month,
          1,
        );

        to = DateTime(
          now.year,
          now.month + 1,
          0,
        );
      }
    });
  }

  Future<void> pick(
    bool isFrom,
  ) async {
    final initialDate =
        isFrom ? from : to;

    final selected =
        await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
      localizationsDelegates:
          GlobalMaterialLocalizations.delegates,
      supportedLocales: const [
        Locale('ar'),
      ],
    );

    if (selected == null ||
        !mounted) {
      return;
    }

    setState(() {
      if (isFrom) {
        from = selected;

        if (to.isBefore(from)) {
          to = from;
        }
      } else {
        to = selected;

        if (to.isBefore(from)) {
          from = to;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;

    final h = list.fold<num>(
      0,
      (sum, row) =>
          sum + ((row['hours'] as num?) ?? 0),
    );

    final total = list.fold<int>(
      0,
      (sum, row) =>
          sum +
          ((row['total'] as num?)?.round() ??
              0),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'day',
              label: Text('يومي'),
            ),
            ButtonSegment(
              value: 'week',
              label: Text('أسبوعي'),
            ),
            ButtonSegment(
              value: 'month',
              label: Text('شهري'),
            ),
            ButtonSegment(
              value: 'custom',
              label: Text('مخصص'),
            ),
          ],
          selected: {mode},
          onSelectionChanged:
              (selection) {
            if (selection.isNotEmpty) {
              setMode(
                selection.first,
              );
            }
          },
        ),
        const SizedBox(height: 16),
        if (mode == 'custom')
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      pick(true),
                  child: Text(
                    'من ${fmtDate(DateFormat('yyyy-MM-dd').format(from))}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      pick(false),
                  child: Text(
                    'إلى ${fmtDate(DateFormat('yyyy-MM-dd').format(to))}',
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding:
                const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'الفترة: '
                  '${fmtDate(DateFormat('yyyy-MM-dd').format(from))}'
                  ' — '
                  '${fmtDate(DateFormat('yyyy-MM-dd').format(to))}',
                  textAlign:
                      TextAlign.center,
                ),
                const SizedBox(
                  height: 16,
                ),
                Text(
                  '${fmtHours(h)} ساعة',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  money(total),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${list.length} سجل',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'لا توجد سجلات في هذه الفترة.',
              ),
            ),
          )
        else
          ...list.map(
            (row) => ListTile(
              leading: const Icon(
                Icons.access_time,
              ),
              title: Text(
                fmtDate(
                  row['date'] as String? ??
                      '',
                ),
              ),
              subtitle: Text(
                '${fmtHours((row['hours'] as num?) ?? 0)} ساعة',
              ),
              trailing: Text(
                money(
                  (row['total'] as num?) ?? 0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================
// Settings Page
// ============================================================

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() =>
      _SettingsPageState();
}

class _SettingsPageState
    extends State<SettingsPage> {
  final rate =
      TextEditingController();

  @override
  void initState() {
    super.initState();

    rate.text =
        '${Settings.instance.rate}';
  }

  @override
  void dispose() {
    rate.dispose();
    super.dispose();
  }

  Future<void> saveRate() async {
    final value = int.tryParse(
      rate.text.trim(),
    );

    if (value == null ||
        value <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              'أدخل سعر ساعة صحيحًا أكبر من صفر',
            ),
          ),
        );
      }

      return;
    }

    Settings.instance.rate =
        value;

    await Settings.instance.save();

    SettingsNotifier.instance
        .refresh();

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content:
            Text('تم حفظ سعر الساعة'),
      ),
    );

    setState(() {});
  }

  Future<void>
      chooseReminderTime() async {
    final selected =
        await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: Settings
            .instance.reminderHour,
        minute: Settings
            .instance.reminderMinute,
      ),
    );

    if (selected == null ||
        !mounted) {
      return;
    }

    Settings.instance.reminderHour =
        selected.hour;

    Settings.instance.reminderMinute =
        selected.minute;

    await Settings.instance.save();

    await NotificationService.schedule(
      enabled:
          Settings.instance.reminders,
      hour: selected.hour,
      minute: selected.minute,
    );

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> backup() async {
    try {
      final rows =
          await AppDb.instance.all();

      final payload = jsonEncode({
        'version': 1,
        'createdAt':
            DateTime.now()
                .toIso8601String(),
        'settings': {
          'rate':
              Settings.instance.rate,
          'themeMode': Settings
              .instance
              .themeMode
              .name,
          'colorSeed': Settings
              .instance
              .colorSeed,
          'reminders':
              Settings.instance
                  .reminders,
          'reminderHour': Settings
              .instance
              .reminderHour,
          'reminderMinute': Settings
              .instance
              .reminderMinute,
          'endTimes': Settings
              .instance
              .endTimes
              .map(
                (key, value) =>
                    MapEntry(
                  '$key',
                  value,
                ),
              ),
        },
        'overtime': rows,
      });

      final dir = await FilePicker
          .platform
          .getDirectoryPath();

      if (dir == null) return;

      final fileName =
          'overtime_backup_'
          '${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}'
          '.json';

      final path =
          p.join(dir, fileName);

      await File(path).writeAsString(
        payload,
        flush: true,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'تم حفظ النسخة الاحتياطية:\n$path',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر إنشاء النسخة الاحتياطية',
          ),
        ),
      );
    }
  }

  Future<void> restore() async {
    final result =
        await FilePicker.platform
            .pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null ||
        result.files.isEmpty) {
      return;
    }

    final filePath =
        result.files.single.path;

    if (filePath == null) {
      return;
    }

    try {
      final content =
          await File(filePath)
              .readAsString();

      final decoded =
          jsonDecode(content);

      if (decoded is! Map) {
        throw const FormatException();
      }

      final version =
          decoded['version'];

      final overtime =
          decoded['overtime'];

      if (version != 1 ||
          overtime is! List) {
        throw const FormatException();
      }

      final ok =
          await showDialog<bool>(
        context: context,
        builder: (_) =>
            AlertDialog(
          title: const Text(
            'استرداد النسخة؟',
          ),
          content: const Text(
            'سيتم استبدال السجلات الحالية بالنسخة الاحتياطية.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                false,
              ),
              child:
                  const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                true,
              ),
              child:
                  const Text('استرداد'),
            ),
          ],
        ),
      );

      if (ok != true) return;

      // نتحقق من كل السجلات قبل حذف البيانات الحالية.
      await AppDb.instance
          .replaceAll(overtime);

      final rawSettings =
          decoded['settings'];

      if (rawSettings is Map) {
        final settings =
            Map<String, dynamic>.from(
          rawSettings,
        );

        final savedRate =
            settings['rate'];

        if (savedRate is num &&
            savedRate.isFinite &&
            savedRate > 0) {
          Settings.instance.rate =
              savedRate.round();
        }

        final savedColor =
            settings['colorSeed'];

        if (savedColor is num &&
            savedColor.isFinite) {
          Settings.instance.colorSeed =
              savedColor
                  .round()
                  .clamp(0, 4);
        }

        final savedReminders =
            settings['reminders'];

        if (savedReminders is bool) {
          Settings.instance
                  .reminders =
              savedReminders;
        }

        final savedHour =
            settings['reminderHour'];

        if (savedHour is num &&
            savedHour.isFinite) {
          Settings.instance
                  .reminderHour =
              savedHour
                  .round()
                  .clamp(0, 23);
        }

        final savedMinute =
            settings['reminderMinute'];

        if (savedMinute is num &&
            savedMinute.isFinite) {
          Settings.instance
                  .reminderMinute =
              savedMinute
                  .round()
                  .clamp(0, 59);
        }

        final savedMode =
            settings['themeMode'];

        if (savedMode is String) {
          Settings.instance
              .themeMode = ThemeMode
              .values
              .firstWhere(
            (mode) =>
                mode.name ==
                savedMode,
            orElse: () =>
                ThemeMode.system,
          );
        }

        final savedEndTimes =
            settings['endTimes'];

        if (savedEndTimes is Map) {
          for (final key
              in Settings.instance
                  .endTimes
                  .keys) {
            final value =
                savedEndTimes['$key'];

            if (value is String &&
                RegExp(
                  r'^([01]\d|2[0-3]):[0-5]\d$',
                ).hasMatch(value)) {
              Settings.instance
                      .endTimes[key] =
                  value;
            }
          }
        }
      }

      await Settings.instance.save();

      await NotificationService
          .schedule(
        enabled:
            Settings.instance
                .reminders,
        hour: Settings
            .instance
            .reminderHour,
        minute: Settings
            .instance
            .reminderMinute,
      );

      if (!mounted) return;

      SettingsNotifier.instance
          .refresh();

      setState(() {
        rate.text =
            '${Settings.instance.rate}';
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'تم استرداد النسخة بنجاح',
          ),
        ),
      );
    } on FormatException {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'ملف النسخة الاحتياطية غير صالح',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر استرداد النسخة الاحتياطية',
          ),
        ),
      );
    }
  }

  Future<void>
      changeTheme(
    ThemeMode? mode,
  ) async {
    if (mode == null) return;

    Settings.instance.themeMode =
        mode;

    await Settings.instance.save();

    SettingsNotifier.instance
        .refresh();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void>
      changeColor(int index) async {
    Settings.instance.colorSeed =
        index;

    await Settings.instance.save();

    SettingsNotifier.instance
        .refresh();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void>
      changeReminders(
    bool enabled,
  ) async {
    Settings.instance.reminders =
        enabled;

    await Settings.instance.save();

    await NotificationService
        .schedule(
      enabled: enabled,
      hour: Settings
          .instance
          .reminderHour,
      minute: Settings
          .instance
          .reminderMinute,
    );

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = [
      Colors.indigo,
      Colors.teal,
      Colors.deepPurple,
      Colors.orange,
      Colors.pink,
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'الإعدادات',
          style: Theme.of(context)
              .textTheme
              .headlineSmall,
        ),
        const SizedBox(height: 12),

        // Rate
        Card(
          child: Padding(
            padding:
                const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'سعر الساعة',
                  style: TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: rate,
                  keyboardType:
                      TextInputType.number,
                  decoration:
                      const InputDecoration(
                    suffixText: 'ريال',
                    border:
                        OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment:
                      AlignmentDirectional
                          .centerEnd,
                  child: FilledButton(
                    onPressed: saveRate,
                    child:
                        const Text('حفظ'),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Theme
        Card(
          child: Column(
            children: [
              const ListTile(
                leading:
                    Icon(Icons.palette),
                title:
                    Text('المظهر'),
              ),
              RadioListTile<ThemeMode>(
                title:
                    const Text('تلقائي'),
                value:
                    ThemeMode.system,
                groupValue:
                    Settings.instance
                        .themeMode,
                onChanged:
                    changeTheme,
              ),
              RadioListTile<ThemeMode>(
                title:
                    const Text('فاتح'),
                value:
                    ThemeMode.light,
                groupValue:
                    Settings.instance
                        .themeMode,
                onChanged:
                    changeTheme,
              ),
              RadioListTile<ThemeMode>(
                title:
                    const Text('داكن'),
                value:
                    ThemeMode.dark,
                groupValue:
                    Settings.instance
                        .themeMode,
                onChanged:
                    changeTheme,
              ),
            ],
          ),
        ),

        // Colors
        Card(
          child: ListTile(
            leading:
                const Icon(Icons.color_lens),
            title:
                const Text('لون التطبيق'),
            subtitle: Padding(
              padding:
                  const EdgeInsets.only(
                top: 12,
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children:
                    List.generate(
                  colors.length,
                  (index) {
                    final selected =
                        Settings.instance
                                .colorSeed ==
                            index;

                    return InkWell(
                      borderRadius:
                          BorderRadius
                              .circular(
                        50,
                      ),
                      onTap: () =>
                          changeColor(
                        index,
                      ),
                      child:
                          CircleAvatar(
                        backgroundColor:
                            colors[index],
                        child: selected
                            ? const Icon(
                                Icons.check,
                                color: Colors
                                    .white,
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),

        // Reminders
        Card(
          child: SwitchListTile(
            secondary:
                const Icon(Icons.notifications),
            title: const Text(
              'التذكير اليومي',
            ),
            subtitle: Text(
              'وقت التذكير: '
              '${TimeOfDay(
                hour: Settings
                    .instance
                    .reminderHour,
                minute: Settings
                    .instance
                    .reminderMinute,
              ).format(context)}',
            ),
            value:
                Settings.instance
                    .reminders,
            onChanged:
                changeReminders,
          ),
        ),

        if (Settings.instance
            .reminders)
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.notifications_active,
              ),
              title: const Text(
                'تغيير وقت التذكير',
              ),
              onTap:
                  chooseReminderTime,
            ),
          ),

        const SizedBox(height: 12),

        // Backup
        Card(
          child: Column(
            children: [
              ListTile(
                leading:
                    const Icon(Icons.backup),
                title: const Text(
                  'إنشاء نسخة احتياطية',
                ),
                onTap: backup,
              ),
              ListTile(
                leading:
                    const Icon(Icons.restore),
                title: const Text(
                  'استرداد نسخة احتياطية',
                ),
                onTap: restore,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        const Center(
          child: Text(
            'إضافي • الإصدار 1.0.0',
          ),
        ),

        const SizedBox(height: 30),
      ],
    );
  }
}

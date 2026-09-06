import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await AppDb.instance.init();
  await Settings.instance.load();
  await await NotificationService.init();
  runApp(const OvertimeApp());
}

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
    _prefs = await SharedPreferences.getInstance();
    rate = _prefs!.getInt('rate') ?? 1500;
    colorSeed = _prefs!.getInt('colorSeed') ?? 0;
    reminders = _prefs!.getBool('reminders') ?? true;
    reminderHour = _prefs!.getInt('reminderHour') ?? 18;
    reminderMinute = _prefs!.getInt('reminderMinute') ?? 0;
    final mode = _prefs!.getString('themeMode') ?? 'system';
    themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == mode,
      orElse: () => ThemeMode.system,
    );
    for (final entry in endTimes.entries) {
      endTimes[entry.key] =
          _prefs!.getString('end_${entry.key}') ?? entry.value;
    }
  }

  Future<void> save() async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    await p.setInt('rate', rate);
    await p.setInt('colorSeed', colorSeed);
    await p.setBool('reminders', reminders);
    await p.setInt('reminderHour', reminderHour);
    await p.setInt('reminderMinute', reminderMinute);
    await p.setString('themeMode', themeMode.name);
    for (final e in endTimes.entries) {
      await p.setString('end_${e.key}', e.value);
    }
  }
}

class AppDb {
  AppDb._();
  static final instance = AppDb._();
  Database? _db;

  Future<void> init() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'overtime_yer.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
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

  Future<List<Map<String, dynamic>>> all() async =>
      _db!.query('overtime', orderBy: 'date DESC, id DESC');

  Future<int> insert(Map<String, dynamic> row) =>
      _db!.insert('overtime', row);

  Future<int> update(int id, Map<String, dynamic> row) =>
      _db!.update('overtime', row, where: 'id = ?', whereArgs: [id]);

  Future<int> delete(int id) =>
      _db!.delete('overtime', where: 'id = ?', whereArgs: [id]);

  Future<void> replaceAll(List<dynamic> rows) async {
    await _db!.transaction((txn) async {
      await txn.delete('overtime');
      for (final item in rows) {
        final map = Map<String, dynamic>.from(item as Map);
        map.remove('id');
        await txn.insert('overtime', map);
      }
    });
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'overtime_reminders',
    'تذكير الساعات الإضافية',
    description: 'تذكيرات يومية لإضافة الساعات الإضافية',
    importance: Importance.defaultImportance,
  );

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);
    await androidPlugin?.requestNotificationsPermission();
  }

  static Future<void> cancel() => _plugin.cancel(1001);

  static Future<void> schedule({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    await cancel();
    if (!enabled) return;

    final now = tz.TZDateTime.now(tz.local);
    for (int weekday = DateTime.saturday;
        weekday <= DateTime.thursday;
        weekday++) {
      var next = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      while (next.weekday != weekday || !next.isAfter(now)) {
        next = next.add(const Duration(days: 1));
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
            channelDescription: 'تذكيرات يومية لإضافة الساعات الإضافية',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }
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
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'إضافي',
        locale: const Locale('ar'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ar')],
        themeMode: Settings.instance.themeMode,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: seeds[Settings.instance.colorSeed],
          fontFamily: 'sans',
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: seeds[Settings.instance.colorSeed],
        ),
        home: const HomePage(),
      ),
    );
  }
}

class SettingsNotifier extends ChangeNotifier {
  SettingsNotifier._();
  static final instance = SettingsNotifier._();
  void refresh() => notifyListeners();
}

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
    rows = await AppDb.instance.all();
    if (mounted) setState(() {});
  }

  num get totalHours => rows.fold<num>(0, (s, r) => s + (r['hours'] as num));
  int get totalMoney =>
      rows.fold<int>(0, (s, r) => s + (r['total'] as int));

  @override
  Widget build(BuildContext context) {
    final pages = [
      Dashboard(rows: rows, onRefresh: load),
      RecordsPage(rows: rows, onRefresh: load),
      ReportsPage(rows: rows),
      const SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('إضافي')),
      body: pages[tab],
      floatingActionButton: tab == 0 || tab == 1
          ? FloatingActionButton.extended(
              onPressed: () async {
                await showDialog(
                  context: context,
                  builder: (_) => AddDialog(onSaved: load),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('إضافة إضافي'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'السجلات'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'التقارير'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

class Dashboard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final VoidCallback onRefresh;
  const Dashboard({super.key, required this.rows, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayRows = rows.where((r) => r['date'] == today);
    final todayHours = todayRows.fold<num>(0, (s, r) => s + (r['hours'] as num));
    final todayMoney = todayRows.fold<int>(0, (s, r) => s + (r['total'] as int));
    final month = DateTime.now().toIso8601String().substring(0, 7);
    final monthRows = rows.where((r) => (r['date'] as String).startsWith(month));
    final monthHours = monthRows.fold<num>(0, (s, r) => s + (r['hours'] as num));
    final monthMoney = monthRows.fold<int>(0, (s, r) => s + (r['total'] as int));

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('ملخص اليوم', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: StatCard(title: 'ساعات اليوم', value: '$todayHours ساعة', icon: Icons.schedule)),
            const SizedBox(width: 12),
            Expanded(child: StatCard(title: 'قيمة اليوم', value: money(todayMoney), icon: Icons.payments)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: StatCard(title: 'ساعات الشهر', value: '$monthHours ساعة', icon: Icons.calendar_month)),
            const SizedBox(width: 12),
            Expanded(child: StatCard(title: 'قيمة الشهر', value: money(monthMoney), icon: Icons.account_balance_wallet)),
          ]),
          const SizedBox(height: 24),
          Text('آخر السجلات', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const Card(child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('لا توجد سجلات بعد. أضف أول ساعاتك الإضافية.')),
            ))
          else
            ...rows.take(5).map((r) => RecordTile(row: r, onRefresh: onRefresh)),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  const StatCard({super.key, required this.title, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon),
        const SizedBox(height: 8),
        Text(title),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ]),
    ),
  );
}

class RecordsPage extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final VoidCallback onRefresh;
  const RecordsPage({super.key, required this.rows, required this.onRefresh});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: rows.isEmpty
      ? [const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('لا توجد سجلات.')))]
      : rows.map((r) => RecordTile(row: r, onRefresh: onRefresh)).toList(),
  );
}

class RecordTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onRefresh;
  const RecordTile({super.key, required this.row, required this.onRefresh});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${row['hours']}')),
        title: Text(fmtDate(row['date'])),
        subtitle: Text('${row['start'] ?? '--'} → ${row['end'] ?? '--'}\n${row['note'] ?? ''}'),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              await showDialog(context: context, builder: (_) => AddDialog(existing: row, onSaved: onRefresh));
            } else if (v == 'delete') {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('حذف السجل؟'),
                  content: const Text('سيتم حذف هذا السجل نهائيًا.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
                  ],
                ),
              );
              if (ok == true) {
                await AppDb.instance.delete(row['id'] as int);
                onRefresh();
              }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('تعديل')),
            PopupMenuItem(value: 'delete', child: Text('حذف')),
          ],
        ),
      ),
    );
  }
}

class AddDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;
  const AddDialog({super.key, this.existing, required this.onSaved});
  @override
  State<AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<AddDialog> {
  late DateTime date;
  TimeOfDay? start;
  TimeOfDay? end;
  final hours = TextEditingController();
  final note = TextEditingController();
  bool useTimes = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    date = e == null ? DateTime.now() : DateTime.parse(e['date']);
    if (e?['start'] != null) start = _parseTime(e!['start']);
    if (e?['end'] != null) end = _parseTime(e!['end']);
    hours.text = e == null ? '' : '${e['hours']}';
    note.text = e?['note'] ?? '';
    useTimes = start != null && end != null;
  }

  TimeOfDay _parseTime(String x) {
    final a = x.split(':');
    return TimeOfDay(hour: int.parse(a[0]), minute: int.parse(a[1]));
  }

  String _time(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  double _calculatedHours() {
    if (start == null || end == null) return double.tryParse(hours.text) ?? 0;
    final s = start!.hour * 60 + start!.minute;
    final e = end!.hour * 60 + end!.minute;
    return ((e - s) / 60).clamp(0, 24);
  }

  Future<void> pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ar')],
    );
    if (d != null) setState(() => date = d);
  }

  Future<void> pickTime(bool isStart) async {
    final t = await showTimePicker(context: context, initialTime: isStart ? (start ?? TimeOfDay.now()) : (end ?? TimeOfDay.now()));
    if (t != null) setState(() {
      if (isStart) start = t; else end = t;
    });
  }

  Future<void> save() async {
    final h = useTimes ? _calculatedHours() : (double.tryParse(hours.text) ?? 0);
    if (h <= 0) return;
    final total = (h * Settings.instance.rate).round();
    final row = {
      'date': DateFormat('yyyy-MM-dd').format(date),
      'start': useTimes && start != null ? _time(start!) : null,
      'end': useTimes && end != null ? _time(end!) : null,
      'hours': h,
      'rate': Settings.instance.rate,
      'total': total,
      'note': note.text.trim(),
    };
    if (widget.existing == null) {
      await AppDb.instance.insert(row);
    } else {
      await AppDb.instance.update(widget.existing!['id'] as int, row);
    }
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'إضافة ساعات' : 'تعديل السجل'),
    content: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_today),
          title: Text(DateFormat('EEEE، yyyy/MM/dd', 'ar').format(date)),
          onTap: pickDate,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('الحساب من وقت البداية والنهاية'),
          value: useTimes,
          onChanged: (v) => setState(() => useTimes = v),
        ),
        if (useTimes) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('بداية الإضافي: ${start == null ? 'اختر الوقت' : start!.format(context)}'),
            onTap: () => pickTime(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('نهاية الإضافي: ${end == null ? 'اختر الوقت' : end!.format(context)}'),
            onTap: () => pickTime(false),
          ),
        ] else
          TextField(
            controller: hours,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'عدد الساعات'),
          ),
        TextField(
          controller: note,
          decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
        ),
        const SizedBox(height: 8),
        Text('سعر الساعة: ${money(Settings.instance.rate)}'),
        if (useTimes && start != null && end != null)
          Text('الإجمالي المتوقع: ${money(_calculatedHours() * Settings.instance.rate)}'),
      ]),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
      FilledButton(onPressed: save, child: const Text('حفظ')),
    ],
  );
}

class ReportsPage extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  const ReportsPage({super.key, required this.rows});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String mode = 'month';
  DateTime from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime to = DateTime.now();

  List<Map<String, dynamic>> get filtered {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day, 23, 59, 59);
    return widget.rows.where((r) {
      final d = DateTime.parse(r['date']);
      return !d.isBefore(a) && !d.isAfter(b);
    }).toList();
  }

  void setMode(String m) {
    final now = DateTime.now();
    setState(() {
      mode = m;
      if (m == 'day') {
        from = DateTime(now.year, now.month, now.day);
        to = from;
      } else if (m == 'week') {
        final monday = now.subtract(Duration(days: now.weekday - 1));
        from = DateTime(monday.year, monday.month, monday.day);
        to = from.add(const Duration(days: 6));
      } else if (m == 'month') {
        from = DateTime(now.year, now.month, 1);
        to = DateTime(now.year, now.month + 1, 0);
      }
    });
  }

  Future<void> pick(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isFrom ? from : to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ar')],
    );
    if (d != null) setState(() {
      if (isFrom) from = d; else to = d;
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    final h = list.fold<num>(0, (s, r) => s + r['hours']);
    final moneyTotal = list.fold<int>(0, (s, r) => s + r['total'] as int);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'day', label: Text('يومي')),
            ButtonSegment(value: 'week', label: Text('أسبوعي')),
            ButtonSegment(value: 'month', label: Text('شهري')),
            ButtonSegment(value: 'custom', label: Text('مخصص')),
          ],
          selected: {mode},
          onSelectionChanged: (s) => setMode(s.first),
        ),
        const SizedBox(height: 16),
        if (mode == 'custom') Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => pick(true), child: Text('من ${fmtDate(DateFormat('yyyy-MM-dd').format(from))}'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () => pick(false), child: Text('إلى ${fmtDate(DateFormat('yyyy-MM-dd').format(to))}'))),
        ]),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Text('الفترة: ${fmtDate(DateFormat('yyyy-MM-dd').format(from))} — ${fmtDate(DateFormat('yyyy-MM-dd').format(to))}'),
              const SizedBox(height: 16),
              Text('$h ساعة', style: Theme.of(context).textTheme.headlineMedium),
              Text(money(moneyTotal), style: Theme.of(context).textTheme.titleLarge),
              Text('${list.length} سجل'),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        ...list.map((r) => ListTile(
          leading: const Icon(Icons.access_time),
          title: Text(fmtDate(r['date'])),
          subtitle: Text('${r['hours']} ساعة'),
          trailing: Text(money(r['total'])),
        )),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final rate = TextEditingController();

  @override
  void initState() {
    super.initState();
    rate.text = '${Settings.instance.rate}';
  }

  Future<void> saveRate() async {
    Settings.instance.rate = int.tryParse(rate.text) ?? Settings.instance.rate;
    await Settings.instance.save();
    SettingsNotifier.instance.refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ سعر الساعة')));
      setState(() {});
    }
  }

  Future<void> chooseReminderTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: Settings.instance.reminderHour, minute: Settings.instance.reminderMinute),
    );
    if (t != null) {
      Settings.instance.reminderHour = t.hour;
      Settings.instance.reminderMinute = t.minute;
      await Settings.instance.save();
      await NotificationService.schedule();
      setState(() {});
    }
  }

  Future<void> backup() async {
    final rows = await AppDb.instance.all();
    final payload = jsonEncode({
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'settings': {
        'rate': Settings.instance.rate,
        'themeMode': Settings.instance.themeMode.name,
        'colorSeed': Settings.instance.colorSeed,
        'reminders': Settings.instance.reminders,
        'reminderHour': Settings.instance.reminderHour,
        'reminderMinute': Settings.instance.reminderMinute,
        'endTimes': Settings.instance.endTimes.map((k, v) => MapEntry('$k', v)),
      },
      'overtime': rows,
    });
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final path = p.join(dir, 'overtime_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json');
    await File(path).writeAsString(payload);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ النسخة: $path')));
  }

  Future<void> restore() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (result == null || result.files.single.path == null) return;
    try {
      final data = jsonDecode(await File(result.files.single.path!).readAsString());
      if (data['version'] != 1 || data['overtime'] is! List) throw Exception();
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('استرداد النسخة؟'),
          content: const Text('سيتم استبدال السجلات الحالية بالنسخة الاحتياطية.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('استرداد')),
          ],
        ),
      );
      if (ok != true) return;
      await AppDb.instance.replaceAll(data['overtime']);
      final s = Map<String, dynamic>.from(data['settings'] ?? {});
      if (s['rate'] != null) Settings.instance.rate = s['rate'];
      if (s['colorSeed'] != null) Settings.instance.colorSeed = s['colorSeed'];
      if (s['reminders'] != null) Settings.instance.reminders = s['reminders'];
      if (s['reminderHour'] != null) Settings.instance.reminderHour = s['reminderHour'];
      if (s['reminderMinute'] != null) Settings.instance.reminderMinute = s['reminderMinute'];
      await Settings.instance.save();
      await NotificationService.schedule();
      if (mounted) {
        SettingsNotifier.instance.refresh();
        setState(() => rate.text = '${Settings.instance.rate}');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم استرداد النسخة بنجاح')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ملف النسخة الاحتياطية غير صالح')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = [Colors.indigo, Colors.teal, Colors.deepPurple, Colors.orange, Colors.pink];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('الإعدادات', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(child: Column(children: [
          ListTile(title: const Text('سعر الساعة'), subtitle: TextField(controller: rate, keyboardType: TextInputType.number, decoration: const InputDecoration(suffixText: 'ريال'))),
          Align(alignment: AlignmentDirectional.centerEnd, child: Padding(padding: const EdgeInsets.all(12), child: FilledButton(onPressed: saveRate, child: const Text('حفظ')))),
        ])),
        const SizedBox(height: 12),
        Card(child: Column(children: [
          const ListTile(title: Text('المظهر')),
          RadioListTile<ThemeMode>(title: const Text('تلقائي'), value: ThemeMode.system, groupValue: Settings.instance.themeMode, onChanged: (v) async { Settings.instance.themeMode = v!; await Settings.instance.save(); SettingsNotifier.instance.refresh(); }),
          RadioListTile<ThemeMode>(title: const Text('فاتح'), value: ThemeMode.light, groupValue: Settings.instance.themeMode, onChanged: (v) async { Settings.instance.themeMode = v!; await Settings.instance.save(); SettingsNotifier.instance.refresh(); }),
          RadioListTile<ThemeMode>(title: const Text('داكن'), value: ThemeMode.dark, groupValue: Settings.instance.themeMode, onChanged: (v) async { Settings.instance.themeMode = v!; await Settings.instance.save(); SettingsNotifier.instance.refresh(); }),
        ])),
        Card(child: ListTile(
          title: const Text('لون التطبيق'),
          subtitle: Wrap(spacing: 10, children: List.generate(colors.length, (i) => InkWell(
            onTap: () async { Settings.instance.colorSeed = i; await Settings.instance.save(); SettingsNotifier.instance.refresh(); },
            child: CircleAvatar(backgroundColor: colors[i], child: Settings.instance.colorSeed == i ? const Icon(Icons.check, color: Colors.white) : null),
          ))),
        )),
        Card(child: SwitchListTile(
          title: const Text('التذكير اليومي'),
          subtitle: Text('وقت التذكير: ${TimeOfDay(hour: Settings.instance.reminderHour, minute: Settings.instance.reminderMinute).format(context)}'),
          value: Settings.instance.reminders,
          onChanged: (v) async { Settings.instance.reminders = v; await Settings.instance.save(); await NotificationService.schedule(); setState(() {}); },
        )),
        if (Settings.instance.reminders)
          Card(child: ListTile(
            leading: const Icon(Icons.notifications_active),
            title: const Text('تغيير وقت التذكير'),
            onTap: chooseReminderTime,
          )),
        const SizedBox(height: 12),
        Card(child: Column(children: [
          ListTile(leading: const Icon(Icons.backup), title: const Text('إنشاء نسخة احتياطية'), onTap: backup),
          ListTile(leading: const Icon(Icons.restore), title: const Text('استرداد نسخة احتياطية'), onTap: restore),
        ])),
        const SizedBox(height: 20),
        const Center(child: Text('إضافي • الإصدار 1.0.0')),
      ],
    );
  }
}

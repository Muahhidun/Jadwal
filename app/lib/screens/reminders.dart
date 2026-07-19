import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/app_state.dart';
import '../notifications/notifications.dart';
import '../theme/tokens.dart';
import '../prayer/schedule_service.dart';

/// Главный экран настроек «Напоминания».
/// Отображает 3 категории: о молитвах, о зикрах и дуа, мои напоминания.
/// Содержит кнопку быстрого добавления своего напоминания на первом уровне.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  static const _prayersRu = ['Фаджр', 'Восход', 'Зухр', 'Аср', 'Магриб', 'Иша'];
  static const _prayersKz = ['Таң', 'Күн шығуы', 'Бесін', 'Екінті', 'Ақшам', 'Құптан'];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final schedule = ScheduleScope.of(context);
    final kz = app.lang == 'kz';
    final brightness = Theme.of(context).brightness;
    final c = brightness == Brightness.light ? JColors.light : JColors.dark;
    final prayers = kz ? _prayersKz : _prayersRu;

    Widget categoryRow(String title, String sub, IconData icon, VoidCallback onTap) =>
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.gold.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: c.gold, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: JType.ui(16, color: c.ink, w: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(sub, style: JType.ui(12.5, color: c.faint)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: c.faint),
            ]),
          ),
        );

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        elevation: 0,
        title: Text(kz ? 'Еске салулар' : 'Напоминания',
            style: JType.ui(17, w: FontWeight.w700, color: c.ink)),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final customCount = app.customReminders.length;
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 90),
            children: [
              categoryRow(
                kz ? 'Намаз еске салулары' : 'Напоминания о молитвах',
                kz ? 'Таң, Күн шығуы, Бесін, Екінті, Ақшам, Құптан' : 'Фаджр, Восход, Зухр, Аср, Магриб, Иша',
                Icons.access_time_filled_outlined,
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrayerRemindersScreen()),
                ),
              ),
              const Divider(height: 1, thickness: 0.5, indent: 24, endIndent: 24),
              categoryRow(
                kz ? 'Зікірлер мен дұғалар' : 'Напоминания о зикрах и дуа',
                kz ? 'Таңғы және кешкі зікірлер, Кәһф сүресі, дұға сағаты' : 'Утренние и вечерние зикры, сура аль-Кахф, час дуа',
                Icons.menu_book,
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WorshipRemindersScreen()),
                ),
              ),
              const Divider(height: 1, thickness: 0.5, indent: 24, endIndent: 24),
              categoryRow(
                kz ? 'Менің еске салуларым' : 'Мои напоминания',
                kz ? 'Қосылды: $customCount' : 'Добавлено: $customCount',
                Icons.playlist_add_check,
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CustomRemindersScreen()),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.gold,
        foregroundColor: c.bg,
        onPressed: () => _addDialog(context, app, schedule, kz, prayers),
        icon: const Icon(Icons.add),
        label: Text(kz ? 'Қосу' : 'Добавить',
            style: JType.ui(14, w: FontWeight.w700, color: c.bg)),
      ),
    );
  }

  Future<void> _addDialog(
      BuildContext context, AppState app, ScheduleService schedule, bool kz, List<String> prayers) async {
    final brightness = Theme.of(context).brightness;
    final c = brightness == Brightness.light ? JColors.light : JColors.dark;
    final titleCtrl = TextEditingController();
    final minCtrl = TextEditingController(text: '15');
    var prayer = 0;
    var before = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: brightness == Brightness.light ? Colors.white : c.card,
          title: Text(kz ? 'Жаңа еске салу' : 'Новое напоминание',
              style: JType.ui(17, w: FontWeight.w700, color: c.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: JType.ui(15, color: c.ink),
                cursorColor: c.gold,
                decoration: InputDecoration(
                  hintText: kz ? 'Атауы (мыс.: Дұға)' : 'Название (напр.: Дуа)',
                  hintStyle: JType.ui(14, color: c.faint),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.hair)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.gold)),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButton<int>(
                value: prayer,
                isExpanded: true,
                dropdownColor: brightness == Brightness.light ? Colors.white : c.card,
                style: JType.ui(15, color: c.ink),
                items: [
                  for (var i = 0; i < prayers.length; i++)
                    DropdownMenuItem(value: i, child: Text(prayers[i])),
                ],
                onChanged: (v) => setSt(() => prayer = v ?? 0),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: c.gold,
                      selectedForegroundColor: c.bg,
                    ),
                    segments: [
                      ButtonSegment(value: true, label: Text(kz ? 'дейін' : 'до')),
                      ButtonSegment(value: false, label: Text(kz ? 'кейін' : 'после')),
                    ],
                    selected: {before},
                    onSelectionChanged: (s) => setSt(() => before = s.first),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    style: JType.ui(15, color: c.ink),
                    cursorColor: c.gold,
                    decoration:
                        InputDecoration(
                          suffixText: kz ? 'мин' : 'мин',
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.hair)),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.gold)),
                        ),
                  ),
                ),
              ]),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(kz ? 'Болдырмау' : 'Отмена',
                    style: JType.ui(14, color: c.faint))),
            TextButton(
              onPressed: () {
                final m = int.tryParse(minCtrl.text) ?? 0;
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                app.addReminder(ReminderConfig(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  title: title,
                  prayer: prayer,
                  offsetMin: before ? -m : m,
                ));
                syncNotifications(app, schedule);
                Navigator.pop(ctx);
              },
              child: Text(kz ? 'Қосу' : 'Добавить',
                  style: JType.ui(14, w: FontWeight.w700, color: c.gold)),
            ),
          ],
        ),
      ),
    );
  }

  static String _configLabel(bool kz, ReminderConfig rc, List<String> prayers) {
    if (!rc.enabled) return kz ? 'Өшірулі' : 'Отключено';
    final repeatStr = switch (rc.repeat) {
      'weekly' => kz ? 'Әр аптада' : 'Каждую неделю',
      'monthly' => kz ? 'Әр айда' : 'Каждый месяц',
      _ => kz ? 'Күн сайын' : 'Каждый день',
    };
    final offsetStr = _offsetLabel(kz, prayers[rc.prayer], rc.offsetMin);
    return '$repeatStr · $offsetStr';
  }

  static String _offsetLabel(bool kz, String prayer, int off) {
    final m = off.abs();
    if (off == 0) return kz ? '$prayer уақытында' : 'в момент: $prayer';
    if (off < 0) return kz ? '$prayer — $m мин бұрын' : 'за $m мин до: $prayer';
    return kz ? '$prayer — $m мин кейін' : 'через $m мин после: $prayer';
  }
}

/// Экран категории «Напоминания о молитвах».
class PrayerRemindersScreen extends StatelessWidget {
  const PrayerRemindersScreen({super.key});

  static const _prayersRu = ['Фаджр', 'Восход', 'Зухр', 'Аср', 'Магриб', 'Иша'];
  static const _prayersKz = ['Таң', 'Күн шығуы', 'Бесін', 'Екінті', 'Ақшам', 'Құптан'];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final brightness = Theme.of(context).brightness;
    final c = brightness == Brightness.light ? JColors.light : JColors.dark;
    final prayers = kz ? _prayersKz : _prayersRu;
    final prayerIds = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        elevation: 0,
        title: Text(kz ? 'Намаз уақыттары' : 'Напоминания о молитвах',
            style: JType.ui(17, w: FontWeight.w700, color: c.ink)),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: prayerIds.length,
          separatorBuilder: (_, index) => const Divider(height: 1, thickness: 0.5, indent: 24, endIndent: 24),
          itemBuilder: (context, i) {
            final rc = app.getReminderConfig(prayerIds[i], app.lang);
            return _ReminderRow(
              title: prayers[i],
              sub: RemindersScreen._configLabel(kz, rc, prayers),
              c: c,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReminderDetailScreen(configId: prayerIds[i]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Экран категории «Напоминания о зикрах и дуа».
class WorshipRemindersScreen extends StatelessWidget {
  const WorshipRemindersScreen({super.key});

  static const _prayersRu = ['Фаджр', 'Восход', 'Зухр', 'Аср', 'Магриб', 'Иша'];
  static const _prayersKz = ['Таң', 'Күн шығуы', 'Бесін', 'Екінті', 'Ақшам', 'Құптан'];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final brightness = Theme.of(context).brightness;
    final c = brightness == Brightness.light ? JColors.light : JColors.dark;
    final prayers = kz ? _prayersKz : _prayersRu;

    final windows = [
      ('morning', kz ? 'Таңғы зікірлер' : 'Утренние зикры'),
      ('evening', kz ? 'Кешкі зікірлер' : 'Вечерние зикры'),
      ('kahf', kz ? '«әл-Кәһф» сүресі (жұма)' : 'Сура аль-Кахф (пятница)'),
      ('dua', kz ? 'Дұға сағаты (жұма)' : 'Час дуа (пятница)'),
    ];

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        elevation: 0,
        title: Text(kz ? 'Зікірлер мен дұғалар' : 'Зикры и дуа',
            style: JType.ui(17, w: FontWeight.w700, color: c.ink)),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: windows.length,
          separatorBuilder: (_, index) => const Divider(height: 1, thickness: 0.5, indent: 24, endIndent: 24),
          itemBuilder: (context, i) {
            final (id, title) = windows[i];
            final rc = app.getReminderConfig(id, app.lang);
            return _ReminderRow(
              title: title,
              sub: RemindersScreen._configLabel(kz, rc, prayers),
              c: c,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReminderDetailScreen(configId: id),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Экран категории «Мои напоминания».
class CustomRemindersScreen extends StatelessWidget {
  const CustomRemindersScreen({super.key});

  static const _prayersRu = ['Фаджр', 'Восход', 'Зухр', 'Аср', 'Магриб', 'Иша'];
  static const _prayersKz = ['Таң', 'Күн шығуы', 'Бесін', 'Екінті', 'Ақшам', 'Құптан'];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final schedule = ScheduleScope.of(context);
    final kz = app.lang == 'kz';
    final brightness = Theme.of(context).brightness;
    final c = brightness == Brightness.light ? JColors.light : JColors.dark;
    final prayers = kz ? _prayersKz : _prayersRu;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        elevation: 0,
        title: Text(kz ? 'Менің еске салуларым' : 'Мои напоминания',
            style: JType.ui(17, w: FontWeight.w700, color: c.ink)),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (app.customReminders.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  kz
                      ? 'Әлі ешқандай еске салу қосылмаған.'
                      : 'Еще не добавлено ни одного напоминания.',
                  textAlign: TextAlign.center,
                  style: JType.ui(14, color: c.faint, h: 1.4),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: app.customReminders.length,
            itemBuilder: (context, i) {
              final r = app.customReminders[i];
              return Dismissible(
                key: ValueKey(r.id),
                direction: DismissDirection.endToStart,
                background: Container(
                    color: c.red.withValues(alpha: .25),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: Icon(Icons.delete_outline, color: c.red)),
                onDismissed: (_) {
                  app.removeReminder(r.id);
                  syncNotifications(app, schedule);
                },
                child: Column(
                  children: [
                    _ReminderRow(
                      title: r.title,
                      sub: RemindersScreen._configLabel(kz, r, prayers),
                      c: c,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReminderDetailScreen(configId: r.id, isCustom: true),
                        ),
                      ),
                    ),
                    if (i < app.customReminders.length - 1)
                      const Divider(height: 1, thickness: 0.5, indent: 24, endIndent: 24),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Виджет строки в списке напоминаний.
class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.title,
    required this.sub,
    required this.c,
    required this.onTap,
  });

  final String title;
  final String sub;
  final JColors c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: JType.ui(15, color: c.ink, w: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(sub, style: JType.ui(12.5, color: c.faint)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: c.faint),
        ]),
      ),
    );
  }
}

/// Экран детальных настроек конкретного напоминания.
class ReminderDetailScreen extends StatefulWidget {
  const ReminderDetailScreen({super.key, required this.configId, this.isCustom = false});
  final String configId;
  final bool isCustom;

  @override
  State<ReminderDetailScreen> createState() => _ReminderDetailScreenState();
}

class _ReminderDetailScreenState extends State<ReminderDetailScreen> {
  late ReminderConfig config;
  late TextEditingController titleCtrl;
  late TextEditingController offsetCtrl;
  bool before = true;
  bool isInitialized = false;

  static const _prayersRu = ['Фаджр', 'Восход', 'Зухр', 'Аср', 'Магриб', 'Иша'];
  static const _prayersKz = ['Таң', 'Күн шығуы', 'Бесін', 'Екінті', 'Ақшам', 'Құптан'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!isInitialized) {
      final app = AppScope.of(context);
      if (widget.isCustom) {
        config = app.customReminders.firstWhere((r) => r.id == widget.configId);
      } else {
        config = app.getReminderConfig(widget.configId, app.lang);
      }
      titleCtrl = TextEditingController(text: config.title);
      offsetCtrl = TextEditingController(text: config.offsetMin.abs().toString());
      before = config.offsetMin <= 0;
      isInitialized = true;
    }
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    offsetCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final app = AppScope.of(context);
    final schedule = ScheduleScope.of(context);
    final m = int.tryParse(offsetCtrl.text) ?? 0;
    final finalOffset = before ? -m : m;

    final updated = config.copyWith(
      title: titleCtrl.text.trim().isEmpty ? config.title : titleCtrl.text.trim(),
      offsetMin: finalOffset,
    );

    if (widget.isCustom) {
      final list = app.customReminders;
      final idx = list.indexWhere((r) => r.id == widget.configId);
      if (idx >= 0) {
        final newList = List<ReminderConfig>.from(list);
        newList[idx] = updated;
        app.saveReminders(newList);
      }
    } else {
      app.saveReminderConfig(updated);
    }
    syncNotifications(app, schedule);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final brightness = Theme.of(context).brightness;
    final c = brightness == Brightness.light ? JColors.light : JColors.dark;
    final prayers = kz ? _prayersKz : _prayersRu;

    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: JType.ui(12, color: c.faint, w: FontWeight.w700)),
              const SizedBox(height: 8),
              child,
            ],
          ),
        );

    final showTitleField = widget.isCustom;
    // Блокируем смену намаза для суры Аль-Кахф и Часа Дуа, так как они имеют жесткую привязку к Джума (Dhuhr/Maghrib)
    final disablePrayerSelection = widget.configId == 'kahf' || widget.configId == 'dua';

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        elevation: 0,
        title: Text(config.title, style: JType.ui(17, w: FontWeight.w700, color: c.ink)),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              _save();
              Navigator.of(context).pop();
            },
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 10, bottom: 40),
        children: [
          // Включено / Выключено
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    kz ? 'Хабарландыру қосулы' : 'Напоминание включено',
                    style: JType.ui(15, color: c.ink, w: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: config.enabled,
                  activeTrackColor: c.gold.withValues(alpha: .5),
                  thumbColor: WidgetStatePropertyAll(config.enabled ? c.gold : c.faint),
                  onChanged: (v) {
                    setState(() {
                      config = config.copyWith(enabled: v);
                    });
                    _save();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 24, thickness: 0.5),

          // Название (только для кастомных)
          if (showTitleField) ...[
            section(
              kz ? 'АТАУЫ' : 'НАЗВАНИЕ',
              TextField(
                controller: titleCtrl,
                style: JType.ui(15, color: c.ink),
                cursorColor: c.gold,
                decoration: InputDecoration(
                  hintText: kz ? 'Атауы' : 'Название',
                  hintStyle: JType.ui(14, color: c.faint),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.hair)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.gold)),
                ),
                onChanged: (v) => _save(),
              ),
            ),
            const Divider(height: 24, thickness: 0.5),
          ],

          // Привязка к намазу
          section(
            kz ? 'НАМАЗҒА ПРИВЯЗКА' : 'ПРИВЯЗКА К СОБЫТИЮ',
            disablePrayerSelection
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      prayers[config.prayer],
                      style: JType.ui(15, color: c.ink, w: FontWeight.w500),
                    ),
                  )
                : DropdownButton<int>(
                    value: config.prayer,
                    isExpanded: true,
                    dropdownColor: brightness == Brightness.light ? Colors.white : c.card,
                    style: JType.ui(15, color: c.ink),
                    underline: Container(height: 1, color: c.hair),
                    items: [
                      for (var i = 0; i < prayers.length; i++)
                        DropdownMenuItem(value: i, child: Text(prayers[i])),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          config = config.copyWith(prayer: v);
                        });
                        _save();
                      }
                    },
                  ),
          ),
          const Divider(height: 24, thickness: 0.5),

          // Коррекция / Смещение в минутах
          section(
            kz ? 'УАҚЫТТЫ ТҮЗЕТУ (МИНУТ)' : 'КОРРЕКЦИЯ ВРЕМЕНИ (МИНУТ)',
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: c.gold,
                      selectedForegroundColor: c.bg,
                    ),
                    segments: [
                      ButtonSegment(value: true, label: Text(kz ? 'дейін' : 'до')),
                      ButtonSegment(value: false, label: Text(kz ? 'кейін' : 'после')),
                    ],
                    selected: {before},
                    onSelectionChanged: (s) {
                      setState(() {
                        before = s.first;
                      });
                      _save();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: offsetCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: JType.ui(15, color: c.ink),
                    cursorColor: c.gold,
                    decoration: InputDecoration(
                      suffixText: kz ? 'мин' : 'мин',
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.hair)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.gold)),
                    ),
                    onChanged: (v) => _save(),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24, thickness: 0.5),

          // Повторение
          section(
            kz ? 'ҚАЙТАЛАУ' : 'ПОВТОРЕНИЕ',
            DropdownButton<String>(
              value: config.repeat,
              isExpanded: true,
              dropdownColor: brightness == Brightness.light ? Colors.white : c.card,
              style: JType.ui(15, color: c.ink),
              underline: Container(height: 1, color: c.hair),
              items: [
                DropdownMenuItem(
                  value: 'daily',
                  child: Text(kz ? 'Күн сайын' : 'Каждый день'),
                ),
                DropdownMenuItem(
                  value: 'weekly',
                  child: Text(kz ? 'Каждую неделю' : 'Каждую неделю'),
                ),
                DropdownMenuItem(
                  value: 'monthly',
                  child: Text(kz ? 'Каждый месяц' : 'Каждый месяц'),
                ),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    config = config.copyWith(repeat: v);
                  });
                  _save();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
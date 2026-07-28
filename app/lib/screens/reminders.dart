import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_state.dart';
import '../notifications/notifications.dart';
import '../prayer/schedule_service.dart';
import '../services/alarm_service.dart';
import '../theme/tokens.dart';
import 'settings_shell.dart';

const _prayerIds = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];
const _prayersRu = ['Фаджр', 'Восход', 'Зухр', 'Аср', 'Магриб', 'Иша'];
const _prayersKz = ['Таң', 'Күн шығуы', 'Бесін', 'Екінті', 'Ақшам', 'Құптан'];

List<String> _prayers(bool kz) => kz ? _prayersKz : _prayersRu;

String _repeatLabel(bool kz, String repeat) => switch (repeat) {
  'weekly' => kz ? 'Әр аптада' : 'Каждую неделю',
  'monthly' => kz ? 'Әр айда' : 'Каждый месяц',
  _ => kz ? 'Күн сайын' : 'Каждый день',
};

String _offsetLabel(bool kz, int offset) {
  if (offset == 0) return kz ? 'Дәл уақытында' : 'В момент события';
  final minutes = offset.abs();
  if (offset < 0) {
    return kz ? '$minutes мин бұрын' : 'За $minutes мин до';
  }
  return kz ? '$minutes мин кейін' : 'Через $minutes мин после';
}

String _configLabel(bool kz, ReminderConfig config) {
  if (!config.enabled) return kz ? 'Өшірулі' : 'Выключено';
  return '${_offsetLabel(kz, config.offsetMin)} · ${_repeatLabel(kz, config.repeat)}';
}

/// Корневой центр напоминаний. Вся дальнейшая навигация происходит внутри
/// одной модальной панели через CupertinoPageRoute.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  static Future<void> open(
    BuildContext context, {
    String? initialConfigId,
    bool isCustom = false,
  }) => DauamSettingsSheet.open<void>(
    context,
    heightFactor: initialConfigId == null ? .93 : .72,
    builder: (_) => initialConfigId == null
        ? const RemindersScreen()
        : ReminderDetailScreen(
            configId: initialConfigId,
            isCustom: isCustom,
            root: true,
          ),
  );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    return DauamSettingsPage(
      root: true,
      title: kz ? 'Еске салулар' : 'Напоминания',
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 30),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 3, 26, 14),
              child: Text(
                kz
                    ? 'Намазға және ғибадатқа қатысты барлық хабарландырулар'
                    : 'Все уведомления о молитвах и поклонении — в одном месте',
                style: JType.ui(
                  13.5,
                  color: dauamSettingsPalette(context).colors.sub,
                  h: 1.4,
                ),
              ),
            ),
            DauamSection(
              children: [
                DauamSettingsRow(
                  icon: CupertinoIcons.clock,
                  title: kz ? 'Намаз уақыттары' : 'Времена молитв',
                  subtitle: kz
                      ? '6 уақыт · әрқайсысы бөлек бапталады'
                      : '6 времён · каждое настраивается отдельно',
                  onTap: () => Navigator.of(
                    context,
                  ).push(dauamSettingsRoute(const PrayerRemindersScreen())),
                ),
                DauamSettingsRow(
                  icon: CupertinoIcons.book,
                  title: kz ? 'Зікірлер мен дұғалар' : 'Зикры и дуа',
                  subtitle: kz
                      ? 'Таң, кеш, Кәһф сүресі және жұма дұғасы'
                      : 'Утро, вечер, сура аль-Кахф и дуа пятницы',
                  onTap: () => Navigator.of(
                    context,
                  ).push(dauamSettingsRoute(const WorshipRemindersScreen())),
                ),
                DauamSettingsRow(
                  icon: CupertinoIcons.list_bullet,
                  title: kz ? 'Менің еске салуларым' : 'Мои напоминания',
                  subtitle: kz
                      ? '${app.customReminders.length} қосылды'
                      : 'Добавлено: ${app.customReminders.length}',
                  onTap: () => Navigator.of(
                    context,
                  ).push(dauamSettingsRoute(const CustomRemindersScreen())),
                ),
              ],
            ),
            DauamSection(
              label: kz ? 'ЖЫЛДАМ ӘРЕКЕТ' : 'БЫСТРОЕ ДЕЙСТВИЕ',
              children: [
                DauamSettingsRow(
                  icon: CupertinoIcons.add,
                  title: kz ? 'Еске салу қосу' : 'Добавить напоминание',
                  subtitle: kz
                      ? 'Намаз уақытына байланыстыру'
                      : 'Привязать к одному из времён молитвы',
                  onTap: () => Navigator.of(
                    context,
                  ).push(dauamSettingsRoute(const ReminderEditorScreen())),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PrayerRemindersScreen extends StatelessWidget {
  const PrayerRemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final prayers = _prayers(kz);
    return DauamSettingsPage(
      title: kz ? 'Намаз уақыттары' : 'Времена молитв',
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            DauamSection(
              footer: kz
                  ? 'Күн шығуы намаз емес, бірақ уақыт белгісі ретінде бапталады.'
                  : 'Восход — не молитва, но остаётся настраиваемой временной точкой.',
              children: [
                for (var i = 0; i < _prayerIds.length; i++)
                  DauamSettingsRow(
                    title: prayers[i],
                    subtitle: _configLabel(
                      kz,
                      app.getReminderConfig(_prayerIds[i], app.lang),
                    ),
                    value:
                        app.getReminderConfig(_prayerIds[i], app.lang).enabled
                        ? (kz ? 'Қосулы' : 'Вкл.')
                        : null,
                    onTap: () => Navigator.of(context).push(
                      dauamSettingsRoute(
                        ReminderDetailScreen(configId: _prayerIds[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class WorshipRemindersScreen extends StatelessWidget {
  const WorshipRemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final items = [
      ('morning', kz ? 'Таңғы зікірлер' : 'Утренние зикры'),
      ('evening', kz ? 'Кешкі зікірлер' : 'Вечерние зикры'),
      ('kahf', kz ? '«әл-Кәһф» сүресі' : 'Сура аль-Кахф'),
      ('dua', kz ? 'Жұма күнгі дұға сағаты' : 'Час дуа в пятницу'),
    ];
    return DauamSettingsPage(
      title: kz ? 'Зікірлер мен дұғалар' : 'Зикры и дуа',
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            DauamSection(
              children: [
                for (final item in items)
                  DauamSettingsRow(
                    title: item.$2,
                    subtitle: _configLabel(
                      kz,
                      app.getReminderConfig(item.$1, app.lang),
                    ),
                    onTap: () => Navigator.of(context).push(
                      dauamSettingsRoute(
                        ReminderDetailScreen(configId: item.$1),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CustomRemindersScreen extends StatelessWidget {
  const CustomRemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final c = dauamSettingsPalette(context).colors;
    final accent = dauamSettingsAccent(context);
    return DauamSettingsPage(
      title: kz ? 'Менің еске салуларым' : 'Мои напоминания',
      trailing: DauamRoundButton(
        icon: CupertinoIcons.add,
        semanticLabel: kz ? 'Қосу' : 'Добавить',
        onTap: () => Navigator.of(
          context,
        ).push(dauamSettingsRoute(const ReminderEditorScreen())),
      ),
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final reminders = app.customReminders;
          if (reminders.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 38),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(CupertinoIcons.bell, color: accent, size: 28),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      kz ? 'Еске салулар жоқ' : 'Пока пусто',
                      style: JType.ui(20, w: FontWeight.w700, color: c.ink),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kz
                          ? 'Намаз уақытына байланысты жеке еске салу қосыңыз.'
                          : 'Создайте личное напоминание и привяжите его ко времени молитвы.',
                      textAlign: TextAlign.center,
                      style: JType.ui(13.5, color: c.sub, h: 1.45),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: 260,
                      child: DauamPrimaryButton(
                        label: kz ? 'Қосу' : 'Добавить',
                        onTap: () => Navigator.of(context).push(
                          dauamSettingsRoute(const ReminderEditorScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              DauamSection(
                footer: kz
                    ? 'Жою үшін еске салуды ашыңыз.'
                    : 'Удалить напоминание можно внутри его настроек.',
                children: [
                  for (final reminder in reminders)
                    DauamSettingsRow(
                      title: reminder.title,
                      subtitle: _configLabel(kz, reminder),
                      onTap: () => Navigator.of(context).push(
                        dauamSettingsRoute(
                          ReminderDetailScreen(
                            configId: reminder.id,
                            isCustom: true,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Создание напоминания — самостоятельная страница внутри текущей панели,
/// а не ещё один bottom sheet.
class ReminderEditorScreen extends StatefulWidget {
  const ReminderEditorScreen({super.key});

  @override
  State<ReminderEditorScreen> createState() => _ReminderEditorScreenState();
}

class _ReminderEditorScreenState extends State<ReminderEditorScreen> {
  final _title = TextEditingController();
  int _prayer = 0;
  int _offset = -15;
  String _repeat = 'daily';
  int _weekday = DateTime.friday;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _selectPrayer() async {
    final result = await Navigator.of(
      context,
    ).push<int>(dauamSettingsRoute(PrayerChoiceScreen(selected: _prayer)));
    if (mounted && result != null) setState(() => _prayer = result);
  }

  Future<void> _selectOffset() async {
    final result = await Navigator.of(
      context,
    ).push<int>(dauamSettingsRoute(OffsetChoiceScreen(offset: _offset)));
    if (mounted && result != null) setState(() => _offset = result);
  }

  Future<void> _selectRepeat() async {
    final result = await Navigator.of(
      context,
    ).push<String>(dauamSettingsRoute(RepeatChoiceScreen(selected: _repeat)));
    if (mounted && result != null) setState(() => _repeat = result);
  }

  void _add() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final app = AppScope.of(context);
    final schedule = ScheduleScope.of(context);
    app.addReminder(
      ReminderConfig(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        prayer: _prayer,
        offsetMin: _offset,
        repeat: _repeat,
        weekday: _weekday,
      ),
    );
    syncNotifications(app, schedule);
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final c = dauamSettingsPalette(context).colors;
    final accent = dauamSettingsAccent(context);
    final prayers = _prayers(kz);
    return DauamSettingsPage(
      title: kz ? 'Жаңа еске салу' : 'Новое напоминание',
      trailing: DauamTextAction(
        label: kz ? 'Қосу' : 'Добавить',
        enabled: _title.text.trim().isNotEmpty,
        onTap: _add,
      ),
      bottom: DauamPrimaryButton(
        label: kz ? 'Еске салуды қосу' : 'Добавить напоминание',
        enabled: _title.text.trim().isNotEmpty,
        onTap: _add,
      ),
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          DauamSection(
            label: kz ? 'АТАУЫ' : 'НАЗВАНИЕ',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: TextField(
                  controller: _title,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  cursorColor: accent,
                  style: JType.ui(16, color: c.ink),
                  decoration: InputDecoration(
                    hintText: kz ? 'Мысалы: Дұға' : 'Например: Дуа',
                    hintStyle: JType.ui(15, color: c.faint),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          DauamSection(
            label: kz ? 'КЕСТЕ' : 'РАСПИСАНИЕ',
            children: [
              DauamSettingsRow(
                title: kz ? 'Намазға байлау' : 'Привязка к событию',
                value: prayers[_prayer],
                onTap: _selectPrayer,
              ),
              DauamSettingsRow(
                title: kz ? 'Қашан еске салу' : 'Когда напомнить',
                value: _offsetLabel(kz, _offset),
                onTap: _selectOffset,
              ),
              DauamSettingsRow(
                title: kz ? 'Қайталау' : 'Повторение',
                value: _repeatLabel(kz, _repeat),
                onTap: _selectRepeat,
              ),
              if (_repeat == 'weekly')
                DauamSettingsRow(
                  title: kz ? 'Апта күні' : 'День недели',
                  value: _weekdayLabel(kz, _weekday),
                  onTap: () async {
                    final result = await Navigator.of(context).push<int>(
                      dauamSettingsRoute(
                        WeekdayChoiceScreen(selected: _weekday),
                      ),
                    );
                    if (mounted && result != null) {
                      setState(() => _weekday = result);
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ReminderDetailScreen extends StatefulWidget {
  const ReminderDetailScreen({
    super.key,
    required this.configId,
    this.isCustom = false,
    this.root = false,
  });

  final String configId;
  final bool isCustom;
  final bool root;

  @override
  State<ReminderDetailScreen> createState() => _ReminderDetailScreenState();
}

class _ReminderDetailScreenState extends State<ReminderDetailScreen> {
  ReminderConfig? _config;
  TextEditingController? _title;
  String? _activeConfigId;

  bool get _isPrayerPreset =>
      !widget.isCustom && _prayerIds.contains(_activeConfigId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_config != null) return;
    _loadConfig(widget.configId);
  }

  void _loadConfig(String id) {
    final app = AppScope.of(context);
    _activeConfigId = id;
    _config = widget.isCustom
        ? app.customReminders.firstWhere((r) => r.id == id)
        : app.getReminderConfig(id, app.lang);
    _title?.dispose();
    _title = TextEditingController(text: _config!.title);
  }

  void _movePrayer(int delta) {
    final current = _prayerIds.indexOf(_activeConfigId!);
    if (current < 0) return;
    final next = (current + delta).clamp(0, _prayerIds.length - 1);
    if (next == current) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _loadConfig(_prayerIds[next]));
  }

  void _stepOffset(int delta) {
    final config = _config!;
    final next = (config.offsetMin + delta).clamp(-120, 120);
    if (next == config.offsetMin) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.selectionClick();
    _persist(config.copyWith(offsetMin: next));
  }

  @override
  void dispose() {
    _title?.dispose();
    super.dispose();
  }

  void _persist(ReminderConfig updated) {
    final app = AppScope.of(context);
    final schedule = ScheduleScope.of(context);
    setState(() => _config = updated);
    if (widget.isCustom) {
      app.saveReminders([
        for (final item in app.customReminders)
          if (item.id == updated.id) updated else item,
      ]);
    } else {
      app.saveReminderConfig(updated);
    }
    syncNotifications(app, schedule);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final c = dauamSettingsPalette(context).colors;
    final accent = dauamSettingsAccent(context);
    final config = _config!;
    final prayers = _prayers(kz);

    return DauamSettingsPage(
      root: widget.root,
      title: config.title,
      trailing: widget.isCustom
          ? DauamTextAction(
              label: kz ? 'Дайын' : 'Готово',
              onTap: () {
                final title = _title!.text.trim();
                if (title.isNotEmpty) _persist(config.copyWith(title: title));
                Navigator.of(context).pop();
              },
            )
          : _isPrayerPreset
          ? _PrayerPagerControls(
              canGoBack: _prayerIds.indexOf(_activeConfigId!) > 0,
              canGoForward:
                  _prayerIds.indexOf(_activeConfigId!) < _prayerIds.length - 1,
              onBack: () => _movePrayer(-1),
              onForward: () => _movePrayer(1),
            )
          : null,
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 30),
        children: [
          DauamSection(
            children: [
              DauamSwitchRow(
                icon: CupertinoIcons.bell,
                title: kz ? 'Хабарландырулар' : 'Уведомления',
                subtitle: config.enabled
                    ? (kz ? 'Қосулы' : 'Включены')
                    : (kz ? 'Өшірулі' : 'Выключены'),
                value: config.enabled,
                onChanged: (value) => _persist(config.copyWith(enabled: value)),
              ),
              if (!widget.isCustom && config.enabled)
                _InlineOffsetStepper(
                  offset: config.offsetMin,
                  kz: kz,
                  onMinus: () => _stepOffset(-5),
                  onPlus: () => _stepOffset(5),
                  onReset: config.offsetMin == 0
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          _persist(config.copyWith(offsetMin: 0));
                        },
                ),
            ],
          ),
          if (_activeConfigId == 'fajr')
            DauamSection(
              label: kz ? 'ОЯТУ БУДИЛЬНИГІ' : 'БУДИЛЬНИК ДЛЯ ПРОБУЖДЕНИЯ',
              footer: kz
                  ? 'Таң намазына ояну үшін жүйелік будильник қосылады.'
                  : 'Системный будильник iOS сработает даже в режиме «Не беспокоить».',
              children: [
                DauamSwitchRow(
                  icon: CupertinoIcons.alarm,
                  title: kz ? 'Будильник' : 'Будильник',
                  subtitle: app.fajrAlarmEnabled
                      ? (kz ? 'Қосулы' : 'Включен')
                      : (kz ? 'Өшірулі' : 'Выключен'),
                  value: app.fajrAlarmEnabled,
                  onChanged: (val) {
                    app.fajrAlarmEnabled = val;
                    AlarmService.sync(app, ScheduleScope.of(context));
                    HapticFeedback.selectionClick();
                  },
                ),
                if (app.fajrAlarmEnabled) ...[
                  _InlineOffsetStepper(
                    offset: app.fajrAlarmOffsetMinutes,
                    kz: kz,
                    onMinus: () {
                      final next = (app.fajrAlarmOffsetMinutes - 5).clamp(-60, 30);
                      if (next != app.fajrAlarmOffsetMinutes) {
                        app.fajrAlarmOffsetMinutes = next;
                        AlarmService.sync(app, ScheduleScope.of(context));
                        HapticFeedback.selectionClick();
                      }
                    },
                    onPlus: () {
                      final next = (app.fajrAlarmOffsetMinutes + 5).clamp(-60, 30);
                      if (next != app.fajrAlarmOffsetMinutes) {
                        app.fajrAlarmOffsetMinutes = next;
                        AlarmService.sync(app, ScheduleScope.of(context));
                        HapticFeedback.selectionClick();
                      }
                    },
                    onReset: app.fajrAlarmOffsetMinutes == -15
                        ? null
                        : () {
                            app.fajrAlarmOffsetMinutes = -15;
                            AlarmService.sync(app, ScheduleScope.of(context));
                            HapticFeedback.selectionClick();
                          },
                  ),
                  DauamSettingsRow(
                    icon: CupertinoIcons.play_circle_fill,
                    title: kz ? 'Будильникті тексеру (10 с)' : 'Проверить будильник (10 сек)',
                    subtitle: kz
                        ? '10 секундтан кейін дабыл соғады. Енді экранды бұғаттаңыз.'
                        : 'Будильник сработает через 10 секунд. Заблокируйте экран для проверки.',
                    onTap: () async {
                      HapticFeedback.mediumImpact();
                      final test = await AlarmService.testAlarm(
                        seconds: 10,
                        title: kz ? 'Таң намазы (Тест)' : 'Фаджр (Тест)',
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              test.success
                                  ? (kz
                                        ? 'Жүйелік будильник 10 секундтан кейін соғады. Экранды бұғаттаңыз.'
                                        : 'Системный будильник сработает через 10 секунд. Заблокируйте экран.')
                                  : _alarmErrorText(kz, test),
                            ),
                            duration: Duration(
                              seconds: test.success ? 4 : 7,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          if (widget.isCustom) ...[
            DauamSection(
              label: kz ? 'АТАУЫ' : 'НАЗВАНИЕ',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  child: TextField(
                    controller: _title,
                    cursorColor: accent,
                    style: JType.ui(16, color: c.ink),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: kz ? 'Атауы' : 'Название',
                      hintStyle: JType.ui(15, color: c.faint),
                    ),
                  ),
                ),
              ],
            ),
            DauamSection(
              label: kz ? 'КЕСТЕ' : 'РАСПИСАНИЕ',
              children: [
                DauamSettingsRow(
                  title: kz ? 'Оқиға' : 'Событие',
                  value: prayers[config.prayer],
                  onTap: () async {
                    final result = await Navigator.of(context).push<int>(
                      dauamSettingsRoute(
                        PrayerChoiceScreen(selected: config.prayer),
                      ),
                    );
                    if (mounted && result != null) {
                      _persist(config.copyWith(prayer: result));
                    }
                  },
                ),
                DauamSettingsRow(
                  title: kz ? 'Қашан еске салу' : 'Когда напомнить',
                  value: _offsetLabel(kz, config.offsetMin),
                  onTap: () async {
                    final result = await Navigator.of(context).push<int>(
                      dauamSettingsRoute(
                        OffsetChoiceScreen(offset: config.offsetMin),
                      ),
                    );
                    if (mounted && result != null) {
                      _persist(config.copyWith(offsetMin: result));
                    }
                  },
                ),
                DauamSettingsRow(
                  title: kz ? 'Қайталау' : 'Повторение',
                  value: _repeatLabel(kz, config.repeat),
                  onTap: () async {
                    final result = await Navigator.of(context).push<String>(
                      dauamSettingsRoute(
                        RepeatChoiceScreen(selected: config.repeat),
                      ),
                    );
                    if (mounted && result != null) {
                      _persist(config.copyWith(repeat: result));
                    }
                  },
                ),
                if (config.repeat == 'weekly')
                  DauamSettingsRow(
                    title: kz ? 'Апта күні' : 'День недели',
                    value: _weekdayLabel(kz, config.weekday),
                    onTap: () async {
                      final result = await Navigator.of(context).push<int>(
                        dauamSettingsRoute(
                          WeekdayChoiceScreen(selected: config.weekday),
                        ),
                      );
                      if (mounted && result != null) {
                        _persist(config.copyWith(weekday: result));
                      }
                    },
                  ),
              ],
            ),
          ],
          if (widget.isCustom)
            DauamSection(
              children: [
                DauamSettingsRow(
                  title: kz ? 'Еске салуды жою' : 'Удалить напоминание',
                  icon: CupertinoIcons.trash,
                  destructive: true,
                  onTap: () {
                    app.removeReminder(config.id);
                    syncNotifications(app, ScheduleScope.of(context));
                    HapticFeedback.heavyImpact();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String _alarmErrorText(bool kz, AlarmOperationResult result) {
  switch (result.errorCode) {
    case 'ALARM_PERMISSION_DENIED':
      return kz
          ? 'Dauam үшін жүйелік будильниктерге рұқсат беріңіз.'
          : 'Разрешите системные будильники для Dauam в настройках iPhone.';
    case 'ALARMKIT_UNAVAILABLE':
      return kz
          ? 'Жүйелік будильник үшін iOS 26 немесе жаңарақ нұсқа қажет.'
          : 'Для системного будильника требуется iOS 26 или новее.';
    default:
      return kz
          ? 'Будильникті орнату мүмкін болмады: ${result.message ?? 'белгісіз қате'}'
          : 'Не удалось поставить будильник: ${result.message ?? 'неизвестная ошибка'}';
  }
}

class _PrayerPagerControls extends StatelessWidget {
  const _PrayerPagerControls({
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
  });

  final bool canGoBack, canGoForward;
  final VoidCallback onBack, onForward;

  @override
  Widget build(BuildContext context) {
    final p = dauamSettingsPalette(context);
    final c = p.colors;
    final accent = dauamSettingsAccent(context);

    Widget button({
      required IconData icon,
      required bool enabled,
      required VoidCallback onTap,
      required String label,
    }) => Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: c.ink.withValues(alpha: enabled ? .055 : .025),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: 18,
              color: enabled ? accent : c.faint.withValues(alpha: .32),
            ),
          ),
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          icon: CupertinoIcons.chevron_left,
          enabled: canGoBack,
          onTap: onBack,
          label: 'Предыдущее время',
        ),
        const SizedBox(width: 5),
        button(
          icon: CupertinoIcons.chevron_right,
          enabled: canGoForward,
          onTap: onForward,
          label: 'Следующее время',
        ),
      ],
    );
  }
}

class _InlineOffsetStepper extends StatelessWidget {
  const _InlineOffsetStepper({
    required this.offset,
    required this.kz,
    required this.onMinus,
    required this.onPlus,
    this.onReset,
  });

  final int offset;
  final bool kz;
  final VoidCallback onMinus, onPlus;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final c = dauamSettingsPalette(context).colors;
    final accent = dauamSettingsAccent(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  kz ? 'Қашан еске салу' : 'Когда напомнить',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JType.ui(15, w: FontWeight.w600, color: c.ink),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    _offsetLabel(kz, offset),
                    key: ValueKey(offset),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: JType.ui(13, w: FontWeight.w600, color: accent),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              _OffsetStepButton(
                icon: CupertinoIcons.minus,
                enabled: offset > -120,
                onTap: onMinus,
              ),
              Expanded(
                child: Column(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Text(
                        offset == 0 ? '0' : '${offset.abs()}',
                        key: ValueKey(offset),
                        style: JType.ui(
                          30,
                          w: FontWeight.w600,
                          color: accent,
                          ls: -.8,
                        ),
                      ),
                    ),
                    Text(
                      kz ? '5 минут қадам' : 'шаг 5 минут',
                      style: JType.ui(10.5, color: c.faint),
                    ),
                  ],
                ),
              ),
              _OffsetStepButton(
                icon: CupertinoIcons.plus,
                enabled: offset < 120,
                onTap: onPlus,
              ),
            ],
          ),
          if (onReset != null) ...[
            const SizedBox(height: 7),
            DauamTextAction(
              label: kz ? 'Дәл уақытында' : 'Вернуть «в момент»',
              onTap: onReset!,
            ),
          ],
        ],
      ),
    );
  }
}

class PrayerChoiceScreen extends StatelessWidget {
  const PrayerChoiceScreen({super.key, required this.selected});
  final int selected;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final prayers = _prayers(kz);
    return DauamSettingsPage(
      title: kz ? 'Оқиғаны таңдаңыз' : 'Выберите событие',
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          DauamSection(
            children: [
              for (var i = 0; i < prayers.length; i++)
                DauamChoiceRow(
                  title: prayers[i],
                  subtitle: i == 1 && !kz
                      ? 'Временная точка, не молитва'
                      : null,
                  selected: selected == i,
                  onTap: () => Navigator.of(context).pop(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class OffsetChoiceScreen extends StatefulWidget {
  const OffsetChoiceScreen({super.key, required this.offset});
  final int offset;

  @override
  State<OffsetChoiceScreen> createState() => _OffsetChoiceScreenState();
}

class _OffsetChoiceScreenState extends State<OffsetChoiceScreen> {
  late int _result = (((widget.offset / 5).round() * 5).clamp(-120, 120));

  void _step(int delta) {
    final next = (_result + delta).clamp(-120, 120);
    if (next == _result) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _result = next);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final p = dauamSettingsPalette(context);
    final c = p.colors;
    final accent = dauamSettingsAccent(context);
    return DauamSettingsPage(
      title: kz ? 'Еске салу уақыты' : 'Когда напомнить',
      trailing: DauamTextAction(
        label: kz ? 'Дайын' : 'Готово',
        onTap: () => Navigator.of(context).pop(_result),
      ),
      child: ListView(
        padding: const EdgeInsets.only(top: 28, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Column(
              children: [
                Text(
                  kz ? 'ОҚИҒАҒА ҚАТЫСТЫ' : 'ОТНОСИТЕЛЬНО СОБЫТИЯ',
                  style: JType.caption(c.faint, size: 10.5),
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween(begin: .97, end: 1.0).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    _offsetLabel(kz, _result),
                    key: ValueKey(_result),
                    textAlign: TextAlign.center,
                    style: JType.ui(
                      23,
                      w: FontWeight.w700,
                      color: c.ink,
                      ls: -.3,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  kz ? '− бұрын · + кейін' : '− раньше · + позже',
                  style: JType.ui(12.5, color: c.sub),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          DauamSection(
            label: kz ? '5 МИНУТТЫҚ ҚАДАМ' : 'ШАГ 5 МИНУТ',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                child: Row(
                  children: [
                    _OffsetStepButton(
                      icon: CupertinoIcons.minus,
                      enabled: _result > -120,
                      onTap: () => _step(-5),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            _result == 0 ? '0' : '${_result.abs()}',
                            style: JType.ui(
                              36,
                              w: FontWeight.w600,
                              color: accent,
                              ls: -1,
                            ),
                          ),
                          Text(
                            kz ? 'минут' : 'минут',
                            style: JType.ui(12.5, color: c.sub),
                          ),
                        ],
                      ),
                    ),
                    _OffsetStepButton(
                      icon: CupertinoIcons.plus,
                      enabled: _result < 120,
                      onTap: () => _step(5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_result != 0)
            Center(
              child: DauamTextAction(
                label: kz ? 'Дәл уақытында' : 'В момент события',
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _result = 0);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _OffsetStepButton extends StatelessWidget {
  const _OffsetStepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = dauamSettingsPalette(context);
    final c = p.colors;
    final accent = dauamSettingsAccent(context);
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: enabled
            ? accent.withValues(alpha: p.isLight ? .11 : .16)
            : c.ink.withValues(alpha: .035),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 58,
            height: 58,
            child: Icon(
              icon,
              size: 24,
              color: enabled ? accent : c.faint.withValues(alpha: .45),
            ),
          ),
        ),
      ),
    );
  }
}

class RepeatChoiceScreen extends StatelessWidget {
  const RepeatChoiceScreen({super.key, required this.selected});
  final String selected;

  @override
  Widget build(BuildContext context) {
    final kz = AppScope.of(context).lang == 'kz';
    const values = ['daily', 'weekly', 'monthly'];
    return DauamSettingsPage(
      title: kz ? 'Қайталау' : 'Повторение',
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          DauamSection(
            children: [
              for (final value in values)
                DauamChoiceRow(
                  title: _repeatLabel(kz, value),
                  selected: selected == value,
                  onTap: () => Navigator.of(context).pop(value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _weekdayLabel(bool kz, int day) {
  const ru = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];
  const kk = [
    'Дүйсенбі',
    'Сейсенбі',
    'Сәрсенбі',
    'Бейсенбі',
    'Жұма',
    'Сенбі',
    'Жексенбі',
  ];
  return (kz ? kk : ru)[day.clamp(1, 7) - 1];
}

class WeekdayChoiceScreen extends StatelessWidget {
  const WeekdayChoiceScreen({super.key, required this.selected});
  final int selected;

  @override
  Widget build(BuildContext context) {
    final kz = AppScope.of(context).lang == 'kz';
    return DauamSettingsPage(
      title: kz ? 'Апта күні' : 'День недели',
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          DauamSection(
            children: [
              for (var day = 1; day <= 7; day++)
                DauamChoiceRow(
                  title: _weekdayLabel(kz, day),
                  selected: selected == day,
                  onTap: () => Navigator.of(context).pop(day),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

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
const _alarmPrayerIds = _prayerIds;
const _prayersRu = ['Фаджр', 'Восход', 'Зухр', 'Аср', 'Магриб', 'Иша'];
const _prayersKz = ['Таң', 'Күн шығуы', 'Бесін', 'Екінті', 'Ақшам', 'Құптан'];

List<String> _prayers(bool kz) => kz ? _prayersKz : _prayersRu;

String _repeatLabel(bool kz, String repeat) => switch (repeat) {
  'once' => kz ? 'Бір рет' : 'Без повторения',
  'weekly' => kz ? 'Апта күндері' : 'По дням недели',
  'monthly' => kz ? 'Әр айда' : 'Каждый месяц',
  'yearly' => kz ? 'Жыл сайын' : 'Каждый год',
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
  final repeat = config.repeat == 'weekly'
      ? _weekdaysLabel(kz, config.effectiveWeekdays)
      : _repeatLabel(kz, config.repeat);
  if (!config.isPrayerLinked) {
    final time = _clockLabel(config.fixedHour, config.fixedMinute);
    return '$time · $repeat';
  }
  return '${_offsetLabel(kz, config.offsetMin)} · $repeat';
}

String _clockLabel(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

String _weekdaysLabel(bool kz, Iterable<int> days) {
  const ru = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  const kk = ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сб', 'Жс'];
  final names = kz ? kk : ru;
  final sorted = days.toSet().where((day) => day >= 1 && day <= 7).toList()
    ..sort();
  return sorted.map((day) => names[day - 1]).join(', ');
}

String _scheduleDateLabel(bool kz, DateTime date, String repeat) {
  const ruMonths = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  const kkMonths = [
    'қаңтар',
    'ақпан',
    'наурыз',
    'сәуір',
    'мамыр',
    'маусым',
    'шілде',
    'тамыз',
    'қыркүйек',
    'қазан',
    'қараша',
    'желтоқсан',
  ];
  if (repeat == 'monthly') {
    return kz ? 'Айдың ${date.day}-күні' : '${date.day}-е число';
  }
  final month = (kz ? kkMonths : ruMonths)[date.month - 1];
  return repeat == 'once'
      ? '${date.day} $month ${date.year}'
      : '${date.day} $month';
}

DateTime _scheduleDateFor(ReminderConfig config) => config.scheduleYear > 0
    ? DateTime(config.scheduleYear, config.scheduleMonth, config.scheduleDay)
    : DateUtils.dateOnly(DateTime.now());

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
    builder: (sheetContext) {
      if (initialConfigId != null) {
        return ReminderDetailScreen(
          configId: initialConfigId,
          isCustom: isCustom,
          root: true,
        );
      }
      final app = AppScope.of(sheetContext);
      return app.remindersGuideSeen
          ? const RemindersScreen()
          : const ReminderGuideScreen(root: true);
    },
  );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    return DauamSettingsPage(
      root: true,
      title: kz ? 'Еске салулар' : 'Напоминания',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DauamRoundButton(
            icon: CupertinoIcons.question,
            semanticLabel: kz ? 'Нұсқаулық' : 'Как это работает',
            onTap: () => Navigator.of(
              context,
            ).push(dauamSettingsRoute(const ReminderGuideScreen(replay: true))),
          ),
        ],
      ),
      bottom: SizedBox(
        width: double.infinity,
        child: DauamPrimaryButton(
          label: kz ? 'Еске салу қосу' : 'Добавить напоминание',
          onTap: () => Navigator.of(
            context,
          ).push(dauamSettingsRoute(const ReminderEditorScreen())),
        ),
      ),
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 30),
          children: [
            DauamSection(
              label: kz ? 'ДАЙЫН' : 'ГОТОВЫЕ',
              children: [
                DauamSettingsRow(
                  icon: CupertinoIcons.clock,
                  title: kz ? 'Намаз уақыттары' : 'Времена молитв',
                  trailing: _ReminderCount(
                    value: '${_enabledCount(app, _prayerIds)}/6',
                  ),
                  onTap: () => Navigator.of(
                    context,
                  ).push(dauamSettingsRoute(const PrayerRemindersScreen())),
                ),
                DauamSettingsRow(
                  icon: CupertinoIcons.book,
                  title: kz ? 'Зікірлер мен жұма' : 'Зикры и пятница',
                  trailing: _ReminderCount(
                    value:
                        '${_enabledCount(app, const ['morning', 'evening', 'kahf', 'dua'])}/4',
                  ),
                  onTap: () => Navigator.of(
                    context,
                  ).push(dauamSettingsRoute(const WorshipRemindersScreen())),
                ),
              ],
            ),
            if (app.customReminders.isNotEmpty)
              DauamSection(
                label: kz ? 'ЖЕКЕ' : 'ЛИЧНЫЕ',
                children: [
                  for (final reminder in app.customReminders)
                    DauamSettingsRow(
                      icon: CupertinoIcons.bell,
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
        ),
      ),
    );
  }
}

int _enabledCount(AppState app, List<String> ids) =>
    ids.where((id) => app.getReminderConfig(id, app.lang).enabled).length;

class _ReminderCount extends StatelessWidget {
  const _ReminderCount({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final c = dauamSettingsPalette(context).colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: JType.ui(13, color: c.sub)),
        const SizedBox(width: 7),
        Icon(CupertinoIcons.chevron_forward, size: 16, color: c.faint),
      ],
    );
  }
}

enum _ReminderGuideKind { schedule, ready, personal }

class _ReminderGuidePreview extends StatelessWidget {
  const _ReminderGuidePreview({required this.kind, required this.kz});

  final _ReminderGuideKind kind;
  final bool kz;

  @override
  Widget build(BuildContext context) {
    final p = dauamSettingsPalette(context);
    final c = p.colors;
    final accent = dauamSettingsAccent(context);
    final content = switch (kind) {
      _ReminderGuideKind.schedule => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _GuideLine(
            icon: CupertinoIcons.moon,
            label: kz ? 'Ақшам' : 'Магриб',
            value: '19:02',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Divider(color: c.hair, height: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    kz ? '+10 мин кейін' : '+10 минут',
                    style: JType.ui(11.5, color: accent),
                  ),
                ),
                Expanded(child: Divider(color: c.hair, height: 1)),
              ],
            ),
          ),
          _GuideLine(
            icon: CupertinoIcons.book,
            label: kz ? 'Кешкі зікірлер' : 'Вечерние зикры',
            value: kz ? 'Еске салу' : 'Напомнить',
          ),
        ],
      ),
      _ReminderGuideKind.ready => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _GuideLine(
            icon: CupertinoIcons.clock,
            label: kz ? 'Намаз уақыттары' : 'Времена молитв',
          ),
          const SizedBox(height: 11),
          _GuideLine(
            icon: CupertinoIcons.book,
            label: kz
                ? 'Таңғы және кешкі зікірлер'
                : 'Утренние и вечерние зикры',
          ),
          const SizedBox(height: 11),
          _GuideLine(
            icon: CupertinoIcons.calendar,
            label: kz ? 'Жұма: әл-Кәһф және дұға' : 'Пятница: аль-Кахф и дуа',
          ),
        ],
      ),
      _ReminderGuideKind.personal => Row(
        children: [
          Expanded(
            child: _GuideChoice(
              icon: CupertinoIcons.link,
              label: kz ? 'Намазға байланысты' : 'От молитвы',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _GuideChoice(
              icon: CupertinoIcons.time,
              label: kz ? 'Нақты уақытта' : 'В своё время',
            ),
          ),
        ],
      ),
    };

    return Container(
      height: 146,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: p.isLight ? .7 : .58),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.border.withValues(alpha: .4), width: .7),
      ),
      child: content,
    );
  }
}

class _GuideLine extends StatelessWidget {
  const _GuideLine({required this.icon, required this.label, this.value});

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final c = dauamSettingsPalette(context).colors;
    final accent = dauamSettingsAccent(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: JType.ui(14, w: FontWeight.w600, color: c.ink),
          ),
        ),
        if (value != null) ...[
          const SizedBox(width: 8),
          Text(value!, style: JType.ui(12.5, color: c.sub)),
        ],
      ],
    );
  }
}

class _GuideChoice extends StatelessWidget {
  const _GuideChoice({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = dauamSettingsPalette(context);
    final c = p.colors;
    final accent = dauamSettingsAccent(context);
    return Container(
      height: 105,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accent, size: 25),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: JType.ui(12.5, w: FontWeight.w600, color: c.ink, h: 1.25),
          ),
        ],
      ),
    );
  }
}

class ReminderGuideScreen extends StatefulWidget {
  const ReminderGuideScreen({
    super.key,
    this.root = false,
    this.replay = false,
  });

  final bool root;
  final bool replay;

  @override
  State<ReminderGuideScreen> createState() => _ReminderGuideScreenState();
}

class _ReminderGuideScreenState extends State<ReminderGuideScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    final app = AppScope.of(context);
    app.remindersGuideSeen = true;
    if (widget.replay) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(
      context,
    ).pushReplacement(dauamSettingsRoute(const RemindersScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final pages = <({_ReminderGuideKind kind, String title, String body})>[
      (
        kind: _ReminderGuideKind.schedule,
        title: kz ? 'Дәл уақытында' : 'В нужный момент',
        body: kz
            ? 'Дауам қалаңыздағы намаз кестесін ескереді. Мысалы, Ақшамнан 10 минут кейін зікірлерді еске салады және уақытты күн сайын өзі есептейді.'
            : 'Дауам учитывает расписание молитв вашего города. Например, напомнит о зикрах через 10 минут после Магриба и сам пересчитает время на следующий день.',
      ),
      (
        kind: _ReminderGuideKind.ready,
        title: kz ? 'Дайын еске салулар' : 'Готовые напоминания',
        body: kz
            ? 'Намаз уақыттары, таңғы және кешкі зікірлер, жұмадағы «әл-Кәһф» сүресі мен дұға сағаты қолданбада дайын тұр. Қажетін ғана қосыңыз.'
            : 'Времена молитв, утренние и вечерние зикры, аль-Кахф и час дуа в пятницу уже настроены. Оставьте включённым только нужное.',
      ),
      (
        kind: _ReminderGuideKind.personal,
        title: kz ? 'Қаласаңыз — өзіңіздікі' : 'Свои — только если нужны',
        body: kz
            ? 'Дайын еске салуларды бірден қолдана беруге болады. Қажет болса, кейін жеке істі намазға байланыстырыңыз немесе кәдімгі уақытты таңдаңыз.'
            : 'Можно сразу пользоваться готовыми сценариями. Если понадобится своё дело, позже привяжите его к молитве или обычному времени.',
      ),
    ];
    final p = dauamSettingsPalette(context);
    final c = p.colors;
    final accent = dauamSettingsAccent(context);
    final last = _page == pages.length - 1;

    return DauamSettingsPage(
      root: widget.root,
      title: kz ? 'Еске салулар' : 'Напоминания',
      trailing: DauamTextAction(
        label: widget.replay
            ? (kz ? 'Дайын' : 'Готово')
            : (kz ? 'Өткізу' : 'Пропустить'),
        onTap: _finish,
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pages.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: i == _page ? 20 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _page ? accent : c.faint.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: DauamPrimaryButton(
              label: last
                  ? (widget.replay
                        ? (kz ? 'Түсінікті' : 'Понятно')
                        : (kz ? 'Еске салуларды ашу' : 'Открыть напоминания'))
                  : (kz ? 'Әрі қарай' : 'Далее'),
              onTap: () {
                if (last) {
                  _finish();
                } else {
                  _controller.nextPage(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                  );
                }
              },
            ),
          ),
        ],
      ),
      child: PageView.builder(
        controller: _controller,
        itemCount: pages.length,
        onPageChanged: (value) => setState(() => _page = value),
        itemBuilder: (context, index) {
          final page = pages[index];
          return Padding(
            padding: const EdgeInsets.fromLTRB(30, 12, 30, 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ReminderGuidePreview(kind: page.kind, kz: kz),
                const SizedBox(height: 24),
                Text(
                  page.title,
                  textAlign: TextAlign.center,
                  style: JType.ui(26, w: FontWeight.w700, color: c.ink),
                ),
                const SizedBox(height: 12),
                Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: JType.ui(16, color: c.sub, h: 1.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum _ReminderHelpTopic { prayer, worship, custom }

Future<void> _showReminderHelp(BuildContext context, _ReminderHelpTopic topic) {
  final app = AppScope.of(context);
  final kz = app.lang == 'kz';
  final p = dauamSettingsPalette(context);
  final c = p.colors;
  final accent = dauamSettingsAccent(context);
  final opaqueSurface = Color.alphaBlend(
    p.surface,
    p.middle,
  ).withValues(alpha: 1);
  final data = switch (topic) {
    _ReminderHelpTopic.prayer => (
      icon: CupertinoIcons.clock,
      title: kz ? 'Намаз еске салулары' : 'Напоминания о молитвах',
      intro: kz
          ? 'Әр уақытты жеке баптауға болады.'
          : 'Каждое время можно настроить отдельно.',
      bullets: kz
          ? [
              'Кесте қала мен күнге қарай автоматты түрде жаңарады.',
              'Хабарлама намазға дейін, дәл уақытында немесе кейін келе алады.',
              'Күн шығуы — намаз емес, бірақ пайдалы уақыт белгісі.',
            ]
          : [
              'Расписание обновляется автоматически при смене города и даты.',
              'Уведомление может прийти до молитвы, в момент события или после.',
              'Восход — не молитва, а отдельная полезная временная точка.',
            ],
    ),
    _ReminderHelpTopic.worship => (
      icon: CupertinoIcons.book,
      title: kz ? 'Зікірлер мен жұма' : 'Зикры и пятница',
      intro: kz
          ? 'Қолданба ғибадат уақытын еске салады.'
          : 'Приложение мягко напоминает о времени поклонения.',
      bullets: kz
          ? [
              'Таңғы және кешкі зікірлер өз уақыт аралығында келеді.',
              'Жұмада «әл-Кәһф» сүресі мен дұға сағаты еске салынады.',
              'Жолды түртіп, тек уақыт пен хабарламаны өзгертіңіз.',
            ]
          : [
              'Утренние и вечерние зикры приходят в подходящий период.',
              'В пятницу доступны напоминания об аль-Кахф и часе дуа.',
              'Нажмите на строку, чтобы изменить время и способ уведомления.',
            ],
    ),
    _ReminderHelpTopic.custom => (
      icon: CupertinoIcons.slider_horizontal_3,
      title: kz ? 'Жеке еске салулар' : 'Личные напоминания',
      intro: kz
          ? 'Қосымша жеке тәртібіңізге бейімделеді.'
          : 'Настройте приложение под свой распорядок.',
      bullets: kz
          ? [
              'Атауы — хабарламада не туралы еске салу керегін жазыңыз.',
              'Негізі — намазға байланыстыруды немесе кәдімгі уақытты таңдаңыз.',
              'Кесте — нақты сәтті және қайталауды белгілеңіз.',
            ]
          : [
              'Название — напишите, о чём должно напомнить уведомление.',
              'Основа — выберите связь с молитвой или обычное время.',
              'Расписание — укажите нужный момент и повторение.',
            ],
    ),
  };

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .3),
    builder: (context) => SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('reminder-help-surface'),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: BoxDecoration(
          // Справка должна перекрывать список полностью: полупрозрачная
          // стеклянная карточка смешивала текст с настройками под ней.
          color: opaqueSurface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: p.border.withValues(alpha: .45)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(data.icon, color: accent, size: 21),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    data.title,
                    style: JType.ui(20, w: FontWeight.w700, color: c.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Text(data.intro, style: JType.ui(14, color: c.sub, h: 1.4)),
            const SizedBox(height: 13),
            for (final bullet in data.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        bullet,
                        style: JType.ui(14, color: c.ink, h: 1.42),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 5),
            SizedBox(
              width: double.infinity,
              child: DauamPrimaryButton(
                label: kz ? 'Түсінікті' : 'Понятно',
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
      trailing: DauamRoundButton(
        icon: CupertinoIcons.question,
        semanticLabel: kz ? 'Түсіндірме' : 'Подсказка',
        onTap: () => _showReminderHelp(context, _ReminderHelpTopic.prayer),
      ),
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            DauamSection(
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
      title: kz ? 'Зікірлер мен жұма' : 'Зикры и пятница',
      trailing: DauamRoundButton(
        icon: CupertinoIcons.question,
        semanticLabel: kz ? 'Түсіндірме' : 'Подсказка',
        onTap: () => _showReminderHelp(context, _ReminderHelpTopic.worship),
      ),
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DauamRoundButton(
            icon: CupertinoIcons.question,
            semanticLabel: kz ? 'Түсіндірме' : 'Подсказка',
            onTap: () => _showReminderHelp(context, _ReminderHelpTopic.custom),
          ),
          const SizedBox(width: 8),
          DauamRoundButton(
            icon: CupertinoIcons.add,
            semanticLabel: kz ? 'Қосу' : 'Добавить',
            onTap: () => Navigator.of(
              context,
            ).push(dauamSettingsRoute(const ReminderEditorScreen())),
          ),
        ],
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
                          ? 'Жеке еске салуды намаз уақытына байлаңыз немесе нақты уақытты таңдаңыз.'
                          : 'Создайте личное напоминание: по времени намаза или в указанное время.',
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
  String _anchor = 'prayer';
  int _prayer = 0;
  int _offset = -15;
  int _fixedHour = 9;
  int _fixedMinute = 0;
  String _repeat = 'daily';
  final Set<int> _weekdays = {DateTime.friday};
  DateTime _scheduleDate = DateUtils.dateOnly(DateTime.now());

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

  Future<void> _selectClock() async {
    final result = await Navigator.of(context).push<(int, int)>(
      dauamSettingsRoute(
        ClockChoiceScreen(hour: _fixedHour, minute: _fixedMinute),
      ),
    );
    if (mounted && result != null) {
      setState(() {
        _fixedHour = result.$1;
        _fixedMinute = result.$2;
      });
    }
  }

  Future<void> _selectRepeat() async {
    final result = await Navigator.of(
      context,
    ).push<String>(dauamSettingsRoute(RepeatChoiceScreen(selected: _repeat)));
    if (mounted && result != null) setState(() => _repeat = result);
  }

  Future<void> _selectWeekdays() async {
    final result = await Navigator.of(context).push<List<int>>(
      dauamSettingsRoute(WeekdayChoiceScreen(selected: _weekdays.toList())),
    );
    if (mounted && result != null) {
      setState(() {
        _weekdays
          ..clear()
          ..addAll(result);
      });
    }
  }

  Future<void> _selectScheduleDate() async {
    final result = await Navigator.of(context).push<DateTime>(
      dauamSettingsRoute(
        ScheduleDateChoiceScreen(selected: _scheduleDate, repeat: _repeat),
      ),
    );
    if (mounted && result != null) setState(() => _scheduleDate = result);
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
        anchor: _anchor,
        fixedHour: _fixedHour,
        fixedMinute: _fixedMinute,
        repeat: _repeat,
        weekday: _weekdays.first,
        weekdays: _weekdays.toList()..sort(),
        scheduleYear: _scheduleDate.year,
        scheduleMonth: _scheduleDate.month,
        scheduleDay: _scheduleDate.day,
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
      trailing: DauamRoundButton(
        icon: CupertinoIcons.question,
        semanticLabel: kz ? 'Түсіндірме' : 'Подсказка',
        onTap: () => _showReminderHelp(context, _ReminderHelpTopic.custom),
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
            label: kz ? 'НЕГІЗІ' : 'ОСНОВА НАПОМИНАНИЯ',
            children: [
              DauamChoiceRow(
                title: kz ? 'Намаз уақытына байлау' : 'От времени намаза',
                subtitle: kz
                    ? 'Қала мен маусым ауысқанда бірге өзгереді'
                    : 'Базовый режим Dauam — меняется вместе с городом и сезоном',
                selected: _anchor == 'prayer',
                onTap: () => setState(() => _anchor = 'prayer'),
              ),
              DauamChoiceRow(
                title: kz ? 'Белгіленген уақытта' : 'В указанное время',
                subtitle: kz
                    ? 'Намаз уақытына байланбайды'
                    : 'Обычное напоминание, не связанное с намазом',
                selected: _anchor == 'clock',
                onTap: () => setState(() => _anchor = 'clock'),
              ),
            ],
          ),
          if (_anchor == 'clock') const _FixedTimeWarning(),
          DauamSection(
            label: kz ? 'КЕСТЕ' : 'РАСПИСАНИЕ',
            children: [
              if (_anchor == 'prayer') ...[
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
              ] else
                DauamSettingsRow(
                  title: kz ? 'Уақыт' : 'Время',
                  value: _clockLabel(_fixedHour, _fixedMinute),
                  onTap: _selectClock,
                ),
              DauamSettingsRow(
                title: kz ? 'Қайталау' : 'Повторение',
                value: _repeatLabel(kz, _repeat),
                onTap: _selectRepeat,
              ),
              if (_repeat == 'weekly')
                DauamSettingsRow(
                  title: kz ? 'Апта күндері' : 'Дни недели',
                  value: _weekdaysLabel(kz, _weekdays),
                  onTap: _selectWeekdays,
                ),
              if (const {'once', 'monthly', 'yearly'}.contains(_repeat))
                DauamSettingsRow(
                  title: _repeat == 'monthly'
                      ? (kz ? 'Ай күні' : 'День месяца')
                      : (kz ? 'Күні' : 'Дата'),
                  value: _scheduleDateLabel(kz, _scheduleDate, _repeat),
                  onTap: _selectScheduleDate,
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
    final alarmPrayerId = _alarmPrayerIds.contains(_activeConfigId)
        ? _activeConfigId
        : null;
    final alarmEnabled = alarmPrayerId != null
        ? app.alarmEnabled(alarmPrayerId)
        : false;
    final alarmOffset = alarmPrayerId != null
        ? app.alarmOffsetMinutes(alarmPrayerId)
        : 0;
    final alarmDefaultOffset = alarmPrayerId == 'fajr' ? -15 : 0;

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
          if (alarmPrayerId != null)
            DauamSection(
              label: kz ? 'ЖҮЙЕЛІК БУДИЛЬНИК' : 'СИСТЕМНЫЙ БУДИЛЬНИК',
              footer: kz
                  ? 'Жүйелік будильник iOS «Мазаламау» режимінде де соғылады. Күн шығуы намаз емес, жеке уақыт белгісі ретінде қолжетімді.'
                  : 'Системный будильник iOS сработает даже в режиме «Не беспокоить». Восход доступен как отдельная временная точка, но не является молитвой.',
              children: [
                DauamSwitchRow(
                  icon: CupertinoIcons.alarm,
                  title: kz ? 'Будильник' : 'Будильник',
                  subtitle: alarmEnabled
                      ? (kz ? 'Қосулы' : 'Включен')
                      : (kz ? 'Өшірулі' : 'Выключен'),
                  value: alarmEnabled,
                  onChanged: (val) {
                    app.setAlarmEnabled(alarmPrayerId, val);
                    AlarmService.sync(app, ScheduleScope.of(context));
                    HapticFeedback.selectionClick();
                  },
                ),
                if (alarmEnabled) ...[
                  _InlineOffsetStepper(
                    offset: alarmOffset,
                    kz: kz,
                    onMinus: () {
                      final next = (alarmOffset - 5).clamp(-60, 60);
                      if (next != alarmOffset) {
                        app.setAlarmOffsetMinutes(alarmPrayerId, next);
                        AlarmService.sync(app, ScheduleScope.of(context));
                        HapticFeedback.selectionClick();
                      }
                    },
                    onPlus: () {
                      final next = (alarmOffset + 5).clamp(-60, 60);
                      if (next != alarmOffset) {
                        app.setAlarmOffsetMinutes(alarmPrayerId, next);
                        AlarmService.sync(app, ScheduleScope.of(context));
                        HapticFeedback.selectionClick();
                      }
                    },
                    onReset: alarmOffset == alarmDefaultOffset
                        ? null
                        : () {
                            app.setAlarmOffsetMinutes(
                              alarmPrayerId,
                              alarmDefaultOffset,
                            );
                            AlarmService.sync(app, ScheduleScope.of(context));
                            HapticFeedback.selectionClick();
                          },
                  ),
                  DauamSettingsRow(
                    icon: CupertinoIcons.play_circle_fill,
                    title: kz
                        ? 'Будильникті тексеру (10 с)'
                        : 'Проверить будильник (10 сек)',
                    subtitle: kz
                        ? '10 секундтан кейін дабыл соғады. Енді экранды бұғаттаңыз.'
                        : 'Будильник сработает через 10 секунд. Заблокируйте экран для проверки.',
                    onTap: () async {
                      HapticFeedback.mediumImpact();
                      final test = await AlarmService.testAlarm(
                        seconds: 10,
                        title: '${config.title} (${kz ? 'Сынақ' : 'Тест'})',
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
                            duration: Duration(seconds: test.success ? 4 : 7),
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
              label: kz ? 'НЕГІЗІ' : 'ОСНОВА НАПОМИНАНИЯ',
              children: [
                DauamChoiceRow(
                  title: kz ? 'Намаз уақытына байлау' : 'От времени намаза',
                  selected: config.isPrayerLinked,
                  onTap: () => _persist(config.copyWith(anchor: 'prayer')),
                ),
                DauamChoiceRow(
                  title: kz ? 'Белгіленген уақытта' : 'В указанное время',
                  selected: !config.isPrayerLinked,
                  onTap: () => _persist(config.copyWith(anchor: 'clock')),
                ),
              ],
            ),
            if (!config.isPrayerLinked) const _FixedTimeWarning(),
            DauamSection(
              label: kz ? 'КЕСТЕ' : 'РАСПИСАНИЕ',
              children: [
                if (config.isPrayerLinked) ...[
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
                ] else
                  DauamSettingsRow(
                    title: kz ? 'Уақыт' : 'Время',
                    value: _clockLabel(config.fixedHour, config.fixedMinute),
                    onTap: () async {
                      final result = await Navigator.of(context)
                          .push<(int, int)>(
                            dauamSettingsRoute(
                              ClockChoiceScreen(
                                hour: config.fixedHour,
                                minute: config.fixedMinute,
                              ),
                            ),
                          );
                      if (mounted && result != null) {
                        _persist(
                          config.copyWith(
                            fixedHour: result.$1,
                            fixedMinute: result.$2,
                          ),
                        );
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
                      final date = _scheduleDateFor(config);
                      _persist(
                        config.copyWith(
                          repeat: result,
                          scheduleYear: date.year,
                          scheduleMonth: date.month,
                          scheduleDay: date.day,
                        ),
                      );
                    }
                  },
                ),
                if (config.repeat == 'weekly')
                  DauamSettingsRow(
                    title: kz ? 'Апта күндері' : 'Дни недели',
                    value: _weekdaysLabel(kz, config.effectiveWeekdays),
                    onTap: () async {
                      final result = await Navigator.of(context)
                          .push<List<int>>(
                            dauamSettingsRoute(
                              WeekdayChoiceScreen(
                                selected: config.effectiveWeekdays,
                              ),
                            ),
                          );
                      if (mounted && result != null) {
                        _persist(
                          config.copyWith(
                            weekday: result.first,
                            weekdays: result,
                          ),
                        );
                      }
                    },
                  ),
                if (const {'once', 'monthly', 'yearly'}.contains(config.repeat))
                  DauamSettingsRow(
                    title: config.repeat == 'monthly'
                        ? (kz ? 'Ай күні' : 'День месяца')
                        : (kz ? 'Күні' : 'Дата'),
                    value: _scheduleDateLabel(
                      kz,
                      _scheduleDateFor(config),
                      config.repeat,
                    ),
                    onTap: () async {
                      final result = await Navigator.of(context).push<DateTime>(
                        dauamSettingsRoute(
                          ScheduleDateChoiceScreen(
                            selected: _scheduleDateFor(config),
                            repeat: config.repeat,
                          ),
                        ),
                      );
                      if (mounted && result != null) {
                        _persist(
                          config.copyWith(
                            scheduleYear: result.year,
                            scheduleMonth: result.month,
                            scheduleDay: result.day,
                          ),
                        );
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

class _FixedTimeWarning extends StatelessWidget {
  const _FixedTimeWarning();

  @override
  Widget build(BuildContext context) {
    final kz = AppScope.of(context).lang == 'kz';
    final palette = dauamSettingsPalette(context);
    final c = palette.colors;
    final accent = dauamSettingsAccent(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: palette.isLight ? .09 : .13),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: accent.withValues(alpha: .22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(CupertinoIcons.info_circle, color: accent, size: 20),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                kz
                    ? 'Dauam намаз уақытымен байланысты еске салуларға негізделген. Бұл еске салу қала немесе маусым ауысқанда өздігінен өзгермейді.'
                    : 'Основа Dauam — напоминания, связанные со временем молитв. Обычное напоминание тоже сработает, но не перестроится при смене города или сезона.',
                style: JType.ui(13, color: c.sub, h: 1.42),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClockChoiceScreen extends StatefulWidget {
  const ClockChoiceScreen({
    super.key,
    required this.hour,
    required this.minute,
  });

  final int hour, minute;

  @override
  State<ClockChoiceScreen> createState() => _ClockChoiceScreenState();
}

class _ClockChoiceScreenState extends State<ClockChoiceScreen> {
  late DateTime _value = DateTime(2026, 1, 1, widget.hour, widget.minute);

  @override
  Widget build(BuildContext context) {
    final kz = AppScope.of(context).lang == 'kz';
    final c = dauamSettingsPalette(context).colors;
    return DauamSettingsPage(
      title: kz ? 'Уақыт' : 'Время',
      trailing: DauamTextAction(
        label: kz ? 'Дайын' : 'Готово',
        onTap: () => Navigator.of(context).pop((_value.hour, _value.minute)),
      ),
      child: ListView(
        padding: const EdgeInsets.only(top: 22, bottom: 24),
        children: [
          Center(
            child: Text(
              _clockLabel(_value.hour, _value.minute),
              style: JType.ui(32, w: FontWeight.w700, color: c.ink, ls: -.6),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              initialDateTime: _value,
              use24hFormat: true,
              minuteInterval: 5,
              onDateTimeChanged: (value) => setState(() => _value = value),
            ),
          ),
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
    const values = ['once', 'daily', 'weekly', 'monthly', 'yearly'];
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

class WeekdayChoiceScreen extends StatefulWidget {
  const WeekdayChoiceScreen({super.key, required this.selected});
  final List<int> selected;

  @override
  State<WeekdayChoiceScreen> createState() => _WeekdayChoiceScreenState();
}

class _WeekdayChoiceScreenState extends State<WeekdayChoiceScreen> {
  late final Set<int> _selected = widget.selected.toSet();

  @override
  Widget build(BuildContext context) {
    final kz = AppScope.of(context).lang == 'kz';
    return DauamSettingsPage(
      title: kz ? 'Апта күндері' : 'Дни недели',
      trailing: DauamTextAction(
        label: kz ? 'Дайын' : 'Готово',
        enabled: _selected.isNotEmpty,
        onTap: () {
          final result = _selected.toList()..sort();
          Navigator.of(context).pop(result);
        },
      ),
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          DauamSection(
            children: [
              for (var day = 1; day <= 7; day++)
                DauamChoiceRow(
                  title: _weekdayLabel(kz, day),
                  selected: _selected.contains(day),
                  onTap: () => setState(() {
                    if (_selected.contains(day)) {
                      if (_selected.length > 1) _selected.remove(day);
                    } else {
                      _selected.add(day);
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ScheduleDateChoiceScreen extends StatefulWidget {
  const ScheduleDateChoiceScreen({
    super.key,
    required this.selected,
    required this.repeat,
  });

  final DateTime selected;
  final String repeat;

  @override
  State<ScheduleDateChoiceScreen> createState() =>
      _ScheduleDateChoiceScreenState();
}

class _ScheduleDateChoiceScreenState extends State<ScheduleDateChoiceScreen> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _selected = widget.repeat == 'once' && widget.selected.isBefore(today)
        ? today
        : widget.selected;
  }

  @override
  Widget build(BuildContext context) {
    final kz = AppScope.of(context).lang == 'kz';
    final monthly = widget.repeat == 'monthly';
    return DauamSettingsPage(
      title: monthly
          ? (kz ? 'Ай күні' : 'День месяца')
          : (kz ? 'Күні' : 'Дата'),
      trailing: DauamTextAction(
        label: kz ? 'Дайын' : 'Готово',
        onTap: () => Navigator.of(context).pop(_selected),
      ),
      child: Center(
        child: SizedBox(
          height: 250,
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.date,
            initialDateTime: _selected,
            minimumDate: widget.repeat == 'once'
                ? DateUtils.dateOnly(DateTime.now())
                : null,
            onDateTimeChanged: (value) => setState(() {
              _selected = DateUtils.dateOnly(value);
            }),
          ),
        ),
      ),
    );
  }
}

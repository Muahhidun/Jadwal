import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/app_state.dart';
import '../theme/tokens.dart';
import '../theme/system_bars.dart';
import 'reminders.dart';
import 'settings_shell.dart';

/// Reuses the real reminder settings; previews never save reminders or permissions.
class FeatureTourScreen extends StatefulWidget {
  const FeatureTourScreen({super.key, this.onFinished});
  final VoidCallback? onFinished;
  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const FeatureTourScreen()));
  @override
  State<FeatureTourScreen> createState() => _FeatureTourScreenState();
}

class _FeatureTourScreenState extends State<FeatureTourScreen> {
  int step = 0;
  bool finished = false;
  void finish() {
    if (finished) return;
    finished = true;
    AppScope.of(context).markFeatureTourSeen();
    if (widget.onFinished != null) {
      widget.onFinished!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final kz = AppScope.of(context).lang == 'kz';
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final c = JColors.light;
    final titles = kz
        ? [
            'Намаз уақыты — бір қарағанда',
            'Намаз уақыты білегіңізде',
            'Әр намазға будильник',
            'Істеріңіз намаз уақытымен бірге',
            'Жұмаға екі еске салу',
          ]
        : [
            'Время молитвы — одним взглядом',
            'Молитвы на запястье',
            'Будильник на любую молитву',
            'Дела в ритме молитв',
            'Два напоминания в пятницу',
          ];
    final descriptions = kz
        ? [
            'Басты экранға Dauam виджетін қосыңыз.${ios ? ' iPhone бұғаттау экранына да қосуға болады.' : ''}',
            ios
                ? 'Apple Watch-та келесі намаз, кесте және істер бар. Dauam-ды iPhone-дағы Watch қолданбасынан орнатыңыз.'
                : 'Apple Watch мүмкіндігі iPhone-мен жұпталған сағатта қолжетімді.',
            'Қолдау көрсетілетін құрылғыда намазды және уақыт ығысуын таңдаңыз. Таң намазында «Қатты ұйқы» режимі де бар.',
            'Жеке еске салуды намазға дейін немесе кейін жоспарлаңыз. Уақыты қалаңыздың кестесіне сәйкес өзгереді.',
            '«әл-Кәһф» еске салуын баптаңыз. Өз дұға мәтініңізді жеке еске салудың атауына жазып, жұманы және Ақшамға дейінгі уақытты таңдаңыз.',
          ]
        : [
            'Добавьте виджет Дауам на домашний экран.${ios ? ' На iPhone доступен и виджет экрана блокировки.' : ''}',
            ios
                ? 'Следующая молитва, расписание и дела — на Apple Watch. Установите Дауам через приложение Watch на iPhone.'
                : 'Apple Watch доступен на часах, сопряжённых с iPhone.',
            'На поддерживаемом устройстве выберите молитву и сдвиг времени. Для Фаджра есть режим «Крепкий сон».',
            'Свяжите личное дело с временем до или после молитвы. Оно следует за расписанием вашего города.',
            'Настройте аль-Кахф. Для собственного дуа впишите текст в название личного напоминания, выберите пятницу и время до Магриба.',
          ];
    return PopScope(
      canPop: widget.onFinished == null && step == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && step > 0) {
          setState(() => step--);
        } else if (!didPop && step == 0 && widget.onFinished != null) {
          finish();
        }
      },
      child: JSystemBars(
        darkIcons: true,
        child: Theme(
          data: Theme.of(context).copyWith(
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: c.ink),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(foregroundColor: c.ink),
            ),
          ),
          child: Scaffold(
            backgroundColor: const Color(0xFFFFF9EF),
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        if (step > 0)
                          IconButton(
                            tooltip: kz ? 'Артқа' : 'Назад',
                            onPressed: () => setState(() => step--),
                            icon: const Icon(CupertinoIcons.chevron_left),
                          ),
                        Text(
                          '${step + 1} / 5',
                          style: JType.ui(13, color: c.sub),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton(
                            onPressed: finish,
                            child: Text(kz ? 'Өткізіп жіберу' : 'Пропустить'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 320),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, .025),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: Column(
                          key: ValueKey(step),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Preview(step: step, kz: kz, ios: ios),
                            const SizedBox(height: 28),
                            Text(
                              titles[step],
                              style: JType.ui(
                                28,
                                w: FontWeight.w700,
                                color: c.ink,
                                h: 1.12,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              descriptions[step],
                              style: JType.ui(16, color: c.sub, h: 1.45),
                            ),
                            const SizedBox(height: 18),
                            if (step < 2)
                              Text(
                                kz
                                    ? 'Жүйелік орнату қолмен жасалады.'
                                    : 'Добавление выполняется вручную в системе.',
                                style: JType.ui(13, color: c.sub),
                              ),
                            if (step == 4) ...[
                              OutlinedButton(
                                onPressed: () => RemindersScreen.open(
                                  context,
                                  initialConfigId: 'kahf',
                                ),
                                child: Text(
                                  kz
                                      ? 'әл-Кәһфті баптау'
                                      : 'Настроить аль-Кахф',
                                ),
                              ),
                              OutlinedButton(
                                onPressed: () =>
                                    ReminderEditorScreen.open(context),
                                child: Text(
                                  kz
                                      ? 'Өз дұғаңызды қосу'
                                      : 'Добавить своё дуа',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (step == 2 || step == 3)
                          OutlinedButton(
                            onPressed: () => step == 3
                                ? ReminderEditorScreen.open(context)
                                : DauamSettingsSheet.open<void>(
                                    context,
                                    builder: (_) =>
                                        const PrayerRemindersScreen(),
                                  ),
                            child: Text(kz ? 'Баптау' : 'Настроить'),
                          ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: c.gold,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 50),
                          ),
                          onPressed: () =>
                              step == 4 ? finish() : setState(() => step++),
                          child: Text(
                            step == 4
                                ? (kz ? 'Дайын' : 'Готово')
                                : (kz ? 'Келесі' : 'Дальше'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Illustrative, noninteractive previews matching the supported native surfaces.
/// Explicit sample labels prevent confusing examples with current prayer times.
class _Preview extends StatelessWidget {
  const _Preview({required this.step, required this.kz, required this.ios});
  final int step;
  final bool kz;
  final bool ios;
  @override
  Widget build(BuildContext context) {
    final c = JColors.light;
    Widget card(
      IconData icon,
      String title,
      String subtitle, {
      bool dark = false,
    }) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF163A34) : Colors.white,
        borderRadius: BorderRadius.circular(step == 1 ? 38 : 24),
        border: Border.all(color: c.hair),
      ),
      child: Row(
        children: [
          Icon(icon, color: dark ? const Color(0xFFE6C786) : c.gold, size: 30),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: JType.ui(
                    19,
                    w: FontWeight.w700,
                    color: dark ? Colors.white : c.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: JType.ui(
                    14,
                    color: dark ? const Color(0xFFE0E8E0) : c.sub,
                    h: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: kz ? 'Интерфейс мысалы' : 'Пример интерфейса',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            kz ? 'DAUAM · МЫСАЛ' : 'ДАУАМ · ПРИМЕР',
            style: JType.ui(11, w: FontWeight.w600, color: c.sub),
          ),
          const SizedBox(height: 14),
          if (step == 0) ...[
            card(
              CupertinoIcons.square_grid_2x2,
              kz ? 'Ақшам · 18:20' : 'Магриб · 18:20',
              kz
                  ? 'Келесі намазға 42 минут\nБасты экран виджеті'
                  : 'До молитвы 42 минуты\nВиджет домашнего экрана',
              dark: true,
            ),
            if (ios)
              card(
                CupertinoIcons.lock,
                '00:42',
                kz ? 'Бұғаттау экраны' : 'Экран блокировки',
              ),
          ],
          if (step == 1)
            Center(
              child: SizedBox(
                width: 250,
                child: card(
                  CupertinoIcons.clock,
                  kz ? 'Ақшам' : 'Магриб',
                  '18:20\n${kz ? 'Кесте · Істер' : 'Расписание · Дела'}',
                  dark: true,
                ),
              ),
            ),
          if (step == 2) ...[
            card(
              CupertinoIcons.alarm,
              kz ? 'Таң · Будильник' : 'Фаджр · Будильник',
              kz ? '15 минут бұрын' : 'За 15 минут до',
            ),
            card(
              CupertinoIcons.moon,
              kz
                  ? 'Бесін · Екінті · Ақшам · Құптан'
                  : 'Зухр · Аср · Магриб · Иша',
              kz ? 'Намазды таңдаңыз' : 'Выберите молитву',
            ),
          ],
          if (step == 3) ...[
            card(
              CupertinoIcons.check_mark_circled,
              kz ? 'Кітап оқу' : 'Почитать книгу',
              kz ? 'Екінтіден 10 минут кейін' : 'Через 10 минут после Асра',
            ),
            card(
              CupertinoIcons.arrow_right,
              kz ? 'Намаз → Іс' : 'Молитва → Дело',
              kz
                  ? 'Күн сайын · Қалаңыздың кестесі'
                  : 'Каждый день · Расписание вашего города',
            ),
          ],
          if (step == 4) ...[
            card(
              CupertinoIcons.book,
              kz ? 'әл-Кәһф сүресі' : 'Сура аль-Кахф',
              kz ? 'Жұма · Қолданбада оқу' : 'Пятница · Чтение в приложении',
            ),
            card(
              CupertinoIcons.bubble_left,
              kz ? 'Өз дұғаңыз' : 'Ваш текст дуа',
              kz ? 'Жұма · Ақшамға дейін' : 'Пятница · До Магриба',
            ),
          ],
        ],
      ),
    );
  }
}

part of 'home.dart';

class _HomeLearning extends StatelessWidget {
  const _HomeLearning({
    required this.page,
    required this.pages,
    required this.onGoTo,
  });
  final double page;
  final bool pages;
  final void Function(double) onGoTo;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), g = app.navigationGuide;
    final kz = app.lang == 'kz';
    final expected = g.expectedPage;
    if (g.moving ||
        g.inModal ||
        (expected != null && (page - expected).abs() > .000001)) {
      return const SizedBox.shrink();
    }
    final next = kz ? 'Әрі қарай' : 'Дальше';
    Widget swipe(String ru, String kk, bool up, double destination) =>
        SwipeLesson(
          key: ValueKey(g.step),
          message: kz ? kk : ru,
          up: up,
          onOpen: () => onGoTo(destination),
        );
    Widget info(
      String target,
      String title,
      String message,
      GuideStep after, {
      String? secondary,
      VoidCallback? onSecondary,
    }) => GuidedSpotlight(
      key: ValueKey(g.step),
      target: g.target(target),
      compact: true,
      title: title,
      message: message,
      action: next,
      onAction: () => g.go(after),
      secondary: secondary,
      onSecondary: onSecondary,
    );

    switch (g.step) {
      case GuideStep.welcome:
        return GuidedSpotlight(
          key: ValueKey(g.step),
          compact: true,
          title: kz ? 'Dauam-мен танысу' : 'Освоимся в Дауам',
          message: kz
              ? 'Бірнеше сырғыту: намаздар, істер, күнтізбе және құбыла.'
              : 'Несколько свайпов: намазы, дела, календарь и Кибла.',
          action: kz ? 'Көрсетіңіз' : 'Показать',
          onAction: () {
            app.beginNavigationGuide(usePages: true);
            onGoTo(0);
          },
        );
      case GuideStep.day:
        return swipe(
          'Свайп вверх — расписание и дела.',
          'Жоғары сырғытыңыз — кесте мен істер.',
          true,
          1,
        );
      case GuideStep.times:
        return info(
          'prayer-times',
          kz ? 'Намаз уақыттары' : 'Время намазов',
          kz
              ? 'Бес намаз және күн шығуы. Уақытты басып, хабарламаны баптаңыз.'
              : 'Пять намазов и восход. Нажмите на время, чтобы настроить уведомление.',
          GuideStep.deeds,
        );
      case GuideStep.deeds:
        return info(
          'today-deeds',
          kz ? 'Бүгінгі істер' : 'Дела сегодня',
          kz
              ? 'Күннің істері осында. Зікірді бассаңыз, оқу ашылады.'
              : 'Здесь дела на сегодня. Нажатие на зикры открывает чтение.',
          GuideStep.add,
        );
      case GuideStep.add:
        return info(
          'page-add',
          kz ? 'Өз ісіңіз' : 'Своё дело',
          kz
              ? 'Осы батырма өз еске салуыңызды қосады. Қалай жасау керегін сол жерде көрсетеміз.'
              : 'Эта кнопка добавляет своё напоминание. Как его настроить — покажем отдельно внутри.',
          GuideStep.calendarSwipe,
        );
      case GuideStep.calendarSwipe:
        return swipe(
          'Ещё свайп вверх — календарь постоянства.',
          'Тағы жоғары сырғытыңыз — тұрақтылық күнтізбесі.',
          true,
          2,
        );
      case GuideStep.calendar:
        return info(
          'calendar',
          kz ? 'Сіздің тұрақтылығыңыз' : 'Ваше постоянство',
          kz
              ? 'Орындалған істер осында сақталады. Күнді басып, мәліметін қараңыз.'
              : 'Здесь отмечены выполненные дела. Нажмите на день для подробностей.',
          GuideStep.appearance,
          secondary: kz ? 'Бүгінгі істерді қарау' : 'Посмотреть дела сегодня',
          onSecondary: () {
            final schedule = ScheduleScope.of(context);
            final now = schedule.now();
            final times = schedule.timesFor(app.city, now);
            if (times == null) return;
            _showDayDetailsSheet(
              context,
              date: now,
              s: S.of(app.lang),
              app: app,
              palette: daySurfacePalette(
                times,
                now.hour * 3600 + now.minute * 60 + now.second,
              ),
            );
          },
        );
      case GuideStep.appearance:
        return info(
          'page-settings',
          kz ? 'Өз көрінісіңіз' : 'Оформление на ваш вкус',
          kz
              ? 'Баптаулар → Көрініс: Мекке, Мәдина, Астана немесе дала.'
              : 'Настройки → Оформление: Мекка, Медина, Астана или степь.',
          GuideStep.returnDay,
          secondary: kz ? 'Көріністерді қарау' : 'Посмотреть темы',
          onSecondary: () async {
            g.go(GuideStep.appearancePicker);
            await AppearancePicker.open(context);
            if (context.mounted && g.step == GuideStep.appearancePicker) {
              g.go(GuideStep.returnDay);
            }
          },
        );
      case GuideStep.returnDay:
        return swipe(
          'Свайп вниз — вернёмся к делам.',
          'Төмен сырғытыңыз — істерге ораламыз.',
          false,
          1,
        );
      case GuideStep.returnHome:
        return swipe(
          'Ещё вниз — главный экран.',
          'Тағы төмен — басты экран.',
          false,
          0,
        );
      case GuideStep.qibla:
        return swipe(
          'Ещё один свайп вниз — Кибла.',
          'Тағы бір рет төмен сырғытыңыз — құбыла.',
          false,
          -1,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

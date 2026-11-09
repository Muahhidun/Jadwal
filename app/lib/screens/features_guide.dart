import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../data/app_state.dart';
import '../theme/tokens.dart';
import 'settings_shell.dart';

/// Постоянная, повторно открываемая справка по возможностям приложения.
/// Показываем только функции, доступные на данной платформе.
class FeaturesGuideScreen extends StatelessWidget {
  const FeaturesGuideScreen({super.key, this.root = false});

  final bool root;

  static Future<void> open(BuildContext context) =>
      DauamSettingsSheet.open<void>(
        context,
        builder: (_) => const FeaturesGuideScreen(root: true),
      );

  @override
  Widget build(BuildContext context) {
    final kz = AppScope.of(context).lang == 'kz';
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final android = defaultTargetPlatform == TargetPlatform.android;
    final c = dauamSettingsPalette(context).colors;

    return DauamSettingsPage(
      root: root,
      title: kz ? 'Қосымша мүмкіндіктері' : 'Возможности приложения',
      child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
            child: Text(
              kz
                  ? 'Dauam-ды өзіңізге ыңғайлап баптаңыз. Төменде әр мүмкіндікті қайдан табуға болатыны жазылған.'
                  : 'Настройте Дауам под себя. Здесь собраны возможности и подсказки, где их найти.',
              style: JType.ui(14, color: c.sub, h: 1.4),
            ),
          ),
          DauamSection(
            label: kz ? 'Күн сайын' : 'На каждый день',
            children: [
              DauamSettingsRow(
                icon: CupertinoIcons.hand_draw,
                title: kz ? 'Қимылдар мен батырмалар' : 'Жесты и кнопки',
                subtitle: kz
                    ? 'Нақты экрандарда үйрену'
                    : 'Попробовать на настоящих экранах',
                onTap: () {
                  AppScope.of(context).navigationGuide.offer();
                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).popUntil((route) => route.isFirst);
                },
              ),
              _FeatureRow(
                icon: CupertinoIcons.clock,
                title: kz ? 'Намаз уақыттары' : 'Времена молитв',
                description: kz
                    ? 'Басты экранда келесі уақытқа дейінгі санақ, төменгі экранда күннің толық кестесі көрсетіледі.'
                    : 'На главном экране — отсчёт до следующего времени, на нижнем — полное расписание дня.',
                path: kz
                    ? 'Басты экраннан жоғары сырғытыңыз'
                    : 'Смахните вверх с главного экрана',
              ),
              _FeatureRow(
                icon: CupertinoIcons.compass,
                title: kz ? 'Құбыла' : 'Кибла',
                description: kz
                    ? 'Бағытты локатордан немесе картадан қараңыз. Дәлдігі құрылғының датчиктері мен геолокациясына байланысты.'
                    : 'Проверьте направление по локатору или карте. Точность зависит от датчиков и геолокации устройства.',
                path: kz
                    ? 'Басты экраннан төмен сырғытыңыз'
                    : 'Смахните вниз с главного экрана',
              ),
              _FeatureRow(
                icon: CupertinoIcons.book,
                title: kz
                    ? 'Таңғы және кешкі зікірлер'
                    : 'Утренние и вечерние зикры',
                description: kz
                    ? 'Арабша мәтін, транскрипция, аударма және дереккөз бір жерде. Хабарламаны бассаңыз, оқу бірден ашылады.'
                    : 'Арабский текст, транскрипция, перевод и источник — в читалке. Нажатие на уведомление открывает чтение.',
                path: kz
                    ? 'Басты экрандағы «Зікірлерді оқу»'
                    : 'Кнопка «Читать зикры» на главном экране',
              ),
              _FeatureRow(
                icon: CupertinoIcons.calendar,
                title: kz ? 'Тұрақтылық дәптері' : 'Тетрадь постоянства',
                description: kz
                    ? 'Күнтізбеде қандай істерді орындағаныңызды көресіз. Ұпайлар мен жарыс жоқ.'
                    : 'В календаре видно, какие дела вы отметили выполненными. Без очков и соревнования.',
                path: kz
                    ? 'Төменгі экрандағы күнтізбе'
                    : 'Календарь на нижнем экране',
              ),
            ],
          ),
          DauamSection(
            label: kz ? 'Еске салулар' : 'Напоминания',
            children: [
              _FeatureRow(
                icon: CupertinoIcons.bell,
                title: kz
                    ? 'Намаз және ғибадат ескертулері'
                    : 'Напоминания о молитвах и поклонении',
                description: kz
                    ? 'Намаз, таңғы және кешкі зікірлер үшін хабарламаларды қосып, уақытын баптаңыз.'
                    : 'Включите уведомления о молитвах, утренних и вечерних зикрах и настройте время.',
                path: kz ? 'Еске салулар' : 'Раздел «Напоминания»',
              ),
              _FeatureRow(
                icon: CupertinoIcons.plus_circle,
                title: kz ? 'Жеке істер' : 'Свои дела',
                description: kz
                    ? 'Өз ісіңізді қосып, оны намаз уақытына немесе белгілі бір сағатқа байланыстырыңыз.'
                    : 'Добавьте личное дело и привяжите его ко времени молитвы или к определённому часу.',
                path: kz
                    ? 'Еске салулар → Еске салу қосу'
                    : 'Напоминания → Добавить напоминание',
              ),
              _FeatureRow(
                icon: CupertinoIcons.bell_fill,
                title: kz
                    ? 'Хабарламадағы жылдам әрекеттер'
                    : 'Действия в уведомлении',
                description: kz
                    ? 'Іс туралы хабарламадан оны орындалды деп белгілеуге немесе 10 минутқа кейінге қалдыруға болады.'
                    : 'Из уведомления о деле можно отметить его выполненным или отложить на 10 минут.',
                path: kz
                    ? 'Іс туралы хабарламаны кеңейтіңіз'
                    : 'Раскройте уведомление о деле',
              ),
              _FeatureRow(
                icon: CupertinoIcons.moon_stars,
                title: kz ? 'Жұма күнгі істер' : 'Пятничные дела',
                description: kz
                    ? '«әл-Кәһф» сүресін қолданбаның ішінде оқыңыз және жұмадағы дұға уақытын еске салуды баптаңыз.'
                    : 'Читайте суру аль-Кахф внутри приложения и настройте напоминание о часе дуа в пятницу.',
                path: kz
                    ? 'Еске салулар → Апта сайын'
                    : 'Напоминания → Еженедельные',
              ),
              _FeatureRow(
                icon: CupertinoIcons.alarm,
                title: kz ? 'Жүйелік будильник' : 'Системный будильник',
                description: kz
                    ? 'Қолдау көрсетілетін құрылғыларда намазға оятатын будильник бар. Таң намазы үшін қосымша «Қатты ұйқы» режимі бар.'
                    : 'На поддерживаемых устройствах можно поставить будильник на молитву. Для Фаджра есть режим «Крепкий сон».',
                path: kz
                    ? 'Еске салулар → Намаз уақыттары → Будильник'
                    : 'Напоминания → Времена молитв → Будильник',
              ),
            ],
          ),
          DauamSection(
            label: kz ? 'Құрылғы экранында' : 'На экране устройства',
            children: [
              _FeatureRow(
                icon: CupertinoIcons.square_grid_2x2,
                title: kz
                    ? 'Басты экран виджеттері'
                    : 'Виджеты на рабочем столе',
                description: kz
                    ? 'Келесі намаз бен кестені қолданбаны ашпай көріңіз. Жаңа күннің істері үшін Dauam-ды ашып, деректерді жаңартыңыз.'
                    : 'Смотрите следующий намаз и расписание без открытия приложения. Для дел нового дня откройте Дауам, чтобы обновить данные.',
                path: ios
                    ? (kz
                          ? 'Басты экранды басып тұрыңыз → виджеттерден Dauam-ды табыңыз'
                          : 'Удерживайте рабочий стол → найдите Дауам в виджетах')
                    : (kz
                          ? 'Басты экранды басып тұрыңыз → Виджеттер → Dauam'
                          : 'Удерживайте рабочий стол → Виджеты → Дауам'),
              ),
              if (ios)
                _FeatureRow(
                  icon: CupertinoIcons.lock,
                  title: kz
                      ? 'Бұғаттау экранының виджеттері'
                      : 'Виджеты экрана блокировки',
                  description: kz
                      ? 'Келесі уақытқа дейінгі санақты iPhone бұғаттау экранынан қараңыз.'
                      : 'Отсчёт до следующего времени можно видеть прямо на экране блокировки iPhone.',
                  path: kz
                      ? 'Бұғаттау экранын басып тұрыңыз → Баптау → Виджеттер'
                      : 'Удерживайте экран блокировки → Настроить → Виджеты',
                ),
              if (ios)
                _FeatureRow(
                  icon: CupertinoIcons.rectangle_3_offgrid,
                  title: 'Dynamic Island',
                  description: kz
                      ? 'Қолдау көрсетілетін iPhone-да, қосымша ашық болса, намазға 15 минут қалғанда санақ пайда болады. Зікір оқуды да көрсетуі мүмкін.'
                      : 'На поддерживаемом iPhone, когда приложение открыто, за 15 минут до молитвы появляется отсчёт. Также может отображаться чтение зикров.',
                  path: kz
                      ? 'iPhone баптауларында Live Activities-ке рұқсат беріңіз'
                      : 'Разрешите Live Activities в настройках iPhone',
                ),
              if (ios)
                _FeatureRow(
                  icon: CupertinoIcons.device_phone_portrait,
                  title: 'Apple Watch',
                  description: kz
                      ? 'Жұпталған сағатта келесі намазды, күн кестесін және істерді көріңіз; циферблатқа компликация қосуға болады.'
                      : 'На сопряжённых часах доступны следующий намаз, расписание и дела; на циферблат можно добавить компликацию.',
                  path: kz
                      ? 'iPhone-дағы Watch қолданбасынан Dauam-ды орнатыңыз'
                      : 'Установите Дауам через приложение Watch на iPhone',
                ),
              if (ios)
                _FeatureRow(
                  icon: CupertinoIcons.mic,
                  title: kz ? 'Siri және Командалар' : 'Siri и «Команды»',
                  description: kz
                      ? 'Келесі намазды сұраңыз немесе таңғы/кешкі зікірлерді дауыспен ашыңыз. Қолдау көрсетілетін iPhone-да команданы Action Button-ға тағайындауға болады.'
                      : 'Спросите о следующем намазе или откройте утренние/вечерние зикры голосом. На поддерживаемом iPhone команду можно назначить на Action Button.',
                  path: kz
                      ? 'iPhone-дағы «Командалар» → Dauam'
                      : 'Приложение «Команды» на iPhone → Дауам',
                ),
              if (android)
                _FeatureRow(
                  icon: CupertinoIcons.device_phone_portrait,
                  title: kz ? 'Android будильнигі' : 'Будильник Android',
                  description: kz
                      ? 'Дәл оятқыш толық экранда ашылады. Жұмысы үшін жүйелік рұқсаттар қажет.'
                      : 'Точный будильник открывается на весь экран. Для его работы нужны системные разрешения.',
                  path: kz
                      ? 'Еске салулар → Намаз уақыттары → Будильник'
                      : 'Напоминания → Времена молитв → Будильник',
                ),
            ],
          ),
          DauamSection(
            label: kz ? 'Өзіңізге бейімдеңіз' : 'Под себя',
            children: [
              _FeatureRow(
                icon: CupertinoIcons.paintbrush,
                title: kz
                    ? 'Басты экран көрінісі'
                    : 'Оформление главного экрана',
                description: kz
                    ? 'Мекке, Мәдина, Астана немесе дала көрінісін таңдаңыз. Намаз уақыттары өзгермейді.'
                    : 'Выберите Мекку, Медину, Астану или степь. Времена молитв останутся прежними.',
                path: kz ? 'Көрініс' : 'Раздел «Оформление»',
              ),
              _FeatureRow(
                icon: CupertinoIcons.globe,
                title: kz ? 'Қала және тіл' : 'Город и язык',
                description: kz
                    ? 'Намаз уақыты таңдалған қалаға қарай есептеледі. Көріністегі қала есепке әсер етпейді.'
                    : 'Времена молитв зависят от выбранного города. Город на картинке оформления на расчёт не влияет.',
                path: kz
                    ? 'Басты экрандағы қала · Тіл баптауы'
                    : 'Город на главном экране · настройка языка',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.path,
  });

  final IconData icon;
  final String title;
  final String description;
  final String path;

  @override
  Widget build(BuildContext context) {
    final c = dauamSettingsPalette(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: c.gold),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: JType.ui(15.5, w: FontWeight.w700, color: c.ink),
                ),
                const SizedBox(height: 5),
                Text(description, style: JType.ui(13, color: c.sub, h: 1.4)),
                const SizedBox(height: 6),
                Text(
                  path,
                  style: JType.ui(
                    12.5,
                    w: FontWeight.w600,
                    color: c.gold,
                    h: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

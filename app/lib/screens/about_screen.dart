import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/app_state.dart';
import '../theme/tokens.dart';
import 'settings_shell.dart';

const kContactEmail = 'muahhidun@gmail.com';
const kPrivacyUrl = 'https://muahhidun.github.io/Jadwal/privacy';

/// «О приложении»: откуда времена и тексты, как связаться, что с данными.
/// Для религиозного приложения доверие начинается с честных источников.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kz = app.lang == 'kz';
    final c = dauamSettingsPalette(context).colors;

    return DauamSettingsPage(
      title: kz ? 'Қосымша туралы' : 'О приложении',
      child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 18),
            child: Column(
              children: [
                Text('دوام', style: JType.arabic(40, color: c.gold)),
                const SizedBox(height: 2),
                Text(
                  kz ? 'Дауам' : 'Дауам',
                  style: JType.ui(22, w: FontWeight.w700, color: c.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  kz ? 'Ғибадат серігі' : 'Ассистент поклонения',
                  style: JType.ui(13.5, color: c.sub),
                ),
                const SizedBox(height: 4),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) => Text(
                    snap.hasData
                        ? (kz
                              ? 'Нұсқа ${snap.data!.version} (${snap.data!.buildNumber})'
                              : 'Версия ${snap.data!.version} (${snap.data!.buildNumber})')
                        : ' ',
                    style: JType.ui(12, color: c.faint),
                  ),
                ),
              ],
            ),
          ),
          DauamSection(
            label: kz ? 'Дереккөздер' : 'Источники',
            children: [
              _SourceRow(
                title: kz ? 'Намаз уақыттары' : 'Времена намазов',
                text: kz
                    ? 'Қазақстанда — ҚМДБ, muftyat.kz. Шетелде — Aladhan жергілікті есебі (сол елдің әдісі, ханафи мазхабы бойынша екінті).'
                    : 'В Казахстане — ДУМК, muftyat.kz. За границей — местный расчёт Aladhan (метод страны пребывания, Аср по ханафитскому мазхабу).',
              ),
              _SourceRow(
                title: kz ? 'Зікірлер' : 'Зикры',
                text: kz
                    ? '«Мұсылман қорғаны» жинағы. Әр зікірдің дереккөзі — хадис жинағы мен нөмірі — мәтін астында көрсетілген.'
                    : 'Сборник «Крепость мусульманина». Источник каждого зикра — сборник хадисов и номер — указан под текстом.',
              ),
              _SourceRow(
                title: kz ? '«әл-Кәһф» сүресі' : 'Сура аль-Кахф',
                text: kz
                    ? 'Мәтін мен қаріп: Quran.com / Quran Foundation, хафс мусхафы.'
                    : 'Текст и шрифт: Quran.com / Quran Foundation, мусхаф хафс.',
              ),
              _SourceRow(
                title: kz ? 'Тұрақтылық туралы хадис' : 'Хадис о постоянстве',
                text: kz
                    ? 'әл-Бухари, 6464 · Муслим, 783'
                    : 'аль-Бухари, 6464 · Муслим, 783',
              ),
              _SourceRow(
                title: kz ? 'Құбыла картасы' : 'Карта Киблы',
                text: kz
                    ? '© OpenStreetMap қатысушылары'
                    : '© участники OpenStreetMap',
              ),
              _SourceRow(
                title: kz ? 'Азан' : 'Азан',
                text: kz
                    ? 'Әл-Харам мешітіндегі ақшам азаны, 25.02.2012 — жазба: 3omar Faruq, CC BY 3.0 (Wikimedia Commons). Қосымшада — басы, 30 секунд.'
                    : 'Азан магриба в Масджид аль-Харам, 25.02.2012 — запись: 3omar Faruq, CC BY 3.0 (Wikimedia Commons). В приложении — начало, 30 секунд.',
              ),
              _SourceRow(
                title: kz ? 'Қаріптер' : 'Шрифты',
                text: 'Manrope, Inter, Literata, Amiri — SIL Open Font License',
              ),
            ],
          ),
          DauamSection(
            label: kz ? 'Байланыс' : 'Связь',
            footer: kz
                ? 'Қате, ұсыныс немесе дереккөз туралы сұрақ болса — жазыңыз.'
                : 'Нашли ошибку, есть предложение или вопрос об источнике — напишите.',
            children: [
              DauamSettingsRow(
                icon: CupertinoIcons.mail,
                title: kz ? 'Авторға жазу' : 'Написать автору',
                value: kContactEmail,
                trailing: Icon(
                  CupertinoIcons.doc_on_doc,
                  size: 16,
                  color: c.faint,
                ),
                onTap: () => _copy(
                  context,
                  kContactEmail,
                  kz ? 'Пошта көшірілді' : 'Адрес скопирован',
                ),
              ),
            ],
          ),
          DauamSection(
            label: kz ? 'Құпиялылық' : 'Конфиденциальность',
            footer: kz
                ? 'Жарнамасыз, тіркеусіз, деректер жинамайды. Барлық белгілер мен баптаулар тек телефоныңызда сақталады.'
                : 'Без рекламы, без регистрации, без сбора данных. Все отметки и настройки хранятся только на вашем телефоне.',
            children: [
              DauamSettingsRow(
                icon: CupertinoIcons.lock_shield,
                title: kz
                    ? 'Құпиялылық саясаты'
                    : 'Политика конфиденциальности',
                onTap: () => Navigator.of(
                  context,
                ).push(dauamSettingsRoute(const PrivacyScreen())),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _copy(BuildContext context, String text, String done) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(done),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.title, required this.text});

  final String title, text;

  @override
  Widget build(BuildContext context) {
    final c = dauamSettingsPalette(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: JType.ui(14.5, w: FontWeight.w600, color: c.ink),
          ),
          const SizedBox(height: 3),
          Text(text, style: JType.ui(13, color: c.sub, h: 1.35)),
        ],
      ),
    );
  }
}

/// Политика конфиденциальности — тот же текст, что опубликован по адресу
/// [kPrivacyUrl] (его требуют App Store и Google Play).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final kz = AppScope.of(context).lang == 'kz';
    final c = dauamSettingsPalette(context).colors;
    final blocks = kz ? _privacyKz : _privacyRu;
    return DauamSettingsPage(
      title: kz ? 'Құпиялылық' : 'Конфиденциальность',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
        children: [
          for (final (heading, body) in blocks) ...[
            if (heading.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                heading.toUpperCase(),
                style: JType.caption(c.gold, size: 11),
              ),
              const SizedBox(height: 6),
            ],
            Text(body, style: JType.ui(14, color: c.ink, h: 1.5)),
          ],
          const SizedBox(height: 18),
          Text(kPrivacyUrl, style: JType.ui(12, color: c.faint)),
        ],
      ),
    );
  }
}

const _privacyRu = [
  (
    '',
    'Дауам не собирает персональные данные. В приложении нет регистрации, '
        'рекламы и аналитики, а у разработчика нет сервера, куда что-либо '
        'отправлялось бы.',
  ),
  (
    'Что хранится на телефоне',
    'Выбранный город, язык, оформление, напоминания и отметки о выполненных '
        'делах хранятся только на вашем устройстве и, если вы пользуетесь ими, '
        'на ваших Apple Watch и в виджетах. Удаление приложения удаляет эти '
        'данные.',
  ),
  (
    'Геопозиция',
    'С вашего разрешения приложение использует геопозицию на самом '
        'устройстве: чтобы предложить ближайший город и показать направление '
        'Киблы. Координаты не передаются разработчику.',
  ),
  (
    'Какие запросы уходят в интернет',
    '• Времена намазов загружаются с api.muftyat.kz по координатам выбранного '
        'города из справочника ДУМК, а не по вашим точным координатам.\n'
        '• Когда приложение замечает, что вы за пределами Казахстана, '
        'координаты места, округлённые примерно до километра, отправляются в '
        'nominatim.openstreetmap.org — чтобы назвать место. Если вы '
        'согласитесь на местный расчёт — ещё и в api.aladhan.com за '
        'временами намаза.\n'
        '• Карта Киблы загружает фрагменты карты с серверов OpenStreetMap: '
        'они видят IP-адрес и район карты, который открывается.\n'
        '• Сура аль-Кахф встроена в приложение; к api.quran.com и '
        'quran.foundation она обращается, только если встроенные файлы '
        'недоступны.\n'
        'Эти сервисы обрабатывают запросы по своим правилам.',
  ),
  (
    'Уведомления',
    'Напоминания создаются и планируются на самом телефоне. Push-серверы '
        'не используются.',
  ),
  ('Связь', 'Вопросы о данных и приложении: $kContactEmail'),
  ('', 'Редакция от 30 сентября 2026 года.'),
];

const _privacyKz = [
  (
    '',
    'Дауам жеке деректерді жинамайды. Қосымшада тіркелу, жарнама және '
        'аналитика жоқ, әзірлеушінің ештеңе жіберілетін сервері де жоқ.',
  ),
  (
    'Телефонда не сақталады',
    'Таңдалған қала, тіл, көрініс, еске салулар мен орындалған істердің '
        'белгілері тек құрылғыңызда, ал қолдансаңыз — Apple Watch пен '
        'виджеттерде сақталады. Қосымшаны өшірсеңіз, бұл деректер де өшеді.',
  ),
  (
    'Геолокация',
    'Рұқсатыңызбен қосымша геолокацияны құрылғының өзінде қолданады: ең '
        'жақын қаланы ұсыну және Құбыла бағытын көрсету үшін. Координаттар '
        'әзірлеушіге жіберілмейді.',
  ),
  (
    'Интернетке қандай сұраулар кетеді',
    '• Намаз уақыттары api.muftyat.kz сайтынан ҚМДБ анықтамалығындағы '
        'таңдалған қаланың координаттары бойынша жүктеледі, сіздің нақты '
        'координаттарыңыз бойынша емес.\n'
        '• Қосымша сіздің Қазақстаннан тыс екеніңізді байқаса, шамамен бір '
        'километрге дейін дөңгелектенген орын координаттары орынның атауын '
        'білу үшін nominatim.openstreetmap.org сайтына жіберіледі. Жергілікті '
        'есепке келіссеңіз — намаз уақыттары үшін api.aladhan.com сайтына да.\n'
        '• Құбыла картасы карта бөліктерін OpenStreetMap серверлерінен '
        'жүктейді: олар IP-мекенжайды және ашылған аймақты көреді.\n'
        '• «әл-Кәһф» сүресі қосымшаға енгізілген; api.quran.com мен '
        'quran.foundation сайттарына тек ішкі файлдар қолжетімсіз болса ғана '
        'жүгінеді.\n'
        'Бұл қызметтер сұрауларды өз ережелері бойынша өңдейді.',
  ),
  (
    'Хабарламалар',
    'Еске салулар телефонның өзінде жасалады және жоспарланады. Push-серверлер '
        'қолданылмайды.',
  ),
  ('Байланыс', 'Деректер мен қосымша туралы сұрақтар: $kContactEmail'),
  ('', '2026 жылғы 30 қыркүйектегі редакция.'),
];

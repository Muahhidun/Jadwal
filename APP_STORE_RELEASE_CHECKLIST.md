# Dauam — подготовка к TestFlight и App Store

Актуально на 24.08.2026. Этот файл фиксирует только подготовку публикации;
рабочая очередь стабилизации остаётся в `TECHNICAL_AUDIT_2026-07-28.md`.

## Уже готово

- Активная индивидуальная Apple Developer Team: `ZV5872VU8H`.
- Основной Bundle ID: `kz.dauam`; отдельно настроены iPhone WidgetKit,
  Apple Watch и Watch Widgets.
- Версия проекта: `1.0.0`, текущий build: `6`.
- Подписанные device-сборки iPhone/Watch ранее устанавливались на физические
  устройства; текущая release-сборка всех target-ов воспроизводима.
- Есть исходник политики конфиденциальности: `privacy.html`.
- Приложение не содержит рекламы, аналитики, аккаунтов и серверного хранилища
  пользовательских данных.
- В каждый собственный исполняемый пакет добавлен `PrivacyInfo.xcprivacy`:
  Runner, iPhone WidgetKit, Watch app и Watch Widgets. Доступ к общему
  `UserDefaults` объявлен причиной App Group `1C8F.1`; сбор данных и tracking
  не заявлены.
- В `Info.plist` указано `ITSAppUsesNonExemptEncryption = NO`: приложение
  использует только системный HTTPS/TLS и не содержит собственной криптографии.

## Ближайший безопасный этап — внутренний TestFlight

1. Создать карточку приложения в App Store Connect, если её ещё нет:
   название `Dauam`, Bundle ID `kz.dauam`, основной язык и SKU.
2. Опубликовать `privacy.html` как обычную HTTPS-страницу. GitHub Pages
   подходит; ссылка на файл внутри интерфейса GitHub хуже подходит как
   пользовательская страница.
3. Выбрать публичный email поддержки и подготовить Support URL с реальными
   контактами.
4. Заполнить App Privacy: «данные не собираются», если это остаётся верно
   после финальной проверки всех зависимостей.
5. Подготовить TestFlight-текст: краткое описание, «что тестировать», email
   обратной связи и заметки для ревьюера.
6. Увеличить build number, собрать Archive/IPA с distribution-подписью,
   выполнить Validate App и только затем загрузить build.
7. Создать Internal Testing group и сначала проверить полный цикл установки
   iPhone + Watch + widgets через TestFlight.

## До внешней беты / публичного релиза

- **Блокер:** владелец/специалист должен утвердить 39 религиозных текстов,
  транслитерации, переводы и источники. Сейчас контент остаётся черновиком.
- Закрыть P0 по длительности и реальной доставке очереди уведомлений; отдельно
  провести многодневный тест без ежедневного открытия приложения.
- Провести финальный языковой проход RU/KZ, включая Siri, Live Activity,
  системные разрешения и тексты Watch.
- Подготовить локализованные название, подзаголовок, описание, ключевые слова,
  категорию, возрастной рейтинг, copyright и App Review notes.
- Подготовить 1–10 App Store screenshots без прозрачности. Для iPhone нужен
  комплект актуального большого формата; если приложение остаётся доступным
  для iPad, нужен также iPad-комплект либо решение ограничить target iPhone.
- Проверить на чистой установке: онбординг, отказ от геолокации, ручной город,
  уведомления, AlarmKit, Live Activity, iPhone widgets, Watch app и
  complications.
- Финально проверить, что production build не сбрасывает онбординг и не
  содержит тестовых/placeholder-данных.

## Официальные ориентиры Apple

- Upload builds: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- TestFlight: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview
- App Privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- Screenshots: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- Privacy manifests: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files

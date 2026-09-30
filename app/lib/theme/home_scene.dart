/// Художественная тема главного экрана. Она намеренно не зависит от города,
/// выбранного для расчёта времён молитв.
enum HomeScene {
  mecca,
  medina,
  astana,
  steppe,
  minimal;

  static HomeScene fromStorage(String? value) => switch (value) {
    'medina' => HomeScene.medina,
    'astana' => HomeScene.astana,
    'steppe' => HomeScene.steppe,
    // «Природа» убрана — по сути это та же степь.
    'nature' => HomeScene.steppe,
    // Убранный вариант не должен оставаться выбранным у прежних пользователей.
    'minimal' => HomeScene.mecca,
    _ => HomeScene.mecca,
  };

  String get storageValue => name;

  /// Фото-тема: картинки владельца по времени суток в assets/images/themes.
  bool get isPhoto => photoSlots.isNotEmpty;

  /// Астана использует один геометрически неизменный дневной кадр: отдельные
  /// генерации давали двойные контуры. В Мекке и Медине кадры выверены по
  /// общему размеру и меняются вместе с освещением неба.
  List<String> get photoSlots => switch (this) {
    HomeScene.astana => const ['day'],
    HomeScene.mecca ||
    HomeScene.medina ||
    HomeScene.steppe => const ['sunrise', 'day', 'sunset', 'night'],
    _ => const [],
  };

  String photoAsset(String slot) => 'assets/images/themes/${name}_$slot.webp';

  /// Ширина кадра относительно экрана. Мечеть Хазрет Султан на кадре
  /// небольшая — крупнее, края с деревьями уходят за экран.
  double get photoZoom => switch (this) {
    HomeScene.astana => 1.45,
    HomeScene.medina || HomeScene.mecca => 1.0,
    HomeScene.steppe => 1.2,
    _ => 1.08,
  };
}

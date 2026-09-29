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
    'minimal' => HomeScene.minimal,
    _ => HomeScene.mecca,
  };

  String get storageValue => name;

  /// Фото-тема: картинки владельца по времени суток в assets/images/themes.
  bool get isPhoto => photoSlots.isNotEmpty;

  /// Какие варианты по времени суток есть у темы. У Астаны восход и закат
  /// пока рисуются из дня тёплым светом: присланные кадры отличаются по
  /// композиции, и при плавной смене мечеть двоилась бы.
  List<String> get photoSlots => switch (this) {
    HomeScene.medina ||
    HomeScene.steppe => const ['sunrise', 'day', 'sunset', 'night'],
    HomeScene.astana => const ['day', 'night'],
    _ => const [],
  };

  String photoAsset(String slot) => 'assets/images/themes/${name}_$slot.webp';

  /// Ширина кадра относительно экрана. Мечеть Хазрет Султан на кадре
  /// небольшая — крупнее, края с деревьями уходят за экран.
  double get photoZoom => switch (this) {
    HomeScene.astana => 1.45,
    HomeScene.steppe => 1.2,
    _ => 1.08,
  };
}

/// Une langue sélectionnable — préférence personnelle, locale à l'appareil
/// (comme le thème), pas partagée via la Box.
class AppLocale {
  final String code;
  final String name;
  final String flag;

  const AppLocale({required this.code, required this.name, required this.flag});

  static const fr = AppLocale(code: 'fr', name: 'Français', flag: '🇫🇷');
  static const en = AppLocale(code: 'en', name: 'English', flag: '🇬🇧');
  static const de = AppLocale(code: 'de', name: 'Deutsch', flag: '🇩🇪');
  static const es = AppLocale(code: 'es', name: 'Español', flag: '🇪🇸');
  static const zh = AppLocale(code: 'zh', name: '中文', flag: '🇨🇳');
  static const ar = AppLocale(code: 'ar', name: 'العربية', flag: '🇸🇦');
  static const id = AppLocale(
    code: 'id',
    name: 'Bahasa Indonesia',
    flag: '🇮🇩',
  );
  static const ru = AppLocale(code: 'ru', name: 'Русский', flag: '🇷🇺');
  static const pt = AppLocale(code: 'pt', name: 'Português', flag: '🇵🇹');
  static const tr = AppLocale(code: 'tr', name: 'Türkçe', flag: '🇹🇷');
  static const uk = AppLocale(code: 'uk', name: 'Українська', flag: '🇺🇦');
  static const ja = AppLocale(code: 'ja', name: '日本語', flag: '🇯🇵');

  static const all = <AppLocale>[
    fr,
    en,
    de,
    es,
    zh,
    ar,
    id,
    ru,
    pt,
    tr,
    uk,
    ja,
  ];

  static const defaultLocale = fr;

  static AppLocale byCode(String code) =>
      all.firstWhere((l) => l.code == code, orElse: () => defaultLocale);
}

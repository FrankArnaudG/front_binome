import '../shop/subscription_status_notifier.dart';

/// Un tome d'une [RomanPhotoStory] — une suite ordonnée de pages déjà
/// composées (bulles de dialogue incrustées, gérées depuis l'espace admin)
/// plutôt que du texte géré par l'app. Voir RomanPhotoReaderScreen.
class RomanPhotoVolume {
  final String id;
  final Map<String, String> title;
  final List<String> pageAssets;
  // Réglable tome par tome depuis l'espace admin — 0 = gratuit. Juste la
  // donnée + le badge pour l'instant, aucun vrai débit ni verrouillage à
  // l'ouverture.
  final int coinPrice;
  // Vrai si déjà payé pour la Box de qui consulte (voir
  // RomanPhotoVolume::isPurchasedByBox côté backend, partagé par tout le
  // couple) — toujours vrai pour un tome gratuit. Absent (donc `false` par
  // défaut) tant que le détail complet n'a pas été chargé (voir
  // RomanPhotoService.fetchStoryDetail), sans conséquence : la liste légère
  // de l'étagère n'a jamais besoin de cette info.
  final bool purchased;

  const RomanPhotoVolume({
    required this.id,
    required this.title,
    required this.pageAssets,
    this.coinPrice = 0,
    this.purchased = false,
  });

  bool get isFree => coinPrice == 0;

  /// Faut-il confirmer un achat avant de proposer le téléchargement ? (voir
  /// demande utilisateur : "pour les bd payant, il faut d'abord confirmer
  /// l'achat et ensuite télécharger"). Un abonnement actif donne un accès
  /// illimité et gratuit (voir RomanPhotoPurchaseController côté backend,
  /// aucun débit pour un abonné) — jamais besoin de confirmer un achat ni
  /// d'afficher le moindre prix dans ce cas (voir demande utilisateur :
  /// "si c'est la formule abonnement... rien ne doit apparaître").
  bool get needsPurchase => !isFree && !purchased && !SubscriptionStatusNotifier.instance.isActive;

  String titleFor(String localeCode) {
    if (title.containsKey(localeCode)) return title[localeCode]!;
    if (title.containsKey('fr')) return title['fr']!;
    return title.values.isNotEmpty ? title.values.first : '';
  }

  factory RomanPhotoVolume.fromJson(Map<String, dynamic> json) => RomanPhotoVolume(
        id: json['id'] as String,
        title: _localeMap(json['title']),
        pageAssets: (json['page_assets'] as List).map((e) => e as String).toList(),
        coinPrice: json['coin_price'] as int? ?? 0,
        purchased: json['purchased'] as bool? ?? false,
      );
}

/// Une histoire de la bibliothèque Roman-Photo — un ou plusieurs tomes déjà
/// sortis, plus éventuellement un tome à venir en teaser (voir
/// [comingSoon]). Le rayon de la bibliothèque (RomanPhotoLibraryScreen)
/// affiche une couverture par histoire, pas par tome. Gérée entièrement
/// depuis l'espace admin (voir RomanPhotoStoryController côté backend).
class RomanPhotoStory {
  final String id;
  final Map<String, String> title;
  // Tomes déjà sortis — peut être vide pour une histoire qui n'existe
  // encore qu'en teaser (voir comingSoon), mais aussi TOUJOURS vide tant que
  // seule l'étagère a été chargée (voir RomanPhotoService.fetchLibraryPage,
  // qui ne renvoie que la couverture) — RomanPhotoService.fetchStoryDetail
  // les remplit à l'ouverture d'une histoire précise.
  final List<RomanPhotoVolume> volumes;
  // Couverture/nombre de tomes/prix du tome unique tels que renvoyés par la
  // liste paginée légère (voir RomanPhotoController::index) — utilisés par
  // RomanPhotoLibraryScreen._BookTile SANS avoir à charger `volumes`.
  // `null` une fois le détail complet chargé (coverAsset/volumes.length
  // prennent le relais, voir plus bas).
  final String? cover;
  final int? volumesCount;
  final int? firstVolumePrice;
  // Badge "Nouveau" (voir espace admin) — affiché sur l'étagère UNIQUEMENT
  // si aucun tome de cette histoire n'a déjà été téléchargé sur CET
  // appareil (voir RomanPhotoLibraryScreen._BookTile, vérifié localement via
  // RomanPhotoLocalDb, jamais depuis ce champ seul).
  final bool isNew;
  // Un tome à venir, en plus des tomes déjà sortis (ou à la place, si
  // `volumes` est vide) — une ligne de plus dans le choix du tome (voir
  // _VolumePickerScreen) plutôt qu'un livre à part. Au clic sur cette
  // ligne, montre `teaserImages`/`teaserText` au lieu d'ouvrir un lecteur.
  final bool comingSoon;
  // Nom de cette ligne "à venir" — jamais générique ("Tome N"), un vrai
  // titre qui donne envie.
  final Map<String, String>? teaserTitle;
  // Une ou plusieurs images.
  final List<String> teaserImages;
  final Map<String, String>? teaserText;

  const RomanPhotoStory({
    required this.id,
    required this.title,
    this.volumes = const [],
    this.cover,
    this.volumesCount,
    this.firstVolumePrice,
    this.isNew = false,
    this.comingSoon = false,
    this.teaserTitle,
    this.teaserImages = const [],
    this.teaserText,
  });

  /// Nombre de tomes sortis — depuis `volumesCount` (liste légère, voir
  /// fetchLibraryPage) tant que le détail complet n'a pas été chargé, sinon
  /// depuis `volumes.length` (toujours à jour une fois le détail chargé).
  int get volumeCountResolved => volumes.isNotEmpty ? volumes.length : (volumesCount ?? 0);

  /// Vrai seulement pour une histoire qui n'a encore aucun tome sorti — le
  /// livre entier n'est alors qu'un teaser (voir RomanPhotoLibraryScreen.
  /// _openStory/_BookTile, bandeau "Bientôt" sur toute la couverture).
  bool get isTeaserOnly => volumeCountResolved == 0 && comingSoon;

  /// Couverture de l'histoire — le champ `cover` déjà résolu côté backend
  /// (liste légère) prime ; sinon calculée depuis le détail complet
  /// (première page du premier tome sorti, ou première image teaser si
  /// aucun tome n'est encore sorti).
  String get coverAsset {
    if (cover != null) return cover!;
    return volumes.isNotEmpty ? volumes.first.pageAssets.first : teaserImages.first;
  }

  String titleFor(String localeCode) {
    if (title.containsKey(localeCode)) return title[localeCode]!;
    if (title.containsKey('fr')) return title['fr']!;
    return title.values.isNotEmpty ? title.values.first : '';
  }

  String? teaserTitleFor(String localeCode) => teaserTitle?[localeCode] ?? teaserTitle?['fr'];

  String? teaserTextFor(String localeCode) => teaserText?[localeCode] ?? teaserText?['fr'];

  factory RomanPhotoStory.fromJson(Map<String, dynamic> json) => RomanPhotoStory(
        id: json['id'] as String,
        title: _localeMap(json['title']),
        volumes: ((json['volumes'] as List?) ?? [])
            .map((e) => RomanPhotoVolume.fromJson(e as Map<String, dynamic>))
            .toList(),
        cover: json['cover'] as String?,
        volumesCount: json['volumes_count'] as int?,
        firstVolumePrice: json['price'] as int?,
        isNew: json['is_new'] as bool? ?? false,
        comingSoon: json['coming_soon'] as bool? ?? false,
        teaserTitle: json['teaser_title'] != null ? _localeMap(json['teaser_title']) : null,
        teaserImages: ((json['teaser_images'] as List?) ?? []).map((e) => e as String).toList(),
        teaserText: json['teaser_text'] != null ? _localeMap(json['teaser_text']) : null,
      );
}

Map<String, String> _localeMap(dynamic value) => (value as Map).map((k, v) => MapEntry(k as String, v as String));

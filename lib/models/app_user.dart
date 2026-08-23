class AppUser {
  final String id;
  final String name;
  final String prenom;
  final String email;
  final String? avatar;
  final String? provider;
  final String? themeId;
  final String? preferredCurrency;
  final String? gender;
  final String? country;
  // Petits noms que la personne se donne (voir CoupleProfileScreen) — ex.
  // ["Chouééé", "Bbé"], vide si jamais renseigné.
  final List<String> loveName;
  // Dernière requête authentifiée (voir TouchLastSeen côté backend) —
  // "vu·e il y a X" quand la présence temps réel ne montre pas cette
  // personne en ligne (voir GameCardThreadScreen).
  final DateTime? lastSeenAt;

  const AppUser({
    required this.id,
    required this.name,
    required this.prenom,
    required this.email,
    this.avatar,
    this.provider,
    this.themeId,
    this.preferredCurrency,
    this.gender,
    this.country,
    this.loveName = const [],
    this.lastSeenAt,
  });

  /// Un compte Google n'a pas de mot de passe local — "Changer le mot de
  /// passe" et la confirmation par mot de passe à la suppression du compte
  /// n'ont pas de sens pour ces comptes (voir ProfileController côté
  /// backend, qui applique la même règle).
  bool get isGoogleAccount => provider == 'google';

  /// Aucun des deux flux d'inscription (Google, classique) ne collecte
  /// genre/pays — et un compte Google peut arriver avec un nom fantaisiste
  /// (voir AuthenticationController::loginWithGoogle). Tant que ces champs
  /// ne sont pas renseignés, AppRouter.routeAfterAuth bloque sur l'écran de
  /// complétion de profil avant de laisser entrer dans l'app.
  bool get needsProfileCompletion =>
      prenom.trim().isEmpty ||
      name.trim().isEmpty ||
      (gender == null || gender!.trim().isEmpty) ||
      (country == null || country!.trim().isEmpty);

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        prenom: json['prenom'] as String? ?? '',
        email: json['email'] as String? ?? '',
        avatar: json['avatar'] as String?,
        provider: json['provider'] as String?,
        themeId: json['theme_id'] as String?,
        preferredCurrency: json['preferred_currency'] as String?,
        gender: json['gender'] as String?,
        country: json['country'] as String?,
        loveName: (json['love_name'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        lastSeenAt: json['last_seen_at'] != null ? DateTime.parse(json['last_seen_at'] as String) : null,
      );
}

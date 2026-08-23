class Gift {
  final String id;
  final String name;
  final String? description;
  final String category; // romantic | sweet | jewelry | luxury | cute | special
  final String? iconPath;
  final int coinPrice;
  final String status; // active | inactive

  const Gift({
    required this.id,
    required this.name,
    this.description,
    required this.category,
    this.iconPath,
    required this.coinPrice,
    required this.status,
  });

  /// Cadeau spécial généré en direct (animation "Quantum Love") plutôt
  /// qu'une simple icône statique — voir QuantumLoveHeart. Identifié par
  /// mot-clé du nom plutôt qu'un nouveau champ backend, pour rester
  /// additif et ne rien changer aux cadeaux existants.
  bool get isQuantumLoveHeart => name.toLowerCase().contains('quantique');

  /// Second cadeau généré en direct : un cœur fixe qui se dessine trait
  /// par trait au crayon — voir SketchedLoveHeart. Même principe de
  /// détection additive par mot-clé que [isQuantumLoveHeart].
  bool get isSketchedHeart => name.toLowerCase().contains('esquiss');

  /// Troisième cadeau généré en direct : une rose vectorielle qui éclot —
  /// voir EternalRose. Le mot-clé exige "éternelle" en plus de "rose" pour
  /// ne pas se déclencher sur les cadeaux statiques existants comme
  /// "Bouquet de roses".
  bool get isEternalRose {
    final n = name.toLowerCase();
    return n.contains('rose') && (n.contains('éternelle') || n.contains('eternelle'));
  }

  /// Quatrième cadeau généré en direct : une rose noire positionnée en
  /// vraie 3D, pilotable au doigt — voir RealisticBlackRose. Mot-clé
  /// "noire"/"noir" en plus de "rose" pour ne pas se confondre avec les
  /// autres roses (statiques ou "Éternelle").
  bool get isBlackRose {
    final n = name.toLowerCase();
    return n.contains('rose') && (n.contains('noire') || n.contains('noir'));
  }

  /// Cinquième cadeau généré en direct : un cœur en 3D composé de mots
  /// d'amour, glissable au doigt — voir WordHeart. Mot-clé "mots" pour ne
  /// pas se confondre avec les autres cœurs (Quantum Love, Esquissé).
  bool get isWordHeart => name.toLowerCase().contains('mots');

  factory Gift.fromJson(Map<String, dynamic> json) => Gift(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        category: json['category'] as String? ?? 'romantic',
        iconPath: json['icon_path'] as String?,
        coinPrice: json['coin_price'] as int,
        status: json['status'] as String,
      );
}

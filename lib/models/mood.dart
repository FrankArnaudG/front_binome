/// "Notre Humeur du Jour" — check-in quotidien d'une personne du couple :
/// humeur (obligatoire) + besoin et envie du jour (facultatifs), chacun une
/// clé fixe (voir MoodController côté backend) plutôt que du texte libre.
class Mood {
  final String id;
  final String boxId;
  final String userId;
  final DateTime moodDate;
  final String moodKey;
  final String? needKey;
  final String? desireKey;

  const Mood({
    required this.id,
    required this.boxId,
    required this.userId,
    required this.moodDate,
    required this.moodKey,
    this.needKey,
    this.desireKey,
  });

  factory Mood.fromJson(Map<String, dynamic> json) => Mood(
        id: json['id'] as String,
        boxId: json['box_id'] as String,
        userId: json['user_id'] as String,
        moodDate: DateTime.parse(json['mood_date'] as String),
        moodKey: json['mood_key'] as String,
        needKey: json['need_key'] as String?,
        desireKey: json['desire_key'] as String?,
      );
}

/// Conseil/défi personnalisé pour une combinaison humeur+besoin+envie (voir
/// MoodController::suggestionFor côté backend) — `null` si aucune
/// suggestion n'existe pour cette combinaison.
class MoodSuggestion {
  final String? proposition;
  final String solution;

  const MoodSuggestion({this.proposition, required this.solution});

  factory MoodSuggestion.fromJson(Map<String, dynamic> json) => MoodSuggestion(
        proposition: json['proposition'] as String?,
        solution: json['solution'] as String,
      );
}

/// Liste fermée des humeurs proposées (voir MoodController::MOOD_KEYS côté
/// backend — les deux listes doivent rester synchronisées). Chacune existe
/// en illustration homme/femme (voir [moodAssetPath]).
const List<String> kMoodKeys = [
  'happy', 'loving', 'calm', 'tired', 'stressed',
  'sad', 'angry', 'excited', 'worried', 'serene',
];

/// Voir MoodController::NEED_KEYS côté backend.
const List<String> kNeedKeys = [
  'loved', 'affection', 'listened', 'talk',
  'reassured', 'supported', 'time_together', 'laugh_together',
  'play_together', 'romantic_moment', 'rest', 'calm_down',
  'space', 'encouraged', 'surprise', 'other',
];

/// Voir MoodController::DESIRE_KEYS côté backend.
const List<String> kDesireKeys = [
  'movie', 'call', 'sweet_word', 'romantic_evening',
  'dinner', 'music', 'photos', 'game',
  'laugh', 'projects', 'adventure', 'walk',
  'dance', 'no_phone', 'surprise_me', 'other',
];

/// Libellés courts affichés sous les cercles de choix (voir MoodScreen) —
/// le texte complet reste dans l'image elle-même, mais un cercle recadré
/// sur le visage n'en montre plus assez pour rester lisible seul. Accordés
/// au genre du profil (voir [moodLabel]/[needLabel]) plutôt qu'une forme
/// neutre "·e", puisqu'on connaît déjà le genre du·de la titulaire du compte.
const Map<String, String> kMoodLabelsM = {
  'happy': 'Heureux',
  'loving': 'Amoureux',
  'calm': 'Calme',
  'tired': 'Fatigué',
  'stressed': 'Stressé',
  'sad': 'Triste',
  'angry': 'En colère',
  'excited': 'Excité',
  'worried': 'Inquiet',
  'serene': 'Serein',
};

const Map<String, String> kMoodLabelsF = {
  'happy': 'Heureuse',
  'loving': 'Amoureuse',
  'calm': 'Calme',
  'tired': 'Fatiguée',
  'stressed': 'Stressée',
  'sad': 'Triste',
  'angry': 'En colère',
  'excited': 'Excitée',
  'worried': 'Inquiète',
  'serene': 'Sereine',
};

/// Base neutre — utilisée telle quelle pour les clés sans accord de genre
/// (ex. "Parler", "Me reposer"). Les 4 clés qui s'accordent ("aimé(e)",
/// "écouté(e)", "soutenu(e)", "encouragé(e)") sont ici en forme masculine ;
/// [kNeedLabelsFemale] fournit leur variante féminine.
const Map<String, String> kNeedLabels = {
  'loved': 'Être aimé',
  'affection': "Recevoir de l'affection",
  'listened': 'Être écouté',
  'talk': 'Parler',
  'reassured': 'Être rassuré(e)',
  'supported': 'Être soutenu',
  'time_together': 'Passer du temps ensemble',
  'laugh_together': 'Rire ensemble',
  'play_together': 'Jouer ensemble',
  'romantic_moment': 'Un moment romantique',
  'rest': 'Me reposer',
  'calm_down': 'Avoir un peu de calme',
  'space': 'Avoir mon espace',
  'encouraged': 'Être encouragé',
  'surprise': 'Une petite surprise',
  'other': 'Autre besoin',
};

const Map<String, String> kNeedLabelsFemale = {
  'loved': 'Être aimée',
  'listened': 'Être écoutée',
  'supported': 'Être soutenue',
  'encouraged': 'Être encouragée',
};

const Map<String, String> kDesireLabels = {
  'movie': 'Regarder un film ensemble',
  'call': 'Un appel rien que nous deux',
  'sweet_word': 'Un petit mot doux',
  'romantic_evening': 'Une soirée romantique à la maison',
  'dinner': 'Un dîner rien que nous deux',
  'music': 'Écouter nos musiques préférées',
  'photos': 'Faire des photos de nous',
  'game': 'Jouer à un petit jeu à deux',
  'laugh': 'Faire quelque chose qui nous fera rire',
  'projects': 'Parler de nos projets',
  'adventure': 'Rêver de notre prochaine aventure',
  'walk': 'Faire une petite balade ensemble',
  'dance': 'Danser ensemble',
  'no_phone': 'Un moment sans téléphone, juste nous deux',
  'surprise_me': 'Me laisser surprendre',
  'other': 'Une autre envie',
};

/// Illustration d'une humeur — voir demande utilisateur : une image dessinée
/// par clé, en version homme/femme selon le genre du profil (voir
/// AppUser.gender, déjà utilisé ainsi dans game_card_widgets.dart : `==
/// 'Femme'`, sinon version homme par défaut).
String moodAssetPath(String moodKey, String? gender) {
  final genderPrefix = gender == 'Femme' ? 'f' : 'm';
  return 'assets/humeur/${genderPrefix}_$moodKey.png';
}

String moodLabel(String moodKey, String? gender) {
  final labels = gender == 'Femme' ? kMoodLabelsF : kMoodLabelsM;
  return labels[moodKey] ?? moodKey;
}

String needLabel(String needKey, String? gender) {
  if (gender == 'Femme' && kNeedLabelsFemale.containsKey(needKey)) {
    return kNeedLabelsFemale[needKey]!;
  }
  return kNeedLabels[needKey] ?? needKey;
}

/// Besoins "personnels" (voir demande utilisateur) — illustrés par une
/// scène solo, en version homme/femme selon le genre du profil, comme pour
/// [moodAssetPath]. Les autres clés de [kNeedKeys] sont des besoins
/// relationnels illustrés par une scène de couple, une seule image quel que
/// soit le genre (voir [needAssetPath]).
const Set<String> kGenderedNeedKeys = {
  'loved', 'affection', 'listened', 'talk',
  'supported', 'rest', 'calm_down', 'encouraged',
  'surprise', 'other',
};

String needAssetPath(String needKey, String? gender) {
  if (kGenderedNeedKeys.contains(needKey)) {
    final genderPrefix = gender == 'Femme' ? 'f' : 'm';
    return 'assets/besoin/${genderPrefix}_$needKey.png';
  }
  return 'assets/besoin/$needKey.png';
}

String desireAssetPath(String desireKey) => 'assets/envi/$desireKey.png';

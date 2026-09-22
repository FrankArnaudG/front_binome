/// Identité portée par le nom Nearby Connections (voir demande utilisateur : "il faut s'assurer que
/// dès que je veux défier un ami... le téléphone ne doit pas se connecter à mon binôme car il ne
/// correspond pas à l'identité recherchée"). Avant, seul le prénom était diffusé — n'importe quel
/// appareil trouvé était accepté sans vérifier qui il était réellement ("confiance de couple", voir
/// memory_game_nearby_connect_screen.dart). Chaque téléphone diffuse désormais aussi son identifiant de
/// compte, et n'accepte une connexion QUE si cet identifiant correspond exactement à la personne
/// recherchée (son binôme, ou l'ami précis choisi avant de lancer la recherche) — tout le reste est
/// ignoré, même si l'application tourne au même moment sur l'appareil trouvé.
///
/// Limite assumée : ce n'est PAS une preuve infalsifiable (pas de code secret à saisir, comme le reste
/// du mode "présentiel connecté") — un appareil physiquement à proximité pourrait en théorie annoncer un
/// identifiant qui n'est pas le sien. Le but ici est d'éviter les mélanges ACCIDENTELS (binôme et ami
/// tous deux à portée en même temps), pas de se défendre contre un appareil malveillant.
class NearbyIdentity {
  NearbyIdentity._();

  static const _separator = '|';

  static String encode(String userId, String prenom) => '$userId$_separator$prenom';

  /// `null` si le nom reçu n'est pas dans ce format (ex. ancienne version de l'app en face, qui ne
  /// diffuse encore que son prénom) — traité comme "personne non identifiable", jamais accepté.
  static ({String userId, String prenom})? decode(String raw) {
    final index = raw.indexOf(_separator);
    if (index < 0) return null;
    final userId = raw.substring(0, index);
    if (userId.isEmpty) return null;
    return (userId: userId, prenom: raw.substring(index + 1));
  }
}

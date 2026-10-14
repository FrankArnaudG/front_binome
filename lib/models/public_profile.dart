/// Profil public minimal de N'IMPORTE QUEL utilisateur (voir
/// FriendController::publicProfile côté backend) — pour afficher
/// l'adversaire d'une invitation à un ami de jeu hors de sa propre Box
/// (voir GameInvite.isFriendInvite), dont l'app n'a par définition aucun
/// profil déjà en cache. Volontairement minimal, jamais rien de privé.
class PublicProfile {
  final String id;
  final String prenom;
  final String? name;
  final String? avatar;
  // Voir diagnostic utilisateur (alignement binôme/défi d'ami, phase 3) :
  // "en ligne" pour un ami, faute de canal de présence partagé — même
  // donnée que lastSeenLabel (voir core/last_seen_label.dart).
  final DateTime? lastSeenAt;

  const PublicProfile({required this.id, required this.prenom, this.name, this.avatar, this.lastSeenAt});

  /// Prénom + nom si connu, sinon prénom seul (voir demande utilisateur :
  /// "on doit lister le prénom et nom").
  String get fullName => (name != null && name!.isNotEmpty) ? '$prenom $name' : prenom;

  factory PublicProfile.fromJson(Map<String, dynamic> json) => PublicProfile(
        id: json['id'] as String,
        prenom: json['prenom'] as String,
        name: json['name'] as String?,
        avatar: json['avatar'] as String?,
        lastSeenAt: json['last_seen_at'] != null ? DateTime.parse(json['last_seen_at'] as String) : null,
      );
}

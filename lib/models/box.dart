import 'app_user.dart';

class Box {
  final String id;
  final String code;
  final String creatorId;
  final String? partnerId;
  final String status; // waiting | active | dissolved
  final DateTime? pairedAt;
  // Date "en couple depuis" corrigible par le couple (voir
  // DarkDayCounterCard) — distincte de pairedAt (jumelage technique dans
  // l'app) : un couple peut être ensemble depuis bien plus longtemps que
  // sa Box. `null` tant que personne ne l'a corrigée : le compteur
  // retombe alors sur pairedAt (voir getter [togetherSince]).
  final DateTime? togetherSinceOverride;
  final DateTime? dissolvedAt;
  final bool eveningRitualEnabled;
  final String eveningRitualTime; // "HH:mm:ss"
  final bool morningRitualEnabled;
  final String morningRitualTime; // "HH:mm:ss"
  final String? motto;
  // Photo de couple affichée à la place du cœur générique sur la carte
  // "jours ensemble" (voir DarkDayCounterCard) — `null` tant qu'aucune
  // n'a été mise, auquel cas ce dernier retombe sur le cœur classique.
  final String? photoUrl;
  final AppUser? creator;
  final AppUser? partner;

  const Box({
    required this.id,
    required this.code,
    required this.creatorId,
    this.partnerId,
    required this.status,
    this.pairedAt,
    this.togetherSinceOverride,
    this.dissolvedAt,
    required this.eveningRitualEnabled,
    required this.eveningRitualTime,
    this.morningRitualEnabled = true,
    this.morningRitualTime = '08:00:00',
    this.motto,
    this.photoUrl,
    this.creator,
    this.partner,
  });

  /// Ce qu'il faut réellement afficher/utiliser pour le calcul des jours
  /// ensemble — la correction si elle existe, sinon le jumelage.
  DateTime? get togetherSince => togetherSinceOverride ?? pairedAt;

  factory Box.fromJson(Map<String, dynamic> json) => Box(
        id: json['id'] as String,
        code: json['code'] as String,
        creatorId: json['creator_id'] as String,
        partnerId: json['partner_id'] as String?,
        status: json['status'] as String,
        pairedAt: json['paired_at'] != null ? DateTime.parse(json['paired_at'] as String) : null,
        togetherSinceOverride: json['together_since'] != null ? DateTime.parse(json['together_since'] as String) : null,
        dissolvedAt: json['dissolved_at'] != null ? DateTime.parse(json['dissolved_at'] as String) : null,
        eveningRitualEnabled: json['evening_ritual_enabled'] as bool? ?? true,
        eveningRitualTime: json['evening_ritual_time'] as String? ?? '21:00:00',
        morningRitualEnabled: json['morning_ritual_enabled'] as bool? ?? true,
        morningRitualTime: json['morning_ritual_time'] as String? ?? '08:00:00',
        motto: json['motto'] as String?,
        photoUrl: json['photo_url'] as String?,
        creator: json['creator'] != null ? AppUser.fromJson(json['creator'] as Map<String, dynamic>) : null,
        partner: json['partner'] != null ? AppUser.fromJson(json['partner'] as Map<String, dynamic>) : null,
      );

  bool get isWaiting => status == 'waiting';
  bool get isActive => status == 'active';
  bool get isDissolved => status == 'dissolved';

  /// Retourne le partenaire de [userId] dans cette Box, si connu (nécessite
  /// que `creator`/`partner` aient été chargés par le backend).
  AppUser? partnerOf(String userId) {
    if (creator != null && creator!.id != userId) return creator;
    if (partner != null && partner!.id != userId) return partner;
    return null;
  }
}

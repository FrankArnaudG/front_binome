import 'dart:math' as math;

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
  // Dernière position partagée VOLONTAIREMENT par chaque membre (voir
  // demande utilisateur : jamais de suivi continu, un bouton "Partager ma
  // position" ponctuel) — `null` tant que la personne n'a jamais partagé.
  final double? creatorLatitude;
  final double? creatorLongitude;
  final DateTime? creatorLocationAt;
  final double? partnerLatitude;
  final double? partnerLongitude;
  final DateTime? partnerLocationAt;

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
    this.creatorLatitude,
    this.creatorLongitude,
    this.creatorLocationAt,
    this.partnerLatitude,
    this.partnerLongitude,
    this.partnerLocationAt,
  });

  /// Ce qu'il faut réellement afficher/utiliser pour le calcul des jours
  /// ensemble — la correction si elle existe, sinon le jumelage.
  DateTime? get togetherSince => togetherSinceOverride ?? pairedAt;

  /// Dernière position connue de [userId] dans cette Box, `null` si
  /// jamais partagée — voir [distanceKm] pour le calcul entre les deux.
  ({double lat, double lon, DateTime at})? locationOf(String userId) {
    if (userId == creatorId && creatorLatitude != null && creatorLongitude != null && creatorLocationAt != null) {
      return (lat: creatorLatitude!, lon: creatorLongitude!, at: creatorLocationAt!);
    }
    if (userId == partnerId && partnerLatitude != null && partnerLongitude != null && partnerLocationAt != null) {
      return (lat: partnerLatitude!, lon: partnerLongitude!, at: partnerLocationAt!);
    }
    return null;
  }

  /// Distance en km entre les deux dernières positions partagées, `null`
  /// si l'une des deux (ou les deux) manque encore.
  double? get distanceKm {
    if (creatorLatitude == null ||
        creatorLongitude == null ||
        partnerLatitude == null ||
        partnerLongitude == null) {
      return null;
    }
    return _haversineKm(creatorLatitude!, creatorLongitude!, partnerLatitude!, partnerLongitude!);
  }

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
        creatorLatitude: _parseDecimal(json['creator_latitude']),
        creatorLongitude: _parseDecimal(json['creator_longitude']),
        creatorLocationAt: json['creator_location_at'] != null ? DateTime.parse(json['creator_location_at'] as String) : null,
        partnerLatitude: _parseDecimal(json['partner_latitude']),
        partnerLongitude: _parseDecimal(json['partner_longitude']),
        partnerLocationAt: json['partner_location_at'] != null ? DateTime.parse(json['partner_location_at'] as String) : null,
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

/// Laravel sérialise un cast `decimal:N` en chaîne (jamais en nombre JSON,
/// pour éviter les imprécisions de virgule flottante) — accepte les deux
/// formes plutôt que de supposer laquelle arrive.
double? _parseDecimal(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value as String);
}

/// Distance à vol d'oiseau entre deux points GPS (formule de Haversine,
/// rayon terrestre moyen 6371 km) — pas de package dédié pour un calcul
/// aussi simple.
double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLon = _degToRad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _degToRad(double deg) => deg * (math.pi / 180);

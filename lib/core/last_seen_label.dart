import 'package:flutter/widgets.dart';

import '../l10n/locale_scope.dart';

/// Libellé "vu il y a X" de la dernière connexion d'un binôme (voir
/// AppUser.lastSeenAt, alimenté par TouchLastSeen côté backend) — partagé par
/// toutes les discussions pour qu'elles affichent exactement la même chose.
/// Le statut "en ligne" (canal presence temps réel) est géré par l'appelant et
/// prime sur ce libellé.
String lastSeenLabel(BuildContext context, DateTime? lastSeenAt) {
  final t = LocaleScope.of(context).t;
  if (lastSeenAt == null) return t('presence_offline');
  final diff = DateTime.now().difference(lastSeenAt.toLocal());
  if (diff.inMinutes < 1) return t('presence_online_now');
  if (diff.inMinutes < 60) return t('presence_online_minutes_ago', {'minutes': '${diff.inMinutes}'});
  if (diff.inHours < 24) return t('presence_online_hours_ago', {'hours': '${diff.inHours}'});
  if (diff.inDays < 7) return t('presence_online_days_ago', {'days': '${diff.inDays}'});
  return t('presence_online_long_ago');
}

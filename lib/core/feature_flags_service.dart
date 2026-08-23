import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// État des fonctionnalités (activées/désactivées depuis le panel admin —
/// voir FeatureFlagController côté backend), même esprit que
/// WalletBalanceNotifier : singleton `ChangeNotifier`, rafraîchi au chargement
/// du Dashboard. Une fonctionnalité inconnue ou en cas d'échec réseau est
/// considérée activée par défaut, pour ne jamais bloquer l'app sur un souci
/// de connexion.
class FeatureFlagsService extends ChangeNotifier {
  FeatureFlagsService._();
  static final FeatureFlagsService instance = FeatureFlagsService._();

  Map<String, bool> _flags = {};

  bool isEnabled(String key) => _flags[key] ?? true;

  Future<void> refresh() async {
    try {
      final data = await ApiClient.instance.get('/feature-flags') as Map<String, dynamic>;
      _flags = data.map((key, value) => MapEntry(key, value as bool));
      notifyListeners();
    } catch (_) {
      // Best effort — on garde le dernier état connu plutôt que de bloquer l'app.
    }
  }
}

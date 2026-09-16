import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
import 'app_router.dart';

/// Vérifie au démarrage si une version plus récente de l'APK est publiée
/// (voir AppReleaseController côté backend) — l'app n'est pas distribuée
/// via le Play Store pour l'instant, donc aucune mise à jour automatique :
/// même mécanisme que le canal APK direct de WhatsApp (voir demande
/// utilisateur : "comment fonctionne WhatsApp... mettre en place").
class AppUpdateChecker {
  AppUpdateChecker._();
  static final AppUpdateChecker instance = AppUpdateChecker._();

  bool _prompted = false;

  Future<void> checkAndPrompt() async {
    // Une seule fois par lancement de l'app — un utilisateur qui a fermé la
    // bannière ne doit pas se la voir réafficher en boucle tant qu'il navigue.
    if (_prompted) return;

    try {
      final data = await ApiClient.instance.get('/app-version') as Map<String, dynamic>;
      final serverBuild = data['build_number'] as int;
      final apkUrl = data['apk_url'] as String?;
      if (apkUrl == null) return;

      final info = await PackageInfo.fromPlatform();
      final localBuild = int.tryParse(info.buildNumber) ?? 0;
      if (serverBuild <= localBuild) return;

      _prompted = true;

      final context = AppRouter.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;

      final version = data['version'] as String;
      final forceUpdate = data['force_update'] as bool? ?? false;
      final releaseNotes = data['release_notes'] as String?;

      if (forceUpdate) {
        _showBlockingDialog(context, version: version, apkUrl: apkUrl, releaseNotes: releaseNotes);
      } else {
        _showDismissibleBanner(context, version: version, apkUrl: apkUrl, releaseNotes: releaseNotes);
      }
    } catch (_) {
      // Jamais bloquant : une panne réseau/serveur sur cette vérification ne
      // doit jamais empêcher l'app de démarrer normalement.
    }
  }

  void _showBlockingDialog(BuildContext context, {required String version, required String apkUrl, String? releaseNotes}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Mise à jour requise ($version)'),
          content: Text(releaseNotes?.isNotEmpty == true
              ? releaseNotes!
              : 'Une nouvelle version de Binome est disponible. Merci de l\'installer pour continuer.'),
          actions: [
            FilledButton(
              onPressed: () => launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication),
              child: const Text('Télécharger la mise à jour'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDismissibleBanner(BuildContext context, {required String version, required String apkUrl, String? releaseNotes}) {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Text('Nouvelle version $version disponible.${releaseNotes?.isNotEmpty == true ? ' $releaseNotes' : ''}'),
        actions: [
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication);
            },
            child: const Text('Télécharger'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';

/// Démo micro/caméra 100% LOCALE du guide pas-à-pas d'un jeu (voir demande
/// utilisateur, Jeu de Mémoire : "je précise que tout ça c'est pour le
/// test... ça n'envoie rien", "c'est uniquement pour le téléphone") —
/// jamais VoiceCallService ni NearbyComms, un simple faux bouton animé.
/// Partagée par TOUS les jeux (voir demande utilisateur : "prends le même
/// soin pour les autres jeux") pour ne pas dupliquer cette mécanique dans
/// chaque écran de plateau — extraite de l'implémentation d'origine dans
/// MemoryGameBoardScreen._buildGuideVoiceDemo.
///
/// [phase] pilote à la fois le texte affiché et l'icône caméra :
/// - [GameGuideVoicePhase.micJoin] : uniquement le micro, au repos ou
///   "en attente du binôme" une fois tapé une première fois (voir
///   [connecting]).
/// - [GameGuideVoicePhase.micReady]/[GameGuideVoicePhase.cameraReady] :
///   micro + caméra affichés ensemble, comme lors d'un appel connecté.
enum GameGuideVoicePhase { micJoin, micReady, cameraReady }

class GameGuideVoiceDemo extends StatelessWidget {
  final GlobalKey micKey;
  final GlobalKey cameraKey;
  final GameGuideVoicePhase phase;
  final bool connecting;
  final VoidCallback? onMicTapToConnect;

  const GameGuideVoiceDemo({
    super.key,
    required this.micKey,
    required this.cameraKey,
    required this.phase,
    required this.connecting,
    this.onMicTapToConnect,
  });

  @override
  Widget build(BuildContext context) {
    final showCamera = phase == GameGuideVoicePhase.micReady || phase == GameGuideVoicePhase.cameraReady;
    return Positioned(
      left: 16,
      bottom: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Showcase(
            key: micKey,
            title: phase == GameGuideVoicePhase.micReady
                ? 'Maintiens pour parler'
                : (connecting ? 'En attente de ton binôme' : 'Active le micro'),
            description: phase == GameGuideVoicePhase.micReady
                ? "Une fois connecté, maintiens ce bouton appuyé pour parler — un simple tap ne suffit pas. (Démonstration : rien n'est envoyé, ceci reste uniquement sur ton téléphone.)"
                : (connecting
                    ? "En ce moment, ton binôme doit lui aussi cliquer sur son micro pour rejoindre l'appel. (Démonstration : rien n'est réellement envoyé, ceci reste uniquement sur ton téléphone.)"
                    : "Clique ici pour activer ton micro. (Démonstration : rien n'est réellement envoyé.)"),
            targetShapeBorder: const CircleBorder(),
            disableDefaultTargetGestures: phase == GameGuideVoicePhase.micJoin,
            child: GestureDetector(
              onTap: (phase == GameGuideVoicePhase.micJoin && !connecting) ? onMicTapToConnect : null,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: connecting ? Colors.orangeAccent : Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(connecting ? Icons.mic_rounded : Icons.mic_none_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
          if (showCamera) ...[
            const SizedBox(width: 10),
            Showcase(
              key: cameraKey,
              title: 'Active la caméra',
              description:
                  "Pour la caméra, un simple clic suffit pour l'activer ou la couper. (Démonstration : rien n'est envoyé, ceci reste uniquement sur ton téléphone.)",
              targetShapeBorder: const CircleBorder(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

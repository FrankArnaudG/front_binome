import '../../../models/game.dart';

/// Ambiance visuelle du template de jeu (voir GameSessionScreen) — un même
/// écran habillé différemment selon la nature du jeu, plutôt qu'un écran
/// dédié par jeu.
enum GameStyle {
  /// Bulle de texte flottante + zone de réponse — jeux de question/devinette.
  reflection,

  /// Élément central façon dé/pièce + CTA dégradé — jeux d'action/classiques.
  action,

  /// Grille épurée d'émojis — jeux expressifs/créatifs.
  creative,
}

/// Association explicite plutôt qu'une heuristique par mot-clé : le
/// catalogue est stable (voir GameSeeder côté backend).
const Map<String, GameStyle> _styles = {
  '20 Questions': GameStyle.reflection,
  'Vérité ou Défi': GameStyle.action,
  'Devine mon émoji': GameStyle.creative,
  'Charades en duo': GameStyle.creative,
  'Qui nous connaît le mieux ?': GameStyle.reflection,
  'Le Portrait Chinois': GameStyle.reflection,
  'Le Sondage Surprise': GameStyle.reflection,
  '20 Vérités sur Nous': GameStyle.reflection,
  'Ai-je le droit ?': GameStyle.reflection,
};

/// Un jeu ajouté au catalogue sans entrée ici retombe sur [GameStyle.reflection]
/// (le gabarit le plus neutre : texte + réponse libre). Toujours comparé au
/// nom français (clé d'identité stable, voir Game.nameFor) — jamais à la
/// langue courante, qui changerait ce qui est reconnu selon qui regarde.
GameStyle styleForGame(Game game) => _styles[game.nameFor('fr')] ?? GameStyle.reflection;

import 'pictionary_word_bank.dart';

/// Copie Dart pure de l'arbitre backend (voir
/// `app/Services/PictionaryEngine.php`) — utilisée par les modes
/// présentiel (Nearby Connections et pass-and-play), qui ne passent
/// jamais par le serveur pendant la partie.
///
/// DEUXIÈME moteur Dart de ce projet à manipuler un état PARTIELLEMENT
/// CACHÉ (voir BattleshipEngine pour le premier) : le mot de la manche en
/// cours ne doit JAMAIS être exposé à qui devine — voir
/// [LocalPictionaryTransport]/[NearbyPictionaryTransport], qui ne
/// construisent la vue "devineur" qu'avec `word: null`.
class PictionaryEngine {
  static const targetScore = 5;
  static const roundSeconds = 70;

  static String pickWord(String locale) => PictionaryWordBank.randomWord(locale);
}

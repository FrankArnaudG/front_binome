import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/box/box_service.dart';
import '../features/games/game_service.dart';
import '../models/game_invite.dart';
import 'realtime_client.dart';

/// Invitations à une partie à distance des 3 mini-jeux à état partagé —
/// singleton `ChangeNotifier` (même esprit que WalletBalanceNotifier),
/// mais dont le rôle est de rester à l'écoute du canal temps réel de la
/// Box EN PERMANENCE, quel que soit l'écran affiché — voir demande
/// utilisateur : "peu importe où ils sont dans l'app... il y a un pop-up
/// mignon qui apparaît".
///
/// [pendingInvite] pilote le pop-up global (voir GameInviteOverlay, monté
/// une fois dans AppShell) côté INVITÉ·E. [watch] fournit un flux par
/// invitation pour l'écran d'attente côté AUTEUR (voir
/// GameInviteWaitingScreen) — les deux mécanismes sont indépendants, une
/// même personne ne joue jamais les deux rôles pour la même invitation.
class GameInviteNotifier extends ChangeNotifier {
  GameInviteNotifier._();
  static final GameInviteNotifier instance = GameInviteNotifier._();

  String? _myUserId;
  String? _subscribedBoxId;
  Timer? _pollTimer;

  GameInvite? _pendingInvite;
  GameInvite? get pendingInvite => _pendingInvite;

  final _resolutionControllers = <String, StreamController<GameInvite>>{};

  // Voir demande utilisateur : "si le modal apparaît, le bouton Rejoindre
  // continue à apparaître, il ne doit plus apparaître" — une invitation dont
  // l'acceptation a déjà échoué (solde/abonnement insuffisant) reste
  // `pending` côté serveur (pour laisser une chance de réessayer après
  // recharge) ; sans cette liste, le poll de secours (8s) ou un écho
  // temps réel la refaisait réapparaître en boucle juste après sa
  // fermeture.
  final Set<String> _failedInviteIds = {};

  // Voir demande utilisateur : "ce modal doit apparaître pour les 2
  // binômes" — l'invité·e voit déjà l'échec via sa propre réponse HTTP
  // (voir GameInviteOverlay), ce flux sert à prévenir l'auteur resté sur
  // GameInviteWaitingScreen, qui sinon attendrait les 60s d'expiration
  // sans jamais savoir pourquoi (voir GameInviteJoinFailed côté serveur).
  final _joinFailedController = StreamController<({String inviteId, String message})>.broadcast();
  Stream<({String inviteId, String message})> get joinFailed => _joinFailedController.stream;

  // Vrai entre le tap sur "Rejoindre" et l'ouverture de l'écran de jeu (voir
  // demande utilisateur : afficher un chargement côté invité·e pendant que la
  // partie s'ouvre). Le pop-up disparaît dès le tap, sans ça l'écran restait
  // figé le temps de l'aller-retour réseau. Garde-fou : jamais plus de 25 s,
  // même si l'ouverture reste bloquée.
  bool _joining = false;
  bool get isJoining => _joining;
  Timer? _joiningTimeout;

  void setJoining(bool value) {
    _joiningTimeout?.cancel();
    if (value) {
      _joiningTimeout = Timer(const Duration(seconds: 25), () => setJoining(false));
    }
    if (_joining == value) return;
    _joining = value;
    notifyListeners();
  }

  /// À appeler une fois l'utilisateur connu (voir AppRouter.routeAfterAuth)
  /// — s'abonne/se réabonne tout seul au bon canal Box au fil des
  /// changements (jumelage, déjumelage, changement de compte...).
  void init(String myUserId) {
    _myUserId = myUserId;
    BoxService.instance.removeListener(_onBoxChanged);
    BoxService.instance.addListener(_onBoxChanged);
    _onBoxChanged();

    // Canal personnel, en plus de celui de la Box ci-dessus — pour les
    // invitations HORS-BOX (défi à un ami de jeu via son code, voir demande
    // utilisateur), qui n'ont par définition aucune Box en commun avec
    // l'invitant·e. Même `_onEvent` pour les deux sources : un GameInvite a
    // la même forme peu importe d'où il vient (seul `boxId` diffère).
    RealtimeClient.instance.subscribePrivate('App.Models.User.$myUserId', onEvent: _onEvent);

    // Temps réel pour une apparition instantanée de la pop-up, + un poll de
    // secours en parallèle (indépendant du socket, même principe que
    // BoxWaitingScreen/GameInviteWaitingScreen) — sans ça, un événement
    // WebSocket manqué au moment précis de l'envoi ne faisait JAMAIS
    // apparaître la pop-up côté invité·e avant de relancer l'app entière
    // (voir demande utilisateur).
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _pollPending());
  }

  Future<void> _pollPending() async {
    if (_subscribedBoxId == null) {
      debugPrint('GameInviteNotifier: poll ignoré, aucune box abonnée (_subscribedBoxId == null)');
      return;
    }
    try {
      final invite = await GameService.instance.fetchPendingInvite();
      debugPrint('GameInviteNotifier: poll -> invite=${invite?.id} inviteeId=${invite?.inviteeId} myUserId=$_myUserId');
      if (invite != null &&
          invite.inviteeId == _myUserId &&
          _pendingInvite?.id != invite.id &&
          !_failedInviteIds.contains(invite.id)) {
        _pendingInvite = invite;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('GameInviteNotifier: poll a échoué ($e)');
    }
  }

  void _onBoxChanged() {
    final box = BoxService.instance.currentBox;
    final boxId = box?.partnerId != null ? box!.id : null;
    if (boxId == _subscribedBoxId) return;

    final previousBoxId = _subscribedBoxId;
    if (previousBoxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(previousBoxId, onEvent: _onEvent);
    }
    _subscribedBoxId = boxId;
    if (boxId != null) {
      RealtimeClient.instance.subscribeToBox(boxId, onEvent: _onEvent);
    }
  }

  void _onEvent(RealtimeEvent event) {
    if (event.event == 'GameInviteJoinFailed') {
      final data = event.data;
      final inviteId = data?['invite_id'] as String?;
      final message = data?['message'] as String?;
      if (inviteId == null || message == null) return;
      _failedInviteIds.add(inviteId);
      if (_pendingInvite?.id == inviteId) {
        _pendingInvite = null;
        notifyListeners();
      }
      _joinFailedController.add((inviteId: inviteId, message: message));
      return;
    }
    if (event.event != 'GameInviteUpdated') return;
    final data = event.data;
    if (data == null) return;
    final invite = GameInvite.fromJson(data['invite'] as Map<String, dynamic>);

    // Côté invité·e : affiche/masque le pop-up global.
    if (invite.inviteeId == _myUserId) {
      if (invite.isPending) {
        if (_failedInviteIds.contains(invite.id)) return;
        _pendingInvite = invite;
        notifyListeners();
      } else if (_pendingInvite?.id == invite.id) {
        _pendingInvite = null;
        notifyListeners();
      }
    }

    // Côté auteur : notifie l'écran d'attente concerné, s'il y en a un
    // (voir watch()) — no-op silencieux sinon (ex. l'auteur a déjà quitté
    // l'écran d'attente localement).
    _resolutionControllers[invite.id]?.add(invite);
  }

  /// Flux de mises à jour d'UNE invitation précise — voir
  /// GameInviteWaitingScreen, qui s'y abonne dès l'envoi et se ferme dès
  /// la première résolution (accepted/declined/expired).
  Stream<GameInvite> watch(String inviteId) {
    final controller = _resolutionControllers.putIfAbsent(inviteId, () => StreamController<GameInvite>.broadcast());
    return controller.stream;
  }

  /// À appeler quand l'écran d'attente se ferme (résolu ou abandonné) —
  /// évite d'accumuler un StreamController par invitation pour toute la
  /// durée de vie de l'app.
  void disposeWatch(String inviteId) {
    _resolutionControllers.remove(inviteId)?.close();
  }

  /// Reprend une invitation par son id — voir PushNotificationService,
  /// utilisé quand le tap vient d'une notification reçue app fermée/en
  /// arrière-plan (le canal temps réel n'a pas pu la délivrer directement,
  /// voir _onEvent). Ignore silencieusement si elle n'est plus valide
  /// (déjà résolue, expirée, ou plus destinée à moi) — aucun crash, juste
  /// pas de pop-up.
  Future<void> showInviteById(String inviteId) async {
    try {
      final invite = await GameService.instance.fetchGameInvite(inviteId);
      if (invite.isPending && invite.inviteeId == _myUserId) {
        _pendingInvite = invite;
        notifyListeners();
      }
    } catch (_) {
      // Best-effort.
    }
  }

  /// Efface le pop-up affiché SANS attendre l'écho temps réel du
  /// accept/decline qu'on vient de déclencher soi-même — sinon il resterait
  /// visible le temps d'un aller-retour réseau après avoir déjà tapé sur
  /// "Rejoindre"/"Refuser".
  void dismissPendingInvite() {
    _pendingInvite = null;
    notifyListeners();
  }
}

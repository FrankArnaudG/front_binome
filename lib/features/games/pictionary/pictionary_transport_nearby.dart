import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';

import '../../../models/pictionary_session.dart';
import 'pictionary_engine.dart';
import 'pictionary_transport.dart';

const kPictionaryHostRole = 'host';
const kPictionaryGuestRole = 'guest';

/// Mode "présentiel connecté" — l'HÔTE est autoritaire ET connaît le mot
/// en toute circonstance ; l'invité ne reçoit QUE la vue filtrée pour lui
/// (voir _sendStateToGuest, `word: null` sauf si l'invité dessine) — même
/// principe que NearbyBattleshipTransport.
class NearbyPictionaryTransport extends PictionaryTransport {
  final Nearby nearby;
  final String endpointId;
  final bool isHost;
  final String locale;
  final _controller = StreamController<PictionaryBoardState>.broadcast();

  String _word = '';
  List<PictionaryStroke> _strokes = [];
  final Map<String, int> _scores = {kPictionaryHostRole: 0, kPictionaryGuestRole: 0};
  String _currentDrawerRole = kPictionaryHostRole;
  int _roundNumber = 1;
  DateTime? _roundStartedAt;
  String? _winnerRole;
  int _movesCount = 0;
  bool _finished = false;
  DateTime? _startedAt;
  String? _pausedByRole;
  DateTime? _pausedAt;

  PictionaryBoardState? _guestState;

  NearbyPictionaryTransport.host({required this.nearby, required this.endpointId, required this.locale}) : isHost = true {
    _word = PictionaryEngine.pickWord(locale);
    _startedAt = DateTime.now();
    _roundStartedAt = DateTime.now();
    _sendStateToGuest();
  }

  NearbyPictionaryTransport.guest({required this.nearby, required this.endpointId})
      : isHost = false,
        locale = 'fr' {
    _guestState = const PictionaryBoardState(myUserId: kPictionaryGuestRole, opponentUserId: kPictionaryHostRole);
  }

  void _send(Map<String, dynamic> message) {
    nearby.sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(jsonEncode(message))));
  }

  PictionaryBoardState _stateFor(String role) => PictionaryBoardState(
        isDrawer: _currentDrawerRole == role,
        word: _currentDrawerRole == role ? _word : null,
        strokes: _strokes,
        scoresByUser: _scores,
        targetScore: PictionaryEngine.targetScore,
        roundNumber: _roundNumber,
        roundStartedAt: _roundStartedAt,
        roundSeconds: PictionaryEngine.roundSeconds,
        currentDrawerUserId: _currentDrawerRole,
        winnerUserId: _winnerRole,
        movesCount: _movesCount,
        finished: _finished,
        startedAt: _startedAt,
        myUserId: role,
        opponentUserId: role == kPictionaryHostRole ? kPictionaryGuestRole : kPictionaryHostRole,
        pausedByUserId: _pausedByRole,
        pausedAt: _pausedAt,
      );

  void _sendStateToGuest() {
    final state = _stateFor(kPictionaryGuestRole);
    _send({
      'type': 'state',
      'isDrawer': state.isDrawer,
      'word': state.word,
      'strokes': state.strokes.map((s) => s.toJson()).toList(),
      'scoresByUser': state.scoresByUser,
      'roundNumber': state.roundNumber,
      'roundStartedAt': state.roundStartedAt?.toIso8601String(),
      'currentDrawerUserId': state.currentDrawerUserId,
      'winnerUserId': state.winnerUserId,
      'movesCount': state.movesCount,
      'finished': state.finished,
      'startedAt': state.startedAt?.toIso8601String(),
      'pausedByUserId': state.pausedByUserId,
      'pausedAt': state.pausedAt?.toIso8601String(),
    });
  }

  void onPayloadReceived(String fromEndpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;
    final message = jsonDecode(utf8.decode(payload.bytes!)) as Map<String, dynamic>;

    switch (message['type']) {
      case 'state':
        final pausedByUserId = message['pausedByUserId'] as String?;
        _guestState = PictionaryBoardState(
          isDrawer: message['isDrawer'] as bool,
          word: message['word'] as String?,
          strokes: (message['strokes'] as List).map((e) => PictionaryStroke.fromJson(e as Map<String, dynamic>)).toList(),
          scoresByUser: (message['scoresByUser'] as Map).map((k, v) => MapEntry(k as String, v as int)),
          targetScore: PictionaryEngine.targetScore,
          roundNumber: message['roundNumber'] as int,
          roundStartedAt: message['roundStartedAt'] != null ? DateTime.parse(message['roundStartedAt'] as String) : null,
          roundSeconds: PictionaryEngine.roundSeconds,
          currentDrawerUserId: message['currentDrawerUserId'] as String?,
          winnerUserId: message['winnerUserId'] as String?,
          movesCount: message['movesCount'] as int,
          finished: message['finished'] as bool,
          startedAt: message['startedAt'] != null ? DateTime.parse(message['startedAt'] as String) : null,
          myUserId: kPictionaryGuestRole,
          opponentUserId: kPictionaryHostRole,
          pausedByUserId: pausedByUserId,
          pausedAt: message['pausedAt'] != null ? DateTime.parse(message['pausedAt'] as String) : null,
        );
        _controller.add(_guestState!);
      case 'stroke':
        if (isHost) _applyStroke(kPictionaryGuestRole, PictionaryStroke.fromJson(message['stroke'] as Map<String, dynamic>));
      case 'found':
        if (isHost) _applyFound(kPictionaryGuestRole);
      case 'skip':
        if (isHost) _applySkip();
      case 'pause_request':
        if (isHost) _applyPause(kPictionaryGuestRole);
      case 'resume_request':
        if (isHost) _applyResume(kPictionaryGuestRole);
    }
  }

  void _applyStroke(String byRole, PictionaryStroke stroke) {
    if (_currentDrawerRole != byRole || _finished || _pausedByRole != null) return;
    _strokes = [..._strokes, stroke];
    _controller.add(_stateFor(kPictionaryHostRole));
    _sendStateToGuest();
  }

  void _applyFound(String byDrawerRole) {
    if (_currentDrawerRole != byDrawerRole || _finished || _pausedByRole != null) return;
    final finderRole = byDrawerRole == kPictionaryHostRole ? kPictionaryGuestRole : kPictionaryHostRole;
    _scores[finderRole] = (_scores[finderRole] ?? 0) + 1;

    if (_scores[finderRole]! >= PictionaryEngine.targetScore) {
      _winnerRole = finderRole;
      _finished = true;
      _word = '';
      _controller.add(_stateFor(kPictionaryHostRole));
      _sendStateToGuest();
      return;
    }

    _movesCount++;
    _startRound(finderRole);
    _controller.add(_stateFor(kPictionaryHostRole));
    _sendStateToGuest();
  }

  void _applySkip() {
    if (_finished || _pausedByRole != null) return;
    final nextDrawer = _currentDrawerRole == kPictionaryHostRole ? kPictionaryGuestRole : kPictionaryHostRole;
    _movesCount++;
    _startRound(nextDrawer);
    _controller.add(_stateFor(kPictionaryHostRole));
    _sendStateToGuest();
  }

  void _startRound(String drawerRole) {
    _word = PictionaryEngine.pickWord(locale);
    _strokes = [];
    _currentDrawerRole = drawerRole;
    _roundNumber++;
    _roundStartedAt = DateTime.now();
  }

  void _applyPause(String byRole) {
    if (_pausedByRole != null || _finished) return;
    _pausedByRole = byRole;
    _pausedAt = DateTime.now();
    _controller.add(_stateFor(kPictionaryHostRole));
    _sendStateToGuest();
  }

  void _applyResume(String byRole) {
    if (_pausedByRole != byRole) return;
    final paused = _pausedAt;
    if (paused != null && _roundStartedAt != null) {
      _roundStartedAt = _roundStartedAt!.add(DateTime.now().difference(paused));
    }
    _pausedByRole = null;
    _pausedAt = null;
    _controller.add(_stateFor(kPictionaryHostRole));
    _sendStateToGuest();
  }

  @override
  Stream<PictionaryBoardState> get stateStream => _controller.stream;

  @override
  PictionaryBoardState get currentState => isHost ? _stateFor(kPictionaryHostRole) : _guestState!;

  @override
  Future<void> addStroke(PictionaryStroke stroke) async {
    if (isHost) {
      _applyStroke(kPictionaryHostRole, stroke);
    } else {
      if (!(_guestState?.isDrawer ?? false)) return;
      _send({'type': 'stroke', 'stroke': stroke.toJson()});
    }
  }

  @override
  Future<void> markFound() async {
    if (isHost) {
      _applyFound(kPictionaryHostRole);
    } else {
      if (!(_guestState?.isDrawer ?? false)) return;
      _send({'type': 'found'});
    }
  }

  @override
  Future<void> skipRound() async {
    if (isHost) {
      _applySkip();
    } else {
      _send({'type': 'skip'});
    }
  }

  @override
  Future<void> abandon() async {
    _finished = true;
    if (isHost) {
      _controller.add(_stateFor(kPictionaryHostRole));
      _sendStateToGuest();
    } else {
      _guestState = _guestState?.copyWith(finished: true);
      _controller.add(_guestState!);
    }
  }

  @override
  Future<void> pause() async {
    if (isHost) {
      _applyPause(kPictionaryHostRole);
    } else {
      _send({'type': 'pause_request'});
    }
  }

  @override
  Future<void> resume() async {
    if (!currentState.pausedByMe) return;
    if (isHost) {
      _applyResume(kPictionaryHostRole);
    } else {
      _send({'type': 'resume_request'});
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}

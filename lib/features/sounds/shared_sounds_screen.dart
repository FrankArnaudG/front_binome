import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/api_client.dart';
import '../../core/realtime_client.dart';
import '../../models/app_user.dart';
import '../../models/box_sound.dart';
import '../../theme/app_colors.dart';
import '../../widgets/empty_state.dart';
import '../box/box_scope.dart';
import 'shared_sounds_service.dart';

/// Sons partagés du couple — voir SharedSoundsService/BoxSoundController.
/// "Jouer" diffuse en direct sur le téléphone du binôme via l'événement
/// temps réel SoundPlayed, uniquement s'il est déjà connecté (pas de
/// notification de repli, voir la discussion produit) — d'où le bouton
/// désactivé/grisé quand [_partnerPresent] est faux.
class SharedSoundsScreen extends StatefulWidget {
  final AppUser user;

  const SharedSoundsScreen({super.key, required this.user});

  @override
  State<SharedSoundsScreen> createState() => _SharedSoundsScreenState();
}

class _SharedSoundsScreenState extends State<SharedSoundsScreen> {
  List<BoxSound>? _sounds;
  bool _initialLoading = true;
  bool _loadError = false;
  bool _uploading = false;

  /// Id du son en cours de déclenchement (appel réseau vers /play) — affiche
  /// un petit spinner le temps de l'appel, distinct de [_activeSoundId] qui
  /// reflète l'état réel de lecture (voir [_playerStateSub]).
  String? _triggeringId;

  /// Id du son actuellement chargé dans [_player] — `null` si rien n'est en
  /// cours de lecture. Piloté par [_playerStateSub], pas par un simple flag
  /// local : c'est la seule source fiable pour savoir si ça joue encore ou
  /// si la lecture est arrivée à son terme.
  String? _activeSoundId;
  bool _isPlaying = false;

  /// Id du son sélectionné (tap sur la tuile) — le bouton de suppression ne
  /// s'affiche que pour lui, pour éviter une suppression accidentelle au
  /// milieu d'une liste de 5 sons maximum.
  String? _selectedId;

  final _player = AudioPlayer();
  late final StreamSubscription<PlayerState> _playerStateSub;
  String? _boxId;
  bool _partnerPresent = false;
  String? _partnerId;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initRealtime());
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing = state.playing && state.processingState != ProcessingState.completed;
      setState(() {
        _isPlaying = playing;
        if (state.processingState == ProcessingState.completed) _activeSoundId = null;
      });
    });
  }

  @override
  void dispose() {
    if (_boxId != null) {
      RealtimeClient.instance.unsubscribeFromBox(
        _boxId!,
        onEvent: _onRealtimeEvent,
        onPresenceChange: _onPresenceChange,
      );
    }
    _playerStateSub.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _initRealtime() async {
    final box = BoxScope.of(context).currentBox;
    if (box == null || !mounted) return;
    _boxId = box.id;
    _partnerId = box.partnerOf(widget.user.id)?.id;
    try {
      await RealtimeClient.instance.subscribeToBox(
        box.id,
        onEvent: _onRealtimeEvent,
        onPresenceChange: _onPresenceChange,
      );
    } catch (_) {
      // Best effort : sans temps réel, l'écran reste utilisable pour
      // gérer les sons (ajouter/supprimer), juste "jouer" restera inopérant.
    }
  }

  void _onPresenceChange(Set<String> memberIds) {
    if (!mounted) return;
    final present = _partnerId != null && memberIds.contains(_partnerId);
    if (present != _partnerPresent) setState(() => _partnerPresent = present);
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event != 'SoundPlayed') return;
    final playedBy = event.data?['played_by'] as String?;
    // On a déjà joué localement au moment du tap (voir _play) — n'y
    // rejoue pas une deuxième fois quand l'écho de son propre envoi revient.
    if (playedBy == widget.user.id) return;

    final soundJson = event.data?['sound'] as Map<String, dynamic>?;
    final url = soundJson?['url'] as String?;
    final soundId = soundJson?['id'] as String?;
    if (url != null) _playUrl(url, soundId: soundId);
  }

  Future<void> _load() async {
    try {
      final sounds = await SharedSoundsService.instance.fetchSounds();
      if (!mounted) return;
      setState(() {
        _sounds = sounds;
        _initialLoading = false;
        _loadError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _loadError = _sounds == null;
      });
    }
  }

  Future<void> _pickAndUpload() async {
    final sounds = _sounds;
    if (sounds != null && sounds.length >= SharedSoundsService.maxSounds) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tu as déjà 5 sons partagés (maximum).')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = result?.files.single.path;
    if (path == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final sound = await SharedSoundsService.instance.uploadSound(File(path));
      if (!mounted) return;
      setState(() => _sounds = [sound, ...?_sounds]);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'ajouter ce son.")),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteSound(BoxSound sound) async {
    try {
      await SharedSoundsService.instance.deleteSound(sound.id);
      if (!mounted) return;
      setState(() {
        _sounds = _sounds?.where((s) => s.id != sound.id).toList();
        if (_selectedId == sound.id) _selectedId = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de supprimer ce son.')),
      );
    }
  }

  Future<void> _playUrl(String url, {String? soundId}) async {
    try {
      if (mounted) setState(() => _activeSoundId = soundId);
      await _player.setUrl(url);
      await _player.play();
    } catch (_) {
      // Best effort — un son qui ne se joue pas ne doit pas planter l'écran.
    }
  }

  /// Tap sur le bouton d'un son déjà en cours de lecture → bascule
  /// pause/reprise plutôt que de relancer depuis le début (et, si c'était
  /// celui-ci, ne re-déclenche jamais le partage en direct une seconde fois).
  void _togglePause() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  /// Joue localement tout de suite (confirmation pour l'expéditeur) ET
  /// diffuse en direct côté binôme — voir SharedSoundsService.playSound.
  Future<void> _play(BoxSound sound) async {
    setState(() => _triggeringId = sound.id);
    unawaited(_playUrl(sound.url, soundId: sound.id));
    try {
      await SharedSoundsService.instance.playSound(sound.id);
    } catch (_) {
      // Best effort — au pire le binôme ne l'entend pas, l'expéditeur si.
    } finally {
      if (mounted) setState(() => _triggeringId = null);
    }
  }

  void _toggleSelection(String soundId) {
    setState(() => _selectedId = _selectedId == soundId ? null : soundId);
  }

  @override
  Widget build(BuildContext context) {
    final sounds = _sounds ?? [];

    return Scaffold(
      backgroundColor: AppColors.blush,
      appBar: AppBar(
        backgroundColor: AppColors.blush,
        elevation: 0,
        foregroundColor: AppColors.textOnBlush,
        title: Text('Sons partagés', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppColors.textOnBlush)),
        actions: [
          if (!_initialLoading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${sounds.length}/${SharedSoundsService.maxSounds}',
                  style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textOnBlushMuted),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: _uploading ? null : _pickAndUpload,
        child: _uploading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Icon(
                    _partnerPresent ? Icons.circle : Icons.circle_outlined,
                    size: 10,
                    color: _partnerPresent ? Colors.green : AppColors.textOnBlushMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _partnerPresent
                          ? 'Ton binôme est connecté·e — un son joué s\'entend chez lui/elle en direct.'
                          : 'Ton binôme n\'est pas connecté·e pour l\'instant.',
                      style: GoogleFonts.nunito(fontSize: 12, color: AppColors.textOnBlushMuted),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(sounds)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<BoxSound> sounds) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError) {
      return const EmptyState(
        icon: Icons.wifi_off_rounded,
        message: 'Impossible de charger les sons partagés.',
      );
    }
    if (sounds.isEmpty) {
      return const EmptyState(
        icon: Icons.music_note_rounded,
        message: 'Aucun son pour l\'instant — ajoutes-en un à partager.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: sounds.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final sound = sounds[index];
        final isTriggering = _triggeringId == sound.id;
        final isActive = _activeSoundId == sound.id;
        final showPause = isActive && _isPlaying;
        final isSelected = _selectedId == sound.id;

        VoidCallback? onPlayTap;
        if (isTriggering) {
          onPlayTap = null;
        } else if (isActive) {
          onPlayTap = _togglePause;
        } else if (_partnerPresent) {
          onPlayTap = () => _play(sound);
        } else {
          onPlayTap = () => _playUrl(sound.url, soundId: sound.id);
        }

        return Material(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.blushCard,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            onTap: () => _toggleSelection(sound.id),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: Icon(Icons.music_note_rounded, color: AppColors.primary),
            ),
            title: Text(
              'Son ${index + 1}',
              style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textOnBlush),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: isTriggering
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(
                          showPause ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                          color: AppColors.primary,
                          size: 32,
                        ),
                  onPressed: onPlayTap,
                  tooltip: showPause
                      ? 'Mettre en pause'
                      : (_partnerPresent ? 'Jouer en duo' : 'Jouer (binôme non connecté)'),
                ),
                if (isSelected)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textOnBlushMuted),
                    onPressed: () => _deleteSound(sound),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}


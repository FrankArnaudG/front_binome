import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_router.dart';
import '../../core/realtime_client.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/box.dart';
import '../../theme/app_colors.dart';
import '../../widgets/binome_wordmark.dart';
import 'box_service.dart';

class BoxWaitingScreen extends StatefulWidget {
  final AppUser user;
  final Box box;

  const BoxWaitingScreen({super.key, required this.user, required this.box});

  @override
  State<BoxWaitingScreen> createState() => _BoxWaitingScreenState();
}

class _BoxWaitingScreenState extends State<BoxWaitingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  late final Animation<double> _pulse = Tween<double>(begin: 0.85, end: 1.05).animate(
    CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
  );

  Timer? _pollTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // Temps réel pour une confirmation instantanée, + un poll de secours en
    // parallèle (indépendant du socket) au cas où le message serait manqué.
    RealtimeClient.instance.subscribeToBox(widget.box.id, onEvent: _onRealtimeEvent);
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _pollStatus());
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.event == 'BoxPaired') {
      _goHome();
    }
  }

  Future<void> _pollStatus() async {
    try {
      final box = await BoxService.instance.fetchCurrent();
      if (box != null && box.isActive) {
        _goHome();
      }
    } catch (_) {
      // best effort, on retente au prochain tick
    }
  }

  void _goHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    AppRouter.toHome(context, widget.user, replace: true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    RealtimeClient.instance.unsubscribeFromBox(widget.box.id, onEvent: _onRealtimeEvent);
    _pulseController.dispose();
    super.dispose();
  }

  void _shareCode() {
    final t = LocaleScope.of(context).t;
    Share.share(t('invite_share_text', {'code': widget.box.code}));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                  ),
                  const Expanded(child: Center(child: BinomeWordmark(fontSize: 20))),
                  const SizedBox(width: 48),
                ],
              ),
              const Spacer(),
              ScaleTransition(
                scale: _pulse,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [AppColors.primary, AppColors.secondary]),
                  ),
                  child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 44),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'En attente de ton/ta partenaire',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
              ),
              const SizedBox(height: 40),
              Text(
                'Ton ID de Box :',
                style: GoogleFonts.nunito(fontSize: 14, color: AppColors.textOnNavyMuted),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  widget.box.code,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 6),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _shareCode,
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Partager le code'),
              ),
              const SizedBox(height: 10),
              Text(
                'Partage-le avec ton/ta partenaire',
                style: GoogleFonts.nunito(fontSize: 13, color: AppColors.textOnNavyMuted),
              ),
              const Spacer(),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

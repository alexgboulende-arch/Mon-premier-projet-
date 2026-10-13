import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/common.dart';

const _navy = Color(0xFF0A1230);
const _navyLight = Color(0xFF18245A);

/// Écran de démarrage : logo, nom et rappel 18+.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.replay = false, this.onDone, this.duration = const Duration(milliseconds: 1400)});

  /// Ouvert depuis le profil : se ferme tout seul.
  final bool replay;
  final VoidCallback? onDone;
  final Duration duration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () {
      if (!mounted) return;
      if (widget.replay) {
        Navigator.of(context).pop();
      } else {
        widget.onDone?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -.4), radius: 1.1, colors: [_navyLight, _navy]),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ButeoLogo(width: 160),
                    SizedBox(height: 14),
                    Text(
                      'BUTEO',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: Color(0xFFEEF1FB),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'PRONOSTICS SPORTIFS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 3,
                        color: Color(0xFF2BF59A),
                      ),
                    ),
                  ],
                ),
              ),
              const Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 28),
                  child: Text('18+ · Joue avec modération', style: TextStyle(fontSize: 12, color: Color(0xFF8F9AC4))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Affiche l'écran de démarrage, puis l'application.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child, this.duration = const Duration(milliseconds: 1400)});

  final Widget child;
  final Duration duration;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 350),
    child: _done ? widget.child : SplashScreen(duration: widget.duration, onDone: () => setState(() => _done = true)),
  );
}

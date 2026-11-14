import '../theme/custom_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon.dart';
import 'package:flutter/material.dart';

/// Branded launch transition; the destination starts its normal session checks.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.destination});
  final Widget destination;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    await Future<void>.delayed(const Duration(milliseconds: 1700));
    if (mounted) setState(() => _finished = true);
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.destination;
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              CustomColors.splashStart,
              CustomColors.splashEnd,
              AppColors.primary,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              FadeTransition(
                opacity: CurvedAnimation(
                  parent: _animation,
                  curve: Curves.easeIn,
                ),
                child: ScaleTransition(
                  scale: Tween<double>(begin: .85, end: 1).animate(
                    CurvedAnimation(
                      parent: _animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: CustomColors.splashRing),
                          color: CustomColors.splashGlass,
                          boxShadow: const [
                            BoxShadow(
                              color: CustomColors.splashGlow,
                              blurRadius: 70,
                            ),
                          ],
                        ),
                        child: const AppIcon(
                          size: 76,
                          radius: 20,
                          color: AppColors.gold,
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        'Hotel Pro',
                        style: TextStyle(
                          color: CustomColors.surface,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Every stay, beautifully managed.',
                        style: TextStyle(
                          color: CustomColors.muted,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              const SizedBox(
                width: 96,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.gold,
                  backgroundColor: CustomColors.border,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'YOUR HOTEL. YOUR WORLD.',
                style: TextStyle(
                  color: CustomColors.bannerRing,
                  fontSize: 10,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}

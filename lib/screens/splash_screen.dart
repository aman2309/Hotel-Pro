import '../theme/custom_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon.dart';
import 'package:flutter/material.dart';

/// Branded launch transition; the destination starts its normal session checks.
///
/// The destination is mounted underneath immediately so the login/cloud read
/// runs while the splash animation plays instead of after it.
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
    duration: const Duration(milliseconds: 900),
  )..forward();
  bool _finished = false;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _finished = true);
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.destination,
        if (!_hidden)
          Positioned.fill(
            child: AbsorbPointer(
              child: AnimatedOpacity(
                opacity: _finished ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                onEnd: () {
                  if (_finished && mounted) setState(() => _hidden = true);
                },
                child: _SplashBody(animation: _animation),
              ),
            ),
          ),
      ],
    );
  }
}

class _SplashBody extends StatelessWidget {
  const _SplashBody({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
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
                  parent: animation,
                  curve: Curves.easeIn,
                ),
                child: ScaleTransition(
                  scale: Tween<double>(begin: .85, end: 1).animate(
                    CurvedAnimation(
                      parent: animation,
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

import 'package:flutter/material.dart';
import '../theme/custom_colors.dart';

/// The app logo, used everywhere the brand is shown.
///
/// Single source of truth: change [assetPath] (and the `flutter_launcher_icons`
/// `image_path` in `pubspec.yaml`, which points at the same PNG) to rebrand the
/// whole app without touching each screen.
class AppIcon extends StatelessWidget {
  const AppIcon({
    super.key,
    this.size,
    this.radius,
    this.color,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.apartment_rounded,
  });

  /// Logo asset shared by every in-app logo and the launcher icons.
  static const String assetPath = 'assets/images/hotel_app_icon.png';

  /// Square edge length. When null the logo fills the given constraints.
  final double? size;

  /// Corner radius; null keeps square corners.
  final double? radius;

  /// Tint of [fallbackIcon] if the asset cannot be loaded.
  final Color? color;

  final BoxFit fit;

  /// Shown when the asset is missing, so the UI never breaks.
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: fit,
      errorBuilder: (_, _, _) => Icon(
        fallbackIcon,
        size: size,
        color: color ?? IconTheme.of(context).color ?? CustomColors.button,
      ),
    );
    if (radius == null) return logo;
    return ClipRRect(borderRadius: BorderRadius.circular(radius!), child: logo);
  }
}

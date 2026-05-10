import 'package:flutter/material.dart';

import '../shared/branding.dart';
import '../shared/themes.dart';

/// Victoria Lush wordmark from packaged PNGs ([VllBranding.logoAsset] / [logoWhiteAsset]).
enum VllLogoTone {
  /// Full-color mark (transparent background) — login, light cards.
  onLightSurface,

  /// White-glyph mark — crimson / dark gradients (home hero).
  onBrandField,
}

class VllBrandLogo extends StatelessWidget {
  const VllBrandLogo({
    super.key,
    this.height = 72,
    this.width,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.high,
    this.tone = VllLogoTone.onLightSurface,
  });

  final double height;
  final double? width;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final VllLogoTone tone;

  String get _asset => tone == VllLogoTone.onBrandField
      ? VllBranding.logoWhiteAsset
      : VllBranding.logoAsset;

  Color get _fallbackIconColor =>
      tone == VllLogoTone.onBrandField ? Colors.white70 : AppTheme.lushRed;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _asset,
      height: height,
      width: width,
      fit: fit,
      filterQuality: filterQuality,
      errorBuilder: (_, __, ___) => SizedBox(
        height: height,
        width: width ?? height,
        child: Center(
          child: Icon(
            Icons.campaign_outlined,
            size: height * 0.72,
            color: _fallbackIconColor,
          ),
        ),
      ),
    );
  }
}

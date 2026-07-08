import 'package:flutter/material.dart';

import '../shared/branding.dart';
import '../shared/themes.dart';

/// Official iMart Group Ltd mark — clean plate, no crush/crop.
enum VllLogoTone {
  onLightSurface,
  onBrandField,
}

class VllBrandLogo extends StatelessWidget {
  const VllBrandLogo({
    super.key,
    this.height = 88,
    this.maxWidth = 240,
    this.tone = VllLogoTone.onLightSurface,
  });

  final double height;
  final double maxWidth;
  final VllLogoTone tone;

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      VllBranding.logoAsset,
      height: height,
      width: maxWidth,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(
        Icons.public,
        size: height * 0.65,
        color: AppTheme.lushRed,
      ),
    );

    // Always sit on a clean white card so red/navy wordmark stays crisp.
    return Semantics(
      label: VllBranding.company,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: height + 24),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: tone == VllLogoTone.onBrandField
                ? Colors.white.withValues(alpha: 0.35)
                : const Color(0xFFE6E8ED),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: tone == VllLogoTone.onBrandField ? 0.18 : 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: logo,
      ),
    );
  }
}

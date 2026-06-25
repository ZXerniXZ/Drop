import 'package:flutter/material.dart';

class DropLogo extends StatelessWidget {
  const DropLogo({
    super.key,
    this.height = 26,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = isDark
        ? 'assets/branding/logo_header_dark.png'
        : 'assets/branding/logo_header_light.png';

    return Image.asset(
      asset,
      height: height,
      width: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}

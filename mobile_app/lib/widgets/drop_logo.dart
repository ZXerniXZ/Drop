import 'package:flutter/material.dart';

class DropLogo extends StatelessWidget {
  const DropLogo({
    super.key,
    this.height = 28,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = isDark
        ? 'assets/branding/logo_header_dark.png'
        : 'assets/branding/logo_header_light.png';

    return Semantics(
      label: 'Drop',
      image: true,
      child: Image.asset(
        asset,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

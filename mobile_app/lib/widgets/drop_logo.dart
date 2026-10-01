import 'package:flutter/material.dart';

/// White hand-drawn droplet on black. Same mark in light and dark UI.
class DropLogo extends StatelessWidget {
  const DropLogo({
    super.key,
    this.height = 26,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/logo_header.png',
      height: height,
      width: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );
  }
}

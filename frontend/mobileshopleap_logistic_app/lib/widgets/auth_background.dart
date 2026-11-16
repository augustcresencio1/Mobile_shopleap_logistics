import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Flat light-blue background shared by the auth screens.
class AuthBackground extends StatelessWidget {
  const AuthBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: kBrandPaleBlue,
      child: child,
    );
  }
}

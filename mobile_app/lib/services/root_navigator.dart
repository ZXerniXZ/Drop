import 'package:flutter/material.dart';

/// Il banner web è disegnato sopra il [Navigator], quindi i dialoghi aperti
/// dal suo context non trovano una route. Usano questa key.
class RootNavigator {
  RootNavigator._();

  static final key = GlobalKey<NavigatorState>();
}

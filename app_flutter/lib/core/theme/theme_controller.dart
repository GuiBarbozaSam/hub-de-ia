import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeControllerProvider =
StateNotifierProvider<ThemeController, ThemeMode>((ref) {
  return ThemeController();
});

class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.dark);

  void setMode(ThemeMode mode) => state = mode;

  void toggle() {
    state = (state == ThemeMode.dark) ? ThemeMode.light : ThemeMode.dark;
  }
}
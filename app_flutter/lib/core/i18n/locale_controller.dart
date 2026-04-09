import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final localeControllerProvider =
StateNotifierProvider<LocaleController, Locale>((ref) {
  return LocaleController();
});

class LocaleController extends StateNotifier<Locale> {
  LocaleController() : super(const Locale('pt', 'BR'));

  void setLocale(Locale locale) => state = locale;

  void setPtBr() => state = const Locale('pt', 'BR');
  void setEn() => state = const Locale('en');
}
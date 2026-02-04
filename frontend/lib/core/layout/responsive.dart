import 'package:flutter/material.dart';

/// Брейкпоинты и утилиты для адаптивной вёрстки (Material / Apple-подход).
class Responsive {
  static const double breakpointTablet = 600;
  static const double breakpointDesktop = 840;

  /// Максимальная ширина контента для читабельности на больших экранах.
  static const double maxContentWidth = 720;

  /// Отступы контента по горизонтали.
  static double contentPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= breakpointDesktop) return 32;
    if (width >= breakpointTablet) return 24;
    return 16;
  }

  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < breakpointTablet;

  static bool isTabletOrWider(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= breakpointTablet;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= breakpointDesktop;

  /// Количество колонок сетки для списка карточек.
  static int gridCrossAxisCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= breakpointDesktop) return 2;
    if (width >= breakpointTablet) return 2;
    return 1;
  }

  /// Показывать drawer (боковое меню) как основную навигацию на планшете/десктопе.
  static bool useDrawer(BuildContext context) => isTabletOrWider(context);
}

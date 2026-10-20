import 'package:flutter/material.dart';

import 'app_colors.dart';

// ============================================================
// أنماط النصوص الموحدة
// ============================================================

class AppTextStyles {
  AppTextStyles._();

  // ============================================================
  // العناوين
  // ============================================================

  static const TextStyle pageTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  // ============================================================
  // النصوص
  // ============================================================

  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontSize: 13,
    color: AppColors.textSecondary,
  );

  static const TextStyle small = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
  );

  // ============================================================
  // الأرقام
  // ============================================================

  static const TextStyle statisticNumber = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  // ============================================================
  // Drawer
  // ============================================================

  static const TextStyle drawerTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static const TextStyle drawerItem = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );
}
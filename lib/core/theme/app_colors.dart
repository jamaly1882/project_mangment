import 'package:flutter/material.dart';

// ============================================================
// ألوان التطبيق الموحدة
// ============================================================

class AppColors {
  AppColors._();

  // ============================================================
  // اللون الأساسي
  // ============================================================

  static const Color primary = Color(0xFF1565C0);

  static const Color primaryDark = Color(0xFF0D47A1);

  static const Color primaryLight = Color(0xFF42A5F5);

  // ============================================================
  // ألوان الحالات
  // ============================================================

  static const Color success = Color(0xFF2E7D32);

  static const Color warning = Color(0xFFF9A825);

  static const Color danger = Color(0xFFC62828);

  static const Color info = Color(0xFF0277BD);

  // ============================================================
  // ألوان الخلفيات
  // ============================================================

  static const Color background = Color(0xFFF5F7FA);

  static const Color surface = Colors.white;

  static const Color border = Color(0xFFE0E0E0);

  // ============================================================
  // ألوان النصوص
  // ============================================================

  static const Color textPrimary = Color(0xFF1F2937);

  static const Color textSecondary = Color(0xFF6B7280);

  static const Color textLight = Color(0xFF9CA3AF);

  // ============================================================
  // ألوان إضافية
  // ============================================================

  static const Color quantity = Color(0xFF1565C0);

  static const Color time = Color(0xFF6A1B9A);

  static const Color engineer = Color(0xFF00897B);

  static const Color driver = Color(0xFFEF6C00);

  /// لون مشرف البند (بديل السائق في إسناد البنود).
  static const Color supervisor = Color(0xFF6A1B9A);

  static const Color accountant = Color(0xFF2E7D32);

  static const Color admin = Color(0xFF4527A0);

  // ============================================================
  // ألوان مناصب الهيكل الإداري
  // ============================================================

  /// المشرف الرئيسي.
  static const Color generalManager = Color(0xFF4527A0);

  /// مدير إدارة المشاريع.
  static const Color projectsDeptManager = Color(0xFF1565C0);

  /// مدير إدارة الجودة والتكلفة.
  static const Color qualityCostManager = Color(0xFF00838F);

  /// مهندس المشروع (= مدير المشروع).
  static const Color projectEngineer = Color(0xFF00897B);

  /// مشرف المشروع.
  static const Color projectSupervisor = Color(0xFF6A1B9A);

  /// مدير إدارة الحركة.
  static const Color movementDeptManager = Color(0xFFEF6C00);

  /// مدير المحروقات.
  static const Color fuelManager = Color(0xFFD84315);

  /// مراقب الحركة.
  static const Color movementMonitor = Color(0xFFF4511E);

  /// المدير المالي.
  static const Color financialManager = Color(0xFF2E7D32);

  /// إدارة الحسابات.
  static const Color accountsManager = Color(0xFF33691E);

  /// محاسب المشروع.
  static const Color projectAccountant = Color(0xFF558B2F);
}
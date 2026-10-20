
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

// ============================================================
// App Widgets
// جميع مكونات الواجهات الموحدة للتطبيق
// ============================================================

class AppWidgets {
  AppWidgets._();

  // ============================================================
  // رسالة نجاح
  // ============================================================

  static void showSuccess(
    BuildContext context,
    String message,
  ) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              const Icon(
                Icons.check_circle,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // رسالة خطأ
  // ============================================================

  static void showError(
    BuildContext context,
    String message,
  ) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              const Icon(
                Icons.error,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // رسالة تحذير
  // ============================================================

  static void showWarning(
    BuildContext context,
    String message,
  ) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              const Icon(
                Icons.warning,
                color: Colors.black,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // نافذة تأكيد
  // ============================================================

  static Future<bool> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = 'تأكيد',
    String cancelText = 'إلغاء',
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(
              title,
              textAlign: TextAlign.right,
            ),
            content: Text(
              message,
              textAlign: TextAlign.right,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    false,
                  );
                },
                child: Text(cancelText),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: danger
                      ? AppColors.danger
                      : AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    true,
                  );
                },
                child: Text(confirmText),
              ),
            ],
          ),
        );
      },
    );

    return result ?? false;
  }
}

// ============================================================
// Scaffold موحد
// ============================================================

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget child;

  final Widget? drawer;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  /// إذا كانت true يظهر زر الرجوع.
  ///
  /// وإذا كانت false فسيظهر زر الرجوع تلقائيًا
  /// إذا كانت الصفحة الحالية داخل Navigator
  /// ويوجد Route سابق.
  final bool showBackButton;

  /// حدث مخصص لزر الرجوع.
  final VoidCallback? onBack;

  final Color? backgroundColor;

  const AppScaffold({
    super.key,
    required this.title,
    required this.child,
    this.drawer,
    this.actions,
    this.floatingActionButton,
    this.showBackButton = false,
    this.onBack,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final bool canPop =
        Navigator.of(context).canPop();

    final bool shouldShowBackButton =
        drawer == null &&
        (showBackButton || canPop);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            backgroundColor ??
                AppColors.background,

        appBar: AppBar(
          title: Text(
            title,
            textAlign: TextAlign.center,
          ),
          centerTitle: true,

          automaticallyImplyLeading:
              drawer != null ||
              shouldShowBackButton,

          leading: shouldShowBackButton
              ? IconButton(
                  tooltip: 'رجوع',
                  icon: const Icon(
                    Icons.arrow_forward,
                  ),
                  onPressed: onBack ??
                      () {
                        if (Navigator.of(
                          context,
                        ).canPop()) {
                          Navigator.of(
                            context,
                          ).pop();
                        }
                      },
                )
              : null,

          actions: actions,
        ),

        drawer: drawer,

        body: SafeArea(
          child: child,
        ),

        floatingActionButton:
            floatingActionButton,
      ),
    );
  }
}

// ============================================================
// مساحة محتوى الصفحة
// ============================================================

class AppPage extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// true:
  /// الصفحة تستخدم SingleChildScrollView.
  ///
  /// false:
  /// الصفحة تستخدم الارتفاع المتاح مباشرة،
  /// ومناسبة للصفحات التي تحتوي Expanded أو TabBarView.
  final bool scrollable;

  const AppPage({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: scrollable
          ? SingleChildScrollView(
              padding: padding,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1200,
                  ),
                  child: child,
                ),
              ),
            )
          : Padding(
              padding: padding,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1200,
                  ),
                  child: child,
                ),
              ),
            ),
    );
  }
}

// ============================================================
// رأس الصفحة
// ============================================================

class AppPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.only(
          bottom: 20,
        ),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius:
                      BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
            ],

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.right,
                    style:
                        AppTextStyles.pageTitle,
                  ),

                  if (subtitle != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      subtitle!,
                      textAlign:
                          TextAlign.right,
                      style: AppTextStyles
                          .bodySecondary,
                    ),
                  ],
                ],
              ),
            ),

            if (trailing != null)
              trailing!,
          ],
        ),
      ),
    );
  }
}

// ============================================================
// عنوان القسم
// ============================================================

class AppSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  const AppSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.only(
          bottom: 12,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
            ],

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    textAlign:
                        TextAlign.right,
                    style:
                        AppTextStyles.sectionTitle,
                  ),

                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      textAlign:
                          TextAlign.right,
                      style: AppTextStyles
                          .bodySecondary,
                    ),
                  ],
                ],
              ),
            ),

            if (trailing != null)
              trailing!,
          ],
        ),
      ),
    );
  }
}

// ============================================================
// بطاقة موحدة
// ============================================================

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;
  final double? elevation;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.color,
    this.elevation,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      color:
          color ?? AppColors.surface,
      elevation:
          elevation ?? 1,
      margin:
          margin ?? EdgeInsets.zero,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    if (onTap == null) {
      return card;
    }

    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(16),
      child: card,
    );
  }
}

// ============================================================
// بطاقة إحصائية
// ============================================================

class AppStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  const AppStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor =
        color ?? AppColors.primary;

    return AppCard(
      onTap: onTap,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color:
                    cardColor.withValues(
                  alpha: 0.12,
                ),
                borderRadius:
                    BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: cardColor,
                size: 28,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    textAlign:
                        TextAlign.right,
                    style: AppTextStyles
                        .bodySecondary,
                  ),

                  const SizedBox(height: 4),

                  Text(
                    value,
                    textAlign:
                        TextAlign.right,
                    style: AppTextStyles
                        .statisticNumber,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// بطاقة إدارة
// ============================================================

class AppManagementCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  const AppManagementCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor =
        color ?? AppColors.primary;

    return AppCard(
      onTap: onTap,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color:
                    cardColor.withValues(
                  alpha: 0.12,
                ),
                borderRadius:
                    BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: cardColor,
                size: 26,
              ),
            ),

            const SizedBox(height: 14),

            Text(
              title,
              textAlign: TextAlign.right,
              style:
                  AppTextStyles.cardTitle,
            ),

            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign:
                    TextAlign.right,
                style: AppTextStyles
                    .bodySecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// زر رئيسي
// ============================================================

class AppButton extends StatelessWidget {
  final String? text;
  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;

  const AppButton({
    super.key,
    this.text,
    this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.expanded = false,
  }) : assert(
          text != null || label != null,
          'يجب تحديد text أو label',
        );

  String get buttonText =>
      text ?? label!;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: _buildButton(),
    );
  }

  Widget _buildButton() {
    Widget button;

    if (icon != null) {
      button = ElevatedButton.icon(
        onPressed:
            loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child:
                    CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(
          buttonText,
          textAlign: TextAlign.center,
        ),
      );
    } else {
      button = ElevatedButton(
        onPressed:
            loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                buttonText,
                textAlign:
                    TextAlign.center,
              ),
      );
    }

    if (expanded) {
      return SizedBox(
        width: double.infinity,
        child: button,
      );
    }

    return button;
  }
}

// ============================================================
// زر ثانوي
// ============================================================

class AppOutlinedButton extends StatelessWidget {
  final String? text;
  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expanded;

  const AppOutlinedButton({
    super.key,
    this.text,
    this.label,
    this.icon,
    this.onPressed,
    this.expanded = false,
  }) : assert(
          text != null || label != null,
          'يجب تحديد text أو label',
        );

  String get buttonText =>
      text ?? label!;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: _buildButton(),
    );
  }

  Widget _buildButton() {
    Widget button;

    if (icon != null) {
      button = OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(
          buttonText,
          textAlign: TextAlign.center,
        ),
      );
    } else {
      button = OutlinedButton(
        onPressed: onPressed,
        child: Text(
          buttonText,
          textAlign: TextAlign.center,
        ),
      );
    }

    if (expanded) {
      return SizedBox(
        width: double.infinity,
        child: button,
      );
    }

    return button;
  }
}

// ============================================================
// حقل إدخال موحد
// ============================================================

class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? helperText;
  final String? suffixText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int maxLines;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool enabled;

  const AppTextField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.helperText,
    this.suffixText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.maxLines = 1,
    this.validator,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        maxLines: maxLines,
        validator: validator,
        onChanged: onChanged,
        onTap: onTap,
        readOnly: readOnly,
        enabled: enabled,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          suffixText: suffixText,
          prefixIcon: prefixIcon != null
              ? Icon(prefixIcon)
              : null,
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }
}

// ============================================================
// حقل أرقام
// ============================================================

class AppNumberField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? suffixText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final bool enabled;
  final bool readOnly;

  const AppNumberField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.suffixText,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.validator,
    this.enabled = true,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        readOnly: readOnly,
        keyboardType:
            const TextInputType.numberWithOptions(
          decimal: true,
        ),
        onChanged: onChanged,
        validator: validator,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffixText,
          prefixIcon: prefixIcon != null
              ? Icon(prefixIcon)
              : null,
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }
}

// ============================================================
// Dropdown / اختيار
// ============================================================

class AppDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final IconData? prefixIcon;
  final String? Function(T?)? validator;
  final String? hint;
  final bool enabled;

  const AppDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.prefixIcon,
    this.validator,
    this.hint,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        items: items,
        onChanged:
            enabled ? onChanged : null,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: prefixIcon != null
              ? Icon(prefixIcon)
              : null,
        ),
      ),
    );
  }
}

// ============================================================
// حقل التاريخ
// ============================================================

class AppDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  final DateTime? firstDate;
  final DateTime? lastDate;

  final IconData icon;
  final bool enabled;

  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.icon = Icons.calendar_month,
    this.enabled = true,
  });

  String _formatDate(DateTime date) {
    final day =
        date.day.toString().padLeft(2, '0');

    final month =
        date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final effectiveFirstDate =
        firstDate ?? DateTime(2000);

    final effectiveLastDate =
        lastDate ?? DateTime(2100);

    DateTime initialDate =
        value ?? now;

    if (initialDate.isBefore(
      effectiveFirstDate,
    )) {
      initialDate =
          effectiveFirstDate;
    }

    if (initialDate.isAfter(
      effectiveLastDate,
    )) {
      initialDate =
          effectiveLastDate;
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: InkWell(
        borderRadius:
            BorderRadius.circular(12),
        onTap: !enabled
            ? null
            : () async {
                final selected =
                    await showDatePicker(
                  context: context,
                  initialDate: initialDate,
                  firstDate:
                      effectiveFirstDate,
                  lastDate:
                      effectiveLastDate,
                  locale:
                      const Locale('ar'),
                );

                if (selected != null) {
                  onChanged(selected);
                }
              },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            enabled: enabled,
          ),
          child: Text(
            value == null
                ? 'اختر التاريخ'
                : _formatDate(value!),
            textAlign:
                TextAlign.right,
            style: TextStyle(
              color: value == null
                  ? AppColors
                      .textSecondary
                  : AppColors
                      .textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// حالة التحميل
// ============================================================

class AppLoading extends StatelessWidget {
  final String message;

  const AppLoading({
    super.key,
    this.message =
        'جاري التحميل...',
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Padding(
          padding:
              const EdgeInsets.all(30),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),

              const SizedBox(height: 16),

              Text(
                message,
                textAlign:
                    TextAlign.center,
                style: AppTextStyles
                    .bodySecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// حالة عدم وجود بيانات
// ============================================================

class AppEmpty extends StatelessWidget {
  final String? message;
  final String? title;
  final String? actionText;
  final IconData icon;
  final VoidCallback? onRetry;

  const AppEmpty({
    super.key,
    this.message,
    this.title,
    this.actionText,
    this.icon =
        Icons.inbox_outlined,
    this.onRetry,
  });

  String get displayMessage =>
      message ??
      title ??
      'لا توجد بيانات';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Padding(
          padding:
              const EdgeInsets.all(30),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 64,
                color:
                    AppColors.textLight,
              ),

              const SizedBox(height: 16),

              Text(
                displayMessage,
                textAlign:
                    TextAlign.center,
                style: AppTextStyles
                    .bodySecondary,
              ),

              if (onRetry != null) ...[
                const SizedBox(height: 16),

                AppOutlinedButton(
                  text:
                      actionText ??
                          'إعادة المحاولة',
                  icon:
                      Icons.refresh,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// حالة الخطأ
// ============================================================

class AppError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const AppError({
    super.key,
    this.message =
        'حدث خطأ أثناء تحميل البيانات',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Padding(
          padding:
              const EdgeInsets.all(30),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color:
                    AppColors.danger,
              ),

              const SizedBox(height: 16),

              Text(
                message,
                textAlign:
                    TextAlign.center,
                style:
                    AppTextStyles.body,
              ),

              if (onRetry != null) ...[
                const SizedBox(height: 16),

                AppOutlinedButton(
                  text:
                      'إعادة المحاولة',
                  icon:
                      Icons.refresh,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Badge للحالة
// ============================================================

class AppStatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const AppStatusBadge({
    super.key,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color:
              color.withValues(
            alpha: 0.12,
          ),
          borderRadius:
              BorderRadius.circular(20),
        ),
        child: Text(
          text,
          textAlign:
              TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// عنصر معلومات
// ============================================================

class AppInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const AppInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          vertical: 7,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 19,
                color:
                    AppColors
                        .textSecondary,
              ),
              const SizedBox(width: 8),
            ],

            Expanded(
              flex: 2,
              child: Text(
                label,
                textAlign:
                    TextAlign.right,
                style: AppTextStyles
                    .bodySecondary,
              ),
            ),

            Expanded(
              flex: 3,
              child: Text(
                value,
                textAlign:
                    TextAlign.right,
                style:
                    AppTextStyles.body.copyWith(
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// مؤشر تقدم
// ============================================================

class AppProgress extends StatelessWidget {
  final double value;
  final String? label;
  final Color? color;
  final Color? progressColor;
  final Color? backgroundColor;

  final double height;

  const AppProgress({
    super.key,
    required this.value,
    this.label,
    this.color,
    this.progressColor,
    this.backgroundColor,
    this.height = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    final double safeValue =
        value
            .clamp(0.0, 1.0)
            .toDouble();

    final effectiveColor =
        progressColor ??
        color ??
        AppColors.primary;

    return Directionality(
      textDirection:
          TextDirection.rtl,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    label!,
                    textAlign:
                        TextAlign.right,
                    style:
                        AppTextStyles.small,
                  ),
                ),

                Text(
                  '${(safeValue * 100).toStringAsFixed(0)}%',
                  style:
                      AppTextStyles.small.copyWith(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 7),
          ],

          ClipRRect(
            borderRadius:
                BorderRadius.circular(
              height,
            ),
            child:
                LinearProgressIndicator(
              value: safeValue,
              minHeight: height,
              color: effectiveColor,
              backgroundColor:
                  backgroundColor ??
                  effectiveColor.withValues(
                    alpha: 0.12,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// قيم المسافات الرقمية
// ============================================================

class AppSpacingValue {
  AppSpacingValue._();

  static const double xs = 6.0;
  static const double sm = 10.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
}

// ============================================================
// المسافات الموحدة
// ============================================================

class AppSpacing {
  AppSpacing._();

  static const double xs =
      AppSpacingValue.xs;

  static const double sm =
      AppSpacingValue.sm;

  static const double md =
      AppSpacingValue.md;

  static const double lg =
      AppSpacingValue.lg;

  static const double xl =
      AppSpacingValue.xl;

  static const SizedBox verticalXs =
      SizedBox(
    height: AppSpacingValue.xs,
  );

  static const SizedBox verticalSm =
      SizedBox(
    height: AppSpacingValue.sm,
  );

  static const SizedBox verticalMd =
      SizedBox(
    height: AppSpacingValue.md,
  );

  static const SizedBox verticalLg =
      SizedBox(
    height: AppSpacingValue.lg,
  );

  static const SizedBox verticalXl =
      SizedBox(
    height: AppSpacingValue.xl,
  );

  static const SizedBox horizontalXs =
      SizedBox(
    width: AppSpacingValue.xs,
  );

  static const SizedBox horizontalSm =
      SizedBox(
    width: AppSpacingValue.sm,
  );

  static const SizedBox horizontalMd =
      SizedBox(
    width: AppSpacingValue.md,
  );

  static const SizedBox horizontalLg =
      SizedBox(
    width: AppSpacingValue.lg,
  );

  static const SizedBox horizontalXl =
      SizedBox(
    width: AppSpacingValue.xl,
  );
}

// ============================================================
// المسافات الأفقية
// للتوافق مع الكود القديم
// ============================================================

class AppSpacingHorizontal {
  AppSpacingHorizontal._();

  static const SizedBox xs =
      SizedBox(
    width: AppSpacingValue.xs,
  );

  static const SizedBox sm =
      SizedBox(
    width: AppSpacingValue.sm,
  );

  static const SizedBox md =
      SizedBox(
    width: AppSpacingValue.md,
  );

  static const SizedBox lg =
      SizedBox(
    width: AppSpacingValue.lg,
  );

  static const SizedBox xl =
      SizedBox(
    width: AppSpacingValue.xl,
  );
}

// ============================================================
// Grid متجاوب
// ============================================================

class AppResponsiveGrid
    extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  const AppResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 250,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection:
          TextDirection.rtl,
      child: LayoutBuilder(
        builder:
            (context, constraints) {
          final availableWidth =
              constraints.maxWidth;

          int columns =
              (availableWidth /
                      (minItemWidth +
                          spacing))
                  .floor();

          if (columns < 1) {
            columns = 1;
          }

          return GridView.builder(
            shrinkWrap: true,
            physics:
                const NeverScrollableScrollPhysics(),
            itemCount:
                children.length,
            gridDelegate:
                SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:
                  columns,
              crossAxisSpacing:
                  spacing,
              mainAxisSpacing:
                  spacing,
              childAspectRatio:
                  columns == 1
                      ? 2.2
                      : 1.55,
            ),
            itemBuilder:
                (context, index) {
              return children[index];
            },
          );
        },
      ),
    );
  }
}

// ============================================================
// Drawer موحد
// ============================================================

class AppDrawer
    extends StatelessWidget {
  final String userName;
  final String roleName;
  final String? projectName;
  final List<AppDrawerItem> items;
  final VoidCallback? onLogout;

  const AppDrawer({
    super.key,
    required this.userName,
    required this.roleName,
    this.projectName,
    required this.items,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection:
          TextDirection.rtl,
      child: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(20),
                decoration:
                    const BoxDecoration(
                  color:
                      AppColors.primary,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor:
                          Colors.white,
                      child: Text(
                        userName.isNotEmpty
                            ? userName
                                .characters
                                .first
                            : 'م',
                        style:
                            const TextStyle(
                          fontSize: 24,
                          fontWeight:
                              FontWeight.bold,
                          color:
                              AppColors
                                  .primary,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    Text(
                      userName,
                      textAlign:
                          TextAlign.right,
                      style: AppTextStyles
                          .drawerTitle,
                    ),

                    const SizedBox(
                      height: 4,
                    ),

                    Text(
                      roleName,
                      textAlign:
                          TextAlign.right,
                      style:
                          const TextStyle(
                        color:
                            Colors.white70,
                        fontSize: 13,
                      ),
                    ),

                    if (projectName !=
                        null) ...[
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        projectName!,
                        textAlign:
                            TextAlign.right,
                        style:
                            const TextStyle(
                          color:
                              Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  children: [
                    ...items.map(
                      (item) =>
                          ListTile(
                        leading: Icon(
                          item.icon,
                          color: item.selected
                              ? AppColors
                                  .primary
                              : AppColors
                                  .textSecondary,
                        ),

                        title: Text(
                          item.title,
                          textAlign:
                              TextAlign.right,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                item.selected
                                    ? FontWeight
                                        .bold
                                    : FontWeight
                                        .normal,
                            color: item.selected
                                ? AppColors
                                    .primary
                                : AppColors
                                    .textPrimary,
                          ),
                        ),

                        selected:
                            item.selected,

                        selectedTileColor:
                            AppColors
                                .primary
                                .withValues(
                          alpha: 0.08,
                        ),

                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(
                            10,
                          ),
                        ),

                        onTap: () {
                          Navigator.pop(
                            context,
                          );

                          item.onTap();
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(),

              ListTile(
                leading: const Icon(
                  Icons.logout,
                  color:
                      AppColors.danger,
                ),

                title: const Text(
                  'تسجيل الخروج',
                  textAlign:
                      TextAlign.right,
                  style: TextStyle(
                    color:
                        AppColors.danger,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                onTap: onLogout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// عنصر Drawer
// ============================================================

class AppDrawerItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  const AppDrawerItem({
    required this.title,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });
}


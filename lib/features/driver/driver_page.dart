import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

// =============================================================
// لوحة السائق (دور قديم — مغلقة)
// =============================================================

/// تم استبدال السائق بـ «مشرف البند» في إسناد البنود وتسجيل الاستهلاك.
///
/// لذلك لم تعد لوحة السائق تفتح لأي حساب، ومن يبقى حسابه على دور
/// `driver` يرى هذه الرسالة فقط حتى يحوّله مسؤول النظام إلى
/// «مشرف بند» من صفحة المستخدمين، فيفتح بعدها لوحته الطبيعية
/// ويظهر له نفس بنوده المسندة سابقًا.
class DriverPage extends StatelessWidget {
  final List<String> projectIds;

  const DriverPage({
    super.key,
    this.projectIds = const <String>[],
  });

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/',
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'حساب السائق قديم',
      child: AppPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.block,
                    size: 54,
                    color: AppColors.warning,
                  ),
                  AppSpacing.verticalMd,
                  const Text(
                    'دور «السائق» لم يعد مستخدمًا في النظام',
                    style: AppTextStyles.cardTitle,
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.verticalSm,
                  const Text(
                    'حلّ «مشرف البند» محله: هو من يسجّل الاستهلاك الفعلي '
                    '(الوقود والزيت وساعات العمل) ويضيف التكاليف الفعلية '
                    'لبند المواد والعمالة والمعدات والمحروقات، '
                    'من صفحة البند المسند إليه.',
                    style: AppTextStyles.body,
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.verticalMd,
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'ما المطلوب؟',
                          style: AppTextStyles.sectionTitle,
                        ),
                        AppSpacing.verticalXs,
                        Text(
                          '1) يفتح مسؤول النظام صفحة «المستخدمين».\n'
                          '2) يختار هذا الحساب ويغيّر دوره إلى '
                          '«مشرف بند».\n'
                          '3) يسجّل المستخدم الدخول من جديد، '
                          'فتظهر له البنود نفسها التي كانت مسندة إليه '
                          'وهو سائق.',
                          style: AppTextStyles.bodySecondary,
                        ),
                      ],
                    ),
                  ),
                  AppSpacing.verticalLg,
                  AppButton(
                    label: 'تسجيل الخروج',
                    icon: Icons.logout,
                    expanded: true,
                    onPressed: () => _logout(context),
                  ),
                ],
              ),
            ),
            AppSpacing.verticalXl,
          ],
        ),
      ),
    );
  }
}

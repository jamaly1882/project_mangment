import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

class AccountantPage extends StatelessWidget {
  const AccountantPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'لوحة مدير الحسابات',
      child: AppPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // =====================================================
            // عنوان الصفحة
            // =====================================================

            AppPageHeader(
              title: 'لوحة مدير الحسابات',
              subtitle: 'إدارة ومتابعة البيانات المالية للمشاريع',
              icon: Icons.account_balance,
            ),

            AppSpacing.verticalLg,

            // =====================================================
            // البطاقة الرئيسية
            // =====================================================

            AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.accountant.withValues(
                        alpha: 0.10,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.account_balance,
                      size: 42,
                      color: AppColors.accountant,
                    ),
                  ),

                  AppSpacing.verticalMd,

                  const Text(
                    'مرحبًا بك في لوحة الحسابات',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.sectionTitle,
                  ),

                  AppSpacing.verticalSm,

                  const Text(
                    'سيتم من هنا إدارة ومتابعة الحسابات والتقارير المالية للمشاريع.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySecondary,
                  ),
                ],
              ),
            ),

            AppSpacing.verticalLg,

            // =====================================================
            // أقسام الحسابات
            // =====================================================

            const AppSectionTitle(
              title: 'إدارة الحسابات',
              icon: Icons.account_balance_wallet,
            ),

            AppSpacing.verticalMd,

            // =====================================================
            // التقارير المالية
            // =====================================================

            AppCard(
              padding: const EdgeInsets.all(18),
              onTap: () {},
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(
                        alpha: 0.10,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bar_chart,
                      color: AppColors.info,
                    ),
                  ),

                  AppSpacingHorizontal.md,

                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'التقارير المالية',
                          style: AppTextStyles.cardTitle,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'عرض ومتابعة التقارير المالية للمشاريع',
                          style: AppTextStyles.bodySecondary,
                        ),
                      ],
                    ),
                  ),

                  const Icon(
                    Icons.arrow_back_ios,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),

            AppSpacing.verticalMd,

            // =====================================================
            // المصروفات
            // =====================================================

            AppCard(
              padding: const EdgeInsets.all(18),
              onTap: () {},
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(
                        alpha: 0.10,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.payments_outlined,
                      color: AppColors.warning,
                    ),
                  ),

                  AppSpacingHorizontal.md,

                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'المصروفات',
                          style: AppTextStyles.cardTitle,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'متابعة مصروفات المشاريع والعمليات المالية',
                          style: AppTextStyles.bodySecondary,
                        ),
                      ],
                    ),
                  ),

                  const Icon(
                    Icons.arrow_back_ios,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),

            AppSpacing.verticalMd,

            // =====================================================
            // الحسابات
            // =====================================================

            AppCard(
              padding: const EdgeInsets.all(18),
              onTap: () {},
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(
                        alpha: 0.10,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.receipt_long,
                      color: AppColors.success,
                    ),
                  ),

                  AppSpacingHorizontal.md,

                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الحسابات',
                          style: AppTextStyles.cardTitle,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'إدارة الحسابات والمعاملات المالية',
                          style: AppTextStyles.bodySecondary,
                        ),
                      ],
                    ),
                  ),

                  const Icon(
                    Icons.arrow_back_ios,
                    size: 18,
                    color: AppColors.textSecondary,
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
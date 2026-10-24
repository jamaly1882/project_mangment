import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/cost_lines.dart';
import '../../core/utils/costs.dart';
import '../../core/widgets/app_widgets.dart';

/// ============================================================
/// بطاقة البند (قراءة فقط) — لمهندس المشروع
/// ============================================================
///
/// مهندس المشروع يتابع الإحصاءات فقط: الكميات، ونِسب التنفيذ،
/// وتكاليف البند المخططة والمنفذة وأسطرها. لا يوجد هنا أي زر
/// إضافة أو تعديل؛ فإدخال البنود والكميات التعاقدية والتكاليف
/// صلاحية مدير إدارة الجودة، وتسجيل الكميات المنفذة صلاحية
/// مشرف البند.
class ItemOverviewPage extends StatefulWidget {
  final String projectId;
  final String itemId;

  const ItemOverviewPage({
    super.key,
    required this.projectId,
    required this.itemId,
  });

  @override
  State<ItemOverviewPage> createState() => _ItemOverviewPageState();
}

class _ItemOverviewPageState extends State<ItemOverviewPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  String? _error;

  Map<String, dynamic> _item = <String, dynamic>{};
  Map<String, dynamic> _details = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final itemDoc =
          await _firestore.collection('items').doc(widget.itemId).get();
      if (!itemDoc.exists) throw Exception('البند غير موجود.');

      final detailsDoc = await _firestore
          .collection('item_details')
          .doc(widget.itemId)
          .get();

      if (!mounted) return;
      setState(() {
        _item = itemDoc.data() ?? <String, dynamic>{};
        _details = detailsDoc.data() ?? <String, dynamic>{};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  double _number(dynamic value) => ProjectCosts.nonNegative(value);

  String _formatDate(dynamic value) {
    if (value is! Timestamp) return 'غير محددة';

    final date = value.toDate();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  CostLines get _planned => CostLines.fromData(
        _details.isNotEmpty ? _details : _item,
        contractQuantity: _quantity,
        unit: _text(_item['unit']),
      );

  CostLines get _actual => CostLines.fromData(
        _details.isNotEmpty ? _details : _item,
        actual: true,
        contractQuantity: _quantity,
        unit: _text(_item['unit']),
      );

  double get _quantity {
    final executed = _number(_item['executedQuantity']);
    return executed > 0 ? executed : _number(_item['contractQuantity']);
  }

  Widget _buildLinesCard(CostLines lines, String title, String emptyMessage) {
    if (lines.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionTitle(title: title, icon: Icons.receipt_long_outlined),
            AppSpacing.verticalSm,
            Text(emptyMessage, style: AppTextStyles.small),
          ],
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionTitle(
            title: '$title — ${ProjectCosts.formatMoney(lines.grandTotal)}',
            icon: Icons.receipt_long_outlined,
          ),
          AppSpacing.verticalSm,
          for (final schema in CostLineSchema.ordered)
            if (lines[schema.kind].isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(schema.icon, size: 16, color: AppColors.textSecondary),
                    AppSpacing.horizontalXs,
                    Expanded(
                      child: Text(
                        schema.title,
                        style: AppTextStyles.small,
                      ),
                    ),
                    Text(
                      ProjectCosts.formatMoney(lines.totalOf(schema.kind)),
                      style: AppTextStyles.small,
                    ),
                  ],
                ),
              ),
              for (final line in lines[schema.kind])
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          schema.describe(line),
                          style: AppTextStyles.small.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        ProjectCosts.formatMoney(schema.costOf(line)),
                        style: AppTextStyles.small.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unit = _text(_item['unit']);
    final contract = _number(_item['contractQuantity']);
    final executed = _number(_item['executedQuantity']);
    final remaining = (contract - executed).clamp(0, double.infinity);
    final progress = contract <= 0
        ? 0.0
        : (executed / contract).clamp(0.0, 1.0).toDouble();

    final plannedTotal = ProjectCosts.totalOf(_details.isNotEmpty ? _details : _item);
    final actualTotal = ProjectCosts.actualTotalOf(
      _details.isNotEmpty ? _details : _item,
    );

    return AppScaffold(
      title: 'إحصاءات البند',
      showBackButton: true,
      child: _loading
          ? const AppLoading(message: 'جاري تحميل إحصاءات البند...')
          : _error != null
              ? AppPage(
                  child: Center(
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body,
                    ),
                  ),
                )
              : AppPage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppPageHeader(
                              title: _text(
                                _item['name'],
                                fallback: _text(
                                  _item['typeName'],
                                  fallback: 'بند',
                                ),
                              ),
                              subtitle: 'عرض فقط — الإدخال لدى مدير الجودة '
                                  'والمشرف',
                              icon: Icons.insights_outlined,
                            ),
                            AppSpacing.verticalMd,
                            AppInfoRow(
                              label: 'كود البند',
                              value: _text(_item['code'], fallback: '—'),
                              icon: Icons.tag_outlined,
                            ),
                            AppSpacing.verticalSm,
                            AppInfoRow(
                              label: 'نوع البند',
                              value: _text(_item['typeName'], fallback: '—'),
                              icon: Icons.category_outlined,
                            ),
                            AppSpacing.verticalSm,
                            AppInfoRow(
                              label: 'المشرف',
                              value: _text(
                                _details['supervisorName'],
                                fallback: 'غير محدد',
                              ),
                              icon: Icons.person_outline,
                            ),
                            AppSpacing.verticalSm,
                            AppInfoRow(
                              label: 'الكمية التعاقدية',
                              value: '${ProjectCosts.formatNumber(contract)} $unit',
                              icon: Icons.assignment_outlined,
                            ),
                            AppSpacing.verticalSm,
                            AppInfoRow(
                              label: 'الكمية المنفذة',
                              value: '${ProjectCosts.formatNumber(executed)} $unit',
                              icon: Icons.done_all,
                            ),
                            AppSpacing.verticalSm,
                            AppInfoRow(
                              label: 'المتبقي',
                              value:
                                  '${ProjectCosts.formatNumber(remaining)} $unit',
                              icon: Icons.pending_actions_outlined,
                            ),
                            AppSpacing.verticalSm,
                            AppInfoRow(
                              label: 'بداية العقد',
                              value: _formatDate(_item['executionStartDate']),
                              icon: Icons.event_available_outlined,
                            ),
                            AppSpacing.verticalSm,
                            AppInfoRow(
                              label: 'نهاية العقد',
                              value: _formatDate(_item['contractEndDate']),
                              icon: Icons.event_busy_outlined,
                            ),
                            AppSpacing.verticalMd,
                            AppProgress(
                              value: progress,
                              label: 'نسبة التنفيذ',
                            ),
                          ],
                        ),
                      ),
                      AppSpacing.verticalMd,
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AppSectionTitle(
                              title: 'إحصاءات التكاليف',
                              icon: Icons.pie_chart_outline,
                            ),
                            AppSpacing.verticalSm,
                            AppInfoRow(
                              label: 'التكلفة المخططة',
                              value: ProjectCosts.formatMoney(plannedTotal),
                              icon: Icons.timeline_outlined,
                            ),
                            AppSpacing.verticalXs,
                            AppInfoRow(
                              label: 'التكلفة الفعلية',
                              value: ProjectCosts.formatMoney(actualTotal),
                              icon: Icons.check_circle_outline,
                            ),
                            AppSpacing.verticalXs,
                            AppInfoRow(
                              label: 'الفرق',
                              value: ProjectCosts.formatMoney(
                                (actualTotal - plannedTotal).abs(),
                              ),
                              icon: Icons.compare_arrows,
                            ),
                          ],
                        ),
                      ),
                      AppSpacing.verticalMd,
                      _buildLinesCard(
                        _planned,
                        'أسطر المخطط',
                        'لم يسجّل مدير الجودة أسطر تكلفة مخططة لهذا البند.',
                      ),
                      AppSpacing.verticalMd,
                      _buildLinesCard(
                        _actual,
                        'أسطر التكلفة الفعلية',
                        'لم يسجّل مشرف البند تكاليف فعلية بعد.',
                      ),
                      AppSpacing.verticalXl,
                    ],
                  ),
                ),
    );
  }
}

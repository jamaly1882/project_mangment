import 'package:flutter/material.dart';

import '../../core/services/cost_prices.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/cost_lines.dart';
import '../../core/utils/costs.dart';
import '../../core/widgets/app_widgets.dart';

// =============================================================
// نافذة لصق جدول التحليل
// =============================================================

class PriceImportDialog extends StatefulWidget {
  final TextEditingController controller;

  /// [title] و[subtitle] للتفريق بين الاستيراد على البند وعلى المشروع.
  final String title;
  final String? subtitle;

  const PriceImportDialog({
    super.key,
    required this.controller,
    this.title = 'استيراد أسعار التكاليف',
    this.subtitle,
  });

  @override
  State<PriceImportDialog> createState() => _PriceImportDialogState();
}

class _PriceImportDialogState extends State<PriceImportDialog> {
  List<PriceEntry> _entries = <PriceEntry>[];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_parse);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_parse);
    super.dispose();
  }

  void _parse() {
    setState(() {
      _entries = CostPrices.parseTable(widget.controller.text);
    });
  }

  String _kindLabel(CostLineKind kind) {
    switch (kind) {
      case CostLineKind.material:
        return 'مواد';
      case CostLineKind.labor:
        return 'عمالة';
      case CostLineKind.equipment:
        return 'معدات';
      case CostLineKind.fuel:
        return 'محروقات';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.subtitle ??
                    'الصق سطور جدول التحليل. كل سطر يقبل 6 قيم مفصولة بـ Tab '
                        'أو شرطة | : المهنة، المصاريف، المعدة، الإهلاك، '
                        'المحروقات/المادة، السعر. الوقود (ديزل، بترول، غاز، '
                        'قاز، زيت) يُصنَّف محروقات، وما سواه في ذلك العمود مواد.',
                style: AppTextStyles.small,
              ),
              AppSpacing.verticalSm,
              AppTextField(
                controller: widget.controller,
                label: 'أسطر جدول التحليل',
                hint: 'سائق حفارة D155 | 11500 | حفارة D155 | 23100 | '
                    'ديزل | 475',
                maxLines: 8,
              ),
              AppSpacing.verticalMd,
              if (_entries.isEmpty)
                const Text(
                  'لا توجد أسطر مقروءة بعد.',
                  style: AppTextStyles.small,
                )
              else ...[
                Text(
                  'تم التعرف على ${_entries.length} سطرًا — '
                  'القسم مستنتج من الكلمات، ويمكن تغييره:',
                  style: AppTextStyles.small,
                ),
                AppSpacing.verticalSm,
                for (var index = 0; index < _entries.length; index++)
                  _buildPreviewRow(index),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: _entries.isEmpty
              ? null
              : () => Navigator.pop(context, _entries),
          child: const Text('تطبيق الأسعار'),
        ),
      ],
    );
  }

  Widget _buildPreviewRow(int index) {
    final entry = _entries[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(entry.label, style: AppTextStyles.body),
          ),
          AppSpacing.horizontalSm,
          Expanded(
            flex: 2,
            child: DropdownButton<CostLineKind>(
              value: entry.kind,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                for (final kind in CostLineKind.values)
                  DropdownMenuItem<CostLineKind>(
                    value: kind,
                    child: Text(_kindLabel(kind)),
                  ),
              ],
              onChanged: (kind) {
                if (kind == null) return;
                setState(() => entry.kind = kind);
              },
            ),
          ),
          AppSpacing.horizontalSm,
          Expanded(
            flex: 2,
            child: Text(
              ProjectCosts.formatNumber(entry.price),
              textAlign: TextAlign.left,
              style: AppTextStyles.body,
            ),
          ),
        ],
      ),
    );
  }
}

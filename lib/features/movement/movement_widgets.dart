import 'package:flutter/material.dart';

import '../../core/services/equipment_service.dart';
import '../../core/utils/equipment_calculations.dart';

// ============================================================
// أدوات مشتركة بين شاشات الحركة والديزل والورشة
// ============================================================

/// تنسيق رقم للعرض: فواصل آلاف، وبدون كسور إن كان صحيحًا.
String fmtNum(double value) {
  if (value.isNaN || value.isInfinite) return '0';
  final bool negative = value < 0;
  final double absValue = value.abs();
  final String text = absValue == absValue.roundToDouble()
      ? absValue.toInt().toString()
      : absValue.toStringAsFixed(2);
  final List<String> parts = text.split('.');
  final String grouped = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (Match m) => '${m[1]},',
  );
  final String result =
      parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
  return negative ? '-$result' : result;
}

/// تنسيق مبلغ بالريال.
String fmtMoney(double value) => '${fmtNum(value)} ر.ي';

/// تنسيق تاريخ للعرض (yyyy-MM-dd).
String fmtDate(DateTime? date) {
  if (date == null) return '—';
  return EquipmentCalc.dayKey(date);
}

/// تحويل نص مدخل إلى رقم (يدعم الأرقام العربية) أو null.
double? parseMovementNumber(String value) {
  final String text = value
      .replaceAll('٠', '0')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4')
      .replaceAll('٥', '5')
      .replaceAll('٦', '6')
      .replaceAll('٧', '7')
      .replaceAll('٨', '8')
      .replaceAll('٩', '9')
      .replaceAll('٫', '.')
      .replaceAll(',', '')
      .replaceAll(' ', '')
      .trim();
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

/// رسالة نجاح/خطأ موحدة لشاشات المنظومة.
void showMovementMessage(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red : Colors.green,
    ),
  );
}

/// حوار تأكيد (حذف/إنهاء) يعيد true عند التأكيد.
Future<bool> confirmMovementAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  bool danger = false,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  return result == true;
}

// ============================================================
// حقول النماذج
// ============================================================

/// حقل نص بسيط داخل نماذج المنظومة.
Widget movementTextField({
  required TextEditingController controller,
  required String label,
  bool required = false,
  bool number = false,
  int maxLines = 1,
  String? hint,
  bool enabled = true,
  ValueChanged<String>? onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: onChanged,
      validator: (String? value) {
        final String text = (value ?? '').trim();
        if (required && text.isEmpty) return 'هذا الحقل مطلوب';
        if (number && text.isNotEmpty) {
          final double? parsed = parseMovementNumber(text);
          if (parsed == null || parsed < 0) {
            return 'أدخل رقمًا صحيحًا غير سالب';
          }
        }
        return null;
      },
    ),
  );
}

/// حقل تاريخ يفتح منتقي التاريخ عند الضغط.
class MovementDateField extends StatelessWidget {
  const MovementDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final DateTime? picked = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(fmtDate(value)),
        ),
      ),
    );
  }
}

// ============================================================
// منتقي المعدة والمشروع (من بيانات النظام الحية)
// ============================================================

/// قائمة اختيار معدة من حصر المعدات.
///
/// تعرض كل معدة بكودها ونوعها ورقم مشروعها الحالي — وهي
/// البيانات نفسها التي أدخلها مدير الحركة، فلا إعادة إدخال.
class EquipmentDropdown extends StatelessWidget {
  const EquipmentDropdown({
    super.key,
    required this.service,
    required this.selectedId,
    required this.onChanged,
    this.label = 'المعدة',
  });

  final EquipmentService service;
  final String? selectedId;
  final ValueChanged<EquipmentDoc?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EquipmentDoc>>(
      stream: service.equipmentStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _decorated(label, const Text('جاري تحميل المعدات...'));
        }
        if (snapshot.hasError) {
          return _decorated(
            label,
            const Text(
              'تعذر تحميل المعدات',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        final List<EquipmentDoc> items = snapshot.data ?? <EquipmentDoc>[];
        if (items.isEmpty) {
          return _decorated(
            label,
            const Text('لا توجد معدات في الحصر بعد — يضيفها مدير الحركة'),
          );
        }

        final bool hasSelected =
            selectedId != null && items.any((e) => e.id == selectedId);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            // يتغير الاختيار برمجيًا، لذا المفتاح يعيد تهيئة الحقل.
            key: ValueKey<String?>('equipment-$selectedId'),
            initialValue: hasSelected ? selectedId : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '$label *',
              border: const OutlineInputBorder(),
              isDense: true,
              prefixIcon: const Icon(Icons.precision_manufacturing_outlined),
            ),
            hint: const Text('اختر المعدة بكودها'),
            items: items
                .map(
                  (EquipmentDoc e) => DropdownMenuItem<String>(
                    value: e.id,
                    child: Text(
                      e.hasProject
                          ? '${e.code} — ${e.type} · مشروع ${e.projectCode}'
                          : '${e.code} — ${e.type} · بدون مشروع',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (String? value) {
              if (value == null) {
                onChanged(null);
                return;
              }
              onChanged(items.firstWhere((e) => e.id == value));
            },
            validator: (String? value) =>
                (value == null || value.isEmpty) ? 'اختر المعدة' : null,
          ),
        );
      },
    );
  }

  Widget _decorated(String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: child,
      ),
    );
  }
}

/// قائمة اختيار مشروع برقمه واسمه.
class ProjectDropdown extends StatelessWidget {
  const ProjectDropdown({
    super.key,
    required this.service,
    required this.selectedId,
    required this.onChanged,
    this.label = 'المشروع',
    this.isRequired = true,
    this.allowNoneLabel,
  });

  final EquipmentService service;
  final String? selectedId;
  final ValueChanged<ProjectOption?> onChanged;
  final String label;
  final bool isRequired;

  /// إن وُضعت ظهر خيار أول فارغ بهذا النص (مثل: بدون مشروع).
  final String? allowNoneLabel;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProjectOption>>(
      stream: service.projectsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              child: const Text('جاري تحميل المشاريع...'),
            ),
          );
        }

        final List<ProjectOption> items =
            snapshot.data ?? <ProjectOption>[];
        final bool hasSelected =
            selectedId != null && items.any((p) => p.id == selectedId);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            key: ValueKey<String?>('project-$selectedId'),
            initialValue: hasSelected
                ? selectedId
                : (allowNoneLabel != null ? '' : null),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: isRequired ? '$label *' : label,
              border: const OutlineInputBorder(),
              isDense: true,
              prefixIcon: const Icon(Icons.apartment_outlined),
            ),
            hint: const Text('اختر المشروع برقمه'),
            items: <DropdownMenuItem<String>>[
              if (allowNoneLabel != null)
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(allowNoneLabel!),
                ),
              ...items.map(
                (ProjectOption p) => DropdownMenuItem<String>(
                  value: p.id,
                  child: Text(p.label, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (String? value) {
              if (value == null || value.isEmpty) {
                onChanged(null);
                return;
              }
              onChanged(items.firstWhere((p) => p.id == value));
            },
            validator: (String? value) {
              if (!isRequired) return null;
              return (value == null || value.isEmpty)
                  ? 'اختر المشروع'
                  : null;
            },
          ),
        );
      },
    );
  }
}

// ============================================================
// عناصر عرض
// ============================================================

/// شارة حالة المعدة (جيدة/معطلة/...).
class ConditionChip extends StatelessWidget {
  const ConditionChip({super.key, required this.condition});

  final String condition;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (condition) {
      case 'معطلة':
        color = Colors.red;
        break;
      case 'تحتاج صيانة':
        color = Colors.orange;
        break;
      case 'متوسطة':
        color = Colors.amber.shade800;
        break;
      case 'جيدة':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }
    return Chip(
      label: Text(
        condition,
        style: TextStyle(color: color, fontSize: 12),
      ),
      backgroundColor: color.withValues(alpha: 0.10),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// بطاقة مؤشر صغيرة (عنوان + قيمة) لقوائم الملخص وملف المعدة.
class MovementStat extends StatelessWidget {
  const MovementStat({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color effective =
        color ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, color: effective, size: 20),
              const SizedBox(height: 6),
            ],
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: effective,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

/// صف مؤشرات بعرض الشاشة (Wrap) من [MovementStat].
class MovementStatGrid extends StatelessWidget {
  const MovementStatGrid({super.key, required this.stats});

  final List<MovementStat> stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width =
            constraints.maxWidth > 520 ? (constraints.maxWidth - 24) / 4 : (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: stats
              .map((MovementStat s) => SizedBox(width: width, child: s))
              .toList(),
        );
      },
    );
  }
}

/// صف معلومة في ملف المعدة: عنوان وقيمة.
class MovementInfoRow extends StatelessWidget {
  const MovementInfoRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}

/// عنوان قسم داخل الصفحات.
class MovementSectionTitle extends StatelessWidget {
  const MovementSectionTitle({super.key, required this.title, this.icon});

  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
          ],
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

/// حالة فارغة موحدة (لا توجد سجلات بعد).
class MovementEmpty extends StatelessWidget {
  const MovementEmpty({
    super.key,
    required this.icon,
    required this.message,
    this.hint,
  });

  final IconData icon;
  final String message;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 52, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (hint != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(hint!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

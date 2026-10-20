import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// شاشات إدارة مبنية على أوراق ملف الإكسل.
/// أضف هذا الملف إلى lib/ ثم اربطه من AdminPage.
/// أسماء المجموعات: equipment, equipment_consumption_rules,
/// diesel_consumption_rules, equipment_costs, reference_data.

class EquipmentPage extends StatelessWidget {
  const EquipmentPage({super.key});

  @override
  Widget build(BuildContext context) => _ExcelFirestoreCrudPage(
        spec: _PageSpec(
          collection: 'equipment',
          title: 'حصر المعدات',
          icon: Icons.construction,
          kind: _PageKind.equipment,
          primaryField: 'equipmentType',
          secondaryFields: const ['equipmentCode', 'workUnit', 'currentMeter'],
          fields: const [
            _FieldSpec('equipmentCode', 'كود المعدة / الرقم الإداري', required: true),
            _FieldSpec('equipmentType', 'نوع المعدة', required: true),
            _FieldSpec('manufactureYear', 'سنة الصنع', number: true),
            _FieldSpec('acquisitionCondition', 'حالة الحصول عليها'),
            _FieldSpec('currentCondition', 'حالة المعدة حالياً'),
            _FieldSpec('manufacturerCountry', 'الشركة المصنعة / الدولة'),
            _FieldSpec('workUnit', 'وحدة عمل المعدة'),
            _FieldSpec('currentMeter', 'عداد المعدة', number: true),
            _FieldSpec('driverName', 'اسم السائق'),
            _FieldSpec('driverPhone', 'رقم التلفون'),
            _FieldSpec('notes', 'ملاحظات'),
          ],
        ),
      );
}

class EquipmentConsumablesPage extends StatelessWidget {
  const EquipmentConsumablesPage({super.key});

  @override
  Widget build(BuildContext context) => _ExcelFirestoreCrudPage(
        spec: _PageSpec(
          collection: 'equipment_consumption_rules',
          title: 'الوحدات الاستهلاكية',
          icon: Icons.oil_barrel,
          kind: _PageKind.consumables,
          primaryField: 'consumableName',
          secondaryFields: const ['equipmentCode', 'category', 'costPerWorkUnit'],
          fields: const [
            _FieldSpec('equipmentCode', 'كود المعدة / الرقم الإداري', required: true),
            _FieldSpec('equipmentType', 'نوع المعدة'),
            _FieldSpec('category', 'مجموعة الاستهلاك', required: true),
            _FieldSpec('consumableName', 'نوع ومواصفات الوحدة الاستهلاكية', required: true),
            _FieldSpec('consumptionUnit', 'وحدة الاستهلاك'),
            _FieldSpec('standardQuantity', 'كمية الاستهلاك المعيارية', number: true),
            _FieldSpec('actualQuantity', 'كمية الاستهلاك الفعلية', number: true),
            _FieldSpec('workUnits', 'عدد وحدات العمل المقابلة للاستهلاك', number: true),
            _FieldSpec('unitPrice', 'سعر الوحدة الاستهلاكية', number: true),
            _FieldSpec('notes', 'ملاحظات'),
          ],
        ),
      );
}

class DieselConsumptionPage extends StatelessWidget {
  const DieselConsumptionPage({super.key});

  @override
  Widget build(BuildContext context) => _ExcelFirestoreCrudPage(
        spec: _PageSpec(
          collection: 'diesel_consumption_rules',
          title: 'استهلاك الديزل للمعدات',
          icon: Icons.local_gas_station,
          kind: _PageKind.diesel,
          primaryField: 'equipmentType',
          secondaryFields: const ['equipmentCode', 'workUnit', 'litersPerWorkUnit'],
          fields: const [
            _FieldSpec('equipmentType', 'نوع المعدة', required: true),
            _FieldSpec('size', 'حجم المعدة'),
            _FieldSpec('variant', 'نوعها / الموديل'),
            _FieldSpec('workUnit', 'وحدة عمل المعدة', required: true),
            _FieldSpec('equipmentCode', 'الرقم الإداري'),
            _FieldSpec('litersPerWorkUnit', 'كمية الاستهلاك باللتر', number: true),
            _FieldSpec('workUnitCount', 'عدد وحدات العمل', number: true),
            _FieldSpec('distanceOrHours', 'المسافة / الساعة'),
            _FieldSpec('quantityText', 'الكمية (مثال: 0.6 لتر)'),
            _FieldSpec('notes', 'ملاحظات'),
          ],
        ),
      );
}

class EquipmentCostsPage extends StatelessWidget {
  const EquipmentCostsPage({super.key});

  @override
  Widget build(BuildContext context) => _ExcelFirestoreCrudPage(
        spec: _PageSpec(
          collection: 'equipment_costs',
          title: 'الإهلاك والإيجار والأعطال',
          icon: Icons.calculate,
          kind: _PageKind.costs,
          primaryField: 'equipmentType',
          secondaryFields: const ['equipmentCode', 'depreciationPerWorkUnit', 'breakdownCostPerWorkUnit'],
          fields: const [
            _FieldSpec('equipmentCode', 'كود المعدة / الرقم الإداري', required: true),
            _FieldSpec('equipmentType', 'نوع المعدة'),
            _FieldSpec('workUnit', 'وحدة عمل المعدة'),
            _FieldSpec('dieselUnit', 'وحدة استهلاك الديزل'),
            _FieldSpec('standardConsumptionQuantity', 'كمية الاستهلاك المعيارية', number: true),
            _FieldSpec('actualConsumptionQuantity', 'كمية الاستهلاك الفعلية', number: true),
            _FieldSpec('workUnits', 'عدد وحدات العمل المقابلة للاستهلاك', number: true),
            _FieldSpec('unitPrice', 'سعر الوحدة الاستهلاكية', number: true),
            _FieldSpec('dieselCostPerWorkUnit', 'تكلفة الديزل / وحدة عمل', number: true),
            _FieldSpec('depreciationRate', 'نسبة الإهلاك (مثلاً 0.5 تعني 50%)', number: true, defaultValue: '0.5'),
            _FieldSpec('currentEquipmentValue', 'القيمة الحالية للمعدة', number: true),
            _FieldSpec('expectedWorkUnits', 'عدد وحدات العمل المتوقعة', number: true),
            _FieldSpec('salvageValue', 'القيمة التخريدية للمعدة', number: true),
            _FieldSpec('breakdownRate', 'نسبة مواجهة الأعطال (مثلاً 0.05 تعني 5%)', number: true, defaultValue: '0.05'),
            _FieldSpec('rentExcludingCosts', 'قيمة الإيجار غير شامل التكاليف', number: true),
            _FieldSpec('rentIncludingCosts', 'قيمة الإيجار شامل كل التكاليف', number: true),
            _FieldSpec('notes', 'ملاحظات'),
          ],
        ),
      );
}

class ReferenceDataPage extends StatelessWidget {
  const ReferenceDataPage({super.key});

  @override
  Widget build(BuildContext context) => _ExcelFirestoreCrudPage(
        spec: _PageSpec(
          collection: 'reference_data',
          title: 'البيانات والأسعار المرجعية',
          icon: Icons.tune,
          kind: _PageKind.reference,
          primaryField: 'name',
          secondaryFields: const ['category', 'unit', 'value'],
          fields: const [
            _FieldSpec('number', 'الرقم'),
            _FieldSpec('category', 'التصنيف (سعر / نسبة / فترة صيانة)', required: true),
            _FieldSpec('name', 'النوع / البيان', required: true),
            _FieldSpec('unit', 'الوحدة'),
            _FieldSpec('value', 'سعر الوحدة أو الكمية أو النسبة', number: true),
            _FieldSpec('notes', 'ملاحظات'),
          ],
        ),
      );
}

enum _PageKind { equipment, consumables, diesel, costs, reference }

class _FieldSpec {
  final String key;
  final String label;
  final bool number;
  final bool required;
  final String? defaultValue;

  const _FieldSpec(
    this.key,
    this.label, {
    this.number = false,
    this.required = false,
    this.defaultValue,
  });
}

class _PageSpec {
  final String collection;
  final String title;
  final IconData icon;
  final _PageKind kind;
  final String primaryField;
  final List<String> secondaryFields;
  final List<_FieldSpec> fields;

  const _PageSpec({
    required this.collection,
    required this.title,
    required this.icon,
    required this.kind,
    required this.primaryField,
    required this.secondaryFields,
    required this.fields,
  });
}

class _ExcelFirestoreCrudPage extends StatefulWidget {
  final _PageSpec spec;

  const _ExcelFirestoreCrudPage({required this.spec});

  @override
  State<_ExcelFirestoreCrudPage> createState() => _ExcelFirestoreCrudPageState();
}

class _ExcelFirestoreCrudPageState extends State<_ExcelFirestoreCrudPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _search = '';

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(widget.spec.collection);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.spec.title)),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _editRecord(),
          icon: const Icon(Icons.add),
          label: const Text('إضافة سجل'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'بحث في ${widget.spec.title}...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _search = value.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _collection.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('تعذر تحميل البيانات. تحقق من اتصال Firebase والصلاحيات.'));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data?.docs ?? [];
                  final filtered = docs.where((doc) {
                    if (_search.isEmpty) return true;
                    final data = doc.data();
                    return data.values.any((value) => value.toString().toLowerCase().contains(_search));
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(widget.spec.icon, size: 52, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text(docs.isEmpty ? 'لا توجد بيانات بعد' : 'لا توجد نتائج مطابقة للبحث'),
                            if (docs.isEmpty) ...[
                              const SizedBox(height: 6),
                              const Text('أضف البيانات يدويًا، أو استورد بيانات ملف الإكسل إلى هذه المجموعة.', textAlign: TextAlign.center),
                            ],
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final doc = filtered[index];
                      final data = doc.data();
                      final title = _displayValue(data[widget.spec.primaryField]);
                      final subtitle = widget.spec.secondaryFields
                          .where((key) => data[key] != null && data[key].toString().trim().isNotEmpty)
                          .map((key) => '${_fieldLabel(key)}: ${_displayValue(data[key])}')
                          .join('  •  ');
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Icon(widget.spec.icon)),
                          title: Text(title.isEmpty ? 'سجل بدون اسم' : title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'edit') _editRecord(docId: doc.id, data: data);
                              if (action == 'delete') _deleteRecord(doc.id);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('تعديل')),
                              PopupMenuItem(value: 'delete', child: Text('حذف')),
                            ],
                          ),
                          onTap: () => _editRecord(docId: doc.id, data: data),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fieldLabel(String key) {
    for (final field in widget.spec.fields) {
      if (field.key == key) return field.label;
    }
    return key;
  }

  String _displayValue(dynamic value) {
    if (value == null) return '';
    if (value is double) return value.toStringAsFixed(value == value.roundToDouble() ? 0 : 4);
    return value.toString();
  }

  Future<void> _editRecord({String? docId, Map<String, dynamic>? data}) async {
    final controllers = <String, TextEditingController>{};
    for (final field in widget.spec.fields) {
      final existing = data?[field.key];
      controllers[field.key] = TextEditingController(
        text: existing == null ? (field.defaultValue ?? '') : _displayValue(existing),
      );
    }

    final rawValues = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(docId == null ? 'إضافة — ${widget.spec.title}' : 'تعديل — ${widget.spec.title}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: widget.spec.fields.map((field) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: controllers[field.key],
                      keyboardType: field.number
                          ? const TextInputType.numberWithOptions(decimal: true, signed: false)
                          : TextInputType.text,
                      maxLines: field.key == 'notes' ? 3 : 1,
                      decoration: InputDecoration(
                        labelText: field.required ? '${field.label} *' : field.label,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                for (final field in widget.spec.fields) {
                  if (field.required && (controllers[field.key]?.text.trim().isEmpty ?? true)) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الحقل مطلوب: ${field.label}')));
                    return;
                  }
                }
                Navigator.pop(dialogContext, {
                  for (final field in widget.spec.fields) field.key: controllers[field.key]!.text.trim(),
                });
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (rawValues == null || !mounted) return;

    try {
      final cleaned = <String, dynamic>{};
      for (final field in widget.spec.fields) {
        final value = rawValues[field.key]?.trim() ?? '';
        if (field.number) {
          cleaned[field.key] = _parseNumber(value);
        } else {
          cleaned[field.key] = value;
        }
      }

      _applyDerivedValues(cleaned);
      cleaned['sourceSheet'] = _sourceSheetName(widget.spec.kind);
      cleaned['updatedAt'] = FieldValue.serverTimestamp();
      if (docId == null) cleaned['createdAt'] = FieldValue.serverTimestamp();

      if (docId != null) {
        await _collection.doc(docId).set(cleaned, SetOptions(merge: true));
      } else if (widget.spec.kind == _PageKind.equipment) {
        final code = (cleaned['equipmentCode'] ?? '').toString().trim();
        if (code.isNotEmpty && code != '0') {
          final existing = await _collection.doc(code).get();
          if (existing.exists) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('هذا الرقم الإداري موجود مسبقًا. ابحث عن المعدة وعدّل سجلها بدل إنشاء سجل مكرر.')),
            );
            return;
          }
          cleaned['status'] = 'active';
          await _collection.doc(code).set(cleaned);
        } else {
          cleaned['status'] = 'active';
          await _collection.add(cleaned);
        }
      } else {
        await _collection.add(cleaned);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ البيانات بنجاح')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ البيانات: $error')));
    }
  }

  void _applyDerivedValues(Map<String, dynamic> data) {
    num? number(String key) {
      final value = data[key];
      if (value is num) return value;
      return num.tryParse((value ?? '').toString());
    }

    if (widget.spec.kind == _PageKind.consumables) {
      final actual = number('actualQuantity');
      final workUnits = number('workUnits');
      final price = number('unitPrice');
      final perWork = (actual != null && workUnits != null && workUnits > 0) ? actual / workUnits : null;
      data['quantityPerWorkUnit'] = perWork;
      data['costPerWorkUnit'] = perWork != null && price != null ? perWork * price : null;
    } else if (widget.spec.kind == _PageKind.costs) {
      final dieselCost = number('dieselCostPerWorkUnit');
      final depRate = number('depreciationRate') ?? 0.5;
      final breakdownRate = number('breakdownRate') ?? 0.05;
      final depreciation = dieselCost == null ? null : dieselCost * depRate;
      data['depreciationRate'] = depRate;
      data['depreciationPerWorkUnit'] = depreciation;
      data['breakdownRate'] = breakdownRate;
      data['breakdownCostPerWorkUnit'] = depreciation == null ? null : depreciation * breakdownRate;

      final currentValue = number('currentEquipmentValue');
      final salvageValue = number('salvageValue');
      final expectedUnits = number('expectedWorkUnits');
      data['actualDepreciationPerWorkUnit'] =
          currentValue != null && salvageValue != null && expectedUnits != null && expectedUnits > 0
              ? (currentValue - salvageValue) / expectedUnits
              : null;
    }
  }

  String _sourceSheetName(_PageKind kind) {
    switch (kind) {
      case _PageKind.equipment:
        return 'حصر المعدات';
      case _PageKind.consumables:
        return 'الوحدات الاستهلاكية';
      case _PageKind.diesel:
        return 'استهلاك الديزل للمعدات';
      case _PageKind.costs:
        return 'الاهلاك -الايجار- الاعطال';
      case _PageKind.reference:
        return 'بيانات';
    }
  }

  num? _parseNumber(String value) {
    if (value.isEmpty) return null;
    final normalized = value
        .replaceAll('٠', '0').replaceAll('١', '1').replaceAll('٢', '2')
        .replaceAll('٣', '3').replaceAll('٤', '4').replaceAll('٥', '5')
        .replaceAll('٦', '6').replaceAll('٧', '7').replaceAll('٨', '8')
        .replaceAll('٩', '9').replaceAll(',', '.');
    final parsed = num.tryParse(normalized);
    if (parsed is double && parsed == parsed.roundToDouble()) return parsed.toInt();
    return parsed;
  }

  Future<void> _deleteRecord(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: const Text('هل تريد حذف هذا السجل؟ لا يمكن التراجع عن الحذف.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _collection.doc(docId).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف السجل')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حذف السجل: $error')));
    }
  }
}

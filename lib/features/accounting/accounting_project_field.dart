import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ============================================================
// اختيار المشروع في وثائق الوحدة المالية
// ============================================================
//
// السند/القيد قد يُربط بمشروع (اختياريًا) لتظهر حركته في
// تقارير المشروع. القائمة تُقرأ مرة واحدة من `projects` وتبقى
// قابلة لإعادة الاستخدام في نموذج السند ونموذج القيد.
// ============================================================

class AccountingProjectOption {
  const AccountingProjectOption({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;
  final String code;
  final String name;

  String get label {
    if (code.isNotEmpty && name.isNotEmpty) return '$code — $name';
    if (name.isNotEmpty) return name;
    if (code.isNotEmpty) return code;
    return 'مشروع بدون اسم';
  }
}

Future<List<AccountingProjectOption>> loadAccountingProjects() async {
  final QuerySnapshot<Map<String, dynamic>> snapshot =
      await FirebaseFirestore.instance.collection('projects').get();

  final List<AccountingProjectOption> options = snapshot.docs.map((doc) {
    final Map<String, dynamic> data = doc.data();

    return AccountingProjectOption(
      id: doc.id,
      code: (data['code'] ?? '').toString().trim(),
      name: (data['name'] ?? '').toString().trim(),
    );
  }).toList();

  options.sort((a, b) => a.label.compareTo(b.label));

  return options;
}

class AccountingProjectField extends StatefulWidget {
  const AccountingProjectField({
    super.key,
    required this.projectId,
    required this.projectCode,
    required this.projectName,
    required this.onChanged,
    this.label = 'المشروع (اختياري)',
    this.enabled = true,
    this.allowNoProject = true,
  });

  final String projectId;
  final String projectCode;
  final String projectName;

  /// تُستدعى عند الاختيار؛ القيم الثلاث فارغة عند «بدون مشروع».
  final void Function(String id, String code, String name) onChanged;

  final String label;
  final bool enabled;
  final bool allowNoProject;

  @override
  State<AccountingProjectField> createState() => _AccountingProjectFieldState();
}

class _AccountingProjectFieldState extends State<AccountingProjectField> {
  late Future<List<AccountingProjectOption>> _future;

  @override
  void initState() {
    super.initState();
    _future = loadAccountingProjects();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AccountingProjectOption>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: widget.label,
              prefixIcon: const Icon(Icons.apartment_outlined),
            ),
            child: const Text('جاري تحميل المشاريع...'),
          );
        }

        final List<AccountingProjectOption> options =
            <AccountingProjectOption>[...(snapshot.data ?? const <AccountingProjectOption>[])];

        if (widget.projectId.isNotEmpty &&
            !options.any((option) => option.id == widget.projectId)) {
          options.add(
            AccountingProjectOption(
              id: widget.projectId,
              code: widget.projectCode,
              name: widget.projectName,
            ),
          );
        }

        final bool hasNoProjectItem = widget.allowNoProject;
        final String? initialValue = widget.projectId.isNotEmpty
            ? widget.projectId
            : (hasNoProjectItem ? '' : null);

        return DropdownButtonFormField<String>(
          key: ValueKey<String>(
            'accounting-project-${widget.label}-${widget.projectId}',
          ),
          initialValue: initialValue,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: const Icon(Icons.apartment_outlined),
          ),
          items: <DropdownMenuItem<String>>[
            if (hasNoProjectItem)
              const DropdownMenuItem<String>(
                value: '',
                child: Text('بدون ربط بمشروع'),
              ),
            ...options.map((option) {
              return DropdownMenuItem<String>(
                value: option.id,
                child: Text(
                  option.label,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
          onChanged: widget.enabled
              ? (value) {
                  final String id = value ?? '';

                  if (id.isEmpty) {
                    widget.onChanged('', '', '');
                    return;
                  }

                  for (final AccountingProjectOption option in options) {
                    if (option.id == id) {
                      widget.onChanged(option.id, option.code, option.name);
                      return;
                    }
                  }
                }
              : null,
        );
      },
    );
  }
}

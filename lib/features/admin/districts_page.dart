import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

import 'governorates_page.dart';

class DistrictsPage extends StatefulWidget {
  const DistrictsPage({
    super.key,
  });

  @override
  State<DistrictsPage> createState() => _DistrictsPageState();
}

class _DistrictsPageState extends State<DistrictsPage> {
  // ============================================================
  // Firestore
  // ============================================================

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // ============================================================
  // البحث
  // ============================================================

  final TextEditingController _searchController =
      TextEditingController();

  String _searchText = '';

  // ============================================================
  // Dispose
  // ============================================================

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // إضافة مديرية
  // ============================================================

  Future<void> _addDistrict() async {
    final TextEditingController nameController =
        TextEditingController();

    String? selectedGovernorateId;
    String? selectedGovernorateName;

    final formKey = GlobalKey<FormState>();

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text(
                  'إضافة مديرية',
                ),
                content: SizedBox(
                  width: 450,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ==================================================
                        // اسم المديرية
                        // ==================================================

                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'اسم المديرية',
                            hintText: 'أدخل اسم المديرية',
                            prefixIcon: Icon(
                              Icons.location_on_outlined,
                            ),
                          ),
                          validator: (value) {
                            if (value == null ||
                                value.trim().isEmpty) {
                              return 'يرجى إدخال اسم المديرية';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        // ==================================================
                        // المحافظة
                        // ==================================================

                        StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>>(
                          stream: firestore
                              .collection('governorates')
                              .where(
                                'active',
                                isEqualTo: true,
                              )
                              .snapshots(),
                          builder: (
                            context,
                            snapshot,
                          ) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(),
                              );
                            }

                            if (snapshot.hasError) {
                              return const Text(
                                'حدث خطأ أثناء تحميل المحافظات',
                              );
                            }

                            final docs =
                                snapshot.data?.docs ?? [];

                            return DropdownButtonFormField<String>(
                              initialValue: selectedGovernorateId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'المحافظة',
                                prefixIcon: Icon(
                                  Icons.location_city_outlined,
                                ),
                              ),
                              items: docs.map(
                                (doc) {
                                  final data = doc.data();

                                  final name =
                                      data['name']?.toString() ??
                                          'بدون اسم';

                                  return DropdownMenuItem<String>(
                                    value: doc.id,
                                    child: Text(name),
                                  );
                                },
                              ).toList(),
                              onChanged: (value) {
                                setDialogState(() {
                                  selectedGovernorateId = value;

                                  final selectedDoc = docs
                                      .where(
                                        (doc) =>
                                            doc.id == value,
                                      )
                                      .firstOrNull;

                                  selectedGovernorateName =
                                      selectedDoc
                                          ?.data()['name']
                                          ?.toString();
                                });
                              },
                              validator: (value) {
                                if (value == null ||
                                    value.isEmpty) {
                                  return 'يرجى اختيار المحافظة';
                                }

                                return null;
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                        false,
                      );
                    },
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(
                      Icons.save_outlined,
                    ),
                    label: const Text('حفظ'),
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }

                      try {
                        await firestore
                            .collection('districts')
                            .add({
                          'name': nameController.text.trim(),
                          'governorateId':
                              selectedGovernorateId,
                          'governorateName':
                              selectedGovernorateName,
                          'active': true,
                          'createdAt':
                              FieldValue.serverTimestamp(),
                          'updatedAt':
                              FieldValue.serverTimestamp(),
                        });

                        if (!mounted) {
                          return;
                        }

                        Navigator.pop(
                          dialogContext,
                          true,
                        );
                      } catch (e) {
                        if (!mounted) {
                          return;
                        }

                        AppWidgets.showError(
                          context,
                          'حدث خطأ أثناء إضافة المديرية: $e',
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    nameController.dispose();

    if (result == true && mounted) {
      AppWidgets.showSuccess(
        context,
        'تمت إضافة المديرية بنجاح',
      );
    }
  }

  // ============================================================
  // تعديل مديرية
  // ============================================================

  Future<void> _editDistrict(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? {};

    final TextEditingController nameController =
        TextEditingController(
      text: data['name']?.toString() ?? '',
    );

    String? selectedGovernorateId =
        data['governorateId']?.toString();

    String? selectedGovernorateName =
        data['governorateName']?.toString();

    final formKey = GlobalKey<FormState>();

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text(
                  'تعديل المديرية',
                ),
                content: SizedBox(
                  width: 450,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ==================================================
                        // اسم المديرية
                        // ==================================================

                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'اسم المديرية',
                            prefixIcon: Icon(
                              Icons.location_on_outlined,
                            ),
                          ),
                          validator: (value) {
                            if (value == null ||
                                value.trim().isEmpty) {
                              return 'يرجى إدخال اسم المديرية';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        // ==================================================
                        // المحافظة
                        // ==================================================

                        StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>>(
                          stream: firestore
                              .collection('governorates')
                              .where(
                                'active',
                                isEqualTo: true,
                              )
                              .snapshots(),
                          builder: (
                            context,
                            snapshot,
                          ) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(),
                              );
                            }

                            if (snapshot.hasError) {
                              return const Text(
                                'حدث خطأ أثناء تحميل المحافظات',
                              );
                            }

                            final docs =
                                snapshot.data?.docs ?? [];

                            final String? initialGovernorateId =
                                docs.any(
                              (doc) =>
                                  doc.id ==
                                  selectedGovernorateId,
                            )
                                    ? selectedGovernorateId
                                    : null;

                            return DropdownButtonFormField<String>(
                              initialValue:
                                  initialGovernorateId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'المحافظة',
                                prefixIcon: Icon(
                                  Icons.location_city_outlined,
                                ),
                              ),
                              items: docs.map(
                                (doc) {
                                  final data = doc.data();

                                  final name =
                                      data['name']?.toString() ??
                                          'بدون اسم';

                                  return DropdownMenuItem<String>(
                                    value: doc.id,
                                    child: Text(name),
                                  );
                                },
                              ).toList(),
                              onChanged: (value) {
                                setDialogState(() {
                                  selectedGovernorateId = value;

                                  final selectedDoc = docs
                                      .where(
                                        (doc) =>
                                            doc.id == value,
                                      )
                                      .firstOrNull;

                                  selectedGovernorateName =
                                      selectedDoc
                                          ?.data()['name']
                                          ?.toString();
                                });
                              },
                              validator: (value) {
                                if (value == null ||
                                    value.isEmpty) {
                                  return 'يرجى اختيار المحافظة';
                                }

                                return null;
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                        false,
                      );
                    },
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(
                      Icons.save_outlined,
                    ),
                    label: const Text('حفظ'),
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }

                      try {
                        await firestore
                            .collection('districts')
                            .doc(doc.id)
                            .update({
                          'name': nameController.text.trim(),
                          'governorateId':
                              selectedGovernorateId,
                          'governorateName':
                              selectedGovernorateName,
                          'updatedAt':
                              FieldValue.serverTimestamp(),
                        });

                        if (!mounted) {
                          return;
                        }

                        Navigator.pop(
                          dialogContext,
                          true,
                        );
                      } catch (e) {
                        if (!mounted) {
                          return;
                        }

                        AppWidgets.showError(
                          context,
                          'حدث خطأ أثناء تعديل المديرية: $e',
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    nameController.dispose();

    if (result == true && mounted) {
      AppWidgets.showSuccess(
        context,
        'تم تعديل المديرية بنجاح',
      );
    }
  }

  // ============================================================
  // تغيير حالة المديرية
  // ============================================================

  Future<void> _toggleDistrict(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? {};

    final bool active = data['active'] != false;

    final String name =
        data['name']?.toString() ?? 'هذه المديرية';

    final bool confirmed =
        await AppWidgets.showConfirmDialog(
      context: context,
      title: active ? 'تعطيل المديرية' : 'تفعيل المديرية',
      message: active
          ? 'هل تريد تعطيل "$name"؟'
          : 'هل تريد تفعيل "$name"؟',
      confirmText: active ? 'تعطيل' : 'تفعيل',
      cancelText: 'إلغاء',
      danger: active,
    );

    if (!confirmed) {
      return;
    }

    try {
      await firestore
          .collection('districts')
          .doc(doc.id)
          .update({
        'active': !active,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      AppWidgets.showSuccess(
        context,
        active ? 'تم تعطيل المديرية' : 'تم تفعيل المديرية',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء تغيير حالة المديرية: $e',
      );
    }
  }

  // ============================================================
  // حذف المديرية
  // ============================================================

  Future<void> _deleteDistrict(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? {};

    final String name =
        data['name']?.toString() ?? 'هذه المديرية';

    final bool confirmed =
        await AppWidgets.showConfirmDialog(
      context: context,
      title: 'حذف المديرية',
      message:
          'هل أنت متأكد من حذف "$name"؟\n\n'
          'سيتم حذف سجل المديرية نهائياً.',
      confirmText: 'حذف',
      cancelText: 'إلغاء',
      danger: true,
    );

    if (!confirmed) {
      return;
    }

    try {
      await firestore
          .collection('districts')
          .doc(doc.id)
          .delete();

      if (!mounted) {
        return;
      }

      AppWidgets.showSuccess(
        context,
        'تم حذف المديرية بنجاح',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء حذف المديرية: $e',
      );
    }
  }

  // ============================================================
  // الانتقال إلى المحافظات
  // ============================================================

  void _openGovernorates() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const GovernoratesPage(),
      ),
    );
  }

  // ============================================================
  // تصفية البيانات
  // ============================================================

  List<QueryDocumentSnapshot<Map<String, dynamic>>>
      _filterDistricts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final String search =
        _searchText.trim().toLowerCase();

    if (search.isEmpty) {
      return docs;
    }

    return docs.where((doc) {
      final data = doc.data();

      final String name =
          data['name']?.toString().toLowerCase() ?? '';

      final String governorate =
          data['governorateName']?.toString().toLowerCase() ??
              '';

      return name.contains(search) ||
          governorate.contains(search);
    }).toList();
  }

  // ============================================================
  // الإحصائيات
  // ============================================================

  int _countActive(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .where(
          (doc) => doc.data()['active'] != false,
        )
        .length;
  }

  int _countInactive(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .where(
          (doc) => doc.data()['active'] == false,
        )
        .length;
  }

  int _countGovernorates(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final Set<String> ids = {};

    for (final doc in docs) {
      final data = doc.data();

      final String id =
          data['governorateId']?.toString() ?? '';

      if (id.isNotEmpty) {
        ids.add(id);
      }
    }

    return ids.length;
  }

  // ============================================================
  // Drawer
  // ============================================================

  Widget _buildDrawer() {
    return AppDrawer(
      userName: 'مدير النظام',
      roleName: 'مدير النظام',
      projectName: 'إدارة المديريات',
      items: [
        // ========================================================
        // الرئيسية
        // ========================================================

        AppDrawerItem(
          title: 'الرئيسية',
          icon: Icons.dashboard_outlined,
          onTap: () {
            Navigator.pop(context);
            Navigator.pop(context);
          },
        ),

        // ========================================================
        // المحافظات
        // ========================================================

        AppDrawerItem(
          title: 'المحافظات',
          icon: Icons.location_city_outlined,
          selected: false,
          onTap: () {
            Navigator.pop(context);
            _openGovernorates();
          },
        ),

        // ========================================================
        // المديريات
        // ========================================================

        AppDrawerItem(
          title: 'المديريات',
          icon: Icons.location_on_outlined,
          selected: true,
          onTap: () {
            Navigator.pop(context);
          },
        ),
      ],
      onLogout: () async {
        await FirebaseAuth.instance.signOut();

        if (!mounted) {
          return;
        }

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const _LoggedOutPage(),
          ),
          (route) => false,
        );
      },
    );
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return AppScaffold(
      title: 'إدارة المديريات',
      drawer: _buildDrawer(),
      actions: [
        // ========================================================
        // تحديث
        // ========================================================

        IconButton(
          tooltip: 'تحديث',
          icon: const Icon(
            Icons.refresh_outlined,
          ),
          onPressed: () {
            setState(() {});
          },
        ),

        // ========================================================
        // إضافة
        // ========================================================

        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
          ),
          child: IconButton(
            tooltip: 'إضافة مديرية',
            icon: const Icon(
              Icons.add_location_alt_outlined,
            ),
            onPressed: _addDistrict,
          ),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDistrict,
        icon: const Icon(
          Icons.add,
        ),
        label: const Text(
          'إضافة مديرية',
        ),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: StreamBuilder<
            QuerySnapshot<Map<String, dynamic>>>(
          stream: firestore
              .collection('districts')
              .snapshots(),
          builder: (
            context,
            snapshot,
          ) {
            // ==================================================
            // تحميل
            // ==================================================

            if (snapshot.connectionState ==
                ConnectionState.waiting) {
              return AppPage(
                child: AppLoading(
                  message: 'جاري تحميل المديريات...',
                ),
              );
            }

            // ==================================================
            // خطأ
            // ==================================================

            if (snapshot.hasError) {
              return AppPage(
                child: AppError(
                  message:
                      'حدث خطأ أثناء تحميل المديريات',
                  onRetry: () {
                    setState(() {});
                  },
                ),
              );
            }

            // ==================================================
            // جميع البيانات
            // ==================================================

            final allDocs =
                snapshot.data?.docs ?? [];

            // ==================================================
            // البيانات المفلترة
            // ==================================================

            final docs =
                _filterDistricts(allDocs);

            // ==================================================
            // الصفحة
            // ==================================================

            return AppPage(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  // ==================================================
                  // رأس الصفحة
                  // ==================================================

                  AppPageHeader(
                    title: 'إدارة المديريات',
                    subtitle:
                        'إضافة وتعديل وتنشيط وتعطيل وحذف المديريات وربطها بالمحافظات.',
                    icon: Icons.location_on_outlined,
                    trailing: AppButton(
                      text: 'إضافة مديرية',
                      icon: Icons.add,
                      onPressed: _addDistrict,
                    ),
                  ),

                  AppSpacing.verticalLg,

                  // ==================================================
                  // البحث
                  // ==================================================

                  AppTextField(
                    controller: _searchController,
                    label: 'البحث',
                    hint:
                        'ابحث باسم المديرية أو المحافظة',
                    prefixIcon: Icons.search,
                    onChanged: (value) {
                      setState(() {
                        _searchText = value;
                      });
                    },
                  ),

                  AppSpacing.verticalLg,

                  // ==================================================
                  // الإحصائيات
                  // ==================================================

                  AppSectionTitle(
                    title: 'نظرة عامة',
                    icon: Icons.analytics_outlined,
                  ),

                  AppSpacing.verticalMd,

                  AppResponsiveGrid(
                    minItemWidth: 220,
                    spacing: 16,
                    children: [
                      // ================================================
                      // إجمالي المديريات
                      // ================================================

                      AppStatCard(
                        title: 'إجمالي المديريات',
                        value: '${allDocs.length}',
                        icon: Icons.location_on_outlined,
                        color: AppColors.primary,
                      ),

                      // ================================================
                      // المديريات النشطة
                      // ================================================

                      AppStatCard(
                        title: 'المديريات النشطة',
                        value:
                            '${_countActive(allDocs)}',
                        icon: Icons.check_circle_outline,
                        color: AppColors.success,
                      ),

                      // ================================================
                      // المديريات غير النشطة
                      // ================================================

                      AppStatCard(
                        title: 'غير النشطة',
                        value:
                            '${_countInactive(allDocs)}',
                        icon: Icons.cancel_outlined,
                        color: AppColors.danger,
                      ),

                      // ================================================
                      // المحافظات
                      // ================================================

                      AppStatCard(
                        title: 'المحافظات المستخدمة',
                        value:
                            '${_countGovernorates(allDocs)}',
                        icon:
                            Icons.location_city_outlined,
                        color: AppColors.info,
                      ),
                    ],
                  ),

                  AppSpacing.verticalXl,

                  // ==================================================
                  // عنوان القائمة
                  // ==================================================

                  AppSectionTitle(
                    title: 'قائمة المديريات',
                    icon: Icons.list_alt_outlined,
                    trailing: Text(
                      '${docs.length} مديرية',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ),

                  AppSpacing.verticalMd,

                  // ==================================================
                  // لا توجد بيانات
                  // ==================================================

                  if (docs.isEmpty)
                    AppEmpty(
                      message: _searchText.isEmpty
                          ? 'لا توجد مديريات حتى الآن'
                          : 'لا توجد نتائج مطابقة للبحث',
                      icon: Icons.location_off_outlined,
                    )

                  // ==================================================
                  // قائمة المديريات
                  // ==================================================

                  else
                    ...docs.map(
                      (doc) {
                        return _DistrictCard(
                          data: doc.data(),
                          onEdit: () => _editDistrict(doc),
                          onToggle: () =>
                              _toggleDistrict(doc),
                          onDelete: () =>
                              _deleteDistrict(doc),
                        );
                      },
                    ),

                  AppSpacing.verticalXl,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// =============================================================
// بطاقة المديرية
// =============================================================

class _DistrictCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _DistrictCard({
    required this.data,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final String name =
        data['name']?.toString() ?? 'بدون اسم';

    final String governorateName =
        data['governorateName']?.toString() ??
            'غير محددة';

    final bool active =
        data['active'] != false;

    return AppCard(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            // ========================================================
            // الأيقونة
            // ========================================================

            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(
                  alpha: 0.10,
                ),
                borderRadius: BorderRadius.circular(
                  15,
                ),
              ),
              child: const Icon(
                Icons.location_on_outlined,
                color: AppColors.primary,
                size: 28,
              ),
            ),

            const SizedBox(
              width: 14,
            ),

            // ========================================================
            // البيانات
            // ========================================================

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTextStyles.cardTitle,
                  ),

                  const SizedBox(
                    height: 6,
                  ),

                  Row(
                    children: [
                      const Icon(
                        Icons.location_city_outlined,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(
                        width: 5,
                      ),
                      Flexible(
                        child: Text(
                          governorateName,
                          style:
                              AppTextStyles.bodySecondary,
                          overflow:
                              TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 7,
                  ),

                  AppStatusBadge(
                    text: active ? 'نشطة' : 'غير نشطة',
                    color: active
                        ? AppColors.success
                        : AppColors.danger,
                  ),
                ],
              ),
            ),

            const SizedBox(
              width: 8,
            ),

            // ========================================================
            // الإجراءات
            // ========================================================

            PopupMenuButton<String>(
              tooltip: 'إجراءات',
              onSelected: (value) {
                if (value == 'edit') {
                  onEdit();
                } else if (value == 'toggle') {
                  onToggle();
                } else if (value == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (context) => [
                // ==============================================
                // تعديل
                // ==============================================

                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_outlined,
                      ),
                      SizedBox(
                        width: 10,
                      ),
                      Text('تعديل'),
                    ],
                  ),
                ),

                // ==============================================
                // تفعيل / تعطيل
                // ==============================================

                PopupMenuItem<String>(
                  value: 'toggle',
                  child: Row(
                    children: [
                      Icon(
                        active
                            ? Icons.block_outlined
                            : Icons.check_circle_outline,
                        color: active
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      Text(
                        active ? 'تعطيل' : 'تفعيل',
                      ),
                    ],
                  ),
                ),

                // ==============================================
                // حذف
                // ==============================================

                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: AppColors.danger,
                      ),
                      SizedBox(
                        width: 10,
                      ),
                      Text(
                        'حذف',
                        style: TextStyle(
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              child: const Icon(
                Icons.more_vert,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// صفحة تسجيل الخروج
// =============================================================

class _LoggedOutPage extends StatelessWidget {
  const _LoggedOutPage();

  @override
  Widget build(
    BuildContext context,
  ) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: AppCard(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.logout_outlined,
                  size: 60,
                  color: AppColors.primary,
                ),

                const SizedBox(
                  height: 20,
                ),

                const Text(
                  'تم تسجيل الخروج',
                  style: AppTextStyles.pageTitle,
                ),

                const SizedBox(
                  height: 10,
                ),

                const Text(
                  'يمكنك تسجيل الدخول مرة أخرى',
                  style: AppTextStyles.bodySecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
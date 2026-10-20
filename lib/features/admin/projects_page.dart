import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/services/project_cost_sync.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/costs.dart';
import '../../core/widgets/app_widgets.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({
    super.key,
  });

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final TextEditingController _searchController =
      TextEditingController();

  String _searchText = '';

  int _totalProjects = 0;
  int _activeProjects = 0;
  int _inactiveProjects = 0;
  int _withoutManager = 0;

  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(_onSearchChanged);

    _loadStats();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();

    super.dispose();
  }

  // ============================================================
  // البحث
  // ============================================================

  void _onSearchChanged() {
    if (!mounted) return;

    setState(() {
      _searchText =
          _searchController.text.trim().toLowerCase();
    });
  }

  bool _matchesSearch(
    Map<String, dynamic> data,
  ) {
    if (_searchText.isEmpty) {
      return true;
    }

    final name =
        (data['name'] ?? '')
            .toString()
            .toLowerCase();

    final code =
        (data['code'] ?? '')
            .toString()
            .toLowerCase();

    final governorate =
        (data['governorateName'] ?? '')
            .toString()
            .toLowerCase();

    final district =
        (data['districtName'] ?? '')
            .toString()
            .toLowerCase();

    final manager =
        (data['managerName'] ?? '')
            .toString()
            .toLowerCase();

    return name.contains(_searchText) ||
        code.contains(_searchText) ||
        governorate.contains(_searchText) ||
        district.contains(_searchText) ||
        manager.contains(_searchText);
  }

  // ============================================================
  // الإحصائيات
  // ============================================================

  Future<void> _loadStats() async {
    if (mounted) {
      setState(() {
        _loadingStats = true;
      });
    }

    try {
      final snapshot =
          await _firestore
              .collection('projects')
              .get();

      int total = 0;
      int active = 0;
      int inactive = 0;
      int withoutManager = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();

        total++;

        if (data['status'] == 'active') {
          active++;
        } else {
          inactive++;
        }

        final managerId = data['managerId'];

        if (managerId == null ||
            managerId.toString().trim().isEmpty) {
          withoutManager++;
        }
      }

      if (!mounted) return;

      setState(() {
        _totalProjects = total;
        _activeProjects = active;
        _inactiveProjects = inactive;
        _withoutManager = withoutManager;
        _loadingStats = false;
      });
    } catch (e, stackTrace) {
      debugPrint(
        'Load projects stats error: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (!mounted) return;

      setState(() {
        _loadingStats = false;
      });
    }
  }

  // ============================================================
  // إضافة مشروع
  // ============================================================

  Future<void> _showAddProjectDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const _ProjectFormDialog();
      },
    );

    if (!mounted) return;

    await _loadStats();
  }

  // ============================================================
  // تعديل مشروع
  // ============================================================

  Future<void> _showEditProjectDialog(
    String projectId,
    Map<String, dynamic> data,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return _ProjectFormDialog(
          projectId: projectId,
          existingData: data,
        );
      },
    );

    if (!mounted) return;

    await _loadStats();
  }

  // ============================================================
  // تفعيل / تعطيل
  // ============================================================

  Future<void> _toggleProjectStatus(
    String projectId,
    Map<String, dynamic> data,
  ) async {
    final currentStatus =
        data['status'] ?? 'active';

    final bool isActive =
        currentStatus == 'active';

    final confirmed =
        await AppWidgets.showConfirmDialog(
      context: context,
      title: isActive
          ? 'تعطيل المشروع'
          : 'تفعيل المشروع',
      message: isActive
          ? 'هل أنت متأكد من تعطيل هذا المشروع؟'
          : 'هل تريد تفعيل هذا المشروع؟',
      confirmText:
          isActive ? 'تعطيل' : 'تفعيل',
      cancelText: 'إلغاء',
      danger: isActive,
    );

    if (!confirmed) return;

    try {
      await _firestore
          .collection('projects')
          .doc(projectId)
          .update({
        'status':
            isActive ? 'inactive' : 'active',
        'updatedAt':
            FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      AppWidgets.showSuccess(
        context,
        isActive
            ? 'تم تعطيل المشروع'
            : 'تم تفعيل المشروع',
      );

      await _loadStats();
    } catch (e, stackTrace) {
      debugPrint(
        'Toggle project error: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (!mounted) return;

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء تحديث حالة المشروع',
      );
    }
  }

  // ============================================================
  // حذف المشروع
  // ============================================================

  Future<void> _deleteProject(
    String projectId,
    Map<String, dynamic> data,
  ) async {
    final projectName =
        data['name']?.toString() ??
            'هذا المشروع';

    final confirmed =
        await AppWidgets.showConfirmDialog(
      context: context,
      title: 'حذف المشروع',
      message:
          'هل أنت متأكد من حذف المشروع "$projectName"؟\n\n'
          'يفضل تعطيل المشروع بدلًا من حذفه إذا كان يحتوي على بيانات مرتبطة.',
      confirmText: 'حذف',
      cancelText: 'إلغاء',
      danger: true,
    );

    if (!confirmed) return;

    try {
      await _firestore
          .collection('projects')
          .doc(projectId)
          .delete();

      if (!mounted) return;

      AppWidgets.showSuccess(
        context,
        'تم حذف المشروع',
      );

      await _loadStats();
    } catch (e, stackTrace) {
      debugPrint(
        'Delete project error: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (!mounted) return;

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء حذف المشروع',
      );
    }
  }

  // ============================================================
  // الصفحة
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'المشاريع',
      actions: [
        IconButton(
          tooltip: 'إضافة مشروع',
          onPressed: _showAddProjectDialog,
          icon: const Icon(
            Icons.add_business,
          ),
        ),
      ],
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: _showAddProjectDialog,
        icon: const Icon(Icons.add),
        label: const Text('إضافة مشروع'),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AppPage(
          scrollable: false,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              // ==================================================
              // رأس الصفحة
              // ==================================================

              AppPageHeader(
                title: 'إدارة المشاريع',
                subtitle:
                    'إضافة ومتابعة وإدارة مشاريع النظام',
                icon: Icons.business,
              ),

              AppSpacing.verticalMd,

              // ==================================================
              // الإحصائيات
              // ==================================================

              _buildStatistics(),

              AppSpacing.verticalLg,

              // ==================================================
              // البحث
              // ==================================================

              AppTextField(
                controller: _searchController,
                label: 'البحث',
                hint:
                    'ابحث باسم المشروع أو الرقم أو المحافظة...',
                prefixIcon: Icons.search,
                suffixIcon:
                    _searchText.isNotEmpty
                        ? IconButton(
                            tooltip: 'مسح البحث',
                            onPressed: () {
                              _searchController.clear();
                            },
                            icon: const Icon(
                              Icons.clear,
                            ),
                          )
                        : null,
              ),

              AppSpacing.verticalLg,

              // ==================================================
              // عنوان المشاريع
              // ==================================================

              AppSectionTitle(
                title: 'المشاريع المضافة',
                subtitle:
                    'اضغط على المشروع لعرض تفاصيله',
                icon: Icons.business_center,
              ),

              AppSpacing.verticalMd,

              // ==================================================
              // قائمة المشاريع
              // ==================================================

              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadStats,
                  child: StreamBuilder<
                      QuerySnapshot<
                          Map<String, dynamic>>>(
                    stream: _firestore
                        .collection('projects')
                        .orderBy(
                          'createdAt',
                          descending: true,
                        )
                        .snapshots(),
                    builder: (
                      context,
                      snapshot,
                    ) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const AppLoading(
                          message:
                              'جاري تحميل المشاريع...',
                        );
                      }

                      if (snapshot.hasError) {
                        debugPrint(
                          'Projects stream error: ${snapshot.error}',
                        );

                        return AppError(
                          message:
                              'حدث خطأ أثناء تحميل المشاريع',
                          onRetry: () {
                            setState(() {});
                          },
                        );
                      }

                      final docs =
                          snapshot.data?.docs ?? [];

                      final filteredDocs =
                          docs.where(
                        (doc) {
                          return _matchesSearch(
                            doc.data(),
                          );
                        },
                      ).toList();

                      if (docs.isEmpty) {
                        return const AppEmpty(
                          icon:
                              Icons.business_outlined,
                          title:
                              'لا توجد مشاريع',
                          message:
                              'لم تتم إضافة أي مشروع حتى الآن',
                        );
                      }

                      if (filteredDocs.isEmpty) {
                        return const AppEmpty(
                          icon:
                              Icons.search_off,
                          title:
                              'لا توجد نتائج',
                          message:
                              'لم يتم العثور على مشروع مطابق للبحث',
                        );
                      }

                      return ListView.separated(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        padding:
                            const EdgeInsets.only(
                          bottom: 100,
                        ),
                        itemCount:
                            filteredDocs.length,
                        separatorBuilder:
                            (
                          context,
                          index,
                        ) =>
                            AppSpacing.verticalSm,
                        itemBuilder:
                            (
                          context,
                          index,
                        ) {
                          final doc =
                              filteredDocs[index];

                          final data =
                              doc.data();

                          return _ProjectCard(
                            projectId:
                                doc.id,
                            data: data,
                            onEdit: () {
                              _showEditProjectDialog(
                                doc.id,
                                data,
                              );
                            },
                            onToggleStatus: () {
                              _toggleProjectStatus(
                                doc.id,
                                data,
                              );
                            },
                            onDelete: () {
                              _deleteProject(
                                doc.id,
                                data,
                              );
                            },
                          );
                        },
                      );
                    },
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
  // الإحصائيات
  // ============================================================

  Widget _buildStatistics() {
    if (_loadingStats) {
      return AppResponsiveGrid(
        minItemWidth: 220,
        spacing: 16,
        children: const [
          AppStatCard(
            title: 'إجمالي المشاريع',
            value: '...',
            icon: Icons.business,
            color: AppColors.primary,
          ),
          AppStatCard(
            title: 'المشاريع النشطة',
            value: '...',
            icon: Icons.check_circle,
            color: AppColors.success,
          ),
          AppStatCard(
            title: 'المشاريع المعطلة',
            value: '...',
            icon: Icons.pause_circle,
            color: AppColors.warning,
          ),
          AppStatCard(
            title: 'بدون مدير',
            value: '...',
            icon: Icons.person_off,
            color: AppColors.danger,
          ),
        ],
      );
    }

    return AppResponsiveGrid(
      minItemWidth: 220,
      spacing: 16,
      children: [
        AppStatCard(
          title: 'إجمالي المشاريع',
          value: '$_totalProjects',
          icon: Icons.business,
          color: AppColors.primary,
        ),
        AppStatCard(
          title: 'المشاريع النشطة',
          value: '$_activeProjects',
          icon: Icons.check_circle,
          color: AppColors.success,
        ),
        AppStatCard(
          title: 'المشاريع المعطلة',
          value: '$_inactiveProjects',
          icon: Icons.pause_circle,
          color: AppColors.warning,
        ),
        AppStatCard(
          title: 'بدون مدير',
          value: '$_withoutManager',
          icon: Icons.person_off,
          color: AppColors.danger,
        ),
      ],
    );
  }
}

// ==================================================================
// بطاقة المشروع
// ==================================================================

class _ProjectCard extends StatefulWidget {
  final String projectId;
  final Map<String, dynamic> data;

  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  const _ProjectCard({
    required this.projectId,
    required this.data,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onDelete,
  });

  @override
  State<_ProjectCard> createState() =>
      _ProjectCardState();
}

class _ProjectCardState
    extends State<_ProjectCard> {
  bool _expanded = false;
  bool _recomputing = false;

  // ============================================================
  // footnote: عدد البنود وآخر تحديث للتكاليف
  // ============================================================

  String _costsFootnote(Map<String, dynamic> data) {
    final items =
        data['costsProjectItemCount'];

    final costed =
        data['costsItemCount'];

    final updated =
        data['costsUpdatedAt'];

    final buffer = StringBuffer();

    if (items is int && items > 0) {
      buffer.write('محسوبة من $items بند');

      if (costed is int) {
        buffer.write('، ولـ $costed بند تكلفة مسجلة');
      }
    } else {
      buffer.write(
        'لا توجد بنود لهذا المشروع بعد، '
        'أو لم تتم إعادة حساب التكاليف',
      );
    }

    if (updated is Timestamp) {
      final date = updated.toDate();

      buffer.write(
        ' — آخر تحديث: ${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}',
      );
    }

    return buffer.toString();
  }

  /// سطر قسم واحد في بطاقة المشروع: المخطط، ومع الفعلي إن وُجد.
  String _costsCategoryValue(
    Map<String, dynamic> data,
    CostCategory category,
  ) {
    final planned =
        ProjectCosts.nonNegative(data[category.totalField]);
    final actual =
        ProjectCosts.nonNegative(data[category.actualField]);

    final plannedText = ProjectCosts.formatMoney(planned);

    if (actual <= 0) return plannedText;

    return 'فعلي ${ProjectCosts.formatMoney(actual)} '
        '/ مخطط $plannedText';
  }

  // ============================================================
  // إعادة حساب تكاليف المشروع من بنوده
  // ============================================================

  Future<void> _recomputeCosts() async {
    if (_recomputing) return;

    setState(() {
      _recomputing = true;
    });

    try {
      final totals =
          await ProjectCostSync.applyTotals(
        widget.projectId,
      );

      if (!mounted) return;

      AppWidgets.showSuccess(
        context,
        totals.hasCosts
            ? 'تمت إعادة الحساب: '
                '${ProjectCosts.formatMoney(totals.total)}'
            : 'لا توجد تكاليف مسجلة في بنود هذا المشروع',
      );
    } catch (e) {
      if (!mounted) return;

      AppWidgets.showError(
        context,
        'تعذرت إعادة حساب التكاليف:\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _recomputing = false;
        });
      }
    }
  }

  // ============================================================
  // تنسيق التاريخ
  // ============================================================

  String _formatDate(dynamic value) {
    if (value == null) {
      return 'غير محدد';
    }

    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    }

    if (date == null) {
      return 'غير محدد';
    }

    return '${date.day.toString().padLeft(2, '0')} / '
        '${date.month.toString().padLeft(2, '0')} / '
        '${date.year}';
  }

  // ============================================================
  // بناء البطاقة
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    final name =
        data['name']?.toString() ??
            'بدون اسم';

    final code =
        data['code']?.toString() ??
            '';

    final governorate =
        data['governorateName']
                ?.toString() ??
            'غير محددة';

    final district =
        data['districtName']
                ?.toString() ??
            'غير محددة';

    final manager =
        data['managerName']
                ?.toString() ??
            'غير محدد';

    final status =
        data['status']?.toString() ??
            'active';

    final bool isActive =
        status == 'active';

    final startDate =
        _formatDate(
      data['startDate'],
    );

    final endDate =
        _formatDate(
      data['endDate'],
    );

    final duration =
        data['duration'];

    return AppCard(
      padding:
          const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          // ======================================================
          // رأس المشروع
          // ======================================================

          InkWell(
            borderRadius:
                BorderRadius.circular(12),
            onTap: () {
              setState(() {
                _expanded =
                    !_expanded;
              });
            },
            child: Padding(
              padding:
                  const EdgeInsets.all(4),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration:
                        BoxDecoration(
                      color: AppColors
                          .primary
                          .withValues(
                        alpha: 0.10,
                      ),
                      borderRadius:
                          BorderRadius
                              .circular(
                        14,
                      ),
                    ),
                    child:
                        const Icon(
                      Icons.business,
                      color:
                          AppColors.primary,
                      size: 27,
                    ),
                  ),

                  AppSpacingHorizontal.md,

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              AppTextStyles
                                  .cardTitle,
                        ),

                        AppSpacing
                            .verticalXs,

                        Row(
                          children: [
                            const Icon(
                              Icons.qr_code,
                              size: 16,
                              color:
                                  AppColors
                                      .textSecondary,
                            ),
                            AppSpacingHorizontal
                                .xs,
                            Expanded(
                              child: Text(
                                code.isEmpty
                                    ? 'رقم المشروع غير محدد'
                                    : 'رقم المشروع: $code',
                                overflow:
                                    TextOverflow
                                        .ellipsis,
                                style:
                                    AppTextStyles
                                        .bodySecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  AppSpacingHorizontal.sm,

                  AppStatusBadge(
                    text: isActive
                        ? 'نشط'
                        : 'معطل',
                    color: isActive
                        ? AppColors.success
                        : AppColors.warning,
                  ),

                  AppSpacingHorizontal.xs,

                  Icon(
                    _expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color:
                        AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // ======================================================
          // التفاصيل
          // ======================================================

          if (_expanded) ...[
            AppSpacing.verticalMd,

            const Divider(),

            AppSpacing.verticalMd,

            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color:
                      AppColors.primary,
                ),
                AppSpacingHorizontal.sm,
                Text(
                  'تفاصيل المشروع',
                  style:
                      AppTextStyles.sectionTitle,
                ),
              ],
            ),

            AppSpacing.verticalMd,

            AppInfoRow(
              icon: Icons.qr_code,
              label: 'رقم المشروع',
              value: code.isEmpty
                  ? 'غير محدد'
                  : code,
            ),

            AppInfoRow(
              icon: Icons.business,
              label: 'اسم المشروع',
              value: name,
            ),

            AppInfoRow(
              icon: Icons.location_city,
              label: 'المحافظة',
              value: governorate,
            ),

            AppInfoRow(
              icon: Icons.location_on,
              label: 'المديرية',
              value: district,
            ),

            AppInfoRow(
              icon: Icons.person,
              label: 'مدير المشروع',
              value: manager,
            ),

            AppInfoRow(
              icon: Icons.info_outline,
              label: 'الحالة',
              value: isActive
                  ? 'نشط'
                  : 'معطل',
            ),

            AppInfoRow(
              icon: Icons.calendar_month,
              label: 'تاريخ البداية',
              value: startDate,
            ),

            AppInfoRow(
              icon: Icons.event,
              label: 'تاريخ النهاية',
              value: endDate,
            ),

            if (duration != null)
              AppInfoRow(
                icon: Icons.timer,
                label: 'مدة المشروع',
                value: '$duration يوم',
              ),

            AppSpacing.verticalMd,

            const Divider(),

            AppSpacing.verticalMd,

            // ======================================================
            // تكاليف المشروع
            // ======================================================

            Row(
              children: [
                const Icon(
                  Icons.payments_outlined,
                  color: AppColors.primary,
                ),
                AppSpacingHorizontal.sm,
                Expanded(
                  child: Text(
                    'تكاليف المشروع (محسوبة من البنود)',
                    style:
                        AppTextStyles.sectionTitle,
                  ),
                ),
                IconButton(
                  tooltip:
                      'إعادة حساب التكاليف من البنود',
                  onPressed:
                      _recomputing
                          ? null
                          : _recomputeCosts,
                  icon: _recomputing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth:
                                2,
                          ),
                        )
                      : const Icon(
                          Icons.refresh,
                        ),
                ),
              ],
            ),

            AppSpacing.verticalSm,

            for (final category in ProjectCosts.categories)
              AppInfoRow(
                icon: category.icon,
                label: category.label,
                value: _costsCategoryValue(data, category),
              ),

            AppInfoRow(
              icon: Icons.calculate_outlined,
              label: 'إجمالي تكلفة المشروع المخطط',
              value: ProjectCosts.formatMoney(
                ProjectCosts.totalOf(data),
              ),
            ),

            if (ProjectCosts.actualTotalOf(data) > 0)
              AppInfoRow(
                icon: Icons.check_circle_outline,
                label: 'الإجمالي الفعلي المسجل في البنود',
                value: ProjectCosts.formatMoney(
                  ProjectCosts.actualTotalOf(data),
                ),
              ),

            if (ProjectCosts.actualTotalOf(data) > 0)
              AppInfoRow(
                icon: Icons.payments_outlined,
                label: 'إجمالي تكلفة المشروع المعتمد',
                value: ProjectCosts.formatMoney(
                  ProjectCosts.effectiveTotalOf(data),
                ),
              ),

            AppSpacing.verticalXs,

            Text(
              _costsFootnote(data),
              textAlign:
                  TextAlign.right,
              style:
                  AppTextStyles.small,
            ),

            AppSpacing.verticalMd,

            const Divider(),

            AppSpacing.verticalMd,

            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment:
                  WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      widget.onEdit,
                  icon: const Icon(
                    Icons.edit,
                    size: 18,
                  ),
                  label:
                      const Text('تعديل'),
                ),

                OutlinedButton.icon(
                  onPressed:
                      widget.onToggleStatus,
                  icon: Icon(
                    isActive
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    size: 18,
                  ),
                  label: Text(
                    isActive
                        ? 'تعطيل'
                        : 'تفعيل',
                  ),
                ),

                IconButton(
                  tooltip:
                      'حذف المشروع',
                  onPressed:
                      widget.onDelete,
                  color:
                      AppColors.danger,
                  icon:
                      const Icon(
                    Icons.delete_outline,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ==================================================================
// نموذج إضافة / تعديل المشروع
// ==================================================================

class _ProjectFormDialog
    extends StatefulWidget {
  final String? projectId;
  final Map<String, dynamic>?
      existingData;

  const _ProjectFormDialog({
    this.projectId,
    this.existingData,
  });

  @override
  State<_ProjectFormDialog> createState() =>
      _ProjectFormDialogState();
}

class _ProjectFormDialogState
    extends State<_ProjectFormDialog> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final GlobalKey<FormState>
      _formKey =
      GlobalKey<FormState>();

  late final TextEditingController
      _nameController;

  late final TextEditingController
      _codeController;

  late final TextEditingController
      _durationController;

  DateTime? _startDate;

  String? _selectedGovernorateId;
  String? _selectedGovernorateName;

  String? _selectedDistrictId;
  String? _selectedDistrictName;

  bool _loading = false;

  bool get _isEditing =>
      widget.projectId != null;

  // ============================================================
  // البداية
  // ============================================================

  @override
  void initState() {
    super.initState();

    final data =
        widget.existingData;

    _nameController =
        TextEditingController(
      text:
          data?['name']?.toString() ??
              '',
    );

    _codeController =
        TextEditingController(
      text:
          data?['code']?.toString() ??
              '',
    );

    _durationController =
        TextEditingController(
      text:
          data?['duration']?.toString() ??
              '',
    );


    _selectedGovernorateId =
        data?['governorateId']?.toString();

    _selectedGovernorateName =
        data?['governorateName']?.toString();

    _selectedDistrictId =
        data?['districtId']?.toString();

    _selectedDistrictName =
        data?['districtName']?.toString();

    final startDate =
        data?['startDate'];

    if (startDate is Timestamp) {
      _startDate =
          startDate.toDate();
    } else if (startDate is DateTime) {
      _startDate = startDate;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _durationController.dispose();

    super.dispose();
  }

  // ============================================================
  // تنسيق التاريخ
  // ============================================================

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')} / '
        '${date.month.toString().padLeft(2, '0')} / '
        '${date.year}';
  }

  // ============================================================
  // اختيار تاريخ البداية
  // ============================================================

  Future<void> _selectStartDate() async {
    if (_loading) return;

    final now = DateTime.now();

    final selected =
        await showDatePicker(
      context: context,

      initialDate:
          _startDate ?? now,

      firstDate:
          DateTime(2020),

      lastDate:
          DateTime(2100),

      // ========================================================
      // مهم:
      // لا نضع locale هنا.
      //
      // هذا يمنع ظهور مشكلة التقويم/التاريخ في بعض
      // إصدارات Flutter وخصوصًا Web.
      // ========================================================

      helpText:
          'اختر تاريخ بداية المشروع',

      cancelText:
          'إلغاء',

      confirmText:
          'اختيار',

      fieldLabelText:
          'التاريخ',

      fieldHintText:
          'يوم/شهر/سنة',
    );

    if (selected == null ||
        !mounted) {
      return;
    }

    // ==========================================================
    // نخزن التاريخ بدون وقت
    // ==========================================================

    setState(() {
      _startDate = DateTime(
        selected.year,
        selected.month,
        selected.day,
      );
    });
  }

  // ============================================================
  // حفظ المشروع
  // ============================================================

  Future<void> _saveProject() async {
    if (_loading) return;

    if (!_formKey.currentState!.validate()) {
      AppWidgets.showWarning(
        context,
        'يرجى إكمال البيانات المطلوبة',
      );

      return;
    }

    if (_selectedGovernorateId == null) {
      AppWidgets.showWarning(
        context,
        'اختر المحافظة',
      );

      return;
    }

    if (_selectedDistrictId == null) {
      AppWidgets.showWarning(
        context,
        'اختر المديرية',
      );

      return;
    }

    if (_startDate == null) {
      AppWidgets.showWarning(
        context,
        'اختر تاريخ بداية المشروع',
      );

      return;
    }

    final duration =
        int.tryParse(
      _durationController.text.trim(),
    );

    if (duration == null ||
        duration <= 0) {
      AppWidgets.showWarning(
        context,
        'أدخل مدة صحيحة بالأيام',
      );

      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final code =
          _codeController.text.trim();

      // ========================================================
      // التحقق من عدم تكرار رقم المشروع
      // ========================================================

      final codeQuery =
          await _firestore
              .collection('projects')
              .where(
                'code',
                isEqualTo: code,
              )
              .limit(10)
              .get();

      final duplicateExists =
          codeQuery.docs.any(
        (doc) =>
            doc.id !=
            widget.projectId,
      );

      if (duplicateExists) {
        if (!mounted) return;

        setState(() {
          _loading = false;
        });

        AppWidgets.showError(
          context,
          'رقم المشروع مستخدم بالفعل',
        );

        return;
      }

      // ========================================================
      // حساب تاريخ النهاية
      //
      // إذا كانت البداية 01/01 والمدة 30 يومًا
      // فالنهاية تكون بعد 30 يومًا.
      // ========================================================

      final endDate =
          DateTime(
        _startDate!.year,
        _startDate!.month,
        _startDate!.day,
      ).add(
        Duration(
          days: duration,
        ),
      );

      // ========================================================
      // بيانات المشروع
      // ========================================================

      final projectData =
          <String, dynamic>{
        'name':
            _nameController.text.trim(),

        'code':
            code,

        'governorateId':
            _selectedGovernorateId,

        'governorateName':
            _selectedGovernorateName,

        'districtId':
            _selectedDistrictId,

        'districtName':
            _selectedDistrictName,

        'startDate':
            Timestamp.fromDate(
          DateTime(
            _startDate!.year,
            _startDate!.month,
            _startDate!.day,
          ),
        ),

        'duration':
            duration,

        'endDate':
            Timestamp.fromDate(
          DateTime(
            endDate.year,
            endDate.month,
            endDate.day,
          ),
        ),

      };

      // ========================================================
      // إضافة مشروع
      // ========================================================

      if (!_isEditing) {
        projectData.addAll({
          'managerId': null,
          'managerName': null,
          'status': 'active',
          'createdAt':
              FieldValue.serverTimestamp(),
        });

        final document =
            await _firestore
                .collection('projects')
                .add(
          projectData,
        );

        debugPrint(
          'Project created: ${document.id}',
        );

        // ========================================================
        // تكاليف المشروع تُحسب من البنود،
        // ونجهّز الوثيقة بقيم صفرية حتى تظهر في القوائم.
        // ========================================================

        try {
          await ProjectCostSync.applyTotals(
            document.id,
          );
        } catch (e) {
          debugPrint(
            'تعذر تهيئة تكاليف المشروع: $e',
          );
        }
      }

      // ========================================================
      // تعديل مشروع
      // ========================================================

      else {
        projectData['updatedAt'] =
            FieldValue.serverTimestamp();

        await _firestore
            .collection('projects')
            .doc(widget.projectId)
            .update(
          projectData,
        );

        debugPrint(
          'Project updated: ${widget.projectId}',
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop();

      // ========================================================
      // ملاحظة:
      // نعرض الرسالة بعد إغلاق Dialog.
      // ========================================================

      Future.microtask(() {
        if (!mounted) return;

        AppWidgets.showSuccess(
          context,
          _isEditing
              ? 'تم تعديل المشروع بنجاح'
              : 'تمت إضافة المشروع بنجاح',
        );
      });
    } catch (e, stackTrace) {
      debugPrint(
        'SAVE PROJECT ERROR: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (!mounted) return;

      AppWidgets.showError(
        context,
        'حدث خطأ أثناء حفظ المشروع',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // اختيار المحافظة
  // ============================================================

  Widget _buildGovernorateDropdown() {
    return StreamBuilder<
        QuerySnapshot<
            Map<String, dynamic>>>(
      stream: _firestore
          .collection('governorates')
          .where(
            'active',
            isEqualTo: true,
          )
          .snapshots(),
      builder:
          (context, snapshot) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }

        if (snapshot.hasError) {
          debugPrint(
            'Governorates error: ${snapshot.error}',
          );

          return AppError(
            message:
                'تعذر تحميل المحافظات',
            onRetry: () {
              setState(() {});
            },
          );
        }

        final docs =
            snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const AppEmpty(
            message:
                'لا توجد محافظات نشطة',
            icon:
                Icons.location_city,
          );
        }

        final sortedDocs =
            [...docs];

        sortedDocs.sort(
          (a, b) {
            final nameA =
                a.data()['name']?.toString() ??
                    '';

            final nameB =
                b.data()['name']?.toString() ??
                    '';

            return nameA.compareTo(nameB);
          },
        );

        return AppDropdown<String>(
          value:
              _selectedGovernorateId,
          label:
              'المحافظة',
          hint:
              'اختر المحافظة',
          prefixIcon:
              Icons.location_city,
          items:
              sortedDocs.map(
            (doc) {
              final data =
                  doc.data();

              return DropdownMenuItem<String>(
                value: doc.id,
                child: Text(
                  data['name']?.toString() ??
                      '',
                ),
              );
            },
          ).toList(),
          onChanged:
              _loading
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }

                      final doc =
                          sortedDocs.firstWhere(
                        (element) =>
                            element.id == value,
                      );

                      final data =
                          doc.data();

                      setState(() {
                        _selectedGovernorateId =
                            value;

                        _selectedGovernorateName =
                            data['name']?.toString();

                        _selectedDistrictId =
                            null;

                        _selectedDistrictName =
                            null;
                      });
                    },
        );
      },
    );
  }

  // ============================================================
  // اختيار المديرية
  // ============================================================

  Widget _buildDistrictDropdown() {
    if (_selectedGovernorateId == null) {
      return AppDropdown<String>(
        value: null,
        label: 'المديرية',
        hint: 'اختر المحافظة أولًا',
        prefixIcon:
            Icons.location_on,
        items: const [],
        onChanged: null,
      );
    }

    return StreamBuilder<
        QuerySnapshot<
            Map<String, dynamic>>>(
      stream: _firestore
          .collection('districts')
          .where(
            'governorateId',
            isEqualTo:
                _selectedGovernorateId,
          )
          .where(
            'active',
            isEqualTo: true,
          )
          .snapshots(),
      builder:
          (context, snapshot) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }

        if (snapshot.hasError) {
          debugPrint(
            'Districts error: ${snapshot.error}',
          );

          return AppError(
            message:
                'تعذر تحميل المديريات',
            onRetry: () {
              setState(() {});
            },
          );
        }

        final docs =
            snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const AppEmpty(
            message:
                'لا توجد مديريات نشطة لهذه المحافظة',
            icon:
                Icons.location_on,
          );
        }

        final sortedDocs =
            [...docs];

        sortedDocs.sort(
          (a, b) {
            final nameA =
                a.data()['name']?.toString() ??
                    '';

            final nameB =
                b.data()['name']?.toString() ??
                    '';

            return nameA.compareTo(nameB);
          },
        );

        return AppDropdown<String>(
          value:
              _selectedDistrictId,
          label:
              'المديرية',
          hint:
              'اختر المديرية',
          prefixIcon:
              Icons.location_on,
          items:
              sortedDocs.map(
            (doc) {
              final data =
                  doc.data();

              return DropdownMenuItem<String>(
                value: doc.id,
                child: Text(
                  data['name']?.toString() ??
                      '',
                ),
              );
            },
          ).toList(),
          onChanged:
              _loading
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }

                      final doc =
                          sortedDocs.firstWhere(
                        (element) =>
                            element.id == value,
                      );

                      final data =
                          doc.data();

                      setState(() {
                        _selectedDistrictId =
                            value;

                        _selectedDistrictName =
                            data['name']?.toString();
                      });
                    },
        );
      },
    );
  }

  // ============================================================
  // تاريخ البداية
  // ============================================================

  Widget _buildStartDateField() {
    final dateText =
        _startDate == null
            ? 'اختر تاريخ البداية'
            : _formatDate(
                _startDate!,
              );

    return InkWell(
      onTap:
          _loading
              ? null
              : _selectStartDate,
      borderRadius:
          BorderRadius.circular(12),
      child: InputDecorator(
        decoration:
            InputDecoration(
          labelText:
              'تاريخ بداية المشروع',
          prefixIcon:
              const Icon(
            Icons.calendar_month,
          ),
          border:
              OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(12),
          ),
        ),
        child: Text(
          dateText,
          textAlign:
              TextAlign.right,
          style:
              _startDate == null
                  ? AppTextStyles.bodySecondary
                  : AppTextStyles.body,
        ),
      ),
    );
  }

  // ============================================================
  // النموذج
  // ============================================================

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller:
                _nameController,
            label:
                'اسم المشروع',
            hint:
                'مثال: مشروع طريق إب',
            prefixIcon:
                Icons.business,
            validator:
                (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return 'أدخل اسم المشروع';
              }

              return null;
            },
          ),

          AppSpacing.verticalMd,

          AppTextField(
            controller:
                _codeController,
            label:
                'رقم / كود المشروع',
            hint:
                'مثال: PRJ-001',
            prefixIcon:
                Icons.qr_code,
            validator:
                (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return 'أدخل رقم المشروع';
              }

              return null;
            },
          ),

          AppSpacing.verticalMd,

          _buildGovernorateDropdown(),

          AppSpacing.verticalMd,

          _buildDistrictDropdown(),

          AppSpacing.verticalMd,

          _buildStartDateField(),

          AppSpacing.verticalMd,

          AppNumberField(
            controller:
                _durationController,
            label:
                'مدة المشروع بالأيام',
            hint:
                'مثال: 360',
            prefixIcon:
                Icons.timer,
            validator:
                (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return 'أدخل مدة المشروع';
              }

              final number =
                  int.tryParse(
                value.trim(),
              );

              if (number == null ||
                  number <= 0) {
                return 'أدخل عدد أيام صحيح';
              }

              return null;
            },
          ),

          AppSpacing.verticalLg,

          // ========================================================
          // ملاحظة التكاليف: لا إدخال يدوي هنا.
          // ========================================================

          AppCard(
            color: AppColors.background,
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: const [
                Icon(
                  Icons.payments_outlined,
                  size: 20,
                  color: AppColors.info,
                ),
                AppSpacingHorizontal.sm,
                Expanded(
                  child: Text(
                    'تكاليف المشروع (المواد، أجور العمالة، المعدات، '
                    'المحروقات) لا تُدخل هنا؛ تُحسب تلقائيًا من '
                    'صفحة تفاصيل كل بند وتُجمّع في هذا المشروع.',
                    style: AppTextStyles.bodySecondary,
                  ),
                ),
              ],
            ),
          ),

          AppSpacing.verticalLg,

          Row(
            children: [
              Expanded(
                child:
                    AppOutlinedButton(
                  text:
                      'إلغاء',
                  icon:
                      Icons.close,
                  onPressed:
                      _loading
                          ? null
                          : () {
                              Navigator.of(
                                context,
                              ).pop();
                            },
                ),
              ),

              AppSpacingHorizontal.md,

              Expanded(
                child:
                    ElevatedButton.icon(
                  onPressed:
                      _loading
                          ? null
                          : _saveProject,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth:
                                2,
                            color:
                                Colors.white,
                          ),
                        )
                      : Icon(
                          _isEditing
                              ? Icons.save
                              : Icons.add_business,
                        ),
                  label: Text(
                    _loading
                        ? 'جاري الحفظ...'
                        : _isEditing
                            ? 'حفظ التعديلات'
                            : 'إضافة المشروع',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // واجهة النافذة
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection:
          TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.business,
              color:
                  AppColors.primary,
            ),

            AppSpacingHorizontal.sm,

            Expanded(
              child: Text(
                _isEditing
                    ? 'تعديل المشروع'
                    : 'إضافة مشروع',
                style:
                    AppTextStyles.sectionTitle,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          child:
              SingleChildScrollView(
            child:
                _buildForm(),
          ),
        ),
      ),
    );
  }
}
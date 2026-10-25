import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../core/constants/org_structure.dart';
import '../../core/constants/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';

/// لون خطوط الربط بين المناصب في المخطط.
const Color _lineColor = Color(0xFFD6DEE9);

// ============================================================
// صفحة الهيكل الإداري
// ============================================================
//
// تعرض شجرة المناصب المعتمدة كما عرّفها [OrgStructure]، مع:
//
// • عدد الشاغلين لكل منصب (مباشر من Firestore).
// • توسيع وتصغير الفروع.
// • بطاقة تفاصيل لكل منصب: المهام، المديرون، المرؤوسون،
//   ما ينشئه، وأسماء الشاغلين.
// • إنشاء حساب لشاغل جديد في أي منصب (إن لم تكن للعرض فقط).
// ============================================================

class OrgChartPage extends StatefulWidget {
  const OrgChartPage({
    super.key,
    this.focusRole,
    this.readOnly = false,
  });

  /// منصب يُبرَز في المخطط ويُوسَّع مساره تلقائيًا.
  final String? focusRole;

  /// true: عرض فقط بدون أزرار إنشاء الحسابات.
  final bool readOnly;

  @override
  State<OrgChartPage> createState() => _OrgChartPageState();
}

class _OrgChartPageState extends State<OrgChartPage> {
  // ============================================================
  // Firebase
  // ============================================================

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late final Stream<QuerySnapshot<Map<String, dynamic>>>
      _usersStream;

  late final Stream<QuerySnapshot<Map<String, dynamic>>>
      _activeProjectsStream;

  // ============================================================
  // المناصب الموسّعة
  // ============================================================

  final Set<String> _expanded = <String>{};

  @override
  void initState() {
    super.initState();

    _usersStream =
        _firestore.collection('users').snapshots();

    _activeProjectsStream = _firestore
        .collection('projects')
        .where('status', isEqualTo: 'active')
        .snapshots();

    final String? focus = widget.focusRole;

    if (focus == null) {
      // افتراضيًا: القمة ومستواها الأول مفتوحان.
      _expanded.add(OrgStructure.root.roleKey);

      for (final OrgNode child
          in OrgStructure.childrenOf(
        OrgStructure.root.roleKey,
      )) {
        _expanded.add(child.roleKey);
      }
    } else {
      // نوسّع سلسلة المنصب المطلوب للوصول إليه.
      for (final OrgNode node
          in OrgStructure.chainOf(focus)) {
        _expanded.add(node.roleKey);
      }
    }
  }

  // ============================================================
  // توسيع / تصغير
  // ============================================================

  void _expandAll() {
    setState(() {
      for (final OrgNode node in OrgStructure.nodes) {
        _expanded.add(node.roleKey);
      }
    });
  }

  void _collapseAll() {
    setState(() {
      _expanded
        ..clear()
        ..add(OrgStructure.root.roleKey);
    });
  }

  void _toggle(String roleKey) {
    setState(() {
      if (_expanded.contains(roleKey)) {
        _expanded.remove(roleKey);
      } else {
        _expanded.add(roleKey);
      }
    });
  }

  // ============================================================
  // الواجهة
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'الهيكل الإداري',
      actions: <Widget>[
        IconButton(
          tooltip: 'توسيع الكل',
          icon: const Icon(Icons.unfold_more),
          onPressed: _expandAll,
        ),
        IconButton(
          tooltip: 'تصغير الكل',
          icon: const Icon(Icons.unfold_less),
          onPressed: _collapseAll,
        ),
      ],
      child: StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
        stream: _usersStream,
        builder: (
          context,
          snapshot,
        ) {
          if (snapshot.hasError) {
            return AppError(
              message:
                  'تعذر تحميل مستخدمي الهيكل:\n${snapshot.error}',
            );
          }

          if (snapshot.connectionState ==
                  ConnectionState.waiting &&
              !snapshot.hasData) {
            return const AppLoading(
              message: 'جاري تحميل الهيكل الإداري...',
            );
          }

          final List<
                  QueryDocumentSnapshot<
                      Map<String, dynamic>>> docs =
              snapshot.data?.docs ??
                  <QueryDocumentSnapshot<
                      Map<String, dynamic>>>[];

          final Map<String, int> counts =
              <String, int>{};

          final Map<String, List<_OrgMember>> members =
              <String, List<_OrgMember>>{};

          for (final doc in docs) {
            final Map<String, dynamic> data =
                doc.data();

            final String canonical =
                AppRoles.normalize(
              data['role']?.toString(),
            );

            counts[canonical] =
                (counts[canonical] ?? 0) + 1;

            members
                .putIfAbsent(
                  canonical,
                  () => <_OrgMember>[],
                )
                .add(
                  _OrgMember(
                    name: (data['name'] ?? '')
                        .toString()
                        .trim(),
                    username: (data['username'] ?? '')
                        .toString()
                        .trim(),
                    phone: (data['phone'] ?? '')
                        .toString()
                        .trim(),
                    active: data['active'] == true,
                    projectNames:
                        (data['projectNames'] as List?)
                                ?.map(
                                  (e) =>
                                      e.toString(),
                                )
                                .toList() ??
                            const <String>[],
                  ),
                );
          }

          return AppPage(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: <Widget>[
                AppPageHeader(
                  icon: Icons.account_tree,
                  title: 'الهيكل الإداري',
                  subtitle:
                      'شجرة المناصب وعدد الشاغلين لكل منصب. '
                      'اضغط أي منصب لعرض مهامه وشاغليه.',
                ),

                _buildSummary(counts, docs.length),

                AppSpacing.verticalLg,

                // ============================================
                // الشجرة
                // ============================================

                for (final OrgNode root
                    in OrgStructure.roots())
                  _buildNode(
                    node: root,
                    counts: counts,
                    members: members,
                  ),

                AppSpacing.verticalLg,

                _buildWorkflowCard(),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // بطاقات الملخص
  // ============================================================

  Widget _buildSummary(
    Map<String, int> counts,
    int totalUsers,
  ) {
    int occupied = 0;

    for (final OrgNode node in OrgStructure.nodes) {
      if (_countFor(node, counts) > 0) {
        occupied++;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool wide = constraints.maxWidth >= 700;

        final List<Widget> cards = <Widget>[
          _SummaryCard(
            icon: Icons.account_tree,
            color: AppColors.primary,
            title: 'مناصب الهيكل',
            value: '${OrgStructure.positionsCount}',
          ),
          _SummaryCard(
            icon: Icons.how_to_reg,
            color: AppColors.success,
            title: 'مناصب مشغولة',
            value: '$occupied',
          ),
          _SummaryCard(
            icon: Icons.people,
            color: AppColors.info,
            title: 'إجمالي المستخدمين',
            value: '$totalUsers',
          ),
        ];

        if (wide) {
          return Row(
            children: cards
                .map(
                  (card) => Expanded(child: card),
                )
                .toList(),
          );
        }

        return Column(
          children: cards,
        );
      },
    );
  }

  // ============================================================
  // الشجرة
  // ============================================================

  Widget _buildNode({
    required OrgNode node,
    required Map<String, int> counts,
    required Map<String, List<_OrgMember>> members,
  }) {
    final List<OrgNode> children =
        OrgStructure.childrenOf(node.roleKey);

    final bool expanded =
        _expanded.contains(node.roleKey);

    final bool focused = widget.focusRole != null &&
        AppRoles.normalize(widget.focusRole) ==
            node.roleKey;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: <Widget>[
        _OrgNodeCard(
          node: node,
          count: _countFor(node, counts),
          expanded: expanded,
          hasChildren: children.isNotEmpty,
          focused: focused,
          showAddMember: !widget.readOnly,
          onToggle: children.isEmpty
              ? null
              : () => _toggle(node.roleKey),
          onAddMember: () =>
              _showAddMemberDialog(node),
          onDetails: () => _showPositionDetails(
            node: node,
            count: _countFor(node, counts),
            members: _membersFor(node, members),
          ),
        ),

        if (children.isNotEmpty && expanded)
          Padding(
            padding:
                const EdgeInsetsDirectional.only(
              start: 24,
            ),
            child: Stack(
              children: <Widget>[
                const PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: ColoredBox(
                    color: _lineColor,
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsetsDirectional
                              .only(
                    start: 2,
                  ),
                  child: Column(
                    children: <Widget>[
                      for (final OrgNode child
                          in children)
                        Row(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: <Widget>[
                            Padding(
                              padding:
                                  const EdgeInsetsDirectional
                                          .only(
                                top: 36,
                              ),
                              child: Container(
                                width: 16,
                                height: 2,
                                color: _lineColor,
                              ),
                            ),
                            Expanded(
                              child: _buildNode(
                                node: child,
                                counts: counts,
                                members: members,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  int _countFor(
    OrgNode node,
    Map<String, int> counts,
  ) {
    final Set<String> keys = node.allRoleKeys
        .map(AppRoles.normalize)
        .toSet();

    int total = 0;

    for (final String key in keys) {
      total += counts[key] ?? 0;
    }

    return total;
  }

  List<_OrgMember> _membersFor(
    OrgNode node,
    Map<String, List<_OrgMember>> members,
  ) {
    final Set<String> keys = node.allRoleKeys
        .map(AppRoles.normalize)
        .toSet();

    final List<_OrgMember> result = <_OrgMember>[];

    for (final String key in keys) {
      result.addAll(members[key] ?? const <_OrgMember>[]);
    }

    return result;
  }

  // ============================================================
  // بطاقة تفاصيل المنصب
  // ============================================================

  Future<void> _showPositionDetails({
    required OrgNode node,
    required int count,
    required List<_OrgMember> members,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final List<OrgNode> chain =
            OrgStructure.chainOf(node.roleKey);

        final List<OrgNode> managers = chain.length > 1
            ? chain.sublist(0, chain.length - 1)
            : <OrgNode>[];

        final List<OrgNode> children =
            OrgStructure.childrenOf(node.roleKey);

        return Directionality(
          textDirection: TextDirection.rtl,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            minChildSize: 0.4,
            maxChildSize: 0.94,
            builder: (
              context,
              scrollController,
            ) {
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(
                  20,
                  6,
                  20,
                  28,
                ),
                children: <Widget>[
                  // ========================================
                  // رأس المنصب
                  // ========================================

                  Row(
                    children: <Widget>[
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: node.color
                              .withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(
                            14,
                          ),
                        ),
                        child: Icon(
                          node.icon,
                          color: node.color,
                          size: 28,
                        ),
                      ),
                      AppSpacingHorizontal.md,
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: <Widget>[
                            Text(
                              node.title,
                              style: AppTextStyles
                                  .sectionTitle,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'المستوى ${node.level} · '
                              '${count > 0 ? '$count شاغل' : 'المنصب شاغر'}',
                              style: AppTextStyles
                                  .small,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  AppSpacing.verticalMd,

                  // ========================================
                  // المهام
                  // ========================================

                  _SheetSection(
                    title: 'المهام',
                    icon: Icons.task_alt,
                    child: Text(
                      node.duties,
                      style: AppTextStyles.body,
                    ),
                  ),

                  // ========================================
                  // ما ينشئه
                  // ========================================

                  if (node.creates.isNotEmpty)
                    _SheetSection(
                      title: 'ما ينشئه هذا المنصب',
                      icon: Icons.add_circle_outline,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: node.creates
                            .map(
                              (text) =>
                                  AppStatusBadge(
                                text: text,
                                color: node.color,
                              ),
                            )
                            .toList(),
                      ),
                    ),

                  // ========================================
                  // المديرون
                  // ========================================

                  _SheetSection(
                    title: 'المديرون (خط الإشراف)',
                    icon: Icons.supervisor_account,
                    child: managers.isEmpty
                        ? const Text(
                            'هذا المنصب في قمة الهيكل.',
                            style: AppTextStyles
                                .bodySecondary,
                          )
                        : Column(
                            children: managers
                                .map(
                                  (manager) =>
                                      _ChainTile(
                                    node: manager,
                                  ),
                                )
                                .toList(),
                          ),
                  ),

                  // ========================================
                  // المرؤوسون
                  // ========================================

                  if (children.isNotEmpty)
                    _SheetSection(
                      title: 'المرؤوسون المباشرون',
                      icon: Icons.account_tree,
                      child: Column(
                        children: children
                            .map(
                              (child) => _ChainTile(
                                node: child,
                              ),
                            )
                            .toList(),
                      ),
                    ),

                  // ========================================
                  // الشاغلون
                  // ========================================

                  _SheetSection(
                    title: 'الشاغلون ($count)',
                    icon: Icons.people,
                    child: members.isEmpty
                        ? const Text(
                            'لا يوجد شاغلون لهذا المنصب.',
                            style: AppTextStyles
                                .bodySecondary,
                          )
                        : Column(
                            children: members
                                .map(
                                  (member) =>
                                      _MemberTile(
                                    member: member,
                                  ),
                                )
                                .toList(),
                          ),
                  ),

                  if (!widget.readOnly) ...<Widget>[
                    AppSpacing.verticalMd,
                    AppButton(
                      text: 'إضافة شاغل لهذا المنصب',
                      icon: Icons.person_add,
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showAddMemberDialog(node);
                      },
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  // ============================================================
  // إنشاء حساب لشاغل منصب
  // ============================================================

  Future<UserCredential> _createSecondaryAuthUser({
    required String email,
    required String password,
  }) async {
    final FirebaseApp secondaryApp =
        await Firebase.initializeApp(
      name:
          'orgCreate_${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );

    try {
      final FirebaseAuth secondaryAuth =
          FirebaseAuth.instanceFor(
        app: secondaryApp,
      );

      return await secondaryAuth
          .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } finally {
      await secondaryApp.delete();
    }
  }

  String _buildAuthEmail(String username) {
    return '${username.trim()}@users.azal.local';
  }

  Future<void> _showAddMemberDialog(
    OrgNode node,
  ) async {
    final TextEditingController nameController =
        TextEditingController();
    final TextEditingController usernameController =
        TextEditingController();
    final TextEditingController passwordController =
        TextEditingController();

    final GlobalKey<FormState> formKey =
        GlobalKey<FormState>();

    final List<String> selectedProjectIds = <String>[];
    final List<String> selectedProjectNames = <String>[];

    bool active = true;
    bool obscurePassword = true;
    bool loading = false;

    String? singleProjectId;
    String? singleProjectName;
    String singleProjectCode = '';

    final bool singleProject =
        AppRoles.bindsSingleProject(node.roleKey);
    final bool multiProject =
        AppRoles.bindsMultipleProjects(node.roleKey);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Row(
                  children: <Widget>[
                    Icon(node.icon, color: node.color),
                    AppSpacingHorizontal.sm,
                    Expanded(
                      child: Text(
                        'إضافة ${node.title}',
                        style: AppTextStyles
                            .sectionTitle,
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 560,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize:
                            MainAxisSize.min,
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .stretch,
                        children: <Widget>[
                          AppTextField(
                            controller:
                                nameController,
                            label: 'الاسم الكامل',
                            hint: 'أدخل الاسم الكامل',
                            prefixIcon:
                                Icons.person,
                            enabled: !loading,
                            validator: (value) {
                              if (value ==
                                      null ||
                                  value.trim()
                                      .isEmpty) {
                                return 'أدخل الاسم الكامل';
                              }
                              return null;
                            },
                          ),

                          AppSpacing.verticalMd,

                          AppTextField(
                            controller:
                                usernameController,
                            label:
                                'اسم المستخدم / رقم الهاتف',
                            hint: 'مثال: 777123456',
                            prefixIcon: Icons.phone,
                            keyboardType:
                                TextInputType.phone,
                            enabled: !loading,
                            validator: (value) {
                              if (value ==
                                      null ||
                                  value.trim()
                                      .isEmpty) {
                                return 'أدخل اسم المستخدم';
                              }
                              return null;
                            },
                          ),

                          AppSpacing.verticalMd,

                          AppTextField(
                            controller:
                                passwordController,
                            label: 'كلمة السر',
                            hint:
                                '6 أحرف أو أرقام على الأقل',
                            prefixIcon: Icons.lock,
                            obscureText:
                                obscurePassword,
                            enabled: !loading,
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscurePassword
                                    ? Icons
                                        .visibility_off
                                    : Icons
                                        .visibility,
                              ),
                              onPressed: () =>
                                  setDialogState(
                                () {
                                  obscurePassword =
                                      !obscurePassword;
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value ==
                                      null ||
                                  value.length <
                                      6) {
                                return 'كلمة السر 6 أحرف على الأقل';
                              }
                              return null;
                            },
                          ),

                          // ==================================
                          // ربط المشروع
                          // ==================================

                          if (singleProject ||
                              multiProject) ...<Widget>[
                            AppSpacing.verticalMd,
                            _ProjectPicker(
                              stream:
                                  _activeProjectsStream,
                              multiSelect:
                                  multiProject,
                              enabled: !loading,
                              selectedIds:
                                  selectedProjectIds,
                              selectedNames:
                                  selectedProjectNames,
                              singleId:
                                  singleProjectId,
                              onSingleChanged: (id, code, name) {
                                setDialogState(() {
                                  singleProjectId = id;
                                  singleProjectCode = code ?? '';
                                  singleProjectName = name;
                                });
                              },
                              onMultiChanged: () =>
                                  setDialogState(
                                () {},
                              ),
                            ),
                          ],

                          AppSpacing.verticalMd,

                          SwitchListTile(
                            contentPadding:
                                EdgeInsets.zero,
                            title: const Text(
                              'الحساب فعال',
                            ),
                            value: active,
                            onChanged: loading
                                ? null
                                : (value) =>
                                    setDialogState(
                                  () {
                                    active = value;
                                  },
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => Navigator.of(
                              dialogContext,
                            ).pop(),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton.icon(
                    onPressed: loading
                        ? null
                        : () async {
                            if (!formKey
                                .currentState!
                                .validate()) {
                              return;
                            }

                            if ((singleProject ||
                                    multiProject) &&
                                singleProjectId ==
                                    null &&
                                selectedProjectIds
                                    .isEmpty) {
                              AppWidgets
                                  .showWarning(
                                context,
                                singleProject
                                    ? 'اختر المشروع المرتبط بهذا المنصب'
                                    : 'اختر مشروعًا واحدًا على الأقل',
                              );
                              return;
                            }

                            setDialogState(
                                () => loading = true);

                            try {
                              final String
                                  username =
                                  usernameController
                                      .text
                                      .trim();

                              final String
                                  authEmail =
                                  _buildAuthEmail(
                                username,
                              );

                              final UserCredential
                                  credential =
                                  await _createSecondaryAuthUser(
                                email: authEmail,
                                password:
                                    passwordController
                                        .text
                                        .trim(),
                              );

                              final User?
                                  firebaseUser =
                                  credential.user;

                              if (firebaseUser ==
                                  null) {
                                throw Exception(
                                  'فشل إنشاء حساب المستخدم',
                                );
                              }

                              final Map<String,
                                      dynamic>
                                  payload =
                                  <String, dynamic>{
                                'name':
                                    nameController
                                        .text
                                        .trim(),
                                'username': username,
                                'phone': username,
                                'authEmail': authEmail,
                                'role': node.roleKey,
                                'positionTitle':
                                    node.title,
                                'active': active,
                                'mustChangePassword':
                                    true,
                                'createdAt':
                                    FieldValue
                                        .serverTimestamp(),
                                'createdBy':
                                    FirebaseAuth
                                        .instance
                                        .currentUser
                                        ?.uid,
                              };

                              if (singleProject) {
                                payload['projectId'] =
                                    singleProjectId ??
                                        '';
                                payload['projectName'] =
                                    singleProjectName ?? '';
                                payload['projectCode'] =
                                    singleProjectCode;
                                payload[
                                        'projectIds'] =
                                    singleProjectId ==
                                            null
                                        ? <String>[]
                                        : <String>[
                                            singleProjectId!,
                                          ];
                                payload[
                                        'projectNames'] =
                                    singleProjectName ==
                                            null
                                        ? <String>[]
                                        : <String>[
                                            singleProjectName!,
                                          ];
                              } else if (multiProject) {
                                payload[
                                        'projectIds'] =
                                    List<String>.from(
                                  selectedProjectIds,
                                );
                                payload[
                                        'projectNames'] =
                                    List<String>.from(
                                  selectedProjectNames,
                                );
                              } else {
                                payload[
                                        'projectIds'] =
                                    <String>[];
                                payload[
                                        'projectNames'] =
                                    <String>[];
                              }

                              await _firestore
                                  .collection('users')
                                  .doc(firebaseUser.uid)
                                  .set(payload);

                              // لا نستدعي setDialogState
                              // بعد إغلاق الحوار.
                              loading = false;

                              if (!mounted) {
                                return;
                              }

                              Navigator.of(
                                dialogContext,
                              ).pop();

                              AppWidgets.showSuccess(
                                context,
                                'تم إنشاء حساب '
                                '${node.title} بنجاح',
                              );
                            } catch (e) {
                              if (!mounted) {
                                return;
                              }

                              setDialogState(
                                  () => loading =
                                      false);

                              AppWidgets.showError(
                                context,
                                'تعذر إنشاء الحساب:\n$e',
                              );
                            }
                          },
                    icon: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.person_add,
                          ),
                    label: Text(
                      loading
                          ? 'جاري الإنشاء...'
                          : 'إنشاء الحساب',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // بطاقة مسار العمل
  // ============================================================

  Widget _buildWorkflowCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary
                      .withValues(alpha: 0.10),
                  borderRadius:
                      BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.alt_route,
                  color: AppColors.primary,
                ),
              ),
              AppSpacingHorizontal.md,
              const Expanded(
                child: Text(
                  'مسار العمل: من ينشئ مَن، وماذا يُدخل',
                  style: AppTextStyles
                      .sectionTitle,
                ),
              ),
            ],
          ),

          AppSpacing.verticalMd,

          for (final _WorkflowStep step
              in _workflowSteps) ...<Widget>[
            _WorkflowTile(step: step),
            AppSpacing.verticalSm,
          ],
        ],
      ),
    );
  }
}

// ==============================================================
// نموذج شاغل المنصب
// ==============================================================

class _OrgMember {
  const _OrgMember({
    required this.name,
    required this.username,
    required this.phone,
    required this.active,
    required this.projectNames,
  });

  final String name;
  final String username;
  final String phone;
  final bool active;
  final List<String> projectNames;

  String get displayName =>
      name.isEmpty ? username : name;
}

// ==============================================================
// بطاقة المنصب في الشجرة
// ==============================================================

class _OrgNodeCard extends StatelessWidget {
  const _OrgNodeCard({
    required this.node,
    required this.count,
    required this.expanded,
    required this.hasChildren,
    required this.focused,
    required this.showAddMember,
    required this.onToggle,
    required this.onAddMember,
    required this.onDetails,
  });

  final OrgNode node;
  final int count;
  final bool expanded;
  final bool hasChildren;
  final bool focused;
  final bool showAddMember;
  final VoidCallback? onToggle;
  final VoidCallback onAddMember;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onDetails,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  BorderRadius.circular(14),
              border: Border.all(
                color: focused
                    ? node.color
                    : AppColors.border,
                width: focused ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: <Widget>[
                // ======================================
                // الأيقونة
                // ======================================

                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: node.color
                        .withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(12),
                  ),
                  child: Icon(
                    node.icon,
                    color: node.color,
                    size: 24,
                  ),
                ),

                AppSpacingHorizontal.md,

                // ======================================
                // العنوان والمهام
                // ======================================

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              node.title,
                              style: AppTextStyles
                                  .cardTitle,
                            ),
                          ),
                          AppStatusBadge(
                            text: count > 0
                                ? '$count شاغل'
                                : 'شاغر',
                            color: count > 0
                                ? node.color
                                : AppColors
                                    .textLight,
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        node.duties,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style:
                            AppTextStyles.small,
                      ),
                    ],
                  ),
                ),

                // ======================================
                // أزرار
                // ======================================

                if (hasChildren)
                  IconButton(
                    tooltip: expanded
                        ? 'تصغير'
                        : 'توسيع',
                    icon: Icon(
                      expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                    ),
                    onPressed: onToggle,
                  ),

                if (showAddMember)
                  IconButton(
                    tooltip: 'إضافة شاغل',
                    icon: const Icon(
                      Icons.person_add_alt_1,
                      size: 20,
                    ),
                    onPressed: onAddMember,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==============================================================
// بطاقة ملخص
// ==============================================================

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
        left: 6,
        right: 6,
      ),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius:
                    BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            AppSpacingHorizontal.md,
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    value,
                    style: AppTextStyles
                        .statisticNumber
                        .copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style:
                        AppTextStyles.bodySecondary,
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

// ==============================================================
// قسم داخل بطاقة التفاصيل
// ==============================================================

class _SheetSection extends StatelessWidget {
  const _SheetSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                icon,
                size: 18,
                color: AppColors.primary,
              ),
              AppSpacingHorizontal.sm,
              Text(
                title,
                style: AppTextStyles.cardTitle,
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ==============================================================
// عنصر منصب في سلسلة الإشراف
// ==============================================================

class _ChainTile extends StatelessWidget {
  const _ChainTile({required this.node});

  final OrgNode node;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.subdirectory_arrow_left,
            size: 18,
            color: node.color,
          ),
          AppSpacingHorizontal.sm,
          Expanded(
            child: Text(
              node.title,
              style: AppTextStyles.body,
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================================================
// عنصر شاغل
// ==============================================================

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});

  final _OrgMember member;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        vertical: 4,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.person_outline,
                size: 18,
                color:
                    AppColors.textSecondary,
              ),
              AppSpacingHorizontal.sm,
              Expanded(
                child: Text(
                  member.displayName,
                  style: AppTextStyles.body
                      .copyWith(
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ),
              AppStatusBadge(
                text: member.active
                    ? 'فعال'
                    : 'معطل',
                color: member.active
                    ? AppColors.success
                    : AppColors.danger,
              ),
            ],
          ),
          if (member.username
              .isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              'اسم المستخدم: ${member.username}',
              style: AppTextStyles.small,
            ),
          ],
          if (member.projectNames
              .isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: member.projectNames
                  .map(
                    (name) => AppStatusBadge(
                      text: name,
                      color: AppColors.primary,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ==============================================================
// منتقي المشاريع داخل حوار الإضافة
// ==============================================================

class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({
    required this.stream,
    required this.multiSelect,
    required this.enabled,
    required this.selectedIds,
    required this.selectedNames,
    required this.singleId,
    required this.onSingleChanged,
    required this.onMultiChanged,
  });

  final Stream<QuerySnapshot<Map<String, dynamic>>>
      stream;
  final bool multiSelect;
  final bool enabled;
  final List<String> selectedIds;
  final List<String> selectedNames;
  final String? singleId;
  final void Function(String? id, String? code, String? name)
      onSingleChanged;
  final VoidCallback onMultiChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<
        QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'تعذر تحميل المشاريع: ${snapshot.error}',
            style: AppTextStyles.small,
          );
        }

        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              vertical: 12,
            ),
            child: Center(
              child:
                  CircularProgressIndicator(),
            ),
          );
        }

        final List<
                QueryDocumentSnapshot<
                    Map<String, dynamic>>> docs =
            snapshot.data!.docs;

        docs.sort((a, b) {
          final String nameA =
              (a.data()['name'] ?? '')
                  .toString();
          final String nameB =
              (b.data()['name'] ?? '')
                  .toString();

          return nameA.compareTo(nameB);
        });

        if (docs.isEmpty) {
          return const Text(
            'لا توجد مشاريع نشطة. أنشئ مشروعًا أولًا.',
            style: AppTextStyles.small,
          );
        }

        // ============================================
        // اختيار مشروع واحد
        // ============================================

        if (!multiSelect) {
          return DropdownButtonFormField<String>(
            initialValue: singleId,
            isExpanded: true,
            decoration:
                const InputDecoration(
              labelText:
                  'المشروع المرتبط بالمنصب',
              prefixIcon: Icon(
                Icons.business,
              ),
            ),
            items: docs
                .map(
                  (doc) => DropdownMenuItem<
                      String>(
                    value: doc.id,
                    child: Text(
                      (doc.data()['name'] ?? '')
                              .toString()
                              .isEmpty
                          ? 'مشروع بدون اسم'
                          : (doc.data()['name'])
                              .toString(),
                    ),
                  ),
                )
                .toList(),
            onChanged: enabled
                ? (String? id) {
                    if (id == null) {
                      onSingleChanged(
                        null,
                        null,
                        null,
                      );
                      return;
                    }

                    final Map<String, dynamic>
                        data = docs
                            .firstWhere(
                              (doc) =>
                                  doc.id == id,
                            )
                            .data();

                    onSingleChanged(
                      id,
                      (data['code'] ?? '')
                          .toString()
                          .trim(),
                      (data['name'] ?? '')
                          .toString(),
                    );
                  }
                : null,
          );
        }

        // ============================================
        // اختيار مشاريع متعددة
        // ============================================

        return Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'المشاريع المرتبطة بالمنصب',
              style:
                  AppTextStyles.bodySecondary,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: docs
                  .map(
                    (doc) {
                      final Map<String, dynamic>
                          data = doc.data();

                      final String name =
                          (data['name'] ?? '')
                                  .toString()
                                  .isEmpty
                              ? 'مشروع بدون اسم'
                              : (data['name'])
                                  .toString();

                      final bool selected =
                          selectedIds
                              .contains(doc.id);

                      return FilterChip(
                        label: Text(name),
                        selected: selected,
                        onSelected: enabled
                            ? (bool value) {
                                if (value) {
                                  if (!selectedIds
                                      .contains(
                                    doc.id,
                                  )) {
                                    selectedIds
                                        .add(
                                      doc.id,
                                    );
                                    selectedNames
                                        .add(
                                      name,
                                    );
                                  }
                                } else {
                                  final int
                                      index =
                                      selectedIds
                                          .indexOf(
                                    doc.id,
                                  );

                                  if (index >=
                                      0) {
                                    selectedIds
                                        .removeAt(
                                      index,
                                    );
                                    selectedNames
                                        .removeAt(
                                      index,
                                    );
                                  }
                                }

                                onMultiChanged();
                              }
                            : null,
                      );
                    },
                  )
                  .toList(),
            ),
          ],
        );
      },
    );
  }
}

// ==============================================================
// مسار العمل
// ==============================================================

class _WorkflowStep {
  const _WorkflowStep({
    required this.title,
    required this.text,
    required this.icon,
    required this.color,
  });

  final String title;
  final String text;
  final IconData icon;
  final Color color;
}

const List<_WorkflowStep> _workflowSteps =
    <_WorkflowStep>[
  _WorkflowStep(
    title: '1) المشرف الرئيسي',
    text: 'يحدد المحافظة والمديرية، ثم ينشئ حسابات رؤساء '
        'الإدارات الثلاثة: مدير إدارة المشاريع، ومدير إدارة '
        'الحركة، والمدير المالي (الاسم، الهاتف، اسم المستخدم، '
        'كلمة السر).',
    icon: Icons.admin_panel_settings,
    color: AppColors.generalManager,
  ),
  _WorkflowStep(
    title: '2) مدير إدارة المشاريع',
    text: 'يدخل باسم المستخدم وكلمة السر، فينشئ المشروع، '
        'وينشئ مهندس المشروع (= مدير المشروع) ومدير الجودة، '
        'ويحدد البنود والأنواع والمعدات.',
    icon: Icons.apartment,
    color: AppColors.projectsDeptManager,
  ),
  _WorkflowStep(
    title: '3) مدير الجودة',
    text: 'يدخل الكمية التعاقدية لكل بند، ويحدد التكلفة '
        'التقديرية لكل بند، ويربط التكلفة الفعلية لكل بند، '
        'ويحدد مشرفًا لكل بند في المشروع.',
    icon: Icons.verified,
    color: AppColors.qualityCostManager,
  ),
  _WorkflowStep(
    title: '4) مشرف المشروع',
    text: 'ميداني: يدخل باسم المستخدم وكلمة السر، فيدخل '
        'الكميات المنفذة لكل بند وتكاليف التنفيذ الفعلية.',
    icon: Icons.supervisor_account,
    color: AppColors.projectSupervisor,
  ),
  _WorkflowStep(
    title: '5) مراقب الحركة',
    text: 'يدخل استهلاك المعدة من المحروقات والكمية التي '
        'اشتغلت فيها المعدة. هذا الإدخال مستقل عن التكاليف '
        'التي يدخلها المشرف.',
    icon: Icons.local_gas_station,
    color: AppColors.movementMonitor,
  ),
  _WorkflowStep(
    title: '6) المدير المالي ← المحاسب',
    text: 'المدير المالي ينشئ المحاسب من لوحته ويحدد له مشروعه. '
        'والمحاسب مسؤول عن أعمال ذلك المشروع: سندات الصرف '
        'والقبض، والصندوق ورصيده، والقيود اليومية — وكل سند '
        'يُرحَّل تلقائيًا إلى قيد يومية متوازن.',
    icon: Icons.receipt_long,
    color: AppColors.projectAccountant,
  ),
];

class _WorkflowTile extends StatelessWidget {
  const _WorkflowTile({required this.step});

  final _WorkflowStep step;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: step.color
                .withValues(alpha: 0.10),
            borderRadius:
                BorderRadius.circular(11),
          ),
          child: Icon(
            step.icon,
            size: 20,
            color: step.color,
          ),
        ),
        AppSpacingHorizontal.md,
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                step.title,
                style: AppTextStyles.body
                    .copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                step.text,
                style:
                    AppTextStyles.bodySecondary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

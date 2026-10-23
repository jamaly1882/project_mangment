import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../core/constants/roles.dart';

// ============================================================
// صفحة مستخدمي إدارة — «كل إدارة تنشئ مستخدميها»
// ============================================================
//
// قاعدة إنشاء الحسابات المعتمدة (AppRoles.creatableBy):
// • المشرف الرئيسي ينشئ رؤساء الإدارات الثلاثة فقط:
//   مدير إدارة المشاريع، مدير إدارة الحركة، المدير المالي.
// • كل رئيس إدارة ينشئ كل من في إدارته من صفحته:
//   - المشاريع: مدير الجودة، مشرف المشروع، مهندس المشروع.
//   - الحركة: مدير المحروقات، مراقب الحركة، مدير الورشة.
//   - المالية: إدارة الحسابات، محاسب المشروع.
// • بقية الأدوار لا تنشئ حسابات.
//
// هذه الصفحة واحدة وتُستخدَم للأربع إدارات: تُمرَّر لها
// قائمة الأدوار المسموحة (من creatableBy) فتعرض تبويبًا
// لكل دور: قائمة شاغليه + إنشاء حساب جديد (Firebase Auth
// بتطبيق ثانوي، كما في صفحة المستخدمين السابقة) + التفعيل
// والتعطيل والحذف من النظام.
//
// ربط المشاريع حسب الدور (من AppRoles):
// • مهندس المشروع: مشروع واحد (projectId).
// • مشرف المشروع ومراقب الحركة: مشاريع متعددة (projectIds).
// • بقية الأدوار: بلا ربط.
//
// Firestore: users/{uid} بنفس حقول النظام الحالية
// (name, username, phone, authEmail, role, projectId(s),
// projectName(s), active, mustChangePassword, createdAt,
// createdBy) — والدور يُكتب بمفتاحه الجديد في الهيكل،
// والحسابات القديمة (supervisor/accountant...) تظهر في
// تبويب دورها الجديد عبر AppRoles.normalize.
// ============================================================

class DepartmentUsersPage extends StatefulWidget {
  const DepartmentUsersPage({
    super.key,
    required this.title,
    required this.roles,
    this.subtitle,
  });

  /// عنوان الصفحة (مثل: مديرو الإدارات / مستخدمو إدارة الحركة).
  final String title;

  /// الأدوار التي يديرها مستخدم هذه الصفحة (من
  /// [AppRoles.creatableBy] لدور رئيس الإدارة).
  final List<String> roles;

  /// شرح اختياري يظهر أعلى القائمة.
  final String? subtitle;

  @override
  State<DepartmentUsersPage> createState() =>
      _DepartmentUsersPageState();
}

class _DepartmentUsersPageState extends State<DepartmentUsersPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  int _tabIndex = 0;
  String _search = '';

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _projects =>
      _firestore.collection('projects');

  String get _currentRole {
    if (widget.roles.isEmpty) return '';
    final int index =
        _tabIndex.clamp(0, widget.roles.length - 1).toInt();
    return widget.roles[index];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  // ==========================================================
  // إنشاء مستخدم Firebase Authentication بتطبيق ثانوي
  // (حتى لا يخرج المنشئ من حسابه) — نفس آلية النظام الحالية.
  // ==========================================================

  Future<UserCredential> _createSecondaryAuthUser({
    required String email,
    required String password,
  }) async {
    final FirebaseApp secondaryApp = await Firebase.initializeApp(
      name: 'usersCreation_${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );

    try {
      final FirebaseAuth secondaryAuth =
          FirebaseAuth.instanceFor(app: secondaryApp);
      return await secondaryAuth.createUserWithEmailAndPassword(
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

  // ==========================================================
  // Build
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title), centerTitle: true),
        floatingActionButton: widget.roles.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _showAddUserDialog(_currentRole),
                icon: const Icon(Icons.person_add_alt_1),
                label: Text('إضافة ${AppRoles.label(_currentRole)}'),
              ),
        body: widget.roles.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'لا توجد أدوار يمكن لهذا الحساب إنشاءها.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Column(
                children: <Widget>[
                  if (widget.subtitle != null)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          widget.subtitle!,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: <Widget>[
                        for (int i = 0; i < widget.roles.length; i++)
                          Padding(
                            padding:
                                const EdgeInsetsDirectional.only(end: 6),
                            child: ChoiceChip(
                              label: Text(AppRoles.label(widget.roles[i])),
                              selected: _tabIndex == i,
                              onSelected: (_) =>
                                  setState(() => _tabIndex = i),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'بحث بالاسم أو اسم المستخدم أو الهاتف...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _search = '');
                                },
                              ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) => setState(
                          () => _search = value.trim().toLowerCase()),
                    ),
                  ),
                  Expanded(child: _usersList()),
                ],
              ),
      ),
    );
  }

  Widget _usersList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _users.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'تعذر تحميل المستخدمين.\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
            (snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where((doc) {
          final Map<String, dynamic> d = doc.data();
          if (AppRoles.normalize(d['role']?.toString()) !=
              _currentRole) {
            return false;
          }
          if (_search.isEmpty) return true;
          final String text =
              '${d['name'] ?? ''} ${d['username'] ?? ''} ${d['phone'] ?? ''}'
                  .toLowerCase();
          return text.contains(_search);
        }).toList()
              ..sort((a, b) => (a.data()['name'] ?? '')
                  .toString()
                  .compareTo((b.data()['name'] ?? '').toString()));

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.people_outline,
                      size: 52, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    'لا يوجد «${AppRoles.label(_currentRole)}» بعد',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'اضغط زر الإضافة لإنشاء أول حساب بهذا الدور.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
          itemCount: docs.length,
          itemBuilder: (context, index) => _userCard(docs[index]),
        );
      },
    );
  }

  Widget _userCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data();
    final String name = (d['name'] ?? '').toString().trim();
    final String username = (d['username'] ?? '').toString().trim();
    final String phone = (d['phone'] ?? '').toString().trim();
    final bool isActive = d['active'] != false;

    final List<String> projectNames = <String>[
      ...((d['projectNames'] as List?) ?? const <dynamic>[])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty),
    ];
    final String singleProject = (d['projectName'] ?? '').toString().trim();
    if (projectNames.isEmpty && singleProject.isNotEmpty) {
      projectNames.add(singleProject);
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              (isActive ? Colors.green : Colors.grey).withValues(alpha: 0.12),
          child: Icon(
            Icons.person_outline,
            color: isActive ? Colors.green : Colors.grey,
          ),
        ),
        title: Text(
          name.isNotEmpty ? name : 'مستخدم بدون اسم',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'اسم المستخدم: ${username.isEmpty ? '—' : username}'
            '${phone.isEmpty || phone == username ? '' : '  |  الهاتف: $phone'}'
            '${projectNames.isEmpty ? '' : '\nالمشاريع: ${projectNames.join('، ')}'}'
            '${isActive ? '' : '\nالحساب معطّل'}',
          ),
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'toggle') _toggleActive(doc);
            if (value == 'delete') _deleteUser(doc);
          },
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            PopupMenuItem(
              value: 'toggle',
              child: Text(isActive ? 'تعطيل الحساب' : 'تفعيل الحساب'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('حذف من النظام'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleActive(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final bool isActive = doc.data()['active'] != false;
    try {
      await _users.doc(doc.id).update(<String, dynamic>{
        'active': !isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _showMessage(isActive ? 'تم تعطيل الحساب' : 'تم تفعيل الحساب');
    } catch (error) {
      _showMessage('تعذر تحديث حالة الحساب: $error', error: true);
    }
  }

  Future<void> _deleteUser(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final String name = (doc.data()['name'] ?? '').toString();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المستخدم من النظام'),
          content: Text(
            'سيُحذف «$name» (${AppRoles.label(_currentRole)}) من قائمة '
            'مستخدمي النظام ولن يستطيع تسجيل الدخول.\n\n'
            'ملاحظة: يبقى حساب الدخول في Firebase Authentication، '
            'فلا يمكن إعادة استخدام اسم المستخدم نفسه لحساب جديد.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
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
      await _users.doc(doc.id).delete();
      _showMessage('تم حذف المستخدم من النظام');
    } catch (error) {
      _showMessage('تعذر حذف المستخدم: $error', error: true);
    }
  }

  // ==========================================================
  // إنشاء حساب جديد بدور محدد
  // ==========================================================

  Future<void> _showAddUserDialog(String role) async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController nameController = TextEditingController();
    final TextEditingController usernameController =
        TextEditingController();
    final TextEditingController passwordController =
        TextEditingController();
    final TextEditingController phoneController = TextEditingController();

    final bool singleProject = AppRoles.bindsSingleProject(role);
    final bool multiProjects = AppRoles.bindsMultipleProjects(role);

    String? selectedProjectId;
    String selectedProjectName = '';
    List<String> selectedProjectIds = <String>[];
    List<String> selectedProjectNames = <String>[];

    bool active = true;
    bool obscurePassword = true;
    bool loading = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text('إضافة ${AppRoles.label(role)}'),
                content: SizedBox(
                  width: 560,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            AppRoles.duties(role),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                          const SizedBox(height: 14),
                          _field(
                            controller: nameController,
                            label: 'الاسم الكامل',
                            required: true,
                            icon: Icons.person_outline,
                          ),
                          _field(
                            controller: usernameController,
                            label: 'اسم المستخدم (للدخول)',
                            required: true,
                            icon: Icons.alternate_email,
                            validator: (value) {
                              final String v = (value ?? '').trim();
                              if (v.isEmpty) return 'اسم المستخدم مطلوب';
                              if (v.contains(' ') || v.contains('@')) {
                                return 'بدون مسافات وبدون @';
                              }
                              return null;
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextFormField(
                              controller: passwordController,
                              obscureText: obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'كلمة السر *',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                prefixIcon:
                                    const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined),
                                  onPressed: () => setDialogState(() =>
                                      obscurePassword = !obscurePassword),
                                ),
                              ),
                              validator: (value) {
                                final String v = value ?? '';
                                if (v.isEmpty) return 'كلمة السر مطلوبة';
                                if (v.length < 6) {
                                  return '6 أحرف على الأقل';
                                }
                                return null;
                              },
                            ),
                          ),
                          _field(
                            controller: phoneController,
                            label: 'رقم الهاتف (اختياري)',
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                          ),
                          if (singleProject)
                            _singleProjectField(
                              selectedProjectId: selectedProjectId,
                              onChanged: (id, name) {
                                setDialogState(() {
                                  selectedProjectId = id;
                                  selectedProjectName = name;
                                });
                              },
                            ),
                          if (multiProjects)
                            _multiProjectsField(
                              selectedProjectIds: selectedProjectIds,
                              onToggle: (id, name, selected) {
                                setDialogState(() {
                                  if (selected) {
                                    if (!selectedProjectIds.contains(id)) {
                                      selectedProjectIds =
                                          <String>[...selectedProjectIds, id];
                                      selectedProjectNames = <String>[
                                        ...selectedProjectNames,
                                        name
                                      ];
                                    }
                                  } else {
                                    final int i =
                                        selectedProjectIds.indexOf(id);
                                    selectedProjectIds = <String>[
                                      ...selectedProjectIds
                                    ]..remove(id);
                                    if (i >= 0 &&
                                        i < selectedProjectNames.length) {
                                      selectedProjectNames = <String>[
                                        ...selectedProjectNames
                                      ]..removeAt(i);
                                    }
                                  }
                                });
                              },
                            ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('الحساب مفعّل'),
                            value: active,
                            onChanged: loading
                                ? null
                                : (value) =>
                                    setDialogState(() => active = value),
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
                        : () => Navigator.pop(dialogContext),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton.icon(
                    onPressed: loading
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            if (singleProject &&
                                (selectedProjectId == null ||
                                    selectedProjectId!.isEmpty)) {
                              _showMessage(
                                'اختر المشروع الذي سيديره ${AppRoles.label(role)}',
                                error: true,
                              );
                              return;
                            }
                            if (multiProjects &&
                                selectedProjectIds.isEmpty) {
                              _showMessage(
                                'اختر مشروعًا واحدًا على الأقل',
                                error: true,
                              );
                              return;
                            }

                            final String name =
                                nameController.text.trim();
                            final String username =
                                usernameController.text.trim();
                            final String password =
                                passwordController.text;
                            final String phone =
                                phoneController.text.trim();
                            final String authEmail =
                                _buildAuthEmail(username);
                            final String singleId =
                                selectedProjectId ?? '';
                            final List<String> finalProjectIds =
                                singleProject
                                    ? <String>[singleId]
                                    : List<String>.of(selectedProjectIds);
                            final List<String> finalProjectNames =
                                singleProject
                                    ? <String>[selectedProjectName]
                                    : List<String>.of(selectedProjectNames);

                            setDialogState(() => loading = true);
                            try {
                              final UserCredential credential =
                                  await _createSecondaryAuthUser(
                                email: authEmail,
                                password: password,
                              );
                              final User? firebaseUser = credential.user;
                              if (firebaseUser == null) {
                                throw Exception('فشل إنشاء حساب المستخدم');
                              }

                              await _users.doc(firebaseUser.uid).set(
                                <String, dynamic>{
                                  'name': name,
                                  'username': username,
                                  'phone':
                                      phone.isEmpty ? username : phone,
                                  'authEmail': authEmail,
                                  'role': role,
                                  if (singleProject)
                                    'projectId': singleId,
                                  if (singleProject)
                                    'projectName': selectedProjectName,
                                  'projectIds': finalProjectIds,
                                  'projectNames': finalProjectNames,
                                  'active': active,
                                  'mustChangePassword': true,
                                  'createdAt':
                                      FieldValue.serverTimestamp(),
                                  'createdBy': FirebaseAuth
                                      .instance.currentUser?.uid,
                                },
                              );

                              // لا setDialogState بعد إغلاق الحوار
                              // (نفس ملاحظة صفحة المستخدمين السابقة).
                              loading = false;
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                              _showMessage(
                                'تم إنشاء حساب ${AppRoles.label(role)} بنجاح',
                              );
                            } on FirebaseAuthException catch (e) {
                              setDialogState(() => loading = false);
                              String message =
                                  'حدث خطأ أثناء إنشاء حساب Firebase';
                              if (e.code == 'email-already-in-use') {
                                message =
                                    'اسم المستخدم موجود بالفعل في نظام الدخول';
                              } else if (e.code == 'weak-password') {
                                message = 'كلمة المرور ضعيفة';
                              } else if (e.code == 'invalid-email') {
                                message = 'بيانات حساب الدخول غير صحيحة';
                              } else if (e.message != null) {
                                message = e.message!;
                              }
                              _showMessage(message, error: true);
                            } catch (error) {
                              setDialogState(() => loading = false);
                              _showMessage(
                                'تعذر إنشاء الحساب: $error',
                                error: true,
                              );
                            }
                          },
                    icon: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.person_add_alt_1),
                    label: Text(loading ? 'جارٍ الإنشاء...' : 'إنشاء الحساب'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    phoneController.dispose();
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String? value)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
          isDense: true,
          prefixIcon: Icon(icon),
        ),
        validator: validator ??
            (required
                ? (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'هذا الحقل مطلوب'
                        : null
                : null),
      ),
    );
  }

  // ==========================================================
  // اختيار مشروع واحد (مهندس المشروع) / مشاريع متعددة
  // (مشرف المشروع ومراقب الحركة) من مشاريع النظام.
  // ==========================================================

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedProjects(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) {
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
        (snapshot?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .toList()
          ..sort((a, b) => (a.data()['name'] ?? '')
              .toString()
              .compareTo((b.data()['name'] ?? '').toString()));
    return docs;
  }

  String _projectLabel(Map<String, dynamic> data) {
    final String name = (data['name'] ?? '').toString().trim();
    final String code = (data['code'] ?? '').toString().trim();
    if (code.isNotEmpty && name.isNotEmpty) return '$code — $name';
    if (name.isNotEmpty) return name;
    if (code.isNotEmpty) return code;
    return 'مشروع بدون اسم';
  }

  Widget _singleProjectField({
    required String? selectedProjectId,
    required void Function(String id, String name) onChanged,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _projects.snapshots(),
      builder: (context, snapshot) {
        final docs = _sortedProjects(snapshot.data);
        final bool hasSelected = selectedProjectId != null &&
            docs.any((d) => d.id == selectedProjectId);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            key: ValueKey<String?>('dept-project-$selectedProjectId'),
            initialValue: hasSelected ? selectedProjectId : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'المشروع *',
              border: OutlineInputBorder(),
              isDense: true,
              prefixIcon: Icon(Icons.apartment_outlined),
            ),
            hint: const Text('اختر المشروع برقمه'),
            items: docs
                .map(
                  (d) => DropdownMenuItem<String>(
                    value: d.id,
                    child: Text(
                      _projectLabel(d.data()),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (String? value) {
              if (value == null) return;
              final doc = docs.firstWhere((d) => d.id == value);
              onChanged(value, (doc.data()['name'] ?? '').toString());
            },
            validator: (String? value) =>
                (value == null || value.isEmpty) ? 'اختر المشروع' : null,
          ),
        );
      },
    );
  }

  Widget _multiProjectsField({
    required List<String> selectedProjectIds,
    required void Function(String id, String name, bool selected) onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'المشاريع *',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _projects.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Text('جاري تحميل المشاريع...');
            }
            final docs = _sortedProjects(snapshot.data);
            if (docs.isEmpty) {
              return const Text('لا توجد مشاريع في النظام بعد');
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        selectedProjectIds.isEmpty
                            ? 'اختر مشروعًا واحدًا على الأقل'
                            : 'تم اختيار ${selectedProjectIds.length} مشروع',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                    ),
                    ...docs.map(
                      (d) => CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(_projectLabel(d.data())),
                        value: selectedProjectIds.contains(d.id),
                        onChanged: (bool? value) => onToggle(
                          d.id,
                          (d.data()['name'] ?? '').toString(),
                          value == true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

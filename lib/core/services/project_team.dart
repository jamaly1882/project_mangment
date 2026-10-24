import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/roles.dart';

// ============================================================
// فريق المشروع — المهندس ومشرف المشروع المرتبطان بالمشروع
// ============================================================
//
// في الهيكل الإداري: مدير إدارة المشاريع ينشئ حساب مشرف المشروع
// ويربطه بالمشروع (users.projectIds أو users.projectId)، وكذلك
// مهندس المشروع. لذلك عند إدخال بند جديد لا حاجة لاختيار المهندس
// أو المشرف يدويًا: يُقرآن من الربط الموجود أصلًا.
// ============================================================

/// عضو من فريق المشروع (مهندس أو مشرف).
class ProjectMember {
  const ProjectMember({
    required this.id,
    required this.name,
    required this.role,
    this.jobNumber = '',
  });

  final String id;
  final String name;
  final String role;

  /// الرقم الوظيفي إن وُجد.
  final String jobNumber;

  String get displayName =>
      jobNumber.trim().isEmpty ? name : '$name - $jobNumber';
}

class ProjectTeam {
  ProjectTeam._();

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// هل بيانات المستخدم [data] مرتبطة بالمشروع [projectId]؟
  ///
  /// الربط يقبل `projectIds` (قائمة أو نص) و`projectId` المفرد،
  /// كما في بقية صفحات التطبيق.
  static bool belongsToProject(
    Map<String, dynamic> data,
    String projectId,
  ) {
    if (projectId.trim().isEmpty) return false;
    if (data['active'] == false) return false;

    final Set<String> ids = <String>{};

    final dynamic rawList = data['projectIds'];
    if (rawList is Iterable) {
      for (final value in rawList) {
        final id = (value ?? '').toString().trim();
        if (id.isNotEmpty) ids.add(id);
      }
    } else if (rawList != null) {
      final id = rawList.toString().trim();
      if (id.isNotEmpty) ids.add(id);
    }

    final single = (data['projectId'] ?? '').toString().trim();
    if (single.isNotEmpty) ids.add(single);

    return ids.contains(projectId.trim());
  }

  static String _nameOf(Map<String, dynamic> data, String fallbackId) {
    final name = (data['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;

    final username = (data['username'] ?? '').toString().trim();
    if (username.isNotEmpty) return username;

    return fallbackId;
  }

  /// المشرفون الميدانيون المرتبطون بالمشروع (الجدد والقدامى).
  static Future<List<ProjectMember>> supervisors(String projectId) async {
    return _loadMembers(
      projectId: projectId,
      roles: <String>[
        AppRoles.projectSupervisor,
        AppRoles.supervisor,
        AppRoles.driver,
      ],
    );
  }

  /// مهندسو المشروع المرتبطون به.
  static Future<List<ProjectMember>> engineers(String projectId) async {
    return _loadMembers(
      projectId: projectId,
      roles: <String>[
        AppRoles.projectEngineer,
        AppRoles.engineer,
      ],
    );
  }

  static Future<List<ProjectMember>> _loadMembers({
    required String projectId,
    required List<String> roles,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', whereIn: roles)
          .get();

      final members = <ProjectMember>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (!belongsToProject(data, projectId)) continue;

        members.add(
          ProjectMember(
            id: doc.id,
            name: _nameOf(data, doc.id),
            role: (data['role'] ?? '').toString(),
            jobNumber: (data['jobNumber'] ?? '').toString().trim(),
          ),
        );
      }

      members.sort((a, b) => a.name.compareTo(b.name));
      return members;
    } catch (e) {
      // غياب الفهرس أو خطأ شبكة لا يمنع إدخال البند.
      return const <ProjectMember>[];
    }
  }

  /// المشرف الوحيد المرتبط بالمشروع، أو null إن لم يوجد أو تعدد.
  static Future<ProjectMember?> singleSupervisor(String projectId) async {
    final members = await supervisors(projectId);
    return members.length == 1 ? members.first : null;
  }

  /// مهندس المشروع الوحيد المرتبط، أو null إن لم يوجد أو تعدد.
  static Future<ProjectMember?> singleEngineer(String projectId) async {
    final members = await engineers(projectId);
    return members.length == 1 ? members.first : null;
  }

  /// المشرف الذي سيُسند إليه البند: من وثيقة البند إن حُفظ فيها،
  /// وإلا المشرف الوحيد المرتبط بالمشروع.
  static Future<ProjectMember?> supervisorForItem({
    required String projectId,
    String? itemSupervisorId,
    String? itemSupervisorName,
  }) async {
    final savedId = (itemSupervisorId ?? '').trim();
    final savedName = (itemSupervisorName ?? '').trim();

    if (savedId.isNotEmpty) {
      return ProjectMember(
        id: savedId,
        name: savedName.isEmpty ? 'مشرف المشروع' : savedName,
        role: AppRoles.projectSupervisor,
      );
    }

    return singleSupervisor(projectId);
  }
}

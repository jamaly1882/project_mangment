import 'package:flutter_test/flutter_test.dart';

import 'package:azal/core/services/project_team.dart';

// ============================================================
// ربط المستخدمين بالمشاريع
// ============================================================
// المشرف والمهندس مربوطان بالمشروع مسبقًا، فلا يُطلبان عند إدخال
// البند. هذه الاختبارات تتحقق من قراءة الربط بكل صيغه المخزّنة.
// ============================================================

void main() {
  group('belongsToProject', () {
    test('قائمة projectIds', () {
      expect(
        ProjectTeam.belongsToProject(
          <String, dynamic>{
            'projectIds': <String>['p1', 'p2'],
          },
          'p2',
        ),
        isTrue,
      );
    });

    test('projectId مفرد', () {
      expect(
        ProjectTeam.belongsToProject(
          <String, dynamic>{'projectId': 'p1'},
          'p1',
        ),
        isTrue,
      );
    });

    test('القائمة المخزّنة كنص مفصول بفواصل', () {
      expect(
        ProjectTeam.belongsToProject(
          <String, dynamic>{'projectIds': 'p1,p2'},
          'p1',
        ),
        isFalse,
        reason: 'النص المفرد يُقرأ كمعرّف واحد فقط',
      );

      expect(
        ProjectTeam.belongsToProject(
          <String, dynamic>{'projectIds': 'p1'},
          'p1',
        ),
        isTrue,
      );
    });

    test('مشروع آخر غير مرتبط', () {
      expect(
        ProjectTeam.belongsToProject(
          <String, dynamic>{'projectIds': <String>['p1']},
          'p9',
        ),
        isFalse,
      );
    });

    test('الحساب المعطّل لا يُعد مرتبطًا', () {
      expect(
        ProjectTeam.belongsToProject(
          <String, dynamic>{
            'projectIds': <String>['p1'],
            'active': false,
          },
          'p1',
        ),
        isFalse,
      );
    });

    test('معرّف مشروع فارغ', () {
      expect(
        ProjectTeam.belongsToProject(
          <String, dynamic>{'projectIds': <String>['p1']},
          '',
        ),
        isFalse,
      );
    });

    test('بيانات بلا ربط', () {
      expect(
        ProjectTeam.belongsToProject(
          <String, dynamic>{'name': 'مشرف'},
          'p1',
        ),
        isFalse,
      );
    });
  });

  group('ProjectMember', () {
    test('الاسم المعروض يضم الرقم الوظيفي إن وُجد', () {
      const withNumber = ProjectMember(
        id: 'u1',
        name: 'أحمد',
        role: 'project_supervisor',
        jobNumber: '1024',
      );

      const withoutNumber = ProjectMember(
        id: 'u2',
        name: 'سالم',
        role: 'project_supervisor',
      );

      expect(withNumber.displayName, 'أحمد - 1024');
      expect(withoutNumber.displayName, 'سالم');
    });
  });
}

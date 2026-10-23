import 'package:flutter_test/flutter_test.dart';

import 'package:azal/core/constants/roles.dart';

// ============================================================
// قاعدة إنشاء الحسابات: «كل إدارة تنشئ مستخدميها»
// المشرف الرئيسي ينشئ رؤساء الإدارات الثلاثة فقط، وكل
// رئيس إدارة ينشئ كل من في إدارته، وبقية الأدوار لا تنشئ.
// ============================================================

void main() {
  group('من ينشئ مَن', () {
    test('المشرف الرئيسي ينشئ ثلاثة فقط: رؤساء الإدارات', () {
      expect(
        AppRoles.creatableBy(AppRoles.generalManager),
        <String>[
          AppRoles.projectsDeptManager,
          AppRoles.movementDeptManager,
          AppRoles.financialManager,
        ],
      );
      // الدور القديم admin = المشرف الرئيسي.
      expect(
        AppRoles.creatableBy(AppRoles.admin),
        AppRoles.creatableBy(AppRoles.generalManager),
      );
    });

    test('مدير إدارة المشاريع ينشئ كل إدارته', () {
      expect(
        AppRoles.creatableBy(AppRoles.projectsDeptManager),
        <String>[
          AppRoles.qualityCostManager,
          AppRoles.projectSupervisor,
          AppRoles.projectEngineer,
        ],
      );
    });

    test('مدير إدارة الحركة ينشئ كل إدارته', () {
      expect(
        AppRoles.creatableBy(AppRoles.movementDeptManager),
        <String>[
          AppRoles.fuelManager,
          AppRoles.movementMonitor,
          AppRoles.workshopManager,
        ],
      );
    });

    test('المدير المالي ينشئ كل إدارته', () {
      expect(
        AppRoles.creatableBy(AppRoles.financialManager),
        <String>[
          AppRoles.accountsManager,
          AppRoles.projectAccountant,
        ],
      );
    });

    test('بقية الأدوار لا تنشئ حسابات إطلاقًا', () {
      for (final String role in <String>[
        AppRoles.qualityCostManager,
        AppRoles.projectEngineer,
        AppRoles.projectSupervisor,
        AppRoles.fuelManager,
        AppRoles.movementMonitor,
        AppRoles.workshopManager,
        AppRoles.accountsManager,
        AppRoles.projectAccountant,
        AppRoles.user,
        '',
      ]) {
        expect(
          AppRoles.creatableBy(role),
          isEmpty,
          reason: 'الدور $role يجب ألا ينشئ أحدًا',
        );
      }
    });

    test('رؤساء الإدارات هم أبناء المشرف الرئيسي المباشرون', () {
      expect(AppRoles.isDepartmentHead(AppRoles.projectsDeptManager), isTrue);
      expect(AppRoles.isDepartmentHead(AppRoles.movementDeptManager), isTrue);
      expect(AppRoles.isDepartmentHead(AppRoles.financialManager), isTrue);

      expect(AppRoles.isDepartmentHead(AppRoles.generalManager), isFalse);
      expect(AppRoles.isDepartmentHead(AppRoles.qualityCostManager), isFalse);
      expect(AppRoles.isDepartmentHead(AppRoles.fuelManager), isFalse);

      // كل رئيس إدارة مديره المباشر هو المشرف الرئيسي.
      for (final String head in AppRoles.creatableBy(
        AppRoles.generalManager,
      )) {
        expect(AppRoles.parentOf(head), AppRoles.generalManager);
        expect(AppRoles.isDepartmentHead(head), isTrue);
      }
    });

    test('كل دور (عدا المشرف والرؤساء) له رئيس إدارة واحد ينشئه', () {
      final Map<String, List<String>> creators = <String, List<String>>{};
      for (final String head in <String>[
        AppRoles.generalManager,
        AppRoles.projectsDeptManager,
        AppRoles.movementDeptManager,
        AppRoles.financialManager,
      ]) {
        for (final String created in AppRoles.creatableBy(head)) {
          creators.putIfAbsent(created, () => <String>[]).add(head);
        }
      }

      // كل دور في الهيكل (عدا المشرف الرئيسي) له منشئ واحد بالضبط.
      for (final String role in AppRoles.all) {
        if (role == AppRoles.generalManager) continue;
        expect(
          creators[role]?.length,
          1,
          reason: 'الدور $role يجب أن ينشئه واحد فقط: ${creators[role]}',
        );
      }
    });
  });

  // ============================================================
  // التعرف على حساب مشرف البند/المشروع
  // ============================================================
  // صفحات إنشاء الحسابات تكتب الدور بصيغ مختلفة:
  // project_supervisor (الهيكل الجديد) أو supervisor/driver (قديمة).
  // كلها يجب أن تُعامل كحساب مشرف ميداني واحد.

  group('isFieldSupervisor', () {
    test('يقبل دور مشرف المشروع الجديد والقديم والسائق القديم', () {
      expect(AppRoles.isFieldSupervisor(AppRoles.projectSupervisor), isTrue);
      expect(AppRoles.isFieldSupervisor(AppRoles.supervisor), isTrue);
      expect(AppRoles.isFieldSupervisor(AppRoles.driver), isTrue);
      // احتمال وجود مسافات أو حروف كبيرة في البيانات القديمة.
      expect(AppRoles.isFieldSupervisor(' Project_Supervisor '), isTrue);
    });

    test('يرفض بقية الأدوار', () {
      expect(AppRoles.isFieldSupervisor(AppRoles.projectEngineer), isFalse);
      expect(AppRoles.isFieldSupervisor(AppRoles.qualityCostManager), isFalse);
      expect(AppRoles.isFieldSupervisor(AppRoles.admin), isFalse);
      expect(AppRoles.isFieldSupervisor(''), isFalse);
      expect(AppRoles.isFieldSupervisor(null), isFalse);
    });
  });
}

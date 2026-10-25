import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'roles.dart';

// ============================================================
// الهيكل الإداري
// ============================================================
//
// يمثّل هذا الملف شجرة المناصب المعتمدة في النظام. كل منصب
// يقابل دورًا من أدوار [AppRoles]، ويحمل:
//
// • العنوان المعروض في المخطط.
// • الأيقونة واللون.
// • مهام المنصب.
// • ما ينشئه هذا المنصب (لمن يعطيه صلاحية إنشاء حسابات).
// • الأدوار القديمة المكافئة (لعدّ المستخدمين الحاليين).
//
// لتعديل الهيكل: عدّل القائمة [OrgStructure.nodes] فقط، وبقية
// الشاشات (المخطط، التوجيه، الصلاحيات) تقرأ منها مباشرة.
// ============================================================

/// منصب في الهيكل الإداري.
class OrgNode {
  const OrgNode({
    required this.roleKey,
    required this.title,
    required this.icon,
    required this.color,
    required this.duties,
    this.parentKey,
    this.creates = const <String>[],
    this.legacyRoles = const <String>[],
  });

  /// مفتاح الدور (من [AppRoles]).
  final String roleKey;

  /// اسم المنصب كما يظهر في المخطط.
  final String title;

  /// الأيقونة.
  final IconData icon;

  /// لون المنصب.
  final Color color;

  /// مهام المنصب.
  final String duties;

  /// مفتاح المنصب المدير المباشر (null للقمة).
  final String? parentKey;

  /// ما ينشئه شاغل هذا المنصب (نص توضيحي).
  final List<String> creates;

  /// أدوار قديمة تُحسب ضمن هذا المنصب عند عدّ المستخدمين.
  final List<String> legacyRoles;

  /// كل مفاتيح الأدوار التي يمثلها هذا المنصب
  /// (الدور الأساسي + الأدوار القديمة المكافئة).
  List<String> get allRoleKeys => <String>[roleKey, ...legacyRoles];

  /// مستوى المنصب في الشجرة (القمة = 0).
  int get level => OrgStructure.levelOf(roleKey);
}

/// شجرة الهيكل الإداري.
class OrgStructure {
  OrgStructure._();

  /// كل مناصب الهيكل مرتبة من القمة إلى الأسفل
  /// (الترتيب هو ترتيب العرض داخل كل مستوى).
  static const List<OrgNode> nodes = <OrgNode>[
    // ========================================================
    // المستوى 0 — القمة
    // ========================================================

    OrgNode(
      roleKey: AppRoles.generalManager,
      title: 'المشرف الرئيسي (المدير)',
      icon: Icons.admin_panel_settings,
      color: AppColors.generalManager,
      duties: 'الإشراف العام على جميع الإدارات. يحدد المحافظة والمديرية، '
          'وينشئ حسابات رؤساء الإدارات الثلاثة فقط (المشاريع، الحركة، '
          'المالية) — وكل إدارة تنشئ بقية مستخدميها بنفسها. يعتمد '
          'الخطط والموازنات وتقارير الإنجاز.',
      creates: <String>[
        'المحافظات والمديريات',
        'حساب مدير إدارة المشاريع',
        'حساب مدير إدارة الحركة',
        'حساب المدير المالي',
      ],
      legacyRoles: <String>[AppRoles.admin],
    ),

    // ========================================================
    // المستوى 1 — رؤساء الإدارات
    // ========================================================

    OrgNode(
      roleKey: AppRoles.projectsDeptManager,
      parentKey: AppRoles.generalManager,
      title: 'مدير إدارة المشاريع',
      icon: Icons.apartment,
      color: AppColors.projectsDeptManager,
      duties: 'ينشئ المشروع، وينشئ حسابات إدارته كلها: مهندس المشروع '
          '(= مدير المشروع) ومدير الجودة ومشرف المشروع، ويحدد البنود '
          'والأنواع والمواد، ويشرف على مديري الجودة ومهندسي المشاريع.',
      creates: <String>[
        'مشروع جديد',
        'مهندس مشروع (= مدير المشروع)',
        'مدير جودة',
        'مشرف مشروع',
        'البنود والأنواع والمواد',
      ],
    ),

    OrgNode(
      roleKey: AppRoles.movementDeptManager,
      parentKey: AppRoles.generalManager,
      title: 'مدير إدارة الحركة',
      icon: Icons.local_shipping,
      color: AppColors.movementDeptManager,
      duties: 'يضيف المعدة بكودها ويربطها بالمشروع الذي تعمل فيه، '
          'فتنتقل بياناتها إلى إدارة الديزل وإدارة الورشة والصيانة. '
          'ينقل المعدات بين المشاريع ويتابع ملف كل معدة.',
      creates: <String>[
        'مدير المحروقات',
        'مراقب حركة',
        'مدير الورشة والصيانة',
        'معدة جديدة ونقلها إلى مشروع',
      ],
    ),

    OrgNode(
      roleKey: AppRoles.financialManager,
      parentKey: AppRoles.generalManager,
      title: 'المدير المالي',
      icon: Icons.account_balance,
      color: AppColors.financialManager,
      duties: 'الإشراف المالي العام، واعتماد الموازنات والصرف، '
          'ومتابعة الالتزامات المالية. ينشئ المحاسب الذي يدير '
          'سندات الصرف والقبض والصندوق والقيود اليومية، ويراجع '
          'أعماله ويعتمدها.',
      creates: <String>[
        'حساب المحاسب',
        'اعتماد الموازنات',
        'مراجعة الصندوق والقيود',
      ],
    ),

    // ========================================================
    // المستوى 2
    // ========================================================

    OrgNode(
      roleKey: AppRoles.qualityCostManager,
      parentKey: AppRoles.projectsDeptManager,
      title: 'مدير إدارة الجودة والتكلفة',
      icon: Icons.verified,
      color: AppColors.qualityCostManager,
      duties: 'يدخل الكمية التعاقدية لكل بند، ويحدد التكلفة التقديرية '
          'لكل بند، ويربط التكلفة الفعلية لكل بند، ويحدد مشرفًا لكل '
          'بند في المشروع.',
      creates: <String>[
        'الكمية التعاقدية للبند',
        'التكلفة التقديرية للبند',
        'ربط التكلفة الفعلية',
        'مشرف لكل بند',
      ],
    ),

    OrgNode(
      roleKey: AppRoles.projectEngineer,
      parentKey: AppRoles.projectsDeptManager,
      title: 'مهندس المشروع (= مدير المشروع)',
      icon: Icons.engineering,
      color: AppColors.projectEngineer,
      duties: 'هو مدير المشروع: يحدده مدير إدارة المشاريع عند بناء '
          'المشروع. يحدد كمية العقد للبنود والتفاصيل ويتابع تنفيذ مشروعه.',
      legacyRoles: <String>[
        AppRoles.projectManager,
        AppRoles.engineer,
      ],
    ),

    OrgNode(
      roleKey: AppRoles.fuelManager,
      parentKey: AppRoles.movementDeptManager,
      title: 'مدير المحروقات',
      icon: Icons.oil_barrel,
      color: AppColors.fuelManager,
      duties: 'إدارة الديزل بنافذتين: «استهلاك المعدات» (كل معدة '
          'بكودها ورقم مشروعها) و«استهلاك الوقود» (استهلاك كل '
          'مشروع برقمه وكميته في اليوم). كل صرف يُضاف إلى ملف المعدة.',
      creates: <String>[
        'مراقب حركة',
        'سجل صرف ديزل لمعدة',
      ],
    ),

    OrgNode(
      roleKey: AppRoles.workshopManager,
      parentKey: AppRoles.movementDeptManager,
      title: 'مدير الورشة والصيانة',
      icon: Icons.handyman,
      color: AppColors.workshopManager,
      duties: 'يكتب الأعطال وبدلات التواير وقطع الغيار والصيانة '
          'الدورية بتكلفتها وساعات التوقف، وكل سجل يُضاف إلى ملف '
          'المعدة. العطل المفتوح يجعل المعدة «معطلة» حتى الإصلاح، '
          'ويُحتسب الإهلاك وبدل الأعطال في الملف تلقائيًا.',
      creates: <String>[
        'سجل عطل',
        'بدل تواير',
        'قطع غيار',
      ],
    ),

    // ========================================================
    // المستوى 3 و 4 — الميدان والتنفيذ
    // ========================================================

    OrgNode(
      roleKey: AppRoles.projectSupervisor,
      parentKey: AppRoles.qualityCostManager,
      title: 'مشرف المشروع',
      icon: Icons.supervisor_account,
      color: AppColors.projectSupervisor,
      duties: 'ميداني: يدخل الكميات المنفذة لكل بند وتكاليف التنفيذ '
          'الفعلية من مواد وعمالة ومعدات.',
      legacyRoles: <String>[
        AppRoles.supervisor,
        AppRoles.driver,
      ],
    ),

    OrgNode(
      roleKey: AppRoles.movementMonitor,
      parentKey: AppRoles.fuelManager,
      title: 'مراقب الحركة',
      icon: Icons.local_gas_station,
      color: AppColors.movementMonitor,
      duties: 'يدخل استهلاك المعدة من المحروقات والكمية التي اشتغلت '
          'فيها المعدة. هذا الإدخال مستقل عن التكاليف التي يدخلها المشرف.',
      legacyRoles: <String>[
        'movement_engineer',
        'movement_representative',
      ],
    ),

    OrgNode(
      roleKey: AppRoles.projectAccountant,
      parentKey: AppRoles.financialManager,
      title: 'المحاسب',
      icon: Icons.receipt_long,
      color: AppColors.projectAccountant,
      duties: 'المسؤول عن كل الأعمال المحاسبية في الوحدة: سندات القبض '
          'وسندات الصرف، والصندوق (الرصيد الافتتاحي والحركة اليومية '
          'والرصيد الجاري)، والقيود اليومية، والتقارير المالية.',
      creates: <String>[
        'سند قبض',
        'سند صرف',
        'قيود يومية',
        'حركة الصندوق',
      ],
      legacyRoles: <String>[
        AppRoles.accountant,
        AppRoles.accountsManager,
      ],
    ),
  ];

  // ==========================================================
  // الوصول إلى الشجرة
  // ==========================================================

  /// منصب القمة (المشرف الرئيسي).
  static OrgNode get root => nodes.first;

  /// المناصب التي لا مدير لها (القمة).
  static List<OrgNode> roots() {
    return nodes
        .where((OrgNode node) => node.parentKey == null)
        .toList();
  }

  /// الأبناء المباشرون لمنصب ما.
  static List<OrgNode> childrenOf(String? roleKey) {
    return nodes
        .where((OrgNode node) => node.parentKey == roleKey)
        .toList();
  }

  /// هل للمنصب أبناء؟
  static bool hasChildren(String? roleKey) {
    return childrenOf(roleKey).isNotEmpty;
  }

  /// المنصب المطابق لدور ما (بعد التطبيع).
  static OrgNode? nodeOf(String? role) {
    final String value = AppRoles.normalize(role);

    for (final OrgNode node in nodes) {
      if (node.roleKey == value) return node;
    }

    return null;
  }

  /// مستوى المنصب (القمة = 0).
  static int levelOf(String roleKey) {
    int level = 0;

    OrgNode? current = _byKey(roleKey);

    while (current != null && current.parentKey != null) {
      level++;
      current = _byKey(current.parentKey!);
    }

    return level;
  }

  /// سلسلة المناصب من القمة حتى هذا المنصب (شاملة إياه).
  static List<OrgNode> chainOf(String? role) {
    final OrgNode? node = nodeOf(role);

    if (node == null) return const <OrgNode>[];

    final List<OrgNode> chain = <OrgNode>[node];

    OrgNode? current = node;

    while (current != null && current.parentKey != null) {
      final OrgNode? parent = _byKey(current.parentKey!);

      if (parent == null) break;

      chain.insert(0, parent);
      current = parent;
    }

    return chain;
  }

  /// كل المناصب الواقعة تحت هذا المنصب.
  static List<OrgNode> descendantsOf(String? roleKey) {
    final List<OrgNode> result = <OrgNode>[];

    void walk(String key) {
      for (final OrgNode child in childrenOf(key)) {
        result.add(child);
        walk(child.roleKey);
      }
    }

    walk(roleKey ?? '');

    return result;
  }

  /// عدد المناصب في الهيكل.
  static int get positionsCount => nodes.length;

  static OrgNode? _byKey(String roleKey) {
    for (final OrgNode node in nodes) {
      if (node.roleKey == roleKey) return node;
    }

    return null;
  }
}

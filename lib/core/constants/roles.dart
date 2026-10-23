// ============================================================
// أدوار النظام — الهيكل الإداري
// ============================================================
//
// الهيكل الإداري المعتمد:
//
//   المشرف الرئيسي (المدير)
//   ├── مدير إدارة المشاريع
//   │   ├── مدير إدارة الجودة والتكلفة (مدير الجودة)
//   │   │   └── مشرف المشروع
//   │   └── مهندس المشروع (= مدير المشروع)
//   ├── مدير إدارة الحركة
//   │   └── مدير المحروقات
//   │       └── مراقب الحركة
//   └── المدير المالي
//       └── إدارة الحسابات
//           └── محاسب المشروع
//
// ------------------------------------------------------------
// مسار العمل (من يخلق مَن، ومن يدخل ماذا)
// ------------------------------------------------------------
//
// 1) المشرف الرئيسي:
//    • يحدد المحافظة والمديرية.
//    • ينشئ حساب مدير إدارة المشاريع (الاسم + الهاتف
//      + اسم المستخدم + كلمة السر).
//
// 2) مدير إدارة المشاريع (يدخل باسم مستخدم وكلمة سر):
//    • ينشئ المشروع.
//    • ينشئ مهندس المشروع (= مدير المشروع) ويربطه بالمشروع.
//    • ينشئ مدير الجودة.
//    • يحدد البنود والأنواع والمعدات.
//
// 3) مدير الجودة:
//    • يدخل الكمية التعاقدية لكل بند.
//    • يحدد التكلفة التقديرية لكل بند.
//    • يربط التكلفة الفعلية لكل بند.
//    • يحدد مشرفًا لكل بند في المشروع.
//
// 4) مشرف المشروع (ميداني — يدخل باسم مستخدم وكلمة سر):
//    • يدخل الكميات المنفذة.
//    • يدخل التكاليف الفعلية للبنود.
//
// 5) مراقب الحركة (مستقل عن تكاليف المشرف):
//    • يدخل استهلاك المعدة من المحروقات.
//    • يدخل الكمية التي اشتغلت فيها المعدة.
//
// 6) محاسب المشروع:
//    • يتابع الحسابات والصندوق على مستوى المشروع.
//
// ------------------------------------------------------------
// الأدوار القديمة
// ------------------------------------------------------------
//
// الأدوار القديمة (admin / project_manager / engineer /
// supervisor / driver / accountant) تبقى مقبولة للقراءة حتى لا
// تتعطل الحسابات الموجودة، وتترجم تلقائيًا إلى الدور الجديد
// المكافئ عبر [AppRoles.normalize].
// ============================================================

class AppRoles {
  AppRoles._();

  // ==========================================================
  // أدوار الهيكل الإداري (المفاتيح الجديدة)
  // ==========================================================

  /// المشرف الرئيسي — قمة الهرم.
  static const String generalManager = 'general_manager';

  /// مدير إدارة المشاريع.
  static const String projectsDeptManager = 'projects_dept_manager';

  /// مدير إدارة الجودة والتكلفة (مدير الجودة).
  static const String qualityCostManager = 'quality_cost_manager';

  /// مهندس المشروع — هو مدير المشروع، يحدده مدير إدارة
  /// المشاريع عند بناء المشروع.
  static const String projectEngineer = 'project_engineer';

  /// مشرف المشروع — ميداني، يدخل الكميات المنفذة والتكاليف.
  static const String projectSupervisor = 'project_supervisor';

  /// مدير إدارة الحركة.
  static const String movementDeptManager = 'movement_dept_manager';

  /// مدير المحروقات.
  static const String fuelManager = 'fuel_manager';

  /// مراقب الحركة — استهلاك المعدات من المحروقات والكمية
  /// التي اشتغلت فيها المعدة. مستقل عن تكاليف المشرف.
  static const String movementMonitor = 'movement_monitor';

  /// المدير المالي.
  static const String financialManager = 'financial_manager';

  /// إدارة الحسابات.
  static const String accountsManager = 'accounts_manager';

  /// محاسب المشروع.
  static const String projectAccountant = 'project_accountant';

  // ==========================================================
  // أدوار قديمة (تبقى للقراءة والتوافق مع البيانات السابقة)
  // ==========================================================

  static const String admin = 'admin';

  /// مدير المشروع = مهندس المشروع في الهيكل الجديد.
  static const String projectManager = 'project_manager';

  static const String engineer = 'engineer';

  static const String supervisor = 'supervisor';

  /// السائق — دور قديم استُبدل بمشرف البند/المشروع.
  static const String driver = 'driver';

  static const String accountant = 'accountant';

  static const String user = 'user';

  // ==========================================================
  // ترجمة الأدوار القديمة إلى أدوار الهيكل الجديد
  // ==========================================================

  static const Map<String, String> _legacyAliases = <String, String>{
    admin: generalManager,
    projectManager: projectEngineer,
    engineer: projectEngineer,
    supervisor: projectSupervisor,
    driver: projectSupervisor,
    accountant: projectAccountant,
  };

  // ==========================================================
  // شجرة الهيكل: كل دور ومديره المباشر
  // (الترتيب هنا هو ترتيب العرض في المخطط)
  // ==========================================================

  static const Map<String, String> _parentOf = <String, String>{
    generalManager: '',
    projectsDeptManager: generalManager,
    qualityCostManager: projectsDeptManager,
    projectEngineer: projectsDeptManager,
    projectSupervisor: qualityCostManager,
    movementDeptManager: generalManager,
    fuelManager: movementDeptManager,
    movementMonitor: fuelManager,
    financialManager: generalManager,
    accountsManager: financialManager,
    projectAccountant: accountsManager,
  };

  // ==========================================================
  // مهام كل دور
  // ==========================================================

  static const Map<String, String> _duties = <String, String>{
    generalManager:
        'الإشراف العام على جميع الإدارات. يحدد المحافظة والمديرية، '
            'وينشئ حساب مدير إدارة المشاريع (الاسم والهاتف واسم المستخدم '
            'وكلمة السر)، ويعتمد الخطط والموازنات وتقارير الإنجاز.',
    projectsDeptManager:
        'ينشئ المشروع، وينشئ مهندس المشروع (= مدير المشروع) ومدير الجودة، '
            'ويحدد البنود والأنواع والمعدات، ويشرف على مديري الجودة '
            'ومهندسي المشاريع.',
    qualityCostManager:
        'يدخل الكمية التعاقدية لكل بند، ويحدد التكلفة التقديرية لكل بند، '
            'ويربط التكلفة الفعلية لكل بند، ويحدد مشرفًا لكل بند في المشروع.',
    projectEngineer:
        'هو مدير المشروع: يحدده مدير إدارة المشاريع عند بناء المشروع. '
            'يحدد كمية العقد للبنود والتفاصيل ويتابع تنفيذ مشروعه.',
    projectSupervisor:
        'ميداني: يدخل الكميات المنفذة لكل بند وتكاليف التنفيذ الفعلية '
            'من مواد وعمالة ومعدات.',
    movementDeptManager:
        'الإشراف على حركة المعدات والمحروقات، ومتابعة استهلاك المعدات '
            'واعتماد تقارير الحركة.',
    fuelManager:
        'إدارة توريد وصرف المحروقات، ومتابعة أرصدة الوقود واستهلاك '
            'كل معدة.',
    movementMonitor:
        'يدخل استهلاك المعدة من المحروقات والكمية التي اشتغلت فيها المعدة. '
            'هذا الإدخال مستقل عن التكاليف التي يدخلها المشرف.',
    financialManager:
        'الإشراف المالي العام، واعتماد الموازنات والصرف ومتابعة '
            'الالتزامات المالية للمشاريع.',
    accountsManager:
        'إدارة الحسابات: القيود اليومية وصندوق المشروع وتسوية '
            'حسابات المشاريع.',
    projectAccountant:
        'محاسب المشروع: يتابع حسابات مشروعه من صندوق ومصروفات '
            'ومستخلصات وتكاليف فعلية.',
  };

  // ==========================================================
  // عمليات على الأدوار
  // ==========================================================

  /// يطبّع الدور: يزيل الفراغات، ويحوّل الدور القديم إلى
  /// الدور الجديد المكافئ في الهيكل الإداري.
  static String normalize(String? role) {
    final String value = (role ?? '').trim().toLowerCase();

    if (value.isEmpty) return user;

    return _legacyAliases[value] ?? value;
  }

  /// هل هذا المفتاح دور قديم؟
  static bool isLegacy(String? role) {
    return _legacyAliases.containsKey(
      (role ?? '').trim().toLowerCase(),
    );
  }

  /// اسم الدور بالعربية (بعد التطبيع).
  static String label(String? role) {
    final String value = normalize(role);

    switch (value) {
      case generalManager:
        return 'المشرف الرئيسي (المدير)';
      case projectsDeptManager:
        return 'مدير إدارة المشاريع';
      case qualityCostManager:
        return 'مدير إدارة الجودة والتكلفة';
      case projectEngineer:
        return 'مهندس المشروع';
      case projectSupervisor:
        return 'مشرف المشروع';
      case movementDeptManager:
        return 'مدير إدارة الحركة';
      case fuelManager:
        return 'مدير المحروقات';
      case movementMonitor:
        return 'مراقب الحركة';
      case financialManager:
        return 'المدير المالي';
      case accountsManager:
        return 'إدارة الحسابات';
      case projectAccountant:
        return 'محاسب المشروع';

      // تسميات قديمة إن وصلت كما هي.
      case admin:
        return 'مسؤول النظام';
      case projectManager:
        return 'مهندس المشروع';
      case engineer:
        return 'مهندس';
      case supervisor:
        return 'مشرف';
      case driver:
        return 'سائق';
      case accountant:
        return 'محاسب';
      default:
        return 'مستخدم';
    }
  }

  /// مهام الدور بالعربية.
  static String duties(String? role) {
    return _duties[normalize(role)] ?? 'لا توجد مهام معرّفة لهذا الدور.';
  }

  /// الدور المدير المباشر (فارغ إن كان الدور في القمة).
  static String parentOf(String? role) {
    final String value = normalize(role);
    return _parentOf[value] ?? '';
  }

  /// الأدوار التابعة مباشرة لهذا الدور.
  static List<String> childrenOf(String? role) {
    final String value = normalize(role);

    return _parentOf.entries
        .where((entry) => entry.value == value)
        .map((entry) => entry.key)
        .toList();
  }

  /// مستوى الدور في الهرم (القمة = 0).
  static int levelOf(String? role) {
    final String value = normalize(role);

    if (!_parentOf.containsKey(value)) return 0;

    int level = 0;
    String current = value;

    while (_parentOf.containsKey(current)) {
      final String parent = _parentOf[current] ?? '';

      if (parent.isEmpty) break;

      level++;
      current = parent;
    }

    return level;
  }

  /// كل الأدوار الواقعة تحت هذا الدور في الشجرة (الأبناء والأحفاد).
  static List<String> descendantsOf(String? role) {
    final List<String> result = <String>[];

    void walk(String current) {
      for (final String child in childrenOf(current)) {
        result.add(child);
        walk(child);
      }
    }

    walk(normalize(role));

    return result;
  }

  /// سلسلة المديرين من القمة وحتى هذا الدور (شاملة الدور نفسه).
  static List<String> chainOf(String? role) {
    final List<String> chain = <String>[normalize(role)];

    String current = chain.first;

    while (_parentOf.containsKey(current)) {
      final String parent = _parentOf[current] ?? '';

      if (parent.isEmpty) break;

      chain.insert(0, parent);
      current = parent;
    }

    return chain;
  }

  /// هل [maybeSuperior] يشرف على [other]؟
  ///
  /// يشمل الدور نفسه وكل من تحته في الشجرة.
  static bool manages(String? maybeSuperior, String? other) {
    final String superior = normalize(maybeSuperior);
    final String target = normalize(other);

    if (superior == target) return true;

    return descendantsOf(superior).contains(target);
  }

  /// الأدوار التي يستطيع هذا الدور إنشاء حسابات لها
  /// (كل من هم تحته في الشجرة).
  static List<String> creatableBy(String? role) {
    return descendantsOf(role);
  }

  /// كل الأدوار التي يمكن إنشاء حسابات لها (عدا المشرف الرئيسي).
  static List<String> get creatable {
    return descendantsOf(generalManager);
  }

  /// كل أدوار الهيكل الإداري مرتبة من القمة إلى الأسفل.
  static List<String> get all {
    return _parentOf.keys.toList();
  }

  /// هل الدور مرتبط بمشروع واحد عبر `projectId`؟
  ///
  /// مهندس المشروع (= مدير المشروع) يرتبط بمشروع واحد فقط.
  static bool bindsSingleProject(String? role) {
    final String value = normalize(role);

    return value == projectEngineer;
  }

  /// هل الدور مرتبط بمشاريع متعددة عبر `projectIds`؟
  static bool bindsMultipleProjects(String? role) {
    final String value = normalize(role);

    return value == projectSupervisor || value == movementMonitor;
  }

  /// هل يحتاج هذا الدور إلى ربط بمشروع قبل أن يتمكن من الدخول؟
  static bool requiresProjectBinding(String? role) {
    final String value = normalize(role);

    return bindsSingleProject(value) || bindsMultipleProjects(value);
  }

  /// هل الدور دورًا ميدانيًا؟
  static bool isFieldRole(String? role) {
    final String value = normalize(role);

    return value == projectSupervisor || value == movementMonitor;
  }
}

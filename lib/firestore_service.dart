import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Collection References
  CollectionReference mahfthRef() => _db.collection('mahfth');
  CollectionReference ereaRef() => _db.collection('erea');
  CollectionReference gahaRef() => _db.collection('gaha');
  CollectionReference albndRef() => _db.collection('albnd');
  CollectionReference almodeRef() => _db.collection('almode');
  CollectionReference projectRef() => _db.collection('project');
  CollectionReference tableCamaRef() => _db.collection('table_cama');
  CollectionReference anjazeCamaRef() => _db.collection('anjaze_cama');

  // ===== Collections المستخدمة في النظام الحديث =====
  CollectionReference projectsRef() => _db.collection('projects');
  CollectionReference usersRef() => _db.collection('users');
  CollectionReference itemsRef() => _db.collection('items');
  CollectionReference itemDetailsRef() => _db.collection('item_details');

  /// إسناد البنود إلى مشرفي البنود ( بدل السائق ).
  CollectionReference itemSupervisorsRef() =>
      _db.collection('item_supervisors');

  /// السجل القديم لإسناد البنود إلى السائقين.
  CollectionReference itemDriversRef() => _db.collection('item_drivers');

  // ===== CRUD for Mahfth =====
  Future<void> addMahfth(Map<String, dynamic> data) => mahfthRef().add(data);

  // ===== CRUD for Erea =====
  Future<void> addErea(Map<String, dynamic> data) => ereaRef().add(data);

  // ===== CRUD for Gaha =====
  Future<void> addGaha(Map<String, dynamic> data) => gahaRef().add(data);

  // ===== CRUD for Albnd =====
  Future<void> addAlbnd(Map<String, dynamic> data) => albndRef().add(data);

  // ===== CRUD for Almode =====
  Future<void> addAlmode(Map<String, dynamic> data) => almodeRef().add(data);

  // ===== CRUD for Project =====
  Future<void> addProject(Map<String, dynamic> data) => projectRef().add(data);

  // ===== CRUD for Table_cama =====
  Future<void> addTableCama(Map<String, dynamic> data) => tableCamaRef().add(data);

  // ===== CRUD for Anjaze_cama =====
  Future<void> addAnjazeCama(Map<String, dynamic> data) => anjazeCamaRef().add(data);
}

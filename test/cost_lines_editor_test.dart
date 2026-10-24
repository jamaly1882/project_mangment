import 'package:flutter_test/flutter_test.dart';

import '../lib/core/utils/cost_lines.dart';
import '../lib/core/widgets/cost_lines_editor.dart';

void main() {
  _readOnlyTests();

  test('material units follow the material type', () {
    expect(MaterialUnits.forName('الإسمنت'), ['كيس']);
    expect(MaterialUnits.forName('الألواح الخشبية'), ['قطعة']);
    expect(MaterialUnits.forName('الزوايا الحديدية'), ['متر', 'قطعة']);
    expect(MaterialUnits.forName('الماء'), ['لتر', 'م³']);
    expect(MaterialUnits.forName('الحديد'), ['طن', 'كجم']);
  });

  for (final kind in [CostLineKind.material, CostLineKind.fuel]) {
    test('$kind recalculates after quantity and price changes', () {
      final editor = CostLinesEditorController(CostLineSchema.of(kind));
      addTearDown(editor.dispose);
      editor.addRow();
      editor.attachRows();
      final price = kind == CostLineKind.material ? 'unitPrice' : 'pricePerLiter';
      editor.setText(0, price, '10');
      editor.setText(0, 'quantity', '3');
      expect(editor.total, 30);
      expect(editor.isManual(0), false);
      editor.setText(0, 'quantity', '5');
      expect(editor.total, 50);
      expect(editor.costControllerOf(0).text, '50');
      editor.setText(0, price, '20');
      expect(editor.total, 100);
      editor.costControllerOf(0).text = '75';
      expect(editor.total, 75);
      editor.toggleManual(0);
      expect(editor.total, 100);
      expect(editor.isManual(0), false);
    });
  }

  test('selecting material fills its unit', () {
    final editor = CostLinesEditorController(CostLineSchema.of(CostLineKind.material));
    addTearDown(editor.dispose);
    editor.addRow();
    editor.pickOption(0, id: 'cement', nameKey: 'materialName', name: 'الإسمنت');
    expect(editor.textOf(0, 'unit'), 'كيس');
  });
}

// ============================================================
// أسعار الوحدات في صفحة المشرف: منقولة من الجودة وتُقرأ ولا تُعدَّل
// ============================================================
void _readOnlyTests() {
  testWidgets('unit prices stay visible but locked for the supervisor',
      (tester) async {
    final schema = CostLineSchema.of(CostLineKind.material);
    final editor = CostLinesEditorController(schema);
    addTearDown(editor.dispose);

    editor.addRow({
      'materialName': 'الإسمنت',
      'unit': 'كيس',
      'unitPrice': '4000',
      'quantity': '0',
    });
    editor.attachRows();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CostLinesEditor(
              schema: schema,
              controller: editor,
              readOnlyKeys: const <String>{'unitPrice'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // حقل السعر مقفل (يُقرأ فقط)، وحقل الكمية يبقى قابلًا للإدخال.
    final priceField = tester.widget<TextField>(
      find.descendant(
        of: find.ancestor(
          of: find.text('سعر الوحدة'),
          matching: find.byType(TextFormField),
        ),
        matching: find.byType(TextField),
      ),
    );
    expect(priceField.readOnly, isTrue);
    expect(priceField.controller?.text, contains('4000'));

    final quantityField = tester.widget<TextField>(
      find.descendant(
        of: find.ancestor(
          of: find.text('الكمية / العدد'),
          matching: find.byType(TextFormField),
        ),
        matching: find.byType(TextField),
      ),
    );
    expect(quantityField.readOnly, isFalse);

    // القيمة تُحفظ كما هي بعد تعديل الكمية.
    editor.setText(0, 'quantity', '2');
    expect(editor.lines.first['unitPrice'], 4000);
    expect(editor.lines.first['quantity'], 2);
  });
}

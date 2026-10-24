import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azal/core/constants/unit_analysis_prices.dart';
import 'package:azal/core/utils/cost_lines.dart';
import 'package:azal/core/widgets/cost_lines_editor.dart';
import 'package:azal/core/widgets/cost_table_editor.dart';

// ============================================================
// جداول الاختيار: ✓ يضيف السطر، وإلغاؤه يصفّر الكمية ولا يحذف
// ============================================================

void main() {
  group('CostLinesEditorController — تعليم أسطر التحليل', () {
    test('التعليم يضيف السطر بالسعر وكمية ١', () {
      final schema = CostLineSchema.of(CostLineKind.material);
      final editor = CostLinesEditorController(schema);
      addTearDown(editor.dispose);

      expect(editor.count, 0);

      editor.selectLabel('أسمنت', 4000);

      expect(editor.count, 1);
      expect(editor.hasQuantity(0), isTrue);
      expect(editor.textOf(0, 'materialName'), 'أسمنت');
      expect(editor.textOf(0, 'unitPrice'), '4000');
      expect(editor.textOf(0, 'quantity'), '1');
      expect(editor.total, 4000);
    });

    test('إلغاء التعليم يصفّر الكمية ويُبقي الاسم والسعر', () {
      final schema = CostLineSchema.of(CostLineKind.material);
      final editor = CostLinesEditorController(schema);
      addTearDown(editor.dispose);

      editor.selectLabel('أسمنت', 4000);
      editor.setText(0, 'quantity', '5');
      expect(editor.total, 20000);

      editor.deselectLabel('أسمنت');

      expect(editor.count, 1, reason: 'السطر لا يُحذف');
      expect(editor.textOf(0, 'materialName'), 'أسمنت');
      expect(editor.textOf(0, 'unitPrice'), '4000');
      expect(editor.textOf(0, 'quantity'), '0');
      expect(editor.hasQuantity(0), isFalse);
      expect(editor.total, 0);
    });

    test('التعليم مرتين لا يُكرر السطر', () {
      final schema = CostLineSchema.of(CostLineKind.material);
      final editor = CostLinesEditorController(schema);
      addTearDown(editor.dispose);

      editor.selectLabel('أسمنت', 4000);
      editor.selectLabel('أسمنت', 4000);

      expect(editor.count, 1);
    });

    test('العمالة: العدد والمدة يحددان المصروف', () {
      final schema = CostLineSchema.of(CostLineKind.labor);
      final editor = CostLinesEditorController(schema);
      addTearDown(editor.dispose);

      editor.selectLabel('عمال', 8500);

      expect(editor.textOf(0, 'count'), '1');
      expect(editor.textOf(0, 'duration'), '1');
      expect(editor.total, 8500);

      editor.setText(0, 'duration', '3');
      expect(editor.total, 25500);

      editor.setText(0, 'count', '2');
      expect(editor.total, 51000);
    });

    test('المعدات والمحروقات تُبنى بالسعر والوحدات الصحيحة', () {
      final equipment = CostLinesEditorController(
        CostLineSchema.of(CostLineKind.equipment),
      );
      addTearDown(equipment.dispose);
      equipment.selectLabel('حرارة D155', 23100);
      expect(equipment.textOf(0, 'count'), '1');
      expect(equipment.textOf(0, 'quantity'), '1');
      expect(equipment.total, 23100);

      final fuel = CostLinesEditorController(
        CostLineSchema.of(CostLineKind.fuel),
      );
      addTearDown(fuel.dispose);
      fuel.selectLabel('ديزل', 475);
      expect(fuel.textOf(0, 'pricePerLiter'), '475');
      fuel.setText(0, 'quantity', '100');
      expect(fuel.total, 47500);
    });

    test('المطابقة تتجاهل الهمزات والتاء المربوطة', () {
      expect(sameLineName('الإسمنت', 'أسمنت'), isTrue);
      expect(sameLineName('عمالة', 'عمال'), isTrue);
      expect(sameLineName('حديد', 'خشب'), isFalse);
      // لا نخلط «أسمنت» بـ«خالطة أسمنتية».
      expect(sameLineName('أسمنت', 'خالطة أسمنتية'), isFalse);
    });
  });

  group('CostTableEditor — الواجهة', () {
    testWidgets('التعليم من الجدول يضيف السطر ويظهر اتجاه التكلفة',
        (tester) async {
      final schema = CostLineSchema.of(CostLineKind.material);
      final controller = CostLinesEditorController(schema);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CostTableEditor(
                schema: schema,
                controller: controller,
                priceEditable: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // الجدول يعرض أسطر التحليل كلها.
      expect(find.byType(Checkbox), findsWidgets);
      expect(find.text('أسمنت'), findsOneWidget);

      // التعليم يضيف السطر بالسعر وكمية ١.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect(controller.count, 1);
      expect(controller.total, unitAnalysisMaterials.first.amount);

      // إلغاء التعليم يصفّر ولا يحذف.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect(controller.count, 1);
      expect(controller.total, 0);
    });


    testWidgets('البحث يُبقي الأسطر المطابقة فقط', (tester) async {
      final schema = CostLineSchema.of(CostLineKind.material);
      final controller = CostLinesEditorController(schema);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CostTableEditor(
                schema: schema,
                controller: controller,
                priceEditable: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // عدّاد أسطر القسم ظاهر في العنوان.
      expect(find.textContaining('42 سطرًا'), findsOneWidget);
      expect(find.text('أسمنت'), findsOneWidget);

      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            (widget.decoration?.hintText ?? '').contains('ابحث'),
      );

      await tester.enterText(search, 'حديد');
      await tester.pumpAndSettle();

      expect(find.text('أسمنت'), findsNothing);
      expect(find.text('حديد G40'), findsOneWidget);
    });

    testWidgets('زر الإضافة على السطر يعلّمه ويُظهر حقول الكمية',
        (tester) async {
      final schema = CostLineSchema.of(CostLineKind.material);
      final controller = CostLinesEditorController(schema);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CostTableEditor(
                schema: schema,
                controller: controller,
                priceEditable: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pumpAndSettle();

      expect(controller.count, 1);
      expect(controller.hasQuantity(0), isTrue);
    });

    testWidgets('وضع مدير المشروع: ✓ تضيف بلا كميات وإلغاؤها تحذف السطر',
        (tester) async {
      final schema = CostLineSchema.of(CostLineKind.material);
      final controller = CostLinesEditorController(schema);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CostTableEditor(
                schema: schema,
                controller: controller,
                priceEditable: true,
                quantitySelection: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect(controller.count, 1);
      expect(controller.hasQuantity(0), isFalse, reason: 'بلا كميات');
      expect(controller.textOf(0, 'unitPrice'), '4000');

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect(controller.count, 0, reason: 'إلغاء ✓ يحذف السطر');
    });
    testWidgets('السعر مقفل للمشرف ولا يظهر كحقل إدخال', (tester) async {
      final schema = CostLineSchema.of(CostLineKind.fuel);
      final controller = CostLinesEditorController(schema);
      addTearDown(controller.dispose);

      controller.selectLabel('ديزل', 475);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CostTableEditor(
                schema: schema,
                controller: controller,
                priceEditable: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // السعر يظهر كنص (ديزل وبترول لهما السعر نفسه 475).
      expect(find.text('475'), findsWidgets);

      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .where((field) => field.controller == controller.numberController(0, 'quantity'));

      expect(fields, isNotEmpty);
    });
  });
}

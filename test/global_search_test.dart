import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/services/global_search.dart';

void main() {
  test('folds Arabic letters, digits, ZWNJ', () {
    expect(foldFa('علي كريمي'), foldFa('علی کریمی'));
    expect(foldFa('۱۲۳٤'), '1234');
    expect(foldFa('می‌خواهم'), 'می خواهم');
  });
  test('matches cheque number, drawer and grouped', () {
    final items = [
      SearchItem(kind: SearchKind.cheque, title: 'a', fields: ['123456', 'رضا كاظمي', 'بانک ملت']),
      SearchItem(kind: SearchKind.asset, title: 'طلا', fields: ['طلای ۱۸ عیار']),
    ];
    expect(searchAll(items, '۱۲۳ ۴۵۶').keys, [SearchKind.cheque]);
    expect(searchAll(items, 'کاظمی رضا').keys, [SearchKind.cheque]);
    expect(searchAll(items, 'طلا').keys, [SearchKind.asset]);
    expect(searchAll(items, 'xyz'), isEmpty);
    expect(searchAll(items, '  '), isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/notification_inbox_store.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationInboxStore.unreadCount.value = 0;
  });

  test('add increases unread and markAllRead clears badge', () async {
    await NotificationInboxStore.add(
      title: 'برداشت ثبت شد',
      body: '۱۰۰٬۰۰۰ تومان',
      kind: NotificationKind.withdrawals,
    );
    await NotificationInboxStore.add(
      title: 'هشدار قیمت',
      body: 'تتر از آستانه گذشت',
      kind: NotificationKind.prices,
    );

    expect(NotificationInboxStore.unreadCount.value, 2);
    final items = await NotificationInboxStore.load();
    expect(items, hasLength(2));
    expect(items.first.kind, NotificationKind.prices);

    await NotificationInboxStore.markAllRead();
    expect(NotificationInboxStore.unreadCount.value, 0);
    final read = await NotificationInboxStore.load();
    expect(read.every((e) => e.read), isTrue);
  });

  test('clear wipes inbox', () async {
    await NotificationInboxStore.add(
      title: 't',
      body: 'b',
      kind: NotificationKind.general,
    );
    await NotificationInboxStore.clear();
    expect(await NotificationInboxStore.load(), isEmpty);
    expect(NotificationInboxStore.unreadCount.value, 0);
  });
}

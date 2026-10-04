import 'package:flutter_test/flutter_test.dart';
import 'package:invest/state/app_state.dart';

void main() {
  test('UI notifications are held during portfolio publish window', () {
    final state = AppState();
    var ticks = 0;
    state.addListener(() => ticks++);

    state.notifyListeners();
    expect(ticks, 1);

    state.debugHoldUiNotifications = true;
    state.notifyListeners();
    state.notifyListeners();
    expect(ticks, 1);

    state.debugHoldUiNotifications = false;
    state.notifyListeners();
    expect(ticks, 2);
  });
}

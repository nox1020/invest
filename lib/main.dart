import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invest/app.dart';
import 'package:invest/domain/services/background_price_worker.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/widgets/user_error.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = userErrorPanel;
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    return true;
  };
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  // Paint the loading screen before plugins and the Vinor handshake.
  // Those calls used to run first, so a thrown notification init or a
  // stalled platform channel left the process on the white splash and
  // the installed app never opened.
  final state = AppState();
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const InvestApp(),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  try {
    await NotificationService.instance.init();
  } catch (_) {}
  try {
    await BackgroundPriceWorker.initialize();
  } catch (_) {}
  try {
    await state.init();
  } catch (_) {}
}

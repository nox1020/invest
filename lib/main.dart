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
  await NotificationService.instance.init();
  await BackgroundPriceWorker.initialize();
  final state = AppState();
  await state.init();
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const InvestApp(),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invest/app.dart';
import 'package:invest/domain/services/background_price_worker.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:invest/state/app_state.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/models/alarm.dart';
import 'package:nothing_clock/providers/clock_provider.dart';
import 'package:nothing_clock/providers/page_provider.dart';
import 'package:nothing_clock/providers/stopwatch_provider.dart';
import 'package:nothing_clock/providers/theme_provider.dart';
import 'package:nothing_clock/providers/timer_provider.dart';
import 'package:nothing_clock/providers/worldclocks_provider.dart';
import 'package:nothing_clock/screens/router.dart' as RouterPage;
import 'package:nothing_clock/services/alarms_service.dart';
import 'package:nothing_clock/services/native_alarms.dart';
import 'package:nothing_clock/services/sync_service.dart';
import 'package:nothing_clock/services/notification_service.dart';
import 'package:nothing_clock/services/time_country.dart';
import 'package:nothing_clock/theme/theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;

Future<void> _safe(String name, Future<void> Function() action) async {
  try {
    await action().timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('Init "$name" failed: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _safe('displaymode', () async {
    await FlutterDisplayMode.setHighRefreshRate();
  });

  if (!Platform.isAndroid) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );
  }

  try {
    tz.initializeTimeZones();
  } catch (e) {
    debugPrint('Init "timezones" failed: $e');
  }

  await _safe('country', () async {
    await TimeCountry.init();
  });
  await _safe('hive', () async {
    await Hive.initFlutter();
    Hive.registerAdapter(AlarmAdapter());
  });
  await _safe('locale', () async {
    await AppLocale.init();
  });
  await _safe('dates', () async {
    await initializeDateFormatting();
  });
  await _safe('notifications', () async {
    await NotificationService.initialize();
  });
  await _safe('migrate', () async {
    await AlarmsService.migrateToNative();
  });

  final themeProvider = ThemeProvider();
  await _safe('theme', () async {
    await themeProvider.loadThemeFromPreferences();
  });

  runApp(
    ChangeNotifierProvider(
      create: (context) => themeProvider,
      child: const NothingClock(),
    ),
  );

  unawaited(NativeAlarms.init(NotificationService.handleRing));
  unawaited(SyncService.instance.init());
  unawaited(Permission.notification.request());
}

class NothingClock extends StatelessWidget {
  const NothingClock({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ClockProvider()),
        ChangeNotifierProvider(create: (context) => LocaleProvider()),
        ChangeNotifierProvider(create: (context) => PageProvider()),
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => TimerProvider()),
        ChangeNotifierProvider(create: (context) => StopwatchProvider()),
        ChangeNotifierProvider(
            create: (context) => WorldClocksProvider(context)),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, value, child) {
          final localeProvider = context.watch<LocaleProvider>();
          return MaterialApp(
            locale: localeProvider.locale,
            supportedLocales: const [Locale('en'), Locale('es')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            navigatorKey: NotificationService.navigatorKey,
            title: 'NothingClock',
            debugShowCheckedModeBanner: false,
            darkTheme: AppTheme.dark,
            theme: AppTheme.light,
            themeMode: value.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: KeyedSubtree(
              key: ValueKey(localeProvider.locale.languageCode),
              child: const RouterPage.Router(),
            ),
          );
        },
      ),
    );
  }
}

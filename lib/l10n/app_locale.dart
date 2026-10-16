import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Map<String, Map<String, String>> _translations = {
  'es': {
    "CLOCK": "RELOJ",
    "ALARMS": "ALARMAS",
    "TIMER": "TEMPORIZADOR",
    "STOPWATCH": "CRONÓMETRO",
    "SETTINGS": "AJUSTES",
    "Github Repository": "Repositorio de GitHub",
    "View the source code on Github, contribute, or report issues.":
        "Mira el código fuente en GitHub, colabora o reporta problemas.",
    "Language": "Idioma",
    "Rings in": "Sonará en",
    "SLEEP": "SUEÑO",
    "BEDTIME": "ACOSTARME",
    "WAKE UP": "DESPERTAR",
    "ACTIVE": "ACTIVA",
    "REMINDER": "RECORDATORIO",
    "OFF": "NO",
    "HOME ASSISTANT": "HOME ASSISTANT",
    "AT BEDTIME": "AL IR A DORMIR",
    "WHEN THE ALARM RINGS": "AL SONAR LA ALARMA",
    "WHEN I WAKE UP": "AL DESPERTARME",
    "None": "Ninguna",
    "Search": "Buscar",
    "Sent": "Enviado",
    "Connect Nextcloud first": "Conecta Nextcloud primero",
    "Add haUrl and haToken to .ecosystem/config.json in your Nextcloud": "Añade haUrl y haToken en .ecosystem/config.json de tu Nextcloud",
    "Nextcloud sync": "Sincronizar con Nextcloud",
    "Nextcloud server": "Servidor de Nextcloud",
    "Not connected": "Sin conectar",
    "Connect": "CONECTAR",
    "Authorize NothingClock in the browser...": "Autoriza NothingClock en el navegador…",
    "Sync now": "Sincronizar ahora",
    "Disconnect": "Desconectar",
    "Synced": "Sincronizado",
    "Sync error": "Error de sincronización",
    "Unknown location": "Ubicación desconocida",
    "TIMERS": "TEMPORIZADORES",
    "NEW TIMER": "NUEVO TEMPORIZADOR",
    "EDIT TIMER": "EDITAR TEMPORIZADOR",
    "TIMER NAME": "NOMBRE DEL TEMPORIZADOR",
    "SAVE TIMER": "GUARDAR TEMPORIZADOR",
    "DELETE TIMER": "ELIMINAR TEMPORIZADOR",
    "Timer": "Temporizador",
    "Time remaining": "Tiempo restante",
    "Time's up": "¡Tiempo!",
    "SNOOZE 1 MIN": "POSPONER 1 MIN",
    "SAVE": "GUARDAR",
    "DELETE": "ELIMINAR",
    "Delete this clock?": "¿Eliminar este reloj?",
    "Show seconds": "Mostrar segundos",
    "World clocks": "Relojes mundiales",
    "System default": "Predeterminado del sistema",
    "Theme": "Tema",
    "Dark": "Oscuro",
    "Light": "Claro",
    "Dark Mode": "Modo oscuro",
    "Light Mode": "Modo claro",
    "Alarm Permission Required": "Permiso de alarmas necesario",
    "To schedule alarms, please enable the SCHEDULE_EXACT_ALARM permission in your system settings.":
        "Para programar alarmas, activa el permiso SCHEDULE_EXACT_ALARM en los ajustes del sistema.",
    "Go to settings": "Ir a ajustes",
    "Alarm": "Alarma",
    "Alarms": "Alarmas",
    "No location available": "Ubicación no disponible",
    "SLEEP TIME": "HORA DE DORMIR",
    "OTHER": "OTRAS",
    "ADD NEW ALARM": "NUEVA ALARMA",
    "EDIT ALARM": "EDITAR ALARMA",
    "ALARM NAME": "NOMBRE DE LA ALARMA",
    "SAVE ALARM": "GUARDAR ALARMA",
    "DELETE ALARM": "ELIMINAR ALARMA",
    "Not scheduled": "Sin programar",
    "Once": "Una vez",
    "ONCE": "UNA VEZ",
    "MON": "LUN",
    "TUE": "MAR",
    "WED": "MIÉ",
    "THU": "JUE",
    "FRI": "VIE",
    "SAT": "SÁB",
    "SUN": "DOM",
    "TURN OFF ALARM": "DESACTIVAR ALARMA",
    "Next time only, or always?": "¿Solo la próxima vez o siempre?",
    "CANCEL": "CANCELAR",
    "NEXT": "PRÓXIMA",
    "ALWAYS": "SIEMPRE",
    "ALARM": "ALARMA",
    "SNOOZE 10 MIN": "POSPONER 10 MIN",
    "STOP": "APAGAR",
    "Enter a city name": "Escribe una ciudad",
    "Search for a city": "Busca una ciudad",
    "Failed to load cities. Please try again.":
        "No se pudieron cargar las ciudades. Inténtalo de nuevo.",
    "Network error. Please check your connection.":
        "Error de red. Revisa tu conexión.",
    "is already added to your world clocks": "ya está en tus relojes mundiales",
  },
};

const Map<String, String> _esInitials = {
  "MON": "L",
  "TUE": "M",
  "WED": "X",
  "THU": "J",
  "FRI": "V",
  "SAT": "S",
  "SUN": "D",
};

class AppLocale {
  static const List<String> supported = ['en', 'es'];
  static String _choice = 'system';

  static String get choice => _choice;

  static String get code {
    if (_choice != 'system') return _choice;
    final sys = PlatformDispatcher.instance.locale.languageCode;
    return supported.contains(sys) ? sys : 'en';
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    _choice = prefs.getString('app_language') ?? 'system';
  }

  static Future<void> setChoice(String value) async {
    _choice = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', value);
  }
}

String tr(String key) {
  final code = AppLocale.code;
  if (code == 'en') return key;
  return _translations[code]?[key] ?? key;
}

String trInitial(String dayKey) {
  if (AppLocale.code == 'es') return _esInitials[dayKey] ?? dayKey.substring(0, 1);
  return dayKey.substring(0, 1);
}

class LocaleProvider extends ChangeNotifier with WidgetsBindingObserver {
  LocaleProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  String get choice => AppLocale.choice;
  Locale get locale => Locale(AppLocale.code);

  Future<void> setChoice(String value) async {
    await AppLocale.setChoice(value);
    notifyListeners();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (AppLocale.choice == 'system') notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

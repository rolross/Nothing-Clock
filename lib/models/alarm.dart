import 'package:hive/hive.dart';

part 'alarm.g.dart';

@HiveType(typeId: 0)
class Alarm extends HiveObject {
  @HiveField(0)
  DateTime time;

  @HiveField(1)
  Map<String, bool> days;

  @HiveField(2, defaultValue: false)
  bool isEnabled;

  @HiveField(3)
  int id;

  int uiRev = 0;

  @HiveField(4, defaultValue: '')
  String label;

  @HiveField(5, defaultValue: false)
  bool isSleep;

  Alarm({int? id, required this.time, required this.days, this.isEnabled = false, this.label = '', this.isSleep = false}) : id = id ?? DateTime.now().millisecondsSinceEpoch % (1 << 31);
}
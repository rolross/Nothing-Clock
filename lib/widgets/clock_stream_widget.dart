import 'package:flutter/material.dart';
import 'package:nothing_clock/providers/clock_provider.dart';
import 'package:nothing_clock/providers/worldclocks_provider.dart';
import 'package:provider/provider.dart';

class ClockStreamWidget extends StatefulWidget {
  const ClockStreamWidget({super.key});

  @override
  State<ClockStreamWidget> createState() => _ClockStreamWidgetState();
}

class _ClockStreamWidgetState extends State<ClockStreamWidget> {
  static const double _sideWidth = 46;

  late final Stream<DateTime> _secondsStream =
      Stream<DateTime>.periodic(const Duration(seconds: 1), (_) => DateTime.now());

  String _two(int v) => v.toString().padLeft(2, "0");

  @override
  Widget build(BuildContext context) {
    final clockProvider = Provider.of<ClockProvider>(context);
    final showSeconds = context.watch<WorldClocksProvider>().showSeconds;

    return StreamBuilder<DateTime>(
      stream: showSeconds ? _secondsStream : clockProvider.clockStream,
      initialData: DateTime.now(),
      builder: (context, snapshot) {
        final time = snapshot.data ?? DateTime.now();
        final hm = "${_two(time.hour)}:${_two(time.minute)}";

        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(width: _sideWidth),
              Text(
                hm,
                style: const TextStyle(fontSize: 60, fontFamily: "NDot"),
              ),
              SizedBox(
                width: _sideWidth,
                child: showSeconds
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 10),
                        child: Text(
                          _two(time.second),
                          style: const TextStyle(
                            fontSize: 24,
                            fontFamily: "NDot",
                            color: Color(0xFFBDBDBD),
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

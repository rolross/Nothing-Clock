import 'package:flutter/material.dart';
import 'package:nothing_clock/providers/timer_provider.dart';
import 'package:nothing_clock/screens/timer_list_view.dart';
import 'package:nothing_clock/screens/timer_run_view.dart';
import 'package:provider/provider.dart';

class TimerScreen extends StatelessWidget {
  const TimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TimerProvider>(
      builder: (context, p, _) {
        if (p.viewing && p.activeTimer != null) return const TimerRunView();
        return const TimerListView();
      },
    );
  }
}

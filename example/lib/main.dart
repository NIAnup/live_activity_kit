import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_activity_kit/live_activity_kit.dart';

import 'demos/delivery_tracking.dart';
import 'demos/demo.dart';
import 'demos/meal_reminder.dart';
import 'demos/meeting_countdown.dart';
import 'demos/running_tracker.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'live_activity_kit',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xFF0B0B0F),
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final List<LiveActivityDemo> _demos = [
    MealReminderDemo(),
    RunningTrackerDemo(),
    DeliveryTrackingDemo(onPushToken: (token) => _log('push token ${_short(token)}')),
    MeetingCountdownDemo(),
  ];

  final Set<String> _running = {};
  final List<String> _events = [];
  final List<StreamSubscription<void>> _subscriptions = [];

  LiveActivitySupport? _support;

  @override
  void initState() {
    super.initState();
    _checkSupport();

    // Lifecycle and deep links are streams, so the app stays in sync even when
    // the user dismisses an activity from the Lock Screen.
    _subscriptions.addAll([
      LiveActivity.states.listen((change) {
        _log('${change.id} → ${change.state.name}');
        if (change.state != LiveActivityState.active) {
          setState(() => _running.remove(change.id));
        }
      }),
      LiveActivity.deepLinks.listen((url) => _log('tapped $url')),
    ]);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  Future<void> _checkSupport() async {
    final support = await LiveActivity.support(refresh: true);
    if (mounted) setState(() => _support = support);
  }

  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _events.insert(0, message);
      if (_events.length > 12) _events.removeLast();
    });
  }

  static String _short(String token) =>
      token.length <= 12 ? token : '${token.substring(0, 12)}…';

  Future<void> _run(
    LiveActivityDemo demo,
    Future<void> Function() action,
    String label,
  ) async {
    try {
      await action();
      _log('$label ${demo.id}');
    } on LiveActivityException catch (e) {
      _log('${e.code}: ${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade900),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('live_activity_kit'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SupportBanner(support: _support, onRefresh: _checkSupport),
          const SizedBox(height: 16),
          for (final demo in _demos) ...[
            _DemoCard(
              demo: demo,
              isRunning: _running.contains(demo.id),
              onStart: () async {
                await _run(demo, demo.start, 'started');
                setState(() => _running.add(demo.id));
              },
              onUpdate: () => _run(demo, demo.update, 'updated'),
              onEnd: () async {
                await _run(demo, demo.end, 'ended');
                demo.reset();
                setState(() => _running.remove(demo.id));
              },
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          _EventLog(events: _events),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              await LiveActivity.endAll(immediate: true);
              for (final demo in _demos) {
                demo.reset();
              }
              setState(_running.clear);
              _log('ended everything');
            },
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('End all activities'),
          ),
        ],
      ),
    );
  }
}

class _SupportBanner extends StatelessWidget {
  const _SupportBanner({required this.support, required this.onRefresh});

  final LiveActivitySupport? support;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final support = this.support;
    if (support == null) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    final (color, icon, message) = switch (support) {
      _ when !support.isSupported => (
          Colors.red,
          Icons.error_outline,
          'Live Activities need iOS 16.1+ — this device reports ${support.systemVersion}.',
        ),
      _ when !support.areActivitiesEnabled => (
          Colors.orange,
          Icons.warning_amber_outlined,
          'Live Activities are switched off for this app in Settings → live_activity_kit.',
        ),
      _ => (
          Colors.green,
          Icons.check_circle_outline,
          support.supportsDynamicIsland
              ? 'Ready — this device has a Dynamic Island.'
              : 'Ready — Lock Screen only (no Dynamic Island on this device).',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Re-check',
          ),
        ],
      ),
    );
  }
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({
    required this.demo,
    required this.isRunning,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final LiveActivityDemo demo;
  final bool isRunning;
  final VoidCallback onStart;
  final VoidCallback onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF15151C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRunning ? demo.accent : Colors.white10,
          width: isRunning ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(demo.icon, color: demo.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  demo.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              if (isRunning)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: demo.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('LIVE',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: demo.accent)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(demo.description,
              style: const TextStyle(fontSize: 12, color: Colors.white54)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: isRunning ? null : onStart,
                  style: FilledButton.styleFrom(backgroundColor: demo.accent),
                  child: const Text('Start'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: isRunning ? onUpdate : null,
                  child: const Text('Update'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: isRunning ? onEnd : null,
                  child: const Text('End'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventLog extends StatelessWidget {
  const _EventLog({required this.events});

  final List<String> events;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Events',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
          const SizedBox(height: 8),
          if (events.isEmpty)
            const Text('—', style: TextStyle(color: Colors.white24))
          else
            for (final event in events)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  event,
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'Menlo',
                      color: Colors.white70),
                ),
              ),
        ],
      ),
    );
  }
}

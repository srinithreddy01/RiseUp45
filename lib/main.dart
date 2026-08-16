import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'task_notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RiseUpApp());
}

class RiseUpApp extends StatefulWidget {
  const RiseUpApp({super.key});

  @override
  State<RiseUpApp> createState() => _RiseUpAppState();
}

class _RiseUpAppState extends State<RiseUpApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff3f6de0);
    return MaterialApp(
      title: 'RiseUP',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff7f8fc),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: RiseUpHome(
          onThemeChanged: (mode) => setState(() => _themeMode = mode)),
    );
  }
}

class RiseUpHome extends StatefulWidget {
  const RiseUpHome({super.key, required this.onThemeChanged});

  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<RiseUpHome> createState() => _RiseUpHomeState();
}

class _RiseUpHomeState extends State<RiseUpHome> with WidgetsBindingObserver {
  static const _storageKey = 'riseup.flutter.data.v1';
  final _pages = const [
    'Home',
    'Tasks',
    'Gym',
    'Learning',
    'Progress',
    'Settings'
  ];
  int _page = 0;
  bool _loaded = false;
  String _name = 'Friend';
  List<Task> _tasks = [];
  List<LearningGoal> _goals = [];
  Map<String, bool> _gym = {};
  ThemeMode _mode = ThemeMode.system;
  ReminderPermissionState _reminderState =
      const ReminderPermissionState.unavailable();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _loaded) {
      _refreshReminderState(resync: true);
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _name = data['name'] as String? ?? _name;
        _tasks = ((data['tasks'] as List?) ?? [])
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList();
        _goals = ((data['goals'] as List?) ?? [])
            .map((e) => LearningGoal.fromJson(e as Map<String, dynamic>))
            .toList();
        _gym = ((data['gym'] as Map?) ?? {})
            .map((key, value) => MapEntry(key.toString(), value == true));
        _mode = ThemeMode.values.firstWhere(
          (mode) => mode.name == data['theme'],
          orElse: () => ThemeMode.system,
        );
      } catch (_) {
        // Keep a usable empty workspace if an old backup is malformed.
      }
    }
    if (mounted) {
      widget.onThemeChanged(_mode);
      setState(() => _loaded = true);
      await TaskNotificationService.instance.syncAll(_tasks);
      await _refreshReminderState();
    }
  }

  Future<void> _refreshReminderState({bool resync = false}) async {
    final state = await TaskNotificationService.instance.permissionState();
    if (resync) await TaskNotificationService.instance.syncAll(_tasks);
    if (mounted) setState(() => _reminderState = state);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _storageKey,
        jsonEncode({
          'name': _name,
          'tasks': _tasks.map((task) => task.toJson()).toList(),
          'goals': _goals.map((goal) => goal.toJson()).toList(),
          'gym': _gym,
          'theme': _mode.name,
        }));
  }

  void _setPage(int value) => setState(() => _page = value);

  Future<ReminderScheduleResult> _upsertTask(Task task) async {
    setState(() {
      final index = _tasks.indexWhere((item) => item.id == task.id);
      if (index == -1) {
        _tasks.add(task);
      } else {
        _tasks[index] = task;
      }
    });
    await _save();
    return TaskNotificationService.instance.schedule(task);
  }

  void _toggleTask(Task task) {
    final completing = !task.done;
    _upsertTask(task.copyWith(done: completing));
    if (completing && task.recurrence != TaskRecurrence.none) {
      final nextDate = nextOccurrence(task.date, task.recurrence);
      final alreadyScheduled = _tasks.any((item) =>
          item.id != task.id &&
          item.title == task.title &&
          item.recurrence == task.recurrence &&
          sameDay(item.date, nextDate));
      if (!alreadyScheduled) {
        _upsertTask(task.copyWith(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          date: nextDate,
          done: false,
        ));
      }
    }
  }

  void _deleteTask(Task task) {
    setState(() => _tasks.removeWhere((item) => item.id == task.id));
    _save();
    TaskNotificationService.instance.cancel(task.id);
  }

  Future<void> _editTask([Task? task]) async {
    final value = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TaskEditor(task: task),
    );
    if (value != null) {
      if (value.time != null) {
        await TaskNotificationService.instance.requestNotificationPermission();
      }
      final result = await _upsertTask(value);
      await _refreshReminderState();
      if (!mounted || value.time == null) return;
      final message = !result.scheduled && result.wasPastDue
          ? 'This reminder time has already passed, so it was not scheduled.'
          : !_reminderState.notificationsAllowed
              ? 'Task saved. Allow notifications in Settings to receive the alert.'
              : result.exact
                  ? result.earlyReminderScheduled
                      ? '5-minute reminder and alarm set for ${value.time}.'
                      : 'Alarm set for ${value.time}. The task is less than 5 minutes away.'
                  : 'Reminder set. Enable precise alarms in Settings for on-time delivery.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _editGoal([LearningGoal? goal]) async {
    final value = await showDialog<LearningGoal>(
      context: context,
      builder: (_) => GoalEditor(goal: goal),
    );
    if (value == null) return;
    setState(() {
      final index = _goals.indexWhere((item) => item.id == value.id);
      if (index < 0) {
        _goals.add(value);
      } else {
        _goals[index] = value;
      }
    });
    _save();
  }

  void _changeGoal(LearningGoal goal, int amount) {
    _upsertGoal(goal.copyWith(
        today: (goal.today + amount).clamp(0, 9999).toInt(),
        total: (goal.total + amount).clamp(0, 999999).toInt()));
  }

  void _upsertGoal(LearningGoal goal) {
    setState(() {
      final index = _goals.indexWhere((item) => item.id == goal.id);
      _goals[index] = goal;
    });
    _save();
  }

  void _deleteGoal(LearningGoal goal) {
    setState(() => _goals.removeWhere((item) => item.id == goal.id));
    _save();
  }

  void _toggleGym() {
    final key = dateKey(DateTime.now());
    setState(() => _gym[key] = !(_gym[key] ?? false));
    _save();
  }

  void _setTheme(ThemeMode mode) {
    setState(() => _mode = mode);
    widget.onThemeChanged(mode);
    _save();
  }

  Future<void> _enableReminders() async {
    final notificationsAllowed =
        await TaskNotificationService.instance.requestNotificationPermission();
    if (!notificationsAllowed) {
      await TaskNotificationService.instance.openNotificationSettings();
      await _refreshReminderState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Android notification settings opened. Allow RiseUP alerts, then return here.')));
      }
      return;
    }
    final exactAlarmsAllowed =
        await TaskNotificationService.instance.requestExactAlarmPermission();
    await TaskNotificationService.instance.syncAll(_tasks);
    await _refreshReminderState();
    if (!mounted) return;
    final message = exactAlarmsAllowed
            ? 'Task reminders and precise alarms are enabled.'
            : 'Task reminders are enabled. Turn on Alarms & reminders in Android settings for exact timing.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _testReminder() async {
    final shown = await TaskNotificationService.instance.showTestNotification();
    await _refreshReminderState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(shown
            ? 'Test reminder sent. Check its sound and alert on this device.'
            : 'Allow notifications first, then try the test again.')));
  }

  Future<void> _showReminderSchedule() async {
    final reminders = _tasks
        .where((task) =>
            !task.done &&
            task.time != null &&
            task.date.isAfter(DateTime.now().subtract(const Duration(days: 1))))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Scheduled reminders',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (reminders.isEmpty)
                const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('No upcoming task reminders.'))
              else
                ...reminders.take(8).map((task) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text(task.title),
                      subtitle:
                          Text('${prettyDate(task.date)} at ${task.time}'),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final desktop = MediaQuery.sizeOf(context).width >= 850;
    final content = _buildPage();
    return Scaffold(
      body: SafeArea(
        child: desktop
            ? Row(children: [
                NavigationRail(
                  selectedIndex: _page,
                  onDestinationSelected: _setPage,
                  labelType: NavigationRailLabelType.all,
                  leading: const Padding(
                      padding: EdgeInsets.only(top: 20), child: Brand()),
                  destinations: navDestinations,
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ])
            : content,
      ),
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: _setPage,
              destinations: navDestinations
                  .map((item) => NavigationDestination(
                      icon: item.icon,
                      selectedIcon: item.selectedIcon,
                      label: (item.label as Text).data ?? ''))
                  .toList(),
            ),
      floatingActionButton: (_page == 0 || _page == 1)
          ? FloatingActionButton.extended(
              onPressed: () => _editTask(),
              icon: const Icon(Icons.add),
              label: const Text('Add task'))
          : null,
    );
  }

  Widget _buildPage() {
    switch (_page) {
      case 0:
        return HomePage(
            name: _name,
            tasks: _tasks,
            goals: _goals,
            gymDone: _gym[dateKey(DateTime.now())] ?? false,
            onToggleTask: _toggleTask,
            onToggleGym: _toggleGym,
            onChangeGoal: _changeGoal,
            onViewTasks: () => _setPage(1),
            onViewReminders: _showReminderSchedule);
      case 1:
        return TasksPage(
            tasks: _tasks,
            onToggle: _toggleTask,
            onEdit: _editTask,
            onDelete: _deleteTask);
      case 2:
        return GymPage(
            done: _gym[dateKey(DateTime.now())] ?? false, onToggle: _toggleGym);
      case 3:
        return LearningPage(
            goals: _goals,
            onAdd: _editGoal,
            onEdit: _editGoal,
            onDelete: _deleteGoal,
            onChange: _changeGoal);
      case 4:
        return ProgressPage(tasks: _tasks, goals: _goals, gym: _gym);
      default:
        return SettingsPage(
            name: _name,
            mode: _mode,
            onTheme: _setTheme,
            onName: (name) {
              setState(() => _name = name);
              _save();
            },
            onClear: () {
              setState(() {
                _tasks = [];
                _goals = [];
                _gym = {};
              });
              _save();
              TaskNotificationService.instance.cancelAll();
            },
            reminderState: _reminderState,
            onEnableReminders: _enableReminders,
            onTestReminder: _testReminder);
    }
  }
}

final navDestinations = <NavigationRailDestination>[
  const NavigationRailDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: Text('Home')),
  const NavigationRailDestination(
      icon: Icon(Icons.check_circle_outline),
      selectedIcon: Icon(Icons.check_circle),
      label: Text('Tasks')),
  const NavigationRailDestination(
      icon: Icon(Icons.fitness_center_outlined),
      selectedIcon: Icon(Icons.fitness_center),
      label: Text('Gym')),
  const NavigationRailDestination(
      icon: Icon(Icons.code_outlined),
      selectedIcon: Icon(Icons.code),
      label: Text('Learning')),
  const NavigationRailDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart),
      label: Text('Progress')),
  const NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: Text('Settings')),
];

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.bolt_rounded, color: Color(0xff3f6de0), size: 28),
        const SizedBox(width: 5),
        Text('RiseUP',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
      ]);
}

class PageFrame extends StatelessWidget {
  const PageFrame(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.child,
      this.action});
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => SafeArea(
          child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(subtitle.toUpperCase(),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 1.1)),
                  const SizedBox(height: 4),
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800))
                ])),
            if (action != null) action!
          ]),
          const SizedBox(height: 20),
          Expanded(child: child),
        ]),
      ));
}

class HomePage extends StatelessWidget {
  const HomePage(
      {super.key,
      required this.name,
      required this.tasks,
      required this.goals,
      required this.gymDone,
      required this.onToggleTask,
      required this.onToggleGym,
      required this.onChangeGoal,
      required this.onViewTasks,
      required this.onViewReminders});
  final String name;
  final List<Task> tasks;
  final List<LearningGoal> goals;
  final bool gymDone;
  final ValueChanged<Task> onToggleTask;
  final VoidCallback onToggleGym;
  final void Function(LearningGoal, int) onChangeGoal;
  final VoidCallback onViewTasks;
  final Future<void> Function() onViewReminders;

  @override
  Widget build(BuildContext context) {
    final todayTasks =
        tasks.where((task) => sameDay(task.date, DateTime.now())).toList();
    final done = todayTasks.where((task) => task.done).length;
    final progress = todayTasks.isEmpty ? 0.0 : done / todayTasks.length;
    final workout = workoutFor(DateTime.now());
    return PageFrame(
      title: 'Good morning, $name 👋',
      subtitle: prettyDate(DateTime.now()),
      action: IconButton(
          onPressed: onViewReminders,
          tooltip: 'Scheduled reminders',
          icon: const Icon(Icons.notifications_none)),
      child: ListView(children: [
        Card(
            child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TODAY\'S FOCUS',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                  letterSpacing: 1.1,
                                  color:
                                      Theme.of(context).colorScheme.primary)),
                      const SizedBox(height: 12),
                      Text('$done of ${todayTasks.length} tasks complete',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 14),
                      ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                              value: progress, minHeight: 12)),
                      const SizedBox(height: 8),
                      Text(
                          '${(progress * 100).round()}% complete — small actions build momentum.'),
                    ]))),
        const SizedBox(height: 16),
        LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth > 680
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: _TodayTasks(
                            tasks: todayTasks,
                            onToggle: onToggleTask,
                            onViewAll: onViewTasks)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: _WorkoutCard(
                            workout: workout,
                            done: gymDone,
                            onToggle: onToggleGym))
                  ])
                : Column(children: [
                    _TodayTasks(
                        tasks: todayTasks,
                        onToggle: onToggleTask,
                        onViewAll: onViewTasks),
                    const SizedBox(height: 16),
                    _WorkoutCard(
                        workout: workout, done: gymDone, onToggle: onToggleGym)
                  ])),
        const SizedBox(height: 16),
        _LearningCard(goals: goals, onChange: onChangeGoal),
      ]),
    );
  }
}

class _TodayTasks extends StatelessWidget {
  const _TodayTasks(
      {required this.tasks, required this.onToggle, required this.onViewAll});
  final List<Task> tasks;
  final ValueChanged<Task> onToggle;
  final VoidCallback onViewAll;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.check_circle_outline),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Today\'s tasks',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold))),
              const SizedBox(width: 8),
              TextButton(
                  style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: onViewAll,
                  child: const Text('View all'))
            ]),
            const Divider(),
            if (tasks.isEmpty)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text('Nothing planned yet. Add one meaningful task.'))
            else
              ...tasks.take(4).map((task) =>
                  TaskTile(task: task, onToggle: () => onToggle(task))),
          ])));
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard(
      {required this.workout, required this.done, required this.onToggle});
  final Workout workout;
  final bool done;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.fitness_center, color: Color(0xff7c4dff)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Today\'s workout',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold))),
              Chip(label: Text(workout.day.substring(0, 3)))
            ]),
            const SizedBox(height: 14),
            Text(workout.title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(workout.rest
                ? 'Recovery is part of the program. Take it easy today.'
                : workout.items.join(' • ')),
            const SizedBox(height: 14),
            if (!workout.rest)
              FilledButton.icon(
                  onPressed: onToggle,
                  icon: Icon(done ? Icons.check : Icons.radio_button_unchecked),
                  label: Text(
                      done ? 'Workout complete' : 'Mark workout complete')),
          ])));
}

class _LearningCard extends StatelessWidget {
  const _LearningCard({required this.goals, required this.onChange});
  final List<LearningGoal> goals;
  final void Function(LearningGoal, int) onChange;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.code, color: Color(0xff3f6de0)),
              const SizedBox(width: 8),
              Text('Today\'s learning',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold))
            ]),
            const SizedBox(height: 10),
            if (goals.isEmpty)
              const Text('Add a learning card to begin tracking your practice.')
            else
              ...goals.take(3).map((goal) => CounterRow(
                  goal: goal, onChange: (amount) => onChange(goal, amount))),
          ])));
}

class TasksPage extends StatefulWidget {
  const TasksPage(
      {super.key,
      required this.tasks,
      required this.onToggle,
      required this.onEdit,
      required this.onDelete});
  final List<Task> tasks;
  final ValueChanged<Task> onToggle;
  final void Function([Task? task]) onEdit;
  final ValueChanged<Task> onDelete;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  String _filter = 'All';
  @override
  Widget build(BuildContext context) {
    final values = widget.tasks
        .where((task) =>
            _filter == 'All' ||
            (_filter == 'Today' && sameDay(task.date, DateTime.now())) ||
            task.category == _filter)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return PageFrame(
        title: 'Tasks',
        subtitle: '${values.length} task${values.length == 1 ? '' : 's'}',
        action: FilledButton.icon(
            onPressed: () => widget.onEdit(),
            icon: const Icon(Icons.add),
            label: const Text('Add task')),
        child: Column(children: [
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                  children: [
                'All',
                'Today',
                'Personal',
                'College',
                'Coding',
                'Fitness',
                'Learning'
              ]
                      .map((item) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                              label: Text(item),
                              selected: _filter == item,
                              onSelected: (_) =>
                                  setState(() => _filter = item))))
                      .toList())),
          const SizedBox(height: 14),
          Expanded(
              child: values.isEmpty
                  ? const EmptyState(
                      icon: Icons.task_alt, text: 'No matching tasks yet.')
                  : ListView.separated(
                      itemCount: values.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final task = values[index];
                        return TaskTile(
                            task: task,
                            onToggle: () => widget.onToggle(task),
                            onEdit: () => widget.onEdit(task),
                            onDelete: () => widget.onDelete(task),
                            detailed: true);
                      })),
        ]));
  }
}

class TaskTile extends StatelessWidget {
  const TaskTile(
      {super.key,
      required this.task,
      required this.onToggle,
      this.onEdit,
      this.onDelete,
      this.detailed = false});
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool detailed;
  @override
  Widget build(BuildContext context) => Card(
          child: ListTile(
        leading: IconButton(
            onPressed: onToggle,
            icon: Icon(task.done ? Icons.check_circle : Icons.circle_outlined,
                color: task.done ? Colors.green : null)),
        title: Text(task.title,
            style: TextStyle(
                decoration: task.done ? TextDecoration.lineThrough : null,
                fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${task.category} • ${task.priority}${task.time == null ? '' : ' • ${task.time}'}${detailed ? ' • ${shortDate(task.date)}' : ''}'),
        trailing: onEdit == null
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit!();
                  if (value == 'delete') onDelete!();
                },
                itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete'))
                    ]),
      ));
}

class GymPage extends StatelessWidget {
  const GymPage({super.key, required this.done, required this.onToggle});
  final bool done;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) {
    final workout = workoutFor(DateTime.now());
    return PageFrame(
        title: '${workout.day} — ${workout.title}',
        subtitle: 'Weekly training plan',
        child: ListView(children: [
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.fitness_center,
                            size: 42,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 14),
                        Text(
                            workout.rest
                                ? 'Rest & recovery'
                                : 'Today\'s session',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (workout.rest)
                          const Text(
                              'A rest day keeps you ready for your next session.')
                        else
                          ...workout.items.asMap().entries.map((entry) =>
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                      radius: 14,
                                      child: Text('${entry.key + 1}')),
                                  title: Text('${entry.value} focus'),
                                  subtitle: const Text(
                                      '3–4 sets • controlled form'))),
                        if (!workout.rest) const SizedBox(height: 10),
                        if (!workout.rest)
                          FilledButton.icon(
                              onPressed: onToggle,
                              icon: Icon(
                                  done ? Icons.check : Icons.fitness_center),
                              label: Text(done
                                  ? 'Workout completed'
                                  : 'Complete workout')),
                      ]))),
          const SizedBox(height: 16),
          Text('Your split',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...weeklyWorkouts.map((item) => Card(
              child: ListTile(
                  leading: Icon(item.day == workout.day
                      ? Icons.play_circle_fill
                      : Icons.fitness_center_outlined),
                  title: Text(item.day),
                  subtitle: Text(item.title),
                  trailing: item.rest ? const Text('Rest') : null))),
        ]));
  }
}

class LearningPage extends StatelessWidget {
  const LearningPage(
      {super.key,
      required this.goals,
      required this.onAdd,
      required this.onEdit,
      required this.onDelete,
      required this.onChange});
  final List<LearningGoal> goals;
  final void Function([LearningGoal? goal]) onAdd;
  final void Function([LearningGoal? goal]) onEdit;
  final ValueChanged<LearningGoal> onDelete;
  final void Function(LearningGoal, int) onChange;
  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Practice with intention.',
        subtitle: 'Coding & learning',
        action: FilledButton.icon(
            onPressed: () => onAdd(),
            icon: const Icon(Icons.add),
            label: const Text('Add card')),
        child: goals.isEmpty
            ? const Center(
                child: EmptyState(
                    icon: Icons.menu_book_outlined,
                    text: 'Add a card for a course, book, or coding practice.'))
            : GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        MediaQuery.sizeOf(context).width > 700 ? 2 : 1,
                    childAspectRatio: 1.8,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12),
                itemCount: goals.length,
                itemBuilder: (_, index) {
                  final goal = goals[index];
                  return Card(
                      child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  CircleAvatar(
                                      backgroundColor: goal.color,
                                      child: Text(
                                          goal.title
                                              .substring(0, 1)
                                              .toUpperCase(),
                                          style: const TextStyle(
                                              color: Colors.white))),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text(goal.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                  PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') onEdit(goal);
                                        if (value == 'delete') onDelete(goal);
                                      },
                                      itemBuilder: (_) => const [
                                            PopupMenuItem(
                                                value: 'edit',
                                                child: Text('Edit')),
                                            PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Delete'))
                                          ]),
                                ]),
                                const SizedBox(height: 8),
                                Text(goal.description.isEmpty
                                    ? 'Track your daily progress.'
                                    : goal.description),
                                const Spacer(),
                                Text('${goal.total} ${goal.unit} all time',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                CounterRow(
                                    goal: goal,
                                    onChange: (amount) =>
                                        onChange(goal, amount)),
                              ])));
                },
              ),
      );
}

class CounterRow extends StatelessWidget {
  const CounterRow({super.key, required this.goal, required this.onChange});
  final LearningGoal goal;
  final ValueChanged<int> onChange;
  @override
  Widget build(BuildContext context) => Row(children: [
        const Text('Today'),
        const Spacer(),
        IconButton(
            onPressed: () => onChange(-1),
            icon: const Icon(Icons.remove_circle_outline)),
        Text('${goal.today}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        IconButton(
            onPressed: () => onChange(1), icon: const Icon(Icons.add_circle))
      ]);
}

class ProgressPage extends StatelessWidget {
  const ProgressPage(
      {super.key, required this.tasks, required this.goals, required this.gym});
  final List<Task> tasks;
  final List<LearningGoal> goals;
  final Map<String, bool> gym;
  @override
  Widget build(BuildContext context) {
    final complete = tasks.where((task) => task.done).length;
    final learn = goals.fold<int>(0, (sum, goal) => sum + goal.total);
    final gymCount = gym.values.where((value) => value).length;
    final now = DateTime.now();
    final days = List.generate(
        7, (index) => DateTime(now.year, now.month, now.day - 6 + index));
    return PageFrame(
        title: 'Your progress',
        subtitle: 'Keep your momentum',
        child: ListView(children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            MetricCard(
                icon: Icons.check_circle,
                label: 'Tasks completed',
                value: '$complete'),
            MetricCard(
                icon: Icons.fitness_center,
                label: 'Gym sessions',
                value: '$gymCount'),
            MetricCard(
                icon: Icons.code, label: 'Learning logged', value: '$learn')
          ]),
          const SizedBox(height: 20),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Weekly completion',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 22),
                        SizedBox(
                            height: 190,
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: days.map((day) {
                                  final dayTasks = tasks
                                      .where((task) => sameDay(task.date, day))
                                      .toList();
                                  final value = dayTasks.isEmpty
                                      ? 0.0
                                      : dayTasks
                                              .where((task) => task.done)
                                              .length /
                                          dayTasks.length;
                                  return Expanded(
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                        Text('${(value * 100).round()}%'),
                                        const SizedBox(height: 6),
                                        Expanded(
                                            child: Align(
                                                alignment:
                                                    Alignment.bottomCenter,
                                                child: FractionallySizedBox(
                                                    heightFactor: value == 0
                                                        ? .04
                                                        : value,
                                                    widthFactor: .55,
                                                    child: DecoratedBox(
                                                        decoration: BoxDecoration(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .primary,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8)))))),
                                        const SizedBox(height: 8),
                                        Text(weekLabel(day)),
                                      ]));
                                }).toList())),
                      ]))),
        ]));
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard(
      {super.key,
      required this.icon,
      required this.label,
      required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 180,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 14),
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(label)
                  ]))));
}

class SettingsPage extends StatelessWidget {
  const SettingsPage(
      {super.key,
      required this.name,
      required this.mode,
      required this.onTheme,
      required this.onName,
      required this.onClear,
      required this.reminderState,
      required this.onEnableReminders,
      required this.onTestReminder});
  final String name;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  final ValueChanged<String> onName;
  final VoidCallback onClear;
  final ReminderPermissionState reminderState;
  final Future<void> Function() onEnableReminders;
  final Future<void> Function() onTestReminder;
  @override
  Widget build(BuildContext context) => PageFrame(
      title: 'Settings',
      subtitle: 'Make RiseUP yours',
      child: ListView(children: [
        Card(
            child: Column(children: [
          ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(name),
              subtitle: const Text('Your local workspace'),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final value = await showDialog<String>(
                    context: context, builder: (_) => NameEditor(name: name));
                if (value != null && value.trim().isNotEmpty)
                  onName(value.trim());
              }),
          const Divider(height: 1),
          ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Theme'),
              subtitle:
                  Text(mode.name[0].toUpperCase() + mode.name.substring(1)),
              trailing: DropdownButton<ThemeMode>(
                  value: mode,
                  underline: const SizedBox(),
                  onChanged: (value) {
                    if (value != null) onTheme(value);
                  },
                  items: const [
                    DropdownMenuItem(
                        value: ThemeMode.system, child: Text('System')),
                    DropdownMenuItem(
                        value: ThemeMode.light, child: Text('Light')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark'))
                  ])),
          const Divider(height: 1),
          const ListTile(
              leading: Icon(Icons.storage_outlined),
              title: Text('Local data'),
              subtitle: Text(
                  'Your tasks, gym sessions, and learning logs stay on this device.'))
        ])),
        const SizedBox(height: 16),
        Card(
            child: ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Task reminders'),
                subtitle: Text(reminderState.notificationsAllowed
                    ? reminderState.exactAlarmsAllowed
                        ? 'Alerts, sound, and precise alarms are ready.'
                        : 'Alerts are ready. Enable precise alarms for on-time delivery.'
                    : 'Notifications are blocked. Enable them to receive task alerts.'),
                trailing: FilledButton(
                    onPressed: onEnableReminders,
                    child: Text(reminderState.notificationsAllowed &&
                            reminderState.exactAlarmsAllowed
                        ? 'Check'
                        : 'Enable')))),
        const SizedBox(height: 8),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                onPressed: onTestReminder,
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('Send a test reminder'))),
        const SizedBox(height: 20),
        OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                          title: const Text('Clear all local data?'),
                          content: const Text(
                              'This removes every task, learning goal, and gym record from this device.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Clear data'))
                          ]));
              if (confirmed == true) onClear();
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Clear all local data')),
      ]));
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center)
      ]));
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, this.task});
  final Task? task;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late DateTime _date;
  late String _category;
  late String _priority;
  late TaskRecurrence _recurrence;
  TimeOfDay? _time;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.task?.title ?? '');
    _notes = TextEditingController(text: widget.task?.notes ?? '');
    _date = widget.task?.date ?? DateTime.now();
    _category = widget.task?.category ?? 'Personal';
    _priority = widget.task?.priority ?? 'Medium';
    _recurrence = widget.task?.recurrence ?? TaskRecurrence.none;
    _time = widget.task?.time == null ? null : timeFrom(widget.task!.time!);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(widget.task == null ? 'Plan something great' : 'Update task',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            TextField(
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Task name', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: DropdownButtonFormField(
                      value: _category,
                      decoration: const InputDecoration(
                          labelText: 'Category', border: OutlineInputBorder()),
                      items: [
                        'Personal',
                        'College',
                        'Coding',
                        'Fitness',
                        'Learning',
                        'Other'
                      ]
                          .map((item) =>
                              DropdownMenuItem(value: item, child: Text(item)))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _category = value!))),
              const SizedBox(width: 12),
              Expanded(
                  child: DropdownButtonFormField(
                      value: _priority,
                      decoration: const InputDecoration(
                          labelText: 'Priority', border: OutlineInputBorder()),
                      items: ['Low', 'Medium', 'High']
                          .map((item) =>
                              DropdownMenuItem(value: item, child: Text(item)))
                          .toList(),
                      onChanged: (value) => setState(() => _priority = value!)))
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () async {
                        final value = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            initialDate: _date);
                        if (value != null) setState(() => _date = value);
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: Text(shortDate(_date)))),
              const SizedBox(width: 12),
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () async {
                        final value = await showTimePicker(
                            context: context,
                            initialTime: _time ?? TimeOfDay.now());
                        if (value != null) setState(() => _time = value);
                      },
                      icon: const Icon(Icons.schedule),
                      label: Text(_time?.format(context) ?? 'Reminder')))
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<TaskRecurrence>(
                value: _recurrence,
                decoration: const InputDecoration(
                    labelText: 'Repeat', border: OutlineInputBorder()),
                items: TaskRecurrence.values
                    .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item.label)))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _recurrence = value ?? TaskRecurrence.none)),
            const SizedBox(height: 12),
            TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Notes', border: OutlineInputBorder())),
            const SizedBox(height: 18),
            SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                    onPressed: () {
                      if (_title.text.trim().isEmpty) return;
                      Navigator.pop(
                          context,
                          Task(
                              id: widget.task?.id ??
                                  DateTime.now()
                                      .microsecondsSinceEpoch
                                      .toString(),
                              title: _title.text.trim(),
                              category: _category,
                              priority: _priority,
                              date: _date,
                              time: _time == null
                                  ? null
                                  : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}',
                              notes: _notes.text.trim(),
                              done: widget.task?.done ?? false,
                              recurrence: _recurrence));
                    },
                    icon: const Icon(Icons.check),
                    label: Text(
                        widget.task == null ? 'Add task' : 'Save changes')))
          ])));
}

class GoalEditor extends StatefulWidget {
  const GoalEditor({super.key, this.goal});
  final LearningGoal? goal;
  @override
  State<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<GoalEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.goal?.title ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.goal?.description ?? '');
  String _unit = 'problems solved';
  @override
  void initState() {
    super.initState();
    _unit = widget.goal?.unit ?? _unit;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(
              widget.goal == null ? 'New learning card' : 'Edit learning card'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title')),
            TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description')),
            DropdownButtonFormField(
                value: _unit,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: [
                  'problems solved',
                  'topics completed',
                  'lessons completed',
                  'chapters read',
                  'sessions'
                ]
                    .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                    .toList(),
                onChanged: (value) => setState(() => _unit = value!))
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  if (_title.text.trim().isEmpty) return;
                  Navigator.pop(
                      context,
                      LearningGoal(
                          id: widget.goal?.id ??
                              DateTime.now().microsecondsSinceEpoch.toString(),
                          title: _title.text.trim(),
                          description: _description.text.trim(),
                          unit: _unit,
                          total: widget.goal?.total ?? 0,
                          today: widget.goal?.today ?? 0,
                          color:
                              widget.goal?.color ?? const Color(0xff3f6de0)));
                },
                child: const Text('Save'))
          ]);
}

class NameEditor extends StatefulWidget {
  const NameEditor({super.key, required this.name});
  final String name;
  @override
  State<NameEditor> createState() => _NameEditorState();
}

class _NameEditorState extends State<NameEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.name);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Edit profile'),
          content: TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Display name')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, _controller.text),
                child: const Text('Save'))
          ]);
}

enum TaskRecurrence {
  none('Does not repeat'),
  daily('Daily'),
  weekdays('Weekdays'),
  weekly('Weekly');

  const TaskRecurrence(this.label);
  final String label;
}

class Task {
  const Task(
      {required this.id,
      required this.title,
      required this.category,
      required this.priority,
      required this.date,
      required this.done,
      this.time,
      this.notes = '',
      this.recurrence = TaskRecurrence.none});
  final String id;
  final String title;
  final String category;
  final String priority;
  final DateTime date;
  final bool done;
  final String? time;
  final String notes;
  final TaskRecurrence recurrence;
  Task copyWith({String? id, DateTime? date, bool? done}) => Task(
      id: id ?? this.id,
      title: title,
      category: category,
      priority: priority,
      date: date ?? this.date,
      done: done ?? this.done,
      time: time,
      notes: notes,
      recurrence: recurrence);
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'priority': priority,
        'date': date.toIso8601String(),
        'done': done,
        'time': time,
        'notes': notes,
        'recurrence': recurrence.name
      };
  factory Task.fromJson(Map<String, dynamic> value) => Task(
      id: value['id'] as String,
      title: value['title'] as String,
      category: value['category'] as String? ?? 'Personal',
      priority: value['priority'] as String? ?? 'Medium',
      date: DateTime.parse(value['date'] as String),
      done: value['done'] == true,
      time: value['time'] as String?,
      notes: value['notes'] as String? ?? '',
      recurrence: TaskRecurrence.values.firstWhere(
          (item) => item.name == value['recurrence'],
          orElse: () => TaskRecurrence.none));
}

class LearningGoal {
  const LearningGoal(
      {required this.id,
      required this.title,
      required this.description,
      required this.unit,
      required this.total,
      required this.today,
      required this.color});
  final String id;
  final String title;
  final String description;
  final String unit;
  final int total;
  final int today;
  final Color color;
  LearningGoal copyWith({int? total, int? today}) => LearningGoal(
      id: id,
      title: title,
      description: description,
      unit: unit,
      total: total ?? this.total,
      today: today ?? this.today,
      color: color);
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'unit': unit,
        'total': total,
        'today': today,
        'color': color.value
      };
  factory LearningGoal.fromJson(Map<String, dynamic> value) => LearningGoal(
      id: value['id'] as String,
      title: value['title'] as String,
      description: value['description'] as String? ?? '',
      unit: value['unit'] as String? ?? 'sessions',
      total: value['total'] as int? ?? 0,
      today: value['today'] as int? ?? 0,
      color: Color(value['color'] as int? ?? 0xff3f6de0));
}

class Workout {
  const Workout(this.day, this.title, this.items, {this.rest = false});
  final String day;
  final String title;
  final List<String> items;
  final bool rest;
}

const weeklyWorkouts = [
  Workout('Monday', 'Back + Bicep', ['Back exercises', 'Bicep exercises']),
  Workout('Tuesday', 'Chest + Tricep', ['Chest exercises', 'Tricep exercises']),
  Workout('Wednesday', 'Shoulder + Forearm',
      ['Shoulder exercises', 'Forearm exercises']),
  Workout(
      'Thursday', 'Core (ABS) + Bicep', ['Core exercises', 'Bicep exercises']),
  Workout('Friday', 'Legs', ['Leg exercises', 'Mobility work']),
  Workout(
      'Saturday', 'Shoulder + ABS', ['Shoulder exercises', 'ABS exercises']),
  Workout('Sunday', 'Rest Day', [], rest: true),
];

Workout workoutFor(DateTime date) => weeklyWorkouts[date.weekday - 1];
String dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
bool sameDay(DateTime a, DateTime b) => dateKey(a) == dateKey(b);
String shortDate(DateTime value) => '${value.day}/${value.month}/${value.year}';
String prettyDate(DateTime value) {
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  return '${days[value.weekday - 1]}, ${months[value.month - 1]} ${value.day}';
}

String weekLabel(DateTime value) =>
    const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][value.weekday - 1];
TimeOfDay timeFrom(String value) {
  final pieces = value.split(':');
  return TimeOfDay(hour: int.parse(pieces[0]), minute: int.parse(pieces[1]));
}

DateTime nextOccurrence(DateTime date, TaskRecurrence recurrence) {
  switch (recurrence) {
    case TaskRecurrence.daily:
      return DateTime(date.year, date.month, date.day + 1);
    case TaskRecurrence.weekdays:
      var next = DateTime(date.year, date.month, date.day + 1);
      while (next.weekday == DateTime.saturday ||
          next.weekday == DateTime.sunday) {
        next = next.add(const Duration(days: 1));
      }
      return next;
    case TaskRecurrence.weekly:
      return DateTime(date.year, date.month, date.day + 7);
    case TaskRecurrence.none:
      return date;
  }
}

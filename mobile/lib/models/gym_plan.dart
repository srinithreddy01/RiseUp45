class GymPlan {
  const GymPlan({
    required this.id,
    required this.title,
    required this.weekdays,
    required this.time,
    required this.exercises,
  });

  final String id;
  final String title;
  final List<int> weekdays;
  final String time;
  final List<String> exercises;

  GymPlan copyWith({
    String? title,
    List<int>? weekdays,
    String? time,
    List<String>? exercises,
  }) =>
      GymPlan(
        id: id,
        title: title ?? this.title,
        weekdays: weekdays ?? this.weekdays,
        time: time ?? this.time,
        exercises: exercises ?? this.exercises,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'weekdays': weekdays,
        'time': time,
        'exercises': exercises,
      };

  factory GymPlan.fromJson(Map<String, dynamic> value) => GymPlan(
        id: value['id'] as String,
        title: value['title'] as String? ?? 'Workout',
        weekdays: ((value['weekdays'] as List?) ?? const <int>[])
            .map((day) => day as int)
            .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
            .toList(),
        time: value['time'] as String? ?? '18:00',
        exercises: ((value['exercises'] as List?) ?? const <String>[])
            .map((exercise) => exercise.toString())
            .toList(),
      );
}

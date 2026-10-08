// Internal observation only: ordinary models do not allocate assignment state.
final _assignments = Expando<Set<String>>('WAMP field assignments');

void observeWampFieldAssignments(Object model) {
  _assignments[model] ??= <String>{};
}

void recordWampFieldAssignment(Object model, String field) {
  _assignments[model]?.add(field);
}

Iterable<String> assignedWampFields(Object model) =>
    _assignments[model] ?? const <String>{};

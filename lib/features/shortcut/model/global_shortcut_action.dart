enum GlobalShortcutAction {
  toggleConnection,
  showWindow,
  cycleServiceMode;

  String get label => switch (this) {
    toggleConnection => 'Toggle connection',
    showWindow => 'Show or hide window',
    cycleServiceMode => 'Cycle service mode',
  };
}

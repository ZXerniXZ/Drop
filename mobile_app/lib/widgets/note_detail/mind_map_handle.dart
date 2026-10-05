class MindMapHandle {
  Future<void> Function()? _fit;

  void attach(Future<void> Function() fit) {
    _fit = fit;
  }

  void detach(Future<void> Function() fit) {
    if (_fit == fit) _fit = null;
  }

  Future<void> fit() async {
    await _fit?.call();
  }
}

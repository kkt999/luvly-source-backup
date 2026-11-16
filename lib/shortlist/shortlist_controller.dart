import 'dart:async';
import 'package:flutter/foundation.dart';
import 'shortlist_repository.dart';

class ShortlistController extends ChangeNotifier {
  ShortlistController(this.repository);
  final ShortlistRepository repository;
  StreamSubscription<ShortlistSnapshot>? _subscription;
  int _generation = 0;
  bool _disposed = false;
  String? uid, error;
  bool loading = false, fromCache = false;
  List<String> _ids = [];
  final _pending = <String>{};
  List<String> get ids => List.unmodifiable(_ids);
  bool contains(String id) => _ids.contains(id);
  bool pending(String id) => _pending.contains(id);
  bool get ready => uid != null && !loading && error == null;

  void bind(String? next, {bool force = false}) {
    if (_disposed || (uid == next && !force)) return;
    final generation = ++_generation;
    _subscription?.cancel();
    _subscription = null;
    uid = next;
    _ids = [];
    _pending.clear();
    error = null;
    fromCache = false;
    loading = next != null;
    notifyListeners();
    if (next == null) return;
    _subscription = repository
        .watch(next)
        .listen(
          (snapshot) {
            if (_disposed || generation != _generation) return;
            _ids = snapshot.ids.toSet().toList();
            fromCache = snapshot.fromCache;
            loading = false;
            error = null;
            notifyListeners();
          },
          onError: (Object _) {
            if (_disposed || generation != _generation) return;
            _ids = [];
            loading = false;
            error =
                'We could not load your shortlist. Check your connection and retry.';
            notifyListeners();
          },
        );
  }

  void retry() {
    if (_pending.isEmpty) bind(uid, force: true);
  }

  Future<void> setSaved(String id, bool saved) async {
    final account = uid;
    if (!ready || account == null) {
      throw StateError('Your shortlist is not ready. Please retry.');
    }
    if (_pending.contains(id)) {
      throw StateError('This gown is already updating.');
    }
    if (contains(id) == saved) return;
    final generation = _generation;
    _pending.add(id);
    notifyListeners();
    try {
      await repository.setSaved(account, id, saved);
      if (_disposed || generation != _generation) return;
      _ids.remove(id);
      if (saved) _ids.insert(0, id);
      notifyListeners();
    } finally {
      if (!_disposed && generation == _generation) {
        _pending.remove(id);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _subscription?.cancel();
    super.dispose();
  }
}

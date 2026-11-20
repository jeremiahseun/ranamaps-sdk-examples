// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:rana_maps/rana_maps.dart';
import 'delivery_controller.dart';

/// Floating search field that adds a drop-off through Rana places search.
class StopSearch extends StatefulWidget {
  const StopSearch({super.key, required this.controller});
  final DeliveryController controller;
  @override
  State<StopSearch> createState() => _StopSearchState();
}

class _StopSearchState extends State<StopSearch> {
  final text = TextEditingController();
  final focus = FocusNode();
  Timer? _debounce;
  List<PlaceSuggestion> results = const [];
  String? error;
  bool loading = false;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  void _changed(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => results = const []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(q.trim()),
    );
  }

  Future<void> _search(String q) async {
    final places = widget.controller.places;
    if (places == null) {
      setState(() => error = 'Search unavailable (no API key)');
      return;
    }
    final seq = ++_seq;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await places.autocomplete(
        SearchOptions(
          query: q,
          near: widget.controller.origin ?? lagos,
          limit: 5,
        ),
      );
      if (mounted && seq == _seq) setState(() => results = r);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => error = 'Search failed');
    } finally {
      if (mounted && seq == _seq) setState(() => loading = false);
    }
  }

  void _pick(PlaceSuggestion s) {
    focus.unfocus();
    text.clear();
    setState(() => results = const []);
    unawaited(widget.controller.addStop(s.name, s.point));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final full = c.stops.length >= maxStops;
    final enabled = !c.running && !full;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('stop-search'),
            controller: text,
            focusNode: focus,
            enabled: enabled,
            onChanged: _changed,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: c.running
                  ? 'Delivery in progress'
                  : full
                  ? 'Stop limit reached'
                  : 'Add a drop-off',
              prefixIcon: const Icon(Icons.add_location_alt_outlined),
              suffixIcon: loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(error!, style: TextStyle(color: scheme.error)),
            ),
          for (final r in results)
            ListTile(
              dense: true,
              leading: const Icon(Icons.place_outlined),
              title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: r.secondary.isEmpty
                  ? null
                  : Text(
                      r.secondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              onTap: () => _pick(r),
            ),
        ],
      ),
    );
  }
}

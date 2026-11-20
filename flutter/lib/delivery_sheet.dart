// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'dart:async';
import 'delivery_controller.dart';

String _km(double m) =>
    m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

String _eta(Duration d) {
  final arrive = DateTime.now().add(d);
  final hh = arrive.hour.toString().padLeft(2, '0');
  final mm = arrive.minute.toString().padLeft(2, '0');
  final mins = (d.inSeconds / 60).ceil();
  return '$mins min  ·  $hh:$mm';
}

/// Sheet content: status/ETA header, run controls, scenario chips, stop list.
class DeliverySheetContent extends StatelessWidget {
  const DeliverySheetContent({
    super.key,
    required this.controller,
    required this.scroll,
  });
  final DeliveryController controller;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final eta = c.eta;
    final bad =
        c.wrongRoute ||
        c.statusLabel.contains('Off') ||
        c.statusLabel.contains('failed');
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eta == null ? '--' : _eta(eta),
                      key: const Key('eta'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.path == null
                          ? c.statusLabel
                          : '${_km(c.running ? c.remainingM : c.distanceM0.toDouble())}'
                                '  ·  ${c.remainingStops} stop${c.remainingStops == 1 ? '' : 's'} left',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const Key('primary-action'),
                style: c.running
                    ? FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                      )
                    : null,
                onPressed: c.running
                    ? () => unawaited(c.endRun())
                    : (c.origin == null || c.path == null || c.planning
                          ? null
                          : c.start),
                icon: Icon(
                  c.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(c.running ? 'End run' : 'Start delivery'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              key: const Key('status'),
              avatar: Icon(
                bad ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                size: 18,
                color: bad
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              label: Text(c.statusLabel),
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (!c.running) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Movement', style: theme.textTheme.labelLarge),
                const Spacer(),
                SegmentedButton<bool>(
                  key: const Key('movement'),
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: true, label: Text('Simulated')),
                    ButtonSegment(
                      value: false,
                      label: const Text('Device GPS'),
                      enabled: !c.locationDenied,
                    ),
                  ],
                  selected: {c.simulated},
                  onSelectionChanged: (v) => c.setSimulated(v.first),
                ),
              ],
            ),
          ],
          if (c.running) ...[
            const SizedBox(height: 4),
            Text(
              c.simulated
                  ? 'Updates ${c.received}  ·  dropped ${c.dropped}'
                  : 'Device GPS  ·  fixes ${c.received}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.simulated) ...[
                  ActionChip(
                    label: const Text('Drop next update'),
                    onPressed: () => c.dropUpdates(1),
                  ),
                  ActionChip(
                    label: const Text('Drop 3 updates'),
                    onPressed: () => c.dropUpdates(3),
                  ),
                ],
                if (c.wrongRoute)
                  ActionChip(
                    avatar: const Icon(Icons.restore, size: 18),
                    label: const Text('Restore route'),
                    onPressed: () => unawaited(c.restoreRoute()),
                  )
                else
                  ActionChip(
                    avatar: const Icon(Icons.alt_route, size: 18),
                    label: const Text('Wrong route'),
                    onPressed: () => unawaited(c.useWrongRoute()),
                  ),
              ],
            ),
            if (c.simulated) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Update interval', style: theme.textTheme.labelLarge),
                  const Spacer(),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1 s')),
                      ButtonSegment(value: 5, label: Text('5 s')),
                    ],
                    selected: {c.interval.inSeconds},
                    onSelectionChanged: (v) =>
                        c.setInterval(Duration(seconds: v.first)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: const Key('mark-delivered'),
              onPressed: c.next == null
                  ? null
                  : () => unawaited(c.markDelivered()),
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(
                'Mark stop delivered'
                '${c.next == null ? '' : ' (${c.stops.indexOf(c.next!) + 1})'}',
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text('Stops', style: theme.textTheme.titleSmall),
          for (var i = 0; i < c.stops.length; i++)
            _StopTile(
              index: i,
              stop: c.stops[i],
              isNext: identical(c.stops[i], c.next),
              onRemove: c.running
                  ? null
                  : () => unawaited(c.removeStop(c.stops[i])),
            ),
        ],
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.index,
    required this.stop,
    required this.isNext,
    required this.onRemove,
  });
  final int index;
  final Stop stop;
  final bool isNext;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: stop.delivered
            ? const Color(0xFF2E7D32)
            : isNext
            ? scheme.primary
            : scheme.surfaceContainerHighest,
        foregroundColor: stop.delivered || isNext
            ? Colors.white
            : scheme.onSurface,
        child: stop.delivered
            ? const Icon(Icons.check, size: 18)
            : Text('${index + 1}'),
      ),
      title: Text(
        stop.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: stop.delivered
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(
        stop.delivered
            ? 'Delivered'
            : isNext
            ? 'Next stop'
            : 'Pending',
      ),
      trailing: onRemove == null
          ? null
          : IconButton(
              tooltip: 'Remove stop',
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
    );
  }
}

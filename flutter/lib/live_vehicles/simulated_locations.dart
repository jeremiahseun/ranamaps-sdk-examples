import 'package:rana_maps/rana_maps.dart';

import '../geo.dart';
import 'lagos_road_tracks.dart';

typedef VehicleFix = ({
  String id,
  VehicleKind kind,
  LatLng point,
  double heading,
});

/// Each snapshot contains the vehicles currently available to this viewer.
/// The independent tracks and staggered availability repeat every 42 seconds.
class SimulatedLocations {
  static const _cycleSeconds = 42;
  final _routes = [for (final track in lagosRoadTracks) _Track(track)];

  List<VehicleFix> at(Duration elapsed) {
    final seconds = (elapsed.inMilliseconds / 1000) % _cycleSeconds;
    return [
      for (final track in _routes)
        if (seconds >= track.enters && seconds < track.leaves)
          track.fixAt(seconds),
    ];
  }
}

class _Track {
  _Track(this.track)
    : path = Path([
        for (final (lat, lng) in track.coordinates)
          LatLng(latitude: lat, longitude: lng),
      ]);

  final LagosRoadTrack track;
  final Path path;

  int get enters => track.enters;
  int get leaves => track.leaves;

  VehicleFix fixAt(double seconds) {
    final metres = path.length * (seconds - enters) / (leaves - enters);
    return (
      id: track.id,
      kind: track.kind,
      point: path.at(metres),
      heading: path.courseAt(metres),
    );
  }
}

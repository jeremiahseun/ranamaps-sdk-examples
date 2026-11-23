import 'package:rana_maps/rana_maps.dart';

typedef LagosRoadTrack = ({
  String id,
  VehicleKind kind,
  int enters,
  int leaves,
  List<(double, double)> coordinates,
});

/// Street centerlines near the Lagos delivery sample from © OpenStreetMap contributors.
/// Coordinates are (latitude, longitude), in the direction of travel.
/// Start and end points are interpolated along the source way.
const lagosRoadTracks = <LagosRoadTrack>[
  // Tejuoso Street · https://www.openstreetmap.org/way/133803795
  (
    id: 'Car 01',
    kind: VehicleKind.car,
    enters: 0,
    leaves: 23,
    coordinates: [
      (6.5058175, 3.3659166),
      (6.5058876, 3.3661043),
      (6.5059057, 3.3661566),
      (6.5059660, 3.3663349),
      (6.5063397, 3.3674798),
      (6.5064164, 3.3676760),
      (6.5065213, 3.3679698),
    ],
  ),
  // Iyun Road · https://www.openstreetmap.org/way/218716733
  (
    id: 'Car 02',
    kind: VehicleKind.car,
    enters: 0,
    leaves: 31,
    coordinates: [
      (6.5028942, 3.3640110),
      (6.5028605, 3.3641070),
      (6.5026940, 3.3645294),
      (6.5024648, 3.3651316),
      (6.5022157, 3.3658142),
      (6.5020402, 3.3663465),
    ],
  ),
  // Clegg Street · https://www.openstreetmap.org/way/90288347
  (
    id: 'Bike 01',
    kind: VehicleKind.okada,
    enters: 0,
    leaves: 19,
    coordinates: [
      (6.5076509, 3.3615979),
      (6.5076827, 3.3617025),
      (6.5077174, 3.3618070),
      (6.5078972, 3.3622604),
      (6.5079666, 3.3624078),
      (6.5080782, 3.3626430),
    ],
  ),
  // Oyabiyi Street · https://www.openstreetmap.org/way/218440816
  (
    id: 'Bike 02',
    kind: VehicleKind.bicycle,
    enters: 3,
    leaves: 26,
    coordinates: [
      (6.5093492, 3.3690541),
      (6.5093671, 3.3691469),
      (6.5094922, 3.3694661),
      (6.5096197, 3.3697423),
    ],
  ),
  // Alhaji Masha Road · https://www.openstreetmap.org/way/16369562
  (
    id: 'Car 03',
    kind: VehicleKind.car,
    enters: 6,
    leaves: 33,
    coordinates: [
      (6.4979119, 3.3619914),
      (6.4979297, 3.3619224),
      (6.4979484, 3.3618434),
      (6.4979942, 3.3615876),
      (6.4980050, 3.3615468),
      (6.4980605, 3.3612140),
      (6.4980939, 3.3609334),
      (6.4981318, 3.3607110),
      (6.4981917, 3.3604833),
      (6.4982355, 3.3603519),
    ],
  ),
  // Onitolo Street · https://www.openstreetmap.org/way/11102824
  (
    id: 'Bike 03',
    kind: VehicleKind.okada,
    enters: 11,
    leaves: 33,
    coordinates: [
      (6.5036833, 3.3607593),
      (6.5038333, 3.3608106),
      (6.5041051, 3.3609138),
      (6.5042730, 3.3609688),
      (6.5045448, 3.3610603),
      (6.5047686, 3.3611451),
      (6.5048783, 3.3611854),
    ],
  ),
  // Lisabi Street · https://www.openstreetmap.org/way/218716732
  (
    id: 'Walker 01',
    kind: VehicleKind.walker,
    enters: 0,
    leaves: 30,
    coordinates: [
      (6.5080727, 3.3664485),
      (6.5080700, 3.3663987),
      (6.5080245, 3.3660791),
      (6.5080224, 3.3660628),
    ],
  ),
  // Olorogun Street · https://www.openstreetmap.org/way/11102835
  (
    id: 'Walker 02',
    kind: VehicleKind.walker,
    enters: 2,
    leaves: 34,
    coordinates: [(6.5055430, 3.3617550), (6.5054122, 3.3621595)],
  ),
  // Pearse Street · https://www.openstreetmap.org/way/441860201
  (
    id: 'Walker 03',
    kind: VehicleKind.walker,
    enters: 5,
    leaves: 35,
    coordinates: [(6.5084673, 3.3677533), (6.5080744, 3.3678508)],
  ),
  // Awolowo Road · https://www.openstreetmap.org/way/138057964
  (
    id: 'Walker 04',
    kind: VehicleKind.walker,
    enters: 8,
    leaves: 37,
    coordinates: [
      (6.4979348, 3.3721599),
      (6.4979344, 3.3721577),
      (6.4979344, 3.3720343),
      (6.4979430, 3.3718277),
      (6.4979430, 3.3717709),
    ],
  ),
  // Olajuwon Street · https://www.openstreetmap.org/way/218440818
  (
    id: 'Maruwa 01',
    kind: VehicleKind.keke,
    enters: 0,
    leaves: 27,
    coordinates: [
      (6.5089926, 3.3683035),
      (6.5091871, 3.3682618),
      (6.5093339, 3.3682361),
      (6.5093871, 3.3682235),
      (6.5094720, 3.3682066),
      (6.5095335, 3.3682041),
      (6.5095993, 3.3682018),
      (6.5097367, 3.3682377),
      (6.5098667, 3.3682909),
      (6.5100499, 3.3683675),
    ],
  ),
  // Akintan Street · https://www.openstreetmap.org/way/90288384
  (
    id: 'Maruwa 02',
    kind: VehicleKind.keke,
    enters: 1,
    leaves: 30,
    coordinates: [
      (6.5087815, 3.3614439),
      (6.5084542, 3.3613778),
      (6.5080119, 3.3613021),
      (6.5075504, 3.3612265),
    ],
  ),
  // Ibukun Street · https://www.openstreetmap.org/way/106100740
  (
    id: 'Maruwa 03',
    kind: VehicleKind.keke,
    enters: 3,
    leaves: 36,
    coordinates: [
      (6.5038215, 3.3643181),
      (6.5036073, 3.3649489),
      (6.5033909, 3.3654629),
      (6.5033320, 3.3656404),
    ],
  ),
  // Tejuosho Avenue · https://www.openstreetmap.org/way/218716715
  (
    id: 'Maruwa 04',
    kind: VehicleKind.keke,
    enters: 5,
    leaves: 38,
    coordinates: [
      (6.5035102, 3.3695439),
      (6.5030058, 3.3695304),
      (6.5029299, 3.3695197),
      (6.5027859, 3.3695492),
      (6.5025834, 3.3696189),
      (6.5023649, 3.3697048),
      (6.5022688, 3.3697572),
    ],
  ),
  // Leigh Street · https://www.openstreetmap.org/way/218440820
  (
    id: 'Maruwa 05',
    kind: VehicleKind.keke,
    enters: 7,
    leaves: 39,
    coordinates: [
      (6.5102033, 3.3653111),
      (6.5105428, 3.3653730),
      (6.5107501, 3.3654173),
      (6.5108367, 3.3654495),
      (6.5108833, 3.3654696),
      (6.5108979, 3.3654944),
      (6.5108994, 3.3655185),
      (6.5108700, 3.3656010),
      (6.5107075, 3.3660168),
      (6.5106981, 3.3660449),
    ],
  ),
];

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/player.dart';

final Random _mosheRandom = Random();

class MosheTeamCalculator {
  static const int _defaultIterations = 120;

  static Future<List<List<Player>>> generateTeams(
    List<Player> players, {
    int? desiredTeamCount,
  }) async {
    if (players.isEmpty) {
      return [];
    }

    final working = List<Player>.from(players);
    final teamCount = desiredTeamCount ?? _resolveTeamCount(working.length);
    final capacities = _buildCapacities(working.length, teamCount);
    final metrics = _buildMetrics(working);
    final pairWeights = await _loadPairWeights();

    final baseline = List<_PlayerMetric>.from(metrics)
      ..sort((a, b) => b.power.compareTo(a.power));
    var bestAllocation = _assignTeams(baseline, capacities);
    var bestFitness = _evaluateFitness(bestAllocation, pairWeights);

    for (var i = 0; i < _defaultIterations; i++) {
      final shuffled = List<_PlayerMetric>.from(metrics);
      shuffled.shuffle(_mosheRandom);
      shuffled.sort((a, b) {
        final diff = b.power.compareTo(a.power);
        if (diff != 0) {
          return diff;
        }
        return _mosheRandom.nextInt(3) - 1; // tie-break randomness
      });

      final allocation = _assignTeams(shuffled, capacities);
      final fitness = _evaluateFitness(allocation, pairWeights);
      if (fitness > bestFitness) {
        bestFitness = fitness;
        bestAllocation = allocation;
      }
    }

    return bestAllocation
        .map((team) => team.members.map((m) => m.player).toList())
        .toList();
  }
}

class _PlayerMetric {
  _PlayerMetric({
    required this.player,
    required this.power,
    required this.position,
  });

  final Player player;
  final double power;
  final String? position;
}

class _TeamState {
  _TeamState({required this.capacity});

  final int capacity;
  final List<_PlayerMetric> members = [];
  final Map<String, int> positionCounts = {};
  double totalStrength = 0;

  bool get isFull => members.length >= capacity;

  void add(_PlayerMetric metric, String? normalizedPosition) {
    members.add(metric);
    totalStrength += metric.power;
    if (normalizedPosition != null) {
      positionCounts.update(normalizedPosition, (value) => value + 1, ifAbsent: () => 1);
    }
  }
}

const Map<String, int> _positionTargets = {
  'center': 1,
  'point guard': 1,
  'shooter': 1,
  'winger': 1,
};

const Map<String, String> _positionAliases = {
  'pg': 'point guard',
  'pointguard': 'point guard',
  'guard': 'point guard',
  'sg': 'shooter',
  'shooting guard': 'shooter',
  'sf': 'winger',
  'pf': 'center',
  'forward': 'winger',
  'center': 'center',
};

String? _normalizePosition(String? value) {
  if (value == null) {
    return null;
  }
  final lower = value.toLowerCase().trim();
  if (_positionTargets.containsKey(lower)) {
    return lower;
  }
  return _positionAliases[lower];
}

List<_TeamState> _assignTeams(List<_PlayerMetric> orderedPlayers, List<int> capacities) {
  final teams = List<_TeamState>.generate(
    capacities.length,
    (index) => _TeamState(capacity: capacities[index]),
  );

  for (final metric in orderedPlayers) {
    final teamIndex = _chooseTeam(teams, metric);
    final normalizedPosition = _normalizePosition(metric.position);
    teams[teamIndex].add(metric, normalizedPosition);
  }

  return teams;
}

int _chooseTeam(List<_TeamState> teams, _PlayerMetric metric) {
  final normalizedPosition = _normalizePosition(metric.position);

  int? selectedIndex;
  int bestNeed = -1;
  double bestStrength = double.infinity;

  for (var i = 0; i < teams.length; i++) {
    final team = teams[i];
    if (team.isFull) {
      continue;
    }

    final need = normalizedPosition == null
        ? 0
        : max(
            0,
            (_positionTargets[normalizedPosition] ?? 0) -
                (team.positionCounts[normalizedPosition] ?? 0),
          );

    if (need > bestNeed) {
      bestNeed = need;
      bestStrength = team.totalStrength;
      selectedIndex = i;
      } else if (need == bestNeed) {
      const double epsilon = 1e-6;
      if (team.totalStrength + epsilon < bestStrength) {
        bestStrength = team.totalStrength;
        selectedIndex = i;
      } else if ((team.totalStrength - bestStrength).abs() <= epsilon && _mosheRandom.nextBool()) {
        selectedIndex = i;
      }
    }
  }

  if (selectedIndex != null) {
    return selectedIndex;
  }

  var fallbackIndex = 0;
  double fallbackStrength = double.infinity;

  for (var i = 0; i < teams.length; i++) {
    final team = teams[i];
    if (!team.isFull && team.totalStrength < fallbackStrength) {
      fallbackStrength = team.totalStrength;
      fallbackIndex = i;
    }
  }

  return fallbackIndex;
}

double _evaluateFitness(List<_TeamState> allocation, Map<String, Map<String, double>> pairWeights) {
  if (allocation.isEmpty) {
    return 0;
  }

  final strengths = allocation.map((team) => team.totalStrength).toList();
  final totalStrength = strengths.fold<double>(0, (sum, value) => sum + value);
  final mean = totalStrength / strengths.length;

  double variance = 0;
  for (final strength in strengths) {
    final diff = strength - mean;
    variance += diff * diff;
  }
  variance /= strengths.length;

  final penalty = _calculatePairingPenalty(allocation, pairWeights);
  return -(variance * 0.6 + penalty * 0.4);
}

double _calculatePairingPenalty(
  List<_TeamState> allocation,
  Map<String, Map<String, double>> pairWeights,
) {
  double penalty = 0;
  for (final team in allocation) {
    final members = team.members;
    for (var i = 0; i < members.length; i++) {
      for (var j = i + 1; j < members.length; j++) {
        final a = members[i].player.username;
        final b = members[j].player.username;
        penalty += pairWeights[a]?[b] ?? pairWeights[b]?[a] ?? 0;
      }
    }
  }
  return penalty;
}

Map<String, Map<String, double>> _buildPairWeightMap(List<dynamic> history) {
  final map = <String, Map<String, double>>{};
  final now = DateTime.now();

  for (final entry in history) {
    if (entry is! Map<String, dynamic>) {
      continue;
    }
    final dateString = entry['date'];
    final teams = entry['teams'];
    if (dateString is! String || teams is! List) {
      continue;
    }

    final parsedDate = DateTime.tryParse(dateString);
    if (parsedDate == null) {
      continue;
    }

    final weeksAgo = now.difference(parsedDate).inDays / 7.0;
    final decayFactor = pow(0.8, weeksAgo).toDouble();
    if (decayFactor <= 0) {
      continue;
    }

    for (final team in teams) {
      if (team is! List) {
        continue;
      }
      final players = team.whereType<String>().toList();
      for (var i = 0; i < players.length; i++) {
        for (var j = i + 1; j < players.length; j++) {
          final a = players[i];
          final b = players[j];
          map.putIfAbsent(a, () => {});
          map[a]![b] = (map[a]?[b] ?? 0.0) + decayFactor;
          map.putIfAbsent(b, () => {});
          map[b]![a] = (map[b]?[a] ?? 0.0) + decayFactor;
        }
      }
    }
  }

  return map;
}

Future<Map<String, Map<String, double>>> _loadPairWeights() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('team_history');
    if (raw == null || raw.isEmpty) {
      return {};
    }
    final decoded = jsonDecode(raw);
    if (decoded is List<dynamic>) {
      return _buildPairWeightMap(decoded);
    }
    return {};
  } catch (_) {
    return {};
  }
}

const _attributeKeys = [
  'scoring',
  'threePt',
  'defense',
  'rebound',
  'playmaking',
  'speed',
  'height',
];

Map<String, double> _extractRawAttributes(Player player) {
  final height = player.height ?? 180.0;
  return {
    'playmaking': player.param1,
    'scoring': player.param2,
    'defense': player.param3,
    'speed': player.param4,
    'threePt': player.param5,
    'rebound': player.param6,
    'height': height,
  };
}

List<_PlayerMetric> _buildMetrics(List<Player> players) {
  final rawAttributeList = players.map(_extractRawAttributes).toList();
  final minValues = <String, double>{};
  final maxValues = <String, double>{};

  for (final key in _attributeKeys) {
    final values = rawAttributeList.map((attrs) => attrs[key] ?? 0.0).toList();
    minValues[key] = values.reduce(min);
    maxValues[key] = values.reduce(max);
  }

  final metrics = <_PlayerMetric>[];
  for (var i = 0; i < players.length; i++) {
    final player = players[i];
    final raw = rawAttributeList[i];
    final normalized = <String, double>{};
    for (final key in _attributeKeys) {
      normalized[key] = _normalize(raw[key] ?? 0.0, minValues[key]!, maxValues[key]!);
    }

    _applySpecialityBonuses(normalized, player.speciality);
    final power = _computeWeightedPower(normalized);

    metrics.add(
      _PlayerMetric(
        player: player,
        power: power,
        position: player.position,
      ),
    );
  }

  return metrics;
}

double _normalize(double value, double minValue, double maxValue) {
  if ((maxValue - minValue).abs() < 1e-6) {
    return 5.0;
  }
  final normalized = (value - minValue) / (maxValue - minValue);
  final clamped = normalized.clamp(0.0, 1.0);
  return (clamped as num).toDouble() * 10.0;
}

void _applySpecialityBonuses(Map<String, double> attributes, String? speciality) {
  if (speciality == null) {
    return;
  }
  final normalized = speciality.toLowerCase().trim();
  void boost(String key, double factor) {
    attributes[key] = (attributes[key] ?? 0) * factor;
    final clamped = attributes[key]!.clamp(0.0, 10.0);
    attributes[key] = (clamped as num).toDouble();
  }

  switch (normalized) {
    case 'passing':
      boost('playmaking', 1.10);
      break;
    case 'scoring':
      boost('scoring', 1.10);
      boost('threePt', 1.05);
      break;
    case 'clutch':
      boost('scoring', 1.08);
      boost('defense', 1.08);
      break;
    case 'lockdown defense':
      boost('defense', 1.15);
      break;
    default:
      break;
  }
}

double _computeWeightedPower(Map<String, double> attributes) {
  const weights = {
    'scoring': 1.0,
    'threePt': 0.9,
    'defense': 1.0,
    'rebound': 0.8,
    'playmaking': 0.9,
    'speed': 0.7,
    'height': 0.05,
  };

  double total = 0;
  weights.forEach((key, weight) {
    total += (attributes[key] ?? 0.0) * weight;
  });
  return total;
}

int _resolveTeamCount(int playerCount) {
  if (playerCount >= 9) {
    return 3;
  }
  if (playerCount >= 5) {
    return 2;
  }
  return 1;
}

List<int> _buildCapacities(int playerCount, int teamCount) {
  final base = playerCount ~/ teamCount;
  final remainder = playerCount % teamCount;
  return List<int>.generate(
    teamCount,
    (index) => base + (index < remainder ? 1 : 0),
  );
}

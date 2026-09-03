import 'dart:math';

import '../models/player.dart';

double computeTotalRanking(Player p) =>
    p.param1 + p.param2 + p.param3 + p.param4 + p.param5 + p.param6;

/// מחלק שלושה תפקידים (Play-Maker, Shooter, Rebounder) לקבוצות
/// כך שכל קבוצה מקבלת *בדיוק* שחקן אחד מתוך שלושת הראשונים בכל תפקיד,
/// ואחר-כך משלים עד 4 שחקנים ע״י איזון ממוצע הדרוג הכולל.
List<List<Player>> distributePlayersSmart(List<Player> players,
    {int numTeams = 3}) {
  if (numTeams != 3) {
    throw ArgumentError('האלגוריתם הנוכחי תומך בדיוק בשלוש קבוצות');
  }

  // עוזר לאתר שחקנים שכבר שובצו
  final assigned = <String>{};
  final teams = List.generate(numTeams, (_) => <Player>[]);

  // פונקציית עזר: מחזירה את n השחקנים הראשונים בתפקיד בלי כפילויות כלליות
  List<Player> topDistinct(
      double Function(Player) score, int n, Set<String> globalTaken) {
    final list = List<Player>.from(players)
      ..sort((a, b) => score(b).compareTo(score(a)));
    final out = <Player>[];
    for (final p in list) {
      if (!globalTaken.contains(p.username)) {
        out.add(p);
        globalTaken.add(p.username);
        if (out.length == n) break;
      }
    }
    return out;
  }

  // שלושת התפקידים
  final playMakers = topDistinct((p) => p.param1, 3, assigned);
  final shooters = topDistinct((p) => p.param2 + p.param5, 3, assigned);
  final rebounders = topDistinct((p) => p.param6, 3, assigned);

  // מיפוי סיבובי:
  //   • PlayMaker:   PM[0]→T0, PM[1]→T1, PM[2]→T2
  //   • Shooter:     SH[0]→T1, SH[1]→T2, SH[2]→T0
  //   • Rebounder:   REB[0]→T2, REB[1]→T0, REB[2]→T1
  void rotateAssign(List<Player> src, int offset) {
    for (var i = 0; i < src.length; i++) {
      final teamIdx = (i + offset) % numTeams;
      teams[teamIdx].add(src[i]);
    }
  }

  rotateAssign(playMakers, 0);
  rotateAssign(shooters, 1);
  rotateAssign(rebounders, 2);

  // שלב השלמה: ממיינים את כל מי שלא שובץ לפי דירוג כולל
  final unassigned = players
      .where((p) => !teams.any((t) => t.contains(p)))
      .toList()
    ..sort((a, b) => computeTotalRanking(b).compareTo(computeTotalRanking(a)));

  for (final p in unassigned) {
    // קבוצה עם ממוצע נמוך ביותר ושעדיין חסרה מקום (4 שחקנים)
    int best = -1;
    double minAvg = double.infinity;

    for (var i = 0; i < numTeams; i++) {
      if (teams[i].length >= 4) continue;
      final avg = teams[i].isEmpty
    ? 0.0
    : (teams[i].map(computeTotalRanking).reduce((a, b) => a + b) /
        teams[i].length).toDouble();

      if (avg < minAvg) {
        minAvg = avg;
        best = i;
      }
    }
    if (best != -1) teams[best].add(p);
  }

  return teams;
}

/// מחלק את השחקנים הנותרים (pool) לקבוצות הקיימות (currentTeams)
/// תוך ניסיון לאזן את הדירוג הכולל של הקבוצות.
/// מכבד את המיקומים הקיימים של שחקנים שכבר נמצאים בקבוצות.
List<List<Player>> distributePlayersWithConstraints(
    List<List<Player>> currentTeams,
    List<Player> pool,
    int maxPerTeam) {
  
  // יצירת עותק עמוק של הקבוצות כדי לא לשנות את המקור ישירות אם לא נרצה
  // אבל כאן אנחנו רוצים להחזיר רשימה חדשה
  List<List<Player>> newTeams = currentTeams.map((team) => List<Player>.from(team)).toList();
  
  // מיון השחקנים הפנויים מהחזק לחלש
  List<Player> sortedPool = List.from(pool)
    ..sort((a, b) => computeTotalRanking(b).compareTo(computeTotalRanking(a)));

  for (var player in sortedPool) {
    // מציאת הקבוצה עם הניקוד הכולל הנמוך ביותר שיש בה מקום
    int bestTeamIndex = -1;
    double minTotalScore = double.infinity;

    for (int i = 0; i < newTeams.length; i++) {
      if (newTeams[i].length >= maxPerTeam) continue;

      double currentScore = newTeams[i].fold(0.0, (sum, p) => sum + computeTotalRanking(p));
      
      // אנחנו רוצים להוסיף את השחקן החזק ביותר לקבוצה החלשה ביותר
      if (currentScore < minTotalScore) {
        minTotalScore = currentScore;
        bestTeamIndex = i;
      }
    }

    if (bestTeamIndex != -1) {
      newTeams[bestTeamIndex].add(player);
    } else {
      // אין מקום באף קבוצה (לא אמור לקרות אם החישובים נכונים)
      print('Warning: No space left for player ${player.username}');
    }
  }

  return newTeams;
}

/// שחקן שהאלגוריתם הציב (מותר להזיז בשלב הליטוש), עם אינדקס הקבוצה שלו.
class _PlacedPlayer {
  final Player player;
  int teamIndex;
  _PlacedPlayer(this.player, this.teamIndex);
}

/// מצב איזון "כוחות משלימים": מחלק את הבריכה (pool) לקבוצות הקיימות תוך איזון
/// של כל אחת משש הקטגוריות (param1..param6) *בנפרד*, במקום לסכם אותן למספר יחיד.
///
/// כך שחקן שמצטיין בקטגוריה אחת (ריבאונדר, רכז, קלע) מנותב לקבוצה שהכי חסרה
/// באותה קטגוריה, והחולשה שלו בשאר הקטגוריות לא "מורידה" אותו. מטופל באופן
/// אגנוסטי-לענף: המימדים מטופלים לפי מיקום ולא לפי שם, כך שזה עובד גם לכדורגל.
///
/// חתימה זהה ל-[distributePlayersWithConstraints] כדי שניתן יהיה להחליף ביניהן.
/// מכבד שחקנים שכבר הונחו ידנית בקבוצות (לא מזיז אותם).
List<List<Player>> distributePlayersByRoleCoverage(
    List<List<Player>> currentTeams,
    List<Player> pool,
    int maxPerTeam) {
  const int dims = 6;
  const double wTotal = 0.15; // משקל משני לחוזק הכולל, כדי שקבוצה לא תהיה מאוזנת-אך-חלשה

  double paramAt(Player p, int d) {
    switch (d) {
      case 0:
        return p.param1;
      case 1:
        return p.param2;
      case 2:
        return p.param3;
      case 3:
        return p.param4;
      case 4:
        return p.param5;
      default:
        return p.param6;
    }
  }

  // עותק עמוק, כדי לא לשנות את המקור ולשמר את מי שכבר בקבוצות.
  final List<List<Player>> newTeams =
      currentTeams.map((team) => List<Player>.from(team)).toList();

  if (pool.isEmpty || newTeams.isEmpty) return newTeams;

  // איחוד כל השחקנים הרלוונטיים (בריכה + מי שכבר בקבוצות) לצורך נרמול.
  final List<Player> all = [
    ...pool,
    for (final team in newTeams) ...team,
  ];

  // נרמול min-max לכל מימד לטווח 0..10 (מימד מנוון -> 5.0 נייטרלי).
  final List<double> minD = List.filled(dims, double.infinity);
  final List<double> maxD = List.filled(dims, -double.infinity);
  for (final p in all) {
    for (int d = 0; d < dims; d++) {
      final v = paramAt(p, d);
      if (v < minD[d]) minD[d] = v;
      if (v > maxD[d]) maxD[d] = v;
    }
  }
  double normalize(double v, int d) {
    final range = maxD[d] - minD[d];
    if (range.abs() < 1e-6) return 5.0;
    final t = ((v - minD[d]) / range).clamp(0.0, 1.0);
    return t * 10.0;
  }

  // וקטור מנורמל לכל שחקן (לפי username).
  final Map<String, List<double>> vec = {};
  for (final p in all) {
    vec[p.username] = [
      for (int d = 0; d < dims; d++) normalize(paramAt(p, d), d)
    ];
  }

  // מצברי קבוצות, נזרעים מהחברים הקיימים (כך שהנחות ידניות נכללות בחוסרים).
  final List<List<double>> teamVec =
      List.generate(newTeams.length, (_) => List.filled(dims, 0.0));
  final List<double> teamTotal = List.filled(newTeams.length, 0.0);
  for (int t = 0; t < newTeams.length; t++) {
    for (final m in newTeams[t]) {
      final mv = vec[m.username]!;
      for (int d = 0; d < dims; d++) {
        teamVec[t][d] += mv[d];
        teamTotal[t] += mv[d];
      }
    }
  }

  final rng = Random();

  // מיון הבריכה מהחזק לחלש (לפי סכום מנורמל).
  double normSum(Player p) => vec[p.username]!.fold(0.0, (a, b) => a + b);
  final List<Player> sortedPool = List.from(pool)
    ..sort((a, b) => normSum(b).compareTo(normSum(a)));

  final List<_PlacedPlayer> added = [];

  // --- שלב 1: הצבה חמדנית לפי חוסר פר-קטגוריה ---
  for (final player in sortedPool) {
    final pv = vec[player.username]!;

    // חישוב colMax לכל מימד ו-maxTotal על פני כל הקבוצות.
    final List<double> colMax = List.filled(dims, 0.0);
    double maxTotal = 0.0;
    for (int t = 0; t < newTeams.length; t++) {
      for (int d = 0; d < dims; d++) {
        if (teamVec[t][d] > colMax[d]) colMax[d] = teamVec[t][d];
      }
      if (teamTotal[t] > maxTotal) maxTotal = teamTotal[t];
    }

    // מגבלת גודל שווה: ממלאים שכבה-אחר-שכבה. מציבים רק בקבוצות שגודלן הנוכחי
    // שווה למינימום מבין הקבוצות שעדיין יש בהן מקום. כך ההפרש בגדלים לא עולה על 1.
    int minLen = 1 << 30;
    for (int t = 0; t < newTeams.length; t++) {
      if (newTeams[t].length >= maxPerTeam) continue;
      if (newTeams[t].length < minLen) minLen = newTeams[t].length;
    }

    int bestTeam = -1;
    double bestScore = -double.infinity;
    for (int t = 0; t < newTeams.length; t++) {
      if (newTeams[t].length >= maxPerTeam) continue;
      if (newTeams[t].length != minLen) continue;

      double needScore = 0.0;
      for (int d = 0; d < dims; d++) {
        final relNeed = colMax[d] - teamVec[t][d]; // >= 0
        needScore += pv[d] * relNeed;
      }
      final score = needScore + wTotal * (maxTotal - teamTotal[t]);

      if (score > bestScore + 1e-9) {
        bestScore = score;
        bestTeam = t;
      } else if (bestTeam != -1 && (score - bestScore).abs() <= 1e-9) {
        // שובר-שוויון: קבוצה עם חוזק כולל נמוך יותר, ואז אקראי.
        if (teamTotal[t] < teamTotal[bestTeam] - 1e-9) {
          bestTeam = t;
        } else if ((teamTotal[t] - teamTotal[bestTeam]).abs() <= 1e-9 &&
            rng.nextBool()) {
          bestTeam = t;
        }
      }
    }

    if (bestTeam == -1) {
      // אין מקום באף קבוצה - התנהגות זהה למצב הסכום.
      print('Warning: No space left for player ${player.username}');
      continue;
    }

    newTeams[bestTeam].add(player);
    added.add(_PlacedPlayer(player, bestTeam));
    for (int d = 0; d < dims; d++) {
      teamVec[bestTeam][d] += pv[d];
      teamTotal[bestTeam] += pv[d];
    }
  }

  // --- שלב 2: ליטוש (hill-climb חסום) - מחליף רק שחקנים שהאלגוריתם הוסיף ---
  double fitness() {
    final n = newTeams.length;
    if (n == 0) return 0.0;
    double f = 0.0;
    for (int d = 0; d < dims; d++) {
      double mean = 0.0;
      for (int t = 0; t < n; t++) {
        mean += teamVec[t][d];
      }
      mean /= n;
      double variance = 0.0;
      for (int t = 0; t < n; t++) {
        final diff = teamVec[t][d] - mean;
        variance += diff * diff;
      }
      f += variance / n;
    }
    double meanTotal = 0.0;
    for (int t = 0; t < n; t++) {
      meanTotal += teamTotal[t];
    }
    meanTotal /= n;
    double varTotal = 0.0;
    for (int t = 0; t < n; t++) {
      final diff = teamTotal[t] - meanTotal;
      varTotal += diff * diff;
    }
    return f + wTotal * (varTotal / n);
  }

  if (added.length >= 2) {
    final int budget = min(200, added.length * added.length);
    for (int iter = 0; iter < budget; iter++) {
      final a = added[rng.nextInt(added.length)];
      final b = added[rng.nextInt(added.length)];
      if (a.teamIndex == b.teamIndex) continue;

      final av = vec[a.player.username]!;
      final bv = vec[b.player.username]!;
      final aSum = av.fold(0.0, (s, x) => s + x);
      final bSum = bv.fold(0.0, (s, x) => s + x);

      final before = fitness();
      // החלפה זמנית במצברים.
      for (int d = 0; d < dims; d++) {
        teamVec[a.teamIndex][d] += bv[d] - av[d];
        teamVec[b.teamIndex][d] += av[d] - bv[d];
      }
      teamTotal[a.teamIndex] += bSum - aSum;
      teamTotal[b.teamIndex] += aSum - bSum;
      final after = fitness();

      if (after < before - 1e-9) {
        // מקבלים את ההחלפה - מעדכנים גם את הרשימות ואת האינדקסים.
        newTeams[a.teamIndex].remove(a.player);
        newTeams[b.teamIndex].remove(b.player);
        newTeams[a.teamIndex].add(b.player);
        newTeams[b.teamIndex].add(a.player);
        final tmp = a.teamIndex;
        a.teamIndex = b.teamIndex;
        b.teamIndex = tmp;
      } else {
        // דוחים - מחזירים את המצברים.
        for (int d = 0; d < dims; d++) {
          teamVec[a.teamIndex][d] -= bv[d] - av[d];
          teamVec[b.teamIndex][d] -= av[d] - bv[d];
        }
        teamTotal[a.teamIndex] -= bSum - aSum;
        teamTotal[b.teamIndex] -= aSum - bSum;
      }
    }
  }

  return newTeams;
}

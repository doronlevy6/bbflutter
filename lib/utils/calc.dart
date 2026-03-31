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

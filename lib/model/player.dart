// הקוד הבא נכתב משמאל לימין

class Player {
  String username;
  double param1; // היה: skillLevel
  double param2; // היה: scoringAbility
  double param3; // היה: defensiveSkills
  double param4; // היה: speedAndAgility
  double param5; // היה: shootingRange
  double param6; // היה: reboundSkills

  Player({
    required this.username,
    required this.param1,
    required this.param2,
    required this.param3,
    required this.param4,
    required this.param5,
    required this.param6,
  });

  // UPDATED: עדכון המיפוי לנתונים עם המפתחות החדשים (param1 ... param6)
  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      username: json['username'],
      param1: double.parse(json['param1']),
      param2: double.parse(json['param2']),
      param3: double.parse(json['param3']),
      param4: double.parse(json['param4']),
      param5: double.parse(json['param5']),
      param6: double.parse(json['param6']),
    );
  }

  // UPDATED: המרת האובייקט חזרה למפה עם המפתחות החדשים (param1 ... param6)
  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'param1': param1.toString(),
      'param2': param2.toString(),
      'param3': param3.toString(),
      'param4': param4.toString(),
      'param5': param5.toString(),
      'param6': param6.toString(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Player && runtimeType == other.runtimeType && username == other.username;

  @override
  int get hashCode => username.hashCode;
}

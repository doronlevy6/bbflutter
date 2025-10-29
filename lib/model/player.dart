// הקוד הבא נכתב משמאל לימין

double _parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value == null) return defaultValue;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? defaultValue;
}

String? _parseString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

class Player {
  String username;
  double param1; // היה: skillLevel
  double param2; // היה: scoringAbility
  double param3; // היה: defensiveSkills
  double param4; // היה: speedAndAgility
  double param5; // היה: shootingRange
  double param6; // היה: reboundSkills
  double? height; // סנטימטרים, אופציונלי
  String? position; // Center, Point Guard, Shooter, Winger
  String? speciality; // Passing, Scoring, Clutch, Lockdown Defense

  Player({
    required this.username,
    required this.param1,
    required this.param2,
    required this.param3,
    required this.param4,
    required this.param5,
    required this.param6,
    this.height,
    this.position,
    this.speciality,
  });

  // UPDATED: עדכון המיפוי לנתונים עם המפתחות החדשים (param1 ... param6)
  factory Player.fromJson(Map<String, dynamic> json) {
    final positionValue = json['position'] ?? json['Position'];
    final specialityValue = json['speciality'] ?? json['specialty'];
    return Player(
      username: json['username'],
      param1: _parseDouble(json['param1']),
      param2: _parseDouble(json['param2']),
      param3: _parseDouble(json['param3']),
      param4: _parseDouble(json['param4']),
      param5: _parseDouble(json['param5']),
      param6: _parseDouble(json['param6']),
      height: json.containsKey('height') ? _parseDouble(json['height'], defaultValue: 180.0) : null,
      position: _parseString(positionValue),
      speciality: _parseString(specialityValue),
    );
  }

  // UPDATED: המרת האובייקט חזרה למפה עם המפתחות החדשים (param1 ... param6)
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'username': username,
      'param1': param1.toString(),
      'param2': param2.toString(),
      'param3': param3.toString(),
      'param4': param4.toString(),
      'param5': param5.toString(),
      'param6': param6.toString(),
    };
    if (height != null) {
      map['height'] = height.toString();
    }
    if (position != null) {
      map['position'] = position;
    }
    if (speciality != null) {
      map['speciality'] = speciality;
    }
    return map;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Player && runtimeType == other.runtimeType && username == other.username;

  @override
  int get hashCode => username.hashCode;
}

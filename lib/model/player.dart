class Player {
  String username;
   double skillLevel;
   double scoringAbility;
   double defensiveSkills;
   double speedAndAgility;
   double shootingRange;
   double reboundSkills;

  Player({
    required this.username,
    required this.skillLevel,
    required this.scoringAbility,
    required this.defensiveSkills,
    required this.speedAndAgility,
    required this.shootingRange,
    required this.reboundSkills,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      username: json['username'],
      skillLevel: double.parse(json['skill_level']),
      scoringAbility: double.parse(json['scoring_ability']),
      defensiveSkills: double.parse(json['defensive_skills']),
      speedAndAgility: double.parse(json['speed_and_agility']),
      shootingRange: double.parse(json['shooting_range']),
      reboundSkills: double.parse(json['rebound_skills']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'skill_level': skillLevel.toString(),
      'scoring_ability': scoringAbility.toString(),
      'defensive_skills': defensiveSkills.toString(),
      'speed_and_agility': speedAndAgility.toString(),
      'shooting_range': shootingRange.toString(),
      'rebound_skills': reboundSkills.toString(),
    };
  }
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Player && runtimeType == other.runtimeType && username == other.username;

  @override
  int get hashCode => username.hashCode;

}

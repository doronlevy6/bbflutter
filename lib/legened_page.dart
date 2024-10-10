import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Legend extends StatelessWidget {
  // Define the legend items
  final List<Map<String, dynamic>> legendItems = [
    {'icon': Icons.handshake, 'label': 'play maker'},
    {'icon': Icons.score, 'label': 'Scoring Ability'},
    {'icon': Icons.shield, 'label': 'Defensive Skills'},
    {'icon': Icons.speed, 'label': 'Speed & Agility'},
    {'icon': Icons.sports_basketball, 'label': 'Shooting Range'},
    {'icon': Icons.grain, 'label': 'Rebound Skills'},
    {'icon': Icons.calculate, 'label': 'Team Average'},
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green[50],
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10), // Slightly smaller radius
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.0), // Reduced padding
        child: Wrap(
          spacing: 12, // Reduced spacing
          runSpacing: 8, // Reduced run spacing
          children: legendItems.map((item) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item['icon'],
                  color: Colors.green[700],
                  size: 16, // Smaller icon
                ),
                SizedBox(width: 4), // Reduced spacing
                Text(
                  item['label'],
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.bold, // Made text bolder
                    fontSize: 12, // Smaller font
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// lib/widgets/icon_button_with_label.dart

import 'package:flutter/material.dart';

class IconButtonWithLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const IconButtonWithLabel({
    Key? key,
    required this.icon,
    required this.label,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Using InkWell for ripple effect on tap
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8), // Rounded corners
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 30, // Adjust icon size as needed
            color: Colors.green[700],
          ),
          SizedBox(height: 4), // Spacing between icon and label
          Text(
            label,
            style: TextStyle(
              fontSize: 12, // Smaller font for labels
              color: Colors.green[700],
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DrawPage extends StatefulWidget {
  @override
  State<DrawPage> createState() => _DrawPageState();
}

class _DrawPageState extends State<DrawPage> {
  final Random _random = Random();

  bool _isHebrew = true;
  bool _isAdmin = false;
  bool _isLoading = true;
  bool _isWheel1Spinning = false;
  bool _isWheel2Spinning = false;

  List<String> _wheel1Options = ['1', '2', '3'];
  int? _outsideIndex;
  int? _ballIndex;

  double _wheel1Turns = 0.0;
  double _wheel2Turns = 0.0;

  static const Duration _spinDuration = Duration(milliseconds: 3200);

  List<String> get _wheel2Options {
    if (_outsideIndex == null || _outsideIndex! < 0 || _outsideIndex! >= _wheel1Options.length) {
      return [];
    }
    final outside = _wheel1Options[_outsideIndex!];
    return _wheel1Options.where((option) => option != outside).toList();
  }

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  Future<void> _initializePage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isHebrew = prefs.getBool('isHebrew') ?? true;
      _isAdmin = prefs.getBool('is_admin') ?? false;
      _isLoading = false;
    });
  }

  double _computeTargetTurns(double currentTurns, int selectedIndex, int segmentsCount) {
    final landingFraction = (1 - ((selectedIndex + 0.5) / segmentsCount)) % 1;
    final currentFraction = currentTurns % 1;
    final deltaFraction = (landingFraction - currentFraction + 1) % 1;
    final extraTurns = 4 + _random.nextInt(3);
    return currentTurns + extraTurns + deltaFraction;
  }

  Future<void> _spinWheel1() async {
    if (_isWheel1Spinning || _wheel1Options.length < 2) return;

    final selected = _random.nextInt(_wheel1Options.length);
    final targetTurns = _computeTargetTurns(_wheel1Turns, selected, _wheel1Options.length);

    setState(() {
      _isWheel1Spinning = true;
      _outsideIndex = null;
      _ballIndex = null;
      _wheel2Turns = 0.0;
      _wheel1Turns = targetTurns;
    });

    await Future.delayed(_spinDuration);
    if (!mounted) return;

    setState(() {
      _outsideIndex = selected;
      _isWheel1Spinning = false;
    });
  }

  Future<void> _spinWheel2() async {
    final options = _wheel2Options;
    if (_isWheel2Spinning || _outsideIndex == null || options.isEmpty) return;

    final selected = _random.nextInt(options.length);
    final targetTurns = _computeTargetTurns(_wheel2Turns, selected, options.length);

    setState(() {
      _isWheel2Spinning = true;
      _ballIndex = null;
      _wheel2Turns = targetTurns;
    });

    await Future.delayed(_spinDuration);
    if (!mounted) return;

    setState(() {
      _ballIndex = selected;
      _isWheel2Spinning = false;
    });
  }

  void _resetDraw() {
    setState(() {
      _outsideIndex = null;
      _ballIndex = null;
      _wheel1Turns = 0.0;
      _wheel2Turns = 0.0;
      _isWheel1Spinning = false;
      _isWheel2Spinning = false;
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openHiddenSettings() async {
    if (!_isAdmin) return;

    final textController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(_isHebrew ? 'הגדרות גלגל 1' : 'Wheel 1 Settings'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isHebrew
                            ? 'הוספה/מחיקה של אפשרויות לגלגל הראשון (לוקלי בלבד)'
                            : 'Add/remove first wheel options (local only)',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: textController,
                        decoration: InputDecoration(
                          labelText: _isHebrew ? 'אפשרות חדשה' : 'New option',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            final newOption = textController.text.trim();
                            if (newOption.isEmpty) {
                              _showSnack(_isHebrew ? 'יש להזין טקסט אפשרות' : 'Option text is required');
                              return;
                            }
                            final exists = _wheel1Options.any((e) => e.toLowerCase() == newOption.toLowerCase());
                            if (exists) {
                              _showSnack(_isHebrew ? 'האפשרות כבר קיימת' : 'Option already exists');
                              return;
                            }
                            setState(() {
                              _wheel1Options = [..._wheel1Options, newOption];
                              _outsideIndex = null;
                              _ballIndex = null;
                              _wheel1Turns = 0.0;
                              _wheel2Turns = 0.0;
                            });
                            textController.clear();
                            setDialogState(() {});
                          },
                          child: Text(_isHebrew ? 'הוסף אפשרות' : 'Add Option'),
                        ),
                      ),
                      SizedBox(height: 12),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        itemCount: _wheel1Options.length,
                        itemBuilder: (context, index) {
                          final option = _wheel1Options[index];
                          final canDelete = _wheel1Options.length > 2;
                          return Card(
                            child: ListTile(
                              dense: true,
                              title: Text(option),
                              subtitle: Text('${_isHebrew ? 'מיקום' : 'Position'}: ${index + 1}'),
                              trailing: IconButton(
                                icon: Icon(Icons.delete, color: canDelete ? Colors.red : Colors.grey),
                                onPressed: canDelete
                                    ? () {
                                        setState(() {
                                          _wheel1Options = [..._wheel1Options]..removeAt(index);
                                          _outsideIndex = null;
                                          _ballIndex = null;
                                          _wheel1Turns = 0.0;
                                          _wheel2Turns = 0.0;
                                        });
                                        setDialogState(() {});
                                      }
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(_isHebrew ? 'סגור' : 'Close'),
                ),
              ],
            );
          },
        );
      },
    );

    textController.dispose();
  }

  Widget _buildWheelCard({
    required String title,
    required List<String> options,
    required double turns,
    required bool isSpinning,
    required String spinLabel,
    required VoidCallback? onSpin,
    required String resultLabel,
    required String resultValue,
  }) {
    final disabled = options.isEmpty || onSpin == null;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            SizedBox(
              width: 280,
              height: 290,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: 0,
                    child: Icon(
                      Icons.arrow_drop_down,
                      size: 48,
                      color: Colors.red[700],
                    ),
                  ),
                  Positioned(
                    top: 20,
                    child: SizedBox(
                      width: 260,
                      height: 260,
                      child: AnimatedRotation(
                        turns: turns,
                        duration: _spinDuration,
                        curve: Curves.easeOutCubic,
                        child: CustomPaint(
                          painter: _WheelPainter(options: options),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: disabled || isSpinning ? null : onSpin,
              icon: Icon(Icons.casino),
              label: Text(spinLabel),
            ),
            SizedBox(height: 8),
            Text(
              '$resultLabel: $resultValue',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isHebrew ? 'הגרלת כדורסל' : 'Basketball Draw';
    final subtitle = _isHebrew ? 'הגרלה הוגנת עם הסתברות שווה לכל אפשרות' : 'Fair draw with equal probability';
    final wheel1Title = _isHebrew ? 'הקבוצה שבחוץ' : 'Team Out';
    final wheel2Title = _isHebrew ? 'כדור + חולצות' : 'Ball + Shirts';
    final spinText = _isHebrew ? 'סובב' : 'Spin';
    final waitingText = _isHebrew ? 'ממתין לסיבוב גלגל 1' : 'Waiting for wheel 1';

    final wheel1Result = (_outsideIndex != null && _outsideIndex! < _wheel1Options.length)
        ? _wheel1Options[_outsideIndex!]
        : (_isHebrew ? 'טרם נבחר' : 'Not selected yet');

    final wheel2Options = _wheel2Options;
    final wheel2Result = (_ballIndex != null && _ballIndex! < wheel2Options.length)
        ? wheel2Options[_ballIndex!]
        : (_isHebrew ? 'טרם נבחר' : 'Not selected yet');

    return Directionality(
      textDirection: _isHebrew ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/reka.webp'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.60), BlendMode.dstATop),
          ),
        ),
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onLongPress: _isAdmin ? _openHiddenSettings : null,
                        child: Text(
                          title,
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 15, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildWheelCard(
                            title: wheel1Title,
                            options: _wheel1Options,
                            turns: _wheel1Turns,
                            isSpinning: _isWheel1Spinning,
                            spinLabel: '$spinText 1',
                            onSpin: _wheel1Options.length >= 2 ? () => _spinWheel1() : null,
                            resultLabel: wheel1Title,
                            resultValue: wheel1Result,
                          ),
                          _buildWheelCard(
                            title: wheel2Title,
                            options: wheel2Options,
                            turns: _wheel2Turns,
                            isSpinning: _isWheel2Spinning,
                            spinLabel: '$spinText 2',
                            onSpin: (_outsideIndex != null && wheel2Options.isNotEmpty) ? () => _spinWheel2() : null,
                            resultLabel: wheel2Title,
                            resultValue: _outsideIndex == null ? waitingText : wheel2Result,
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _resetDraw,
                        icon: Icon(Icons.refresh),
                        label: Text(_isHebrew ? 'איפוס הגרלה' : 'Reset Draw'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final List<String> options;

  _WheelPainter({required this.options});

  static const List<Color> _palette = [
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFFEF6C00),
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFFC62828),
    Color(0xFF283593),
    Color(0xFFAD1457),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 4;

    if (options.isEmpty) {
      final paint = Paint()..color = Colors.grey.shade400;
      canvas.drawCircle(center, radius, paint);
      return;
    }

    final segmentSweep = (2 * pi) / options.length;
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 0; i < options.length; i += 1) {
      final startAngle = -pi / 2 + (i * segmentSweep);
      final fillPaint = Paint()
        ..color = _palette[i % _palette.length]
        ..style = PaintingStyle.fill;

      canvas.drawArc(arcRect, startAngle, segmentSweep, true, fillPaint);
      canvas.drawArc(arcRect, startAngle, segmentSweep, true, borderPaint);

      final midAngle = startAngle + (segmentSweep / 2);
      final labelOffset = Offset(
        center.dx + cos(midAngle) * radius * 0.62,
        center.dy + sin(midAngle) * radius * 0.62,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: options[i],
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: max(11, 18 - options.length.toDouble()),
          ),
        ),
        textDirection: TextDirection.rtl,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: radius * 0.55);

      canvas.save();
      canvas.translate(labelOffset.dx, labelOffset.dy);
      canvas.rotate(midAngle + pi / 2);
      textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
      canvas.restore();
    }

    final hubPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius * 0.12, hubPaint);
    canvas.drawCircle(
      center,
      radius * 0.12,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) {
    if (oldDelegate.options.length != options.length) return true;
    for (int i = 0; i < options.length; i += 1) {
      if (oldDelegate.options[i] != options[i]) return true;
    }
    return false;
  }
}

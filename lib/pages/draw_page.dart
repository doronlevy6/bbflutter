import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DrawPage extends StatefulWidget {
  @override
  State<DrawPage> createState() => _DrawPageState();
}

class _DrawPageState extends State<DrawPage> {
  final Random _random = Random();

  bool _isHebrew = true;
  bool _isLoading = true;
  bool _isWheel1Spinning = false;
  bool _isWheel2Spinning = false;
  bool _enableSecondDraw = true;

  List<String> _wheel1Options = ['1', '2', '3'];
  int? _outsideIndex;
  int? _ballIndex;

  double _wheel1Turns = 0.0;
  double _wheel2Turns = 0.0;

  String _pageTitle = '';
  String _pageSubtitle = '';
  String _wheel1Title = '';
  String _wheel2Title = '';
  int _spinSessionId = 0;

  static const Duration _spinDuration = Duration(milliseconds: 3200);

  ButtonStyle _primaryButtonStyle(BuildContext context) {
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.green[700],
      foregroundColor: Colors.white,
      disabledBackgroundColor: Colors.grey[400],
      disabledForegroundColor: Colors.white70,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
  }

  String _defaultPageTitle(bool isHebrew) =>
      isHebrew ? 'הגרלת כדורסל' : 'Basketball Draw';

  String _defaultPageSubtitle(bool isHebrew) => isHebrew
      ? 'הגרלה הוגנת עם הסתברות שווה לכל אפשרות'
      : 'Fair draw with equal probability';

  String _defaultWheel1Title(bool isHebrew) =>
      isHebrew ? 'הקבוצה שבחוץ' : 'Team Out';

  String _defaultWheel2Title(bool isHebrew) =>
      isHebrew ? 'כדור + חולצות' : 'Ball + Shirts';

  List<int> get _wheel2Indexes {
    if (_outsideIndex == null ||
        _outsideIndex! < 0 ||
        _outsideIndex! >= _wheel1Options.length) {
      return [];
    }

    return List<int>.generate(_wheel1Options.length, (i) => i)
        .where((index) => index != _outsideIndex)
        .toList();
  }

  List<String> get _wheel2Options =>
      _wheel2Indexes.map((index) => _wheel1Options[index]).toList();

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  Future<void> _initializePage() async {
    final prefs = await SharedPreferences.getInstance();
    final isHebrew = prefs.getBool('isHebrew') ?? true;

    if (!mounted) return;

    setState(() {
      _isHebrew = isHebrew;
      _pageTitle = _defaultPageTitle(isHebrew);
      _pageSubtitle = _defaultPageSubtitle(isHebrew);
      _wheel1Title = _defaultWheel1Title(isHebrew);
      _wheel2Title = _defaultWheel2Title(isHebrew);
      _isLoading = false;
    });
  }

  double _computeTargetTurns(
      double currentTurns, int selectedIndex, int segmentsCount) {
    final landingFraction = (1 - ((selectedIndex + 0.5) / segmentsCount)) % 1;
    final currentFraction = currentTurns % 1;
    final deltaFraction = (landingFraction - currentFraction + 1) % 1;
    final extraTurns = 4 + _random.nextInt(3);
    return currentTurns + extraTurns + deltaFraction;
  }

  void _resetDraw() {
    setState(() {
      _spinSessionId += 1;
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

  String _probabilityText(int count) {
    if (count <= 0) return _isHebrew ? 'אין אפשרויות' : 'No options';
    if (count == 1)
      return _isHebrew
          ? '100% לכל האפשרות היחידה'
          : '100% for the single option';

    final percent = (100 / count).toStringAsFixed(2);
    return _isHebrew
        ? 'סיכוי שווה: 1/$count (${percent}%) לכל אפשרות'
        : 'Equal chance: 1/$count (${percent}%) per option';
  }

  String _outsideResultText() {
    if (_outsideIndex == null ||
        _outsideIndex! < 0 ||
        _outsideIndex! >= _wheel1Options.length) {
      return _isHebrew ? 'טרם נבחר' : 'Not selected yet';
    }
    return _wheel1Options[_outsideIndex!];
  }

  String _secondResultText() {
    if (_ballIndex == null ||
        _ballIndex! < 0 ||
        _ballIndex! >= _wheel1Options.length) {
      return _isHebrew ? 'טרם נבחר' : 'Not selected yet';
    }
    return _wheel1Options[_ballIndex!];
  }

  Future<void> _showFinalResultsDialog() async {
    if (!mounted || _outsideIndex == null) return;

    final firstResult = _outsideResultText();
    final hasSecondResult = _enableSecondDraw && _ballIndex != null;
    final secondResult = hasSecondResult ? _secondResultText() : null;

    final messageLines = <String>[
      '${_wheel1Title.trim()}: $firstResult',
      if (secondResult != null) '${_wheel2Title.trim()}: $secondResult',
    ];

    final summaryText = messageLines.join('\n');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.emoji_events, color: Colors.amber[700]),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isHebrew ? 'תוצאות ההגרלה' : 'Draw Results',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Container(
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summaryText,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
                ),
                SizedBox(height: 8),
                Text(
                  _isHebrew
                      ? 'לחץ על העתק כדי להדביק ישירות בוואטסאפ.'
                      : 'Tap copy and paste directly to WhatsApp.',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_isHebrew ? 'סגור' : 'Close'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: summaryText));
                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.pop(dialogContext);
                }
                _showSnack(
                  _isHebrew
                      ? 'התוצאות הועתקו. אפשר להדביק בוואטסאפ.'
                      : 'Results copied. You can paste them in WhatsApp.',
                );
              },
              icon: Icon(Icons.copy),
              label: Text(_isHebrew ? 'העתק תוצאות' : 'Copy Results'),
              style: _primaryButtonStyle(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> _spinWheel1() async {
    if (_isWheel1Spinning || _wheel1Options.length < 2) return;

    final sessionId = ++_spinSessionId;
    final selected = _random.nextInt(_wheel1Options.length);
    final targetTurns =
        _computeTargetTurns(_wheel1Turns, selected, _wheel1Options.length);

    setState(() {
      _isWheel1Spinning = true;
      _outsideIndex = null;
      _ballIndex = null;
      _wheel2Turns = 0.0;
      _wheel1Turns = targetTurns;
    });

    await Future.delayed(_spinDuration);
    if (!mounted || sessionId != _spinSessionId) return;

    setState(() {
      _outsideIndex = selected;
      _isWheel1Spinning = false;
    });

    if (!_enableSecondDraw) {
      await _showFinalResultsDialog();
    }
  }

  Future<void> _spinWheel2() async {
    final optionsIndexes = _wheel2Indexes;
    if (_isWheel2Spinning || _outsideIndex == null || optionsIndexes.isEmpty)
      return;

    final sessionId = ++_spinSessionId;
    final selectedPosition = _random.nextInt(optionsIndexes.length);
    final selectedIndex = optionsIndexes[selectedPosition];
    final targetTurns = _computeTargetTurns(
        _wheel2Turns, selectedPosition, optionsIndexes.length);

    setState(() {
      _isWheel2Spinning = true;
      _ballIndex = null;
      _wheel2Turns = targetTurns;
    });

    await Future.delayed(_spinDuration);
    if (!mounted || sessionId != _spinSessionId) return;

    setState(() {
      _ballIndex = selectedIndex;
      _isWheel2Spinning = false;
    });

    await _showFinalResultsDialog();
  }

  Future<void> _openSettings() async {
    final titleController = TextEditingController(text: _pageTitle);
    final subtitleController = TextEditingController(text: _pageSubtitle);
    final wheel1TitleController = TextEditingController(text: _wheel1Title);
    final wheel2TitleController = TextEditingController(text: _wheel2Title);
    final optionControllers = _wheel1Options
        .map((option) => TextEditingController(text: option))
        .toList();

    bool localEnableSecondDraw = _enableSecondDraw;

    String defaultOptionName(int index) =>
        _isHebrew ? 'קבוצה ${index + 1}' : 'Team ${index + 1}';

    void syncToCount(int targetCount) {
      while (optionControllers.length < targetCount) {
        optionControllers.add(TextEditingController(
            text: defaultOptionName(optionControllers.length)));
      }
      while (optionControllers.length > targetCount) {
        final controller = optionControllers.removeLast();
        controller.dispose();
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(_isHebrew ? 'הגדרות הגרלה' : 'Draw Settings'),
              content: SizedBox(
                width: min(
                  520,
                  MediaQuery.of(dialogContext).size.width - 32,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: _isHebrew ? 'כותרת ראשית' : 'Main title',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: subtitleController,
                        decoration: InputDecoration(
                          labelText: _isHebrew ? 'כותרת משנה' : 'Subtitle',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: wheel1TitleController,
                        decoration: InputDecoration(
                          labelText:
                              _isHebrew ? 'שם הגרלה 1' : 'First draw name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: wheel2TitleController,
                        decoration: InputDecoration(
                          labelText:
                              _isHebrew ? 'שם הגרלה 2' : 'Second draw name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_isHebrew
                            ? 'להפעיל הגרלה שנייה'
                            : 'Enable second draw'),
                        subtitle: Text(
                          _isHebrew
                              ? 'אם כבוי - מבוצעת רק הגרלה ראשונה.'
                              : 'If off, only the first draw is used.',
                        ),
                        value: localEnableSecondDraw,
                        onChanged: (value) {
                          setDialogState(() {
                            localEnableSecondDraw = value;
                          });
                        },
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _isHebrew
                                  ? 'מספר קבוצות / אפשרויות'
                                  : 'Number of teams / options',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            onPressed: optionControllers.length > 2
                                ? () {
                                    setDialogState(() {
                                      syncToCount(optionControllers.length - 1);
                                    });
                                  }
                                : null,
                            icon: Icon(Icons.remove_circle_outline),
                          ),
                          Text('${optionControllers.length}',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(
                            onPressed: () {
                              setDialogState(() {
                                syncToCount(optionControllers.length + 1);
                              });
                            },
                            icon: Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      Text(
                        _isHebrew
                            ? 'כל אפשרות בגלגל מקבלת סיכוי שווה לחלוטין.'
                            : 'Every option gets an exactly equal chance on each wheel.',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      SizedBox(height: 10),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        itemCount: optionControllers.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextField(
                              controller: optionControllers[index],
                              decoration: InputDecoration(
                                labelText: _isHebrew
                                    ? 'שם קבוצה ${index + 1}'
                                    : 'Team name ${index + 1}',
                                border: OutlineInputBorder(),
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
                  child: Text(_isHebrew ? 'ביטול' : 'Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final titleText = titleController.text.trim();
                    final subtitleText = subtitleController.text.trim();
                    final wheel1Text = wheel1TitleController.text.trim();
                    final wheel2Text = wheel2TitleController.text.trim();

                    final options = optionControllers
                        .map((controller) => controller.text.trim())
                        .where((text) => text.isNotEmpty)
                        .toList();

                    if (options.length < 2) {
                      _showSnack(_isHebrew
                          ? 'נדרשות לפחות 2 אפשרויות תקינות'
                          : 'At least 2 valid options are required');
                      return;
                    }
                    final normalizedOptions =
                        options.map((name) => name.toLowerCase()).toList();
                    if (normalizedOptions.toSet().length !=
                        normalizedOptions.length) {
                      _showSnack(_isHebrew
                          ? 'יש שמות כפולים. לכל קבוצה חייב להיות שם ייחודי.'
                          : 'Duplicate names found. Each team must have a unique name.');
                      return;
                    }

                    setState(() {
                      _spinSessionId += 1;
                      _pageTitle = titleText.isEmpty
                          ? _defaultPageTitle(_isHebrew)
                          : titleText;
                      _pageSubtitle = subtitleText.isEmpty
                          ? _defaultPageSubtitle(_isHebrew)
                          : subtitleText;
                      _wheel1Title = wheel1Text.isEmpty
                          ? _defaultWheel1Title(_isHebrew)
                          : wheel1Text;
                      _wheel2Title = wheel2Text.isEmpty
                          ? _defaultWheel2Title(_isHebrew)
                          : wheel2Text;
                      _enableSecondDraw = localEnableSecondDraw;
                      _wheel1Options = options;

                      _outsideIndex = null;
                      _ballIndex = null;
                      _wheel1Turns = 0.0;
                      _wheel2Turns = 0.0;
                      _isWheel1Spinning = false;
                      _isWheel2Spinning = false;
                    });

                    Navigator.pop(dialogContext);
                  },
                  child: Text(_isHebrew ? 'שמור' : 'Save'),
                  style: _primaryButtonStyle(context),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    subtitleController.dispose();
    wheel1TitleController.dispose();
    wheel2TitleController.dispose();
    for (final controller in optionControllers) {
      controller.dispose();
    }
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
    required String probabilityLabel,
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
            SizedBox(height: 6),
            Text(
              probabilityLabel,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.black54, fontWeight: FontWeight.w500),
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
                          painter: _WheelPainter(
                              options: options, isHebrew: _isHebrew),
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
              style: _primaryButtonStyle(context),
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
    final spinText = _isHebrew ? 'סובב' : 'Spin';
    final waitingText =
        _isHebrew ? 'ממתין לסיבוב גלגל 1' : 'Waiting for wheel 1';

    final wheel1Result = _outsideResultText();
    final wheel2Result = _secondResultText();
    final wheel2Options = _wheel2Options;

    return Directionality(
      textDirection: _isHebrew ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/reka.webp'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.60), BlendMode.dstATop),
          ),
        ),
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              _pageTitle,
                              style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          IconButton(
                            tooltip: _isHebrew ? 'הגדרות' : 'Settings',
                            onPressed: _openSettings,
                            icon: Icon(Icons.tune, color: Colors.white),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        _pageSubtitle,
                        style: TextStyle(fontSize: 15, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        _isHebrew
                            ? 'הוגנות: הבחירה מתבצעת תמיד באקראיות אחידה (Uniform Random)'
                            : 'Fairness: selection always uses uniform random distribution',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildWheelCard(
                            title: _wheel1Title,
                            options: _wheel1Options,
                            turns: _wheel1Turns,
                            isSpinning: _isWheel1Spinning,
                            spinLabel: '$spinText 1',
                            onSpin: _wheel1Options.length >= 2
                                ? () => _spinWheel1()
                                : null,
                            resultLabel: _wheel1Title,
                            resultValue: wheel1Result,
                            probabilityLabel:
                                _probabilityText(_wheel1Options.length),
                          ),
                          if (_enableSecondDraw)
                            _buildWheelCard(
                              title: _wheel2Title,
                              options: wheel2Options,
                              turns: _wheel2Turns,
                              isSpinning: _isWheel2Spinning,
                              spinLabel: '$spinText 2',
                              onSpin: (_outsideIndex != null &&
                                      wheel2Options.isNotEmpty)
                                  ? () => _spinWheel2()
                                  : null,
                              resultLabel: _wheel2Title,
                              resultValue: _outsideIndex == null
                                  ? waitingText
                                  : wheel2Result,
                              probabilityLabel: _outsideIndex == null
                                  ? (_isHebrew
                                      ? 'יופיע אחרי סיבוב 1'
                                      : 'Appears after spin 1')
                                  : _probabilityText(wheel2Options.length),
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
  final bool isHebrew;

  _WheelPainter({required this.options, required this.isHebrew});

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
        textDirection: isHebrew ? TextDirection.rtl : TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: radius * 0.55);

      canvas.save();
      canvas.translate(labelOffset.dx, labelOffset.dy);
      canvas.rotate(midAngle + pi / 2);
      textPainter.paint(
          canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
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
    if (oldDelegate.isHebrew != isHebrew) return true;
    for (int i = 0; i < options.length; i += 1) {
      if (oldDelegate.options[i] != options[i]) return true;
    }
    return false;
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _CoachBoardTool {
  move,
  offenseMarker,
  defenseMarker,
  ballMarker,
  movementArrow,
  passArrow,
  dribbleArrow,
  eraser,
}

enum _CoachMarkerType { offense, defense, ball }

enum _CoachStrokeType { movement, pass, dribble }

class CoachBoardPage extends StatefulWidget {
  final bool fullscreen;
  final _CoachBoardBundle? initialBundle;
  final bool? isHebrewOverride;

  const CoachBoardPage({
    super.key,
    this.fullscreen = false,
    this.initialBundle,
    this.isHebrewOverride,
  });

  @override
  State<CoachBoardPage> createState() => _CoachBoardPageState();
}

class _CoachBoardPageState extends State<CoachBoardPage> {
  bool _isHebrew = true;
  bool _isLoading = true;

  _CoachBoardTool _selectedTool = _CoachBoardTool.move;

  final List<_CoachMarker> _markers = <_CoachMarker>[];
  final List<_CoachStroke> _strokes = <_CoachStroke>[];
  final List<_CoachBoardSnapshot> _undoStack = <_CoachBoardSnapshot>[];

  List<Offset> _activeStrokePoints = <Offset>[];
  _CoachStrokeType? _activeStrokeType;
  bool _isRefreshing = false;

  int? _draggingMarkerId;
  int _nextEntityId = 1;
  int _nextOffenseLabel = 1;
  int _nextDefenseLabel = 1;

  static const int _maxUndoSteps = 80;

  @override
  void initState() {
    super.initState();
    _initializePage();
    if (widget.fullscreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _enableImmersiveMode();
      });
    }
  }

  @override
  void dispose() {
    if (widget.fullscreen) {
      _disableImmersiveMode();
    }
    super.dispose();
  }

  Future<void> _initializePage() async {
    if (widget.initialBundle != null) {
      _restoreBundle(widget.initialBundle!);
      _isHebrew = widget.isHebrewOverride ?? _isHebrew;
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final hebrew =
        widget.isHebrewOverride ?? (prefs.getBool('isHebrew') ?? true);
    if (!mounted) return;
    setState(() {
      _isHebrew = hebrew;
      _isLoading = false;
    });
  }

  Future<void> _enableImmersiveMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _disableImmersiveMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _exitFullscreen() async {
    if (!widget.fullscreen) return;
    await _disableImmersiveMode();
    if (!mounted) return;
    Navigator.of(context).pop(_exportBundle());
  }

  Future<void> _openFullscreen() async {
    final result = await Navigator.of(context).push<_CoachBoardBundle>(
      MaterialPageRoute<_CoachBoardBundle>(
        builder: (_) => CoachBoardPage(
          fullscreen: true,
          initialBundle: _exportBundle(),
          isHebrewOverride: _isHebrew,
        ),
        fullscreenDialog: true,
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      _restoreBundle(result);
    });
  }

  _CoachBoardBundle _exportBundle() {
    return _CoachBoardBundle(
      selectedTool: _selectedTool,
      markers: _markers.map((marker) => marker.copy()).toList(),
      strokes: _strokes.map((stroke) => stroke.copy()).toList(),
      nextEntityId: _nextEntityId,
      nextOffenseLabel: _nextOffenseLabel,
      nextDefenseLabel: _nextDefenseLabel,
    );
  }

  void _restoreBundle(_CoachBoardBundle bundle) {
    _selectedTool = bundle.selectedTool;
    _markers
      ..clear()
      ..addAll(bundle.markers.map((marker) => marker.copy()));
    _strokes
      ..clear()
      ..addAll(bundle.strokes.map((stroke) => stroke.copy()));
    _nextEntityId = bundle.nextEntityId;
    _nextOffenseLabel = bundle.nextOffenseLabel;
    _nextDefenseLabel = bundle.nextDefenseLabel;
    _activeStrokePoints = <Offset>[];
    _activeStrokeType = null;
    _draggingMarkerId = null;
    _undoStack.clear();
  }

  void _pushSnapshotForUndo() {
    _undoStack.add(
      _CoachBoardSnapshot(
        markers: _markers.map((marker) => marker.copy()).toList(),
        strokes: _strokes.map((stroke) => stroke.copy()).toList(),
        nextEntityId: _nextEntityId,
        nextOffenseLabel: _nextOffenseLabel,
        nextDefenseLabel: _nextDefenseLabel,
      ),
    );
    if (_undoStack.length > _maxUndoSteps) {
      _undoStack.removeAt(0);
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final previous = _undoStack.removeLast();
    setState(() {
      _markers
        ..clear()
        ..addAll(previous.markers.map((marker) => marker.copy()));
      _strokes
        ..clear()
        ..addAll(previous.strokes.map((stroke) => stroke.copy()));
      _nextEntityId = previous.nextEntityId;
      _nextOffenseLabel = previous.nextOffenseLabel;
      _nextDefenseLabel = previous.nextDefenseLabel;
      _activeStrokePoints = <Offset>[];
      _activeStrokeType = null;
      _draggingMarkerId = null;
    });
  }

  void _clearBoard() {
    if (_markers.isEmpty && _strokes.isEmpty) return;
    _pushSnapshotForUndo();
    setState(() {
      _markers.clear();
      _strokes.clear();
      _activeStrokePoints.clear();
      _activeStrokeType = null;
      _draggingMarkerId = null;
      _nextOffenseLabel = 1;
      _nextDefenseLabel = 1;
    });
  }

  bool _isArrowTool(_CoachBoardTool tool) {
    return tool == _CoachBoardTool.movementArrow ||
        tool == _CoachBoardTool.passArrow ||
        tool == _CoachBoardTool.dribbleArrow;
  }

  _CoachStrokeType _toolToStrokeType(_CoachBoardTool tool) {
    switch (tool) {
      case _CoachBoardTool.passArrow:
        return _CoachStrokeType.pass;
      case _CoachBoardTool.dribbleArrow:
        return _CoachStrokeType.dribble;
      default:
        return _CoachStrokeType.movement;
    }
  }

  Offset _toNormalized(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) return const Offset(0.5, 0.5);
    final dx = (local.dx / size.width).clamp(0.0, 1.0);
    final dy = (local.dy / size.height).clamp(0.0, 1.0);
    return Offset(dx, dy);
  }

  Offset _toCanvas(Offset normalized, Size size) {
    return Offset(normalized.dx * size.width, normalized.dy * size.height);
  }

  Offset _safeMarkerPosition(Offset normalized) {
    return Offset(
      normalized.dx.clamp(0.03, 0.97),
      normalized.dy.clamp(0.03, 0.97),
    );
  }

  int? _hitMarkerId(Offset normalizedPoint, Size size) {
    for (int i = _markers.length - 1; i >= 0; i--) {
      final marker = _markers[i];
      final markerPoint = _toCanvas(marker.position, size);
      final touchPoint = _toCanvas(normalizedPoint, size);
      if ((markerPoint - touchPoint).distance <= 22) {
        return marker.id;
      }
    }
    return null;
  }

  int? _hitStrokeId(Offset normalizedPoint, Size size) {
    final point = _toCanvas(normalizedPoint, size);
    for (int i = _strokes.length - 1; i >= 0; i--) {
      final stroke = _strokes[i];
      if (stroke.points.length < 2) continue;
      for (int segment = 0; segment < stroke.points.length - 1; segment++) {
        final a = _toCanvas(stroke.points[segment], size);
        final b = _toCanvas(stroke.points[segment + 1], size);
        if (_distancePointToSegment(point, a, b) <= 14) {
          return stroke.id;
        }
      }
    }
    return null;
  }

  double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) return (p - a).distance;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
    final projection = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - projection).distance;
  }

  void _addMarker(Offset normalizedPoint, _CoachMarkerType type) {
    _pushSnapshotForUndo();

    String label = '';
    if (type == _CoachMarkerType.offense) {
      label = _nextOffenseLabel.toString();
      _nextOffenseLabel += 1;
    } else if (type == _CoachMarkerType.defense) {
      label = _nextDefenseLabel.toString();
      _nextDefenseLabel += 1;
    }

    setState(() {
      _markers.add(
        _CoachMarker(
          id: _nextEntityId++,
          type: type,
          position: _safeMarkerPosition(normalizedPoint),
          label: label,
        ),
      );
    });
  }

  void _eraseAt(Offset normalizedPoint, Size size) {
    final markerId = _hitMarkerId(normalizedPoint, size);
    if (markerId != null) {
      _pushSnapshotForUndo();
      setState(() {
        _markers.removeWhere((marker) => marker.id == markerId);
      });
      return;
    }

    final strokeId = _hitStrokeId(normalizedPoint, size);
    if (strokeId != null) {
      _pushSnapshotForUndo();
      setState(() {
        _strokes.removeWhere((stroke) => stroke.id == strokeId);
      });
    }
  }

  void _handleTap(Offset localPoint, Size size) {
    final normalizedPoint = _toNormalized(localPoint, size);

    switch (_selectedTool) {
      case _CoachBoardTool.offenseMarker:
        _addMarker(normalizedPoint, _CoachMarkerType.offense);
        return;
      case _CoachBoardTool.defenseMarker:
        _addMarker(normalizedPoint, _CoachMarkerType.defense);
        return;
      case _CoachBoardTool.ballMarker:
        _addMarker(normalizedPoint, _CoachMarkerType.ball);
        return;
      case _CoachBoardTool.eraser:
        _eraseAt(normalizedPoint, size);
        return;
      default:
        return;
    }
  }

  void _handlePanStart(Offset localPoint, Size size) {
    final normalized = _toNormalized(localPoint, size);

    if (_isArrowTool(_selectedTool)) {
      setState(() {
        _activeStrokeType = _toolToStrokeType(_selectedTool);
        _activeStrokePoints = <Offset>[normalized];
      });
      return;
    }

    if (_selectedTool == _CoachBoardTool.move) {
      final markerId = _hitMarkerId(normalized, size);
      if (markerId != null) {
        _pushSnapshotForUndo();
        setState(() {
          _draggingMarkerId = markerId;
        });
      }
      return;
    }

    if (_selectedTool == _CoachBoardTool.eraser) {
      _eraseAt(normalized, size);
    }
  }

  void _handlePanUpdate(Offset localPoint, Size size) {
    final normalized = _toNormalized(localPoint, size);

    if (_draggingMarkerId != null) {
      setState(() {
        final markerIndex =
            _markers.indexWhere((marker) => marker.id == _draggingMarkerId);
        if (markerIndex != -1) {
          _markers[markerIndex] = _markers[markerIndex]
              .copyWith(position: _safeMarkerPosition(normalized));
        }
      });
      return;
    }

    if (_activeStrokeType != null) {
      if (_activeStrokePoints.isEmpty) {
        setState(() {
          _activeStrokePoints = <Offset>[normalized];
        });
        return;
      }

      final lastPoint = _activeStrokePoints.last;
      if ((lastPoint - normalized).distance < 0.004) return;
      setState(() {
        _activeStrokePoints.add(normalized);
      });
    }
  }

  void _handlePanEnd() {
    if (_draggingMarkerId != null) {
      setState(() {
        _draggingMarkerId = null;
      });
      return;
    }

    if (_activeStrokeType != null && _activeStrokePoints.length >= 2) {
      _pushSnapshotForUndo();
      setState(() {
        _strokes.add(
          _CoachStroke(
            id: _nextEntityId++,
            type: _activeStrokeType!,
            points: List<Offset>.from(_activeStrokePoints),
          ),
        );
        _activeStrokePoints = <Offset>[];
        _activeStrokeType = null;
      });
      return;
    }

    if (_activeStrokeType != null) {
      setState(() {
        _activeStrokePoints = <Offset>[];
        _activeStrokeType = null;
      });
    }
  }

  String _toolLabel(_CoachBoardTool tool) {
    switch (tool) {
      case _CoachBoardTool.move:
        return _isHebrew ? 'הזזה' : 'Move';
      case _CoachBoardTool.offenseMarker:
        return _isHebrew ? 'שחקן התקפה' : 'Offense';
      case _CoachBoardTool.defenseMarker:
        return _isHebrew ? 'שחקן הגנה' : 'Defense';
      case _CoachBoardTool.ballMarker:
        return _isHebrew ? 'כדור' : 'Ball';
      case _CoachBoardTool.movementArrow:
        return _isHebrew ? 'חץ תנועה' : 'Move Arrow';
      case _CoachBoardTool.passArrow:
        return _isHebrew ? 'חץ מסירה' : 'Pass Arrow';
      case _CoachBoardTool.dribbleArrow:
        return _isHebrew ? 'חץ כדרור' : 'Dribble Arrow';
      case _CoachBoardTool.eraser:
        return _isHebrew ? 'מחק' : 'Erase';
    }
  }

  IconData _toolIcon(_CoachBoardTool tool) {
    switch (tool) {
      case _CoachBoardTool.move:
        return Icons.open_with;
      case _CoachBoardTool.offenseMarker:
        return Icons.sports;
      case _CoachBoardTool.defenseMarker:
        return Icons.shield;
      case _CoachBoardTool.ballMarker:
        return Icons.sports_basketball;
      case _CoachBoardTool.movementArrow:
        return Icons.trending_flat;
      case _CoachBoardTool.passArrow:
        return Icons.subdirectory_arrow_right;
      case _CoachBoardTool.dribbleArrow:
        return Icons.gesture;
      case _CoachBoardTool.eraser:
        return Icons.cleaning_services;
    }
  }

  Color _toolColor(_CoachBoardTool tool) {
    switch (tool) {
      case _CoachBoardTool.move:
        return const Color(0xFF37474F);
      case _CoachBoardTool.offenseMarker:
        return const Color(0xFF1565C0);
      case _CoachBoardTool.defenseMarker:
        return const Color(0xFFC62828);
      case _CoachBoardTool.ballMarker:
        return const Color(0xFFEF6C00);
      case _CoachBoardTool.movementArrow:
        return const Color(0xFF00695C);
      case _CoachBoardTool.passArrow:
        return const Color(0xFF6A1B9A);
      case _CoachBoardTool.dribbleArrow:
        return const Color(0xFFD84315);
      case _CoachBoardTool.eraser:
        return const Color(0xFF5D4037);
    }
  }

  Widget _buildToolButton(_CoachBoardTool tool) {
    final selected = _selectedTool == tool;
    final color = _toolColor(tool);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: selected ? color.withValues(alpha: 0.15) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _selectedTool = tool;
            });
          },
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? color : const Color(0xFFDCE0E5),
                width: selected ? 2 : 1,
              ),
            ),
            child: Icon(
              _toolIcon(tool),
              color: color,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, const Color(0xFFF4F7FB)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFE0E6EE)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.co_present, color: Colors.green.shade800, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isHebrew ? 'לוח מאמן' : 'Coach Board',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              if (_isRefreshing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed:
                    widget.fullscreen ? _exitFullscreen : _openFullscreen,
                icon: Icon(
                  widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  size: 18,
                ),
                label: Text(widget.fullscreen
                    ? (_isHebrew ? 'הקטן' : 'Exit')
                    : (_isHebrew ? 'פול סקרין' : 'Full Screen')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _CoachBoardTool.values.map(_buildToolButton).toList(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_isHebrew ? "כלי פעיל" : "Active Tool"}: ${_toolLabel(_selectedTool)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFE0E6EE)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _undoStack.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo, size: 18),
              label: Text(_isHebrew ? 'בטל' : 'Undo'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _clearBoard,
              icon: const Icon(Icons.layers_clear, size: 18),
              label: Text(_isHebrew ? 'נקה לוח' : 'Clear Board'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                setState(() {
                  _selectedTool = _CoachBoardTool.move;
                });
              },
              icon: const Icon(Icons.touch_app, size: 18),
              label: Text(_isHebrew ? 'מצב בחירה' : 'Select'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.clamp(10, double.infinity),
          constraints.maxHeight.clamp(10, double.infinity),
        );

        return MouseRegion(
          cursor: _selectedTool == _CoachBoardTool.move
              ? SystemMouseCursors.grab
              : SystemMouseCursors.precise,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTap(details.localPosition, size),
            onPanStart: (details) =>
                _handlePanStart(details.localPosition, size),
            onPanUpdate: (details) =>
                _handlePanUpdate(details.localPosition, size),
            onPanEnd: (_) => _handlePanEnd(),
            onPanCancel: _handlePanEnd,
            child: CustomPaint(
              painter: _CoachBoardPainter(
                markers: _markers,
                strokes: _strokes,
                activeStrokePoints: _activeStrokePoints,
                activeStrokeType: _activeStrokeType,
                isHebrew: _isHebrew,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildTopControls(),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCCD7E5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _buildBoardCanvas(),
          ),
        ),
        _buildBottomActions(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final scaffold = Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      body: SafeArea(
        child: _buildBody(),
      ),
    );

    if (!widget.fullscreen) {
      return scaffold;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _exitFullscreen();
      },
      child: scaffold,
    );
  }
}

class _CoachBoardPainter extends CustomPainter {
  final List<_CoachMarker> markers;
  final List<_CoachStroke> strokes;
  final List<Offset> activeStrokePoints;
  final _CoachStrokeType? activeStrokeType;
  final bool isHebrew;

  _CoachBoardPainter({
    required this.markers,
    required this.strokes,
    required this.activeStrokePoints,
    required this.activeStrokeType,
    required this.isHebrew,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintCourtBackground(canvas, size);

    for (final stroke in strokes) {
      _paintStroke(canvas, size, stroke.points, stroke.type, isDraft: false);
    }

    if (activeStrokeType != null && activeStrokePoints.length >= 2) {
      _paintStroke(canvas, size, activeStrokePoints, activeStrokeType!,
          isDraft: true);
    }

    for (final marker in markers) {
      _paintMarker(canvas, size, marker);
    }

    _paintLegend(canvas, size);
  }

  void _paintCourtBackground(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final courtRect = fullRect.deflate(10);

    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [
          Color(0xFF466C34),
          Color(0xFF355D2B),
          Color(0xFF2F5326),
        ],
      ).createShader(fullRect);
    canvas.drawRect(fullRect, bg);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    canvas.drawRect(courtRect, linePaint);

    // Half-court layout (single basket) for better clarity on small iPhone screens.
    final centerX = courtRect.center.dx;
    // Keep the basket very close to the top edge, like a real half-court board.
    final hoopCenter = Offset(centerX, courtRect.top + courtRect.height * 0.04);
    final hoopRadius = (courtRect.width * 0.015).clamp(5.5, 8.5);

    // Backboard is behind the rim (towards baseline/top), not towards court.
    final backboardY =
        (hoopCenter.dy - courtRect.height * 0.018).clamp(courtRect.top + 4, courtRect.bottom);
    final backboardHalf = courtRect.width * 0.052;
    canvas.drawLine(
      Offset(centerX - backboardHalf, backboardY),
      Offset(centerX + backboardHalf, backboardY),
      linePaint,
    );
    canvas.drawCircle(hoopCenter, hoopRadius, linePaint);

    final keyWidth = courtRect.width * 0.3;
    final keyHeight = courtRect.height * 0.5;
    final keyRect = Rect.fromCenter(
      center: Offset(centerX, courtRect.top + keyHeight / 2),
      width: keyWidth,
      height: keyHeight,
    );
    canvas.drawRect(keyRect, linePaint);

    final freeThrowCenter = Offset(centerX, keyRect.bottom);
    final freeThrowRadius = courtRect.width * 0.062;
    canvas.drawCircle(freeThrowCenter, freeThrowRadius, linePaint);

    final leftCornerX = courtRect.left + courtRect.width * 0.085;
    final rightCornerX = courtRect.right - courtRect.width * 0.085;

    // Mid-court indicator at the bottom edge of the visible half.
    final midRadius = math.min(courtRect.width, courtRect.height) * 0.12;

    // Keep the 3pt arc just a bit above the mid-court semicircle.
    final targetMidGap = midRadius + courtRect.height * 0.012;
    final arcRadius = (courtRect.bottom - hoopCenter.dy - targetMidGap)
        .clamp(courtRect.width * 0.42, courtRect.height * 0.86);
    final cornerDx = rightCornerX - centerX;
    final cornerDy =
        math.sqrt(math.max(0.0, arcRadius * arcRadius - cornerDx * cornerDx));
    final cornerTopY = (hoopCenter.dy + cornerDy).clamp(
      courtRect.top + courtRect.height * 0.22,
      courtRect.bottom - courtRect.height * 0.025,
    );

    canvas.drawLine(
      Offset(leftCornerX, courtRect.top),
      Offset(leftCornerX, cornerTopY),
      linePaint,
    );
    canvas.drawLine(
      Offset(rightCornerX, courtRect.top),
      Offset(rightCornerX, cornerTopY),
      linePaint,
    );

    final arcRect = Rect.fromCircle(center: hoopCenter, radius: arcRadius);
    final leftVector = Offset(leftCornerX - hoopCenter.dx, cornerTopY - hoopCenter.dy);
    final rightVector =
        Offset(rightCornerX - hoopCenter.dx, cornerTopY - hoopCenter.dy);
    final leftAngle = math.atan2(leftVector.dy, leftVector.dx);
    final rightAngle = math.atan2(rightVector.dy, rightVector.dx);
    canvas.drawArc(arcRect, rightAngle, leftAngle - rightAngle, false, linePaint);

    final midRect = Rect.fromCircle(
      center: Offset(centerX, courtRect.bottom),
      radius: midRadius,
    );
    canvas.drawArc(midRect, math.pi, math.pi, false, linePaint);
  }

  Color _strokeColor(_CoachStrokeType type, {required bool isDraft}) {
    final color = switch (type) {
      _CoachStrokeType.movement => const Color(0xFF29B6F6),
      _CoachStrokeType.pass => const Color(0xFFFFEB3B),
      _CoachStrokeType.dribble => const Color(0xFFFF7043),
    };
    return isDraft ? color.withValues(alpha: 0.65) : color;
  }

  Path _buildStrokePath(List<Offset> normalizedPoints, Size size) {
    final path = Path();
    if (normalizedPoints.isEmpty) return path;
    final first = Offset(
      normalizedPoints.first.dx * size.width,
      normalizedPoints.first.dy * size.height,
    );
    path.moveTo(first.dx, first.dy);
    for (int i = 1; i < normalizedPoints.length; i++) {
      final p = Offset(
        normalizedPoints[i].dx * size.width,
        normalizedPoints[i].dy * size.height,
      );
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  void _paintStroke(
    Canvas canvas,
    Size size,
    List<Offset> normalizedPoints,
    _CoachStrokeType type, {
    required bool isDraft,
  }) {
    if (normalizedPoints.length < 2) return;

    final path = _buildStrokePath(normalizedPoints, size);
    final color = _strokeColor(type, isDraft: isDraft);

    final basePaint = Paint()
      ..color = color
      ..strokeWidth = isDraft ? 2.5 : 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (type == _CoachStrokeType.movement) {
      canvas.drawPath(path, basePaint);
    } else if (type == _CoachStrokeType.pass) {
      _drawDashedPath(canvas, path, basePaint, dash: 12, gap: 7);
    } else {
      _drawDottedPath(canvas, path, color, radius: 2.2, gap: 9);
    }

    final a = normalizedPoints[normalizedPoints.length - 2];
    final b = normalizedPoints.last;
    final start = Offset(a.dx * size.width, a.dy * size.height);
    final end = Offset(b.dx * size.width, b.dy * size.height);
    _drawArrowHead(canvas, start, end, color);
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0, metric.length).toDouble();
        final extract = metric.extractPath(distance, end);
        canvas.drawPath(extract, paint);
        distance += dash + gap;
      }
    }
  }

  void _drawDottedPath(
    Canvas canvas,
    Path path,
    Color color, {
    required double radius,
    required double gap,
  }) {
    final dotPaint = Paint()..color = color;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final tangent = metric.getTangentForOffset(distance);
        if (tangent != null) {
          canvas.drawCircle(tangent.position, radius, dotPaint);
        }
        distance += gap;
      }
    }
  }

  void _drawArrowHead(Canvas canvas, Offset start, Offset end, Color color) {
    final direction = end - start;
    if (direction.distance < 1) return;
    final unit = direction / direction.distance;
    const arrowLength = 14.0;
    const spread = 0.55;

    final left = Offset(
      end.dx -
          arrowLength *
              (unit.dx * math.cos(spread) - unit.dy * math.sin(spread)),
      end.dy -
          arrowLength *
              (unit.dx * math.sin(spread) + unit.dy * math.cos(spread)),
    );
    final right = Offset(
      end.dx -
          arrowLength *
              (unit.dx * math.cos(-spread) - unit.dy * math.sin(-spread)),
      end.dy -
          arrowLength *
              (unit.dx * math.sin(-spread) + unit.dy * math.cos(-spread)),
    );

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(end, left, paint);
    canvas.drawLine(end, right, paint);
  }

  void _paintMarker(Canvas canvas, Size size, _CoachMarker marker) {
    final center = Offset(
        marker.position.dx * size.width, marker.position.dy * size.height);

    if (marker.type == _CoachMarkerType.ball) {
      final fill = Paint()..color = const Color(0xFFFF9800);
      final seam = Paint()
        ..color = const Color(0xFF5D4037)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, 13, fill);
      canvas.drawCircle(center, 13, seam);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 9),
        -math.pi / 2,
        math.pi,
        false,
        seam,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 9),
        math.pi / 2,
        math.pi,
        false,
        seam,
      );
      canvas.drawLine(
        Offset(center.dx - 13, center.dy),
        Offset(center.dx + 13, center.dy),
        seam,
      );
      return;
    }

    final baseColor = marker.type == _CoachMarkerType.offense
        ? const Color(0xFF1565C0)
        : const Color(0xFFC62828);

    final fill = Paint()..color = baseColor;
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(center, 16, fill);
    canvas.drawCircle(center, 16, border);

    final prefix = marker.type == _CoachMarkerType.offense ? 'O' : 'X';
    final text = '$prefix${marker.label}';
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2,
          center.dy - textPainter.height / 2),
    );
  }

  void _paintLegend(Canvas canvas, Size size) {
    final caption = isHebrew
        ? 'O = התקפה, X = הגנה, כתום = כדור'
        : 'O = offense, X = defense, orange = ball';
    final textPainter = TextPainter(
      text: TextSpan(
        text: caption,
        style: TextStyle(
          fontSize: 11.5,
          color: Colors.white.withValues(alpha: 0.88),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 24);

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        10,
        size.height - textPainter.height - 14,
        textPainter.width + 12,
        textPainter.height + 6,
      ),
      const Radius.circular(8),
    );
    final bg = Paint()..color = Colors.black.withValues(alpha: 0.2);
    canvas.drawRRect(bgRect, bg);
    textPainter.paint(
      canvas,
      Offset(16, size.height - textPainter.height - 11),
    );
  }

  @override
  bool shouldRepaint(covariant _CoachBoardPainter oldDelegate) {
    return oldDelegate.markers != markers ||
        oldDelegate.strokes != strokes ||
        oldDelegate.activeStrokePoints != activeStrokePoints ||
        oldDelegate.activeStrokeType != activeStrokeType ||
        oldDelegate.isHebrew != isHebrew;
  }
}

class _CoachMarker {
  final int id;
  final _CoachMarkerType type;
  final Offset position;
  final String label;

  _CoachMarker({
    required this.id,
    required this.type,
    required this.position,
    required this.label,
  });

  _CoachMarker copy() {
    return _CoachMarker(
      id: id,
      type: type,
      position: Offset(position.dx, position.dy),
      label: label,
    );
  }

  _CoachMarker copyWith({Offset? position}) {
    return _CoachMarker(
      id: id,
      type: type,
      position: position ?? this.position,
      label: label,
    );
  }
}

class _CoachStroke {
  final int id;
  final _CoachStrokeType type;
  final List<Offset> points;

  _CoachStroke({
    required this.id,
    required this.type,
    required this.points,
  });

  _CoachStroke copy() {
    return _CoachStroke(
      id: id,
      type: type,
      points: points.map((point) => Offset(point.dx, point.dy)).toList(),
    );
  }
}

class _CoachBoardSnapshot {
  final List<_CoachMarker> markers;
  final List<_CoachStroke> strokes;
  final int nextEntityId;
  final int nextOffenseLabel;
  final int nextDefenseLabel;

  _CoachBoardSnapshot({
    required this.markers,
    required this.strokes,
    required this.nextEntityId,
    required this.nextOffenseLabel,
    required this.nextDefenseLabel,
  });
}

class _CoachBoardBundle {
  final _CoachBoardTool selectedTool;
  final List<_CoachMarker> markers;
  final List<_CoachStroke> strokes;
  final int nextEntityId;
  final int nextOffenseLabel;
  final int nextDefenseLabel;

  _CoachBoardBundle({
    required this.selectedTool,
    required this.markers,
    required this.strokes,
    required this.nextEntityId,
    required this.nextOffenseLabel,
    required this.nextDefenseLabel,
  });
}

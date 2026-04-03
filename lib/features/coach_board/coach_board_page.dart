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
  _CoachQuickPlayTemplate? _infoPlay;
  Offset _infoPanelOffset = const Offset(12, 140);

  int? _draggingMarkerId;
  int _nextEntityId = 1;
  int _nextOffenseLabel = 1;
  int _nextDefenseLabel = 1;

  static const int _maxUndoSteps = 80;
  static const double _markerDragHitRadius = 30.0;
  static const List<_CoachQuickPlayTemplate> _quickPlayTemplates =
      <_CoachQuickPlayTemplate>[
    _CoachQuickPlayTemplate(
      id: 'give_go',
      labelHe: 'גיב אנד גו',
      labelEn: 'Give & Go',
      descriptionHe:
          '1) מוביל הכדור מוסר לאגף.\n2) מיד חותך חזק לסל.\n3) האגף מחזיר מסירה לחיתוך.',
      descriptionEn:
          '1) Ball handler passes to wing.\n2) Immediately cuts hard to the rim.\n3) Wing returns the pass to the cutter.',
      markers: <_CoachQuickMarker>[
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.50, 0.82)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.72, 0.68)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.28, 0.68)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.50, 0.54)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.50, 0.75)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.72, 0.60)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.28, 0.60)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.50, 0.46)),
        _CoachQuickMarker(_CoachMarkerType.ball, Offset(0.50, 0.82)),
      ],
      strokes: <_CoachQuickStroke>[
        _CoachQuickStroke(_CoachStrokeType.pass, <Offset>[
          Offset(0.50, 0.82),
          Offset(0.72, 0.68),
        ]),
        _CoachQuickStroke(_CoachStrokeType.movement, <Offset>[
          Offset(0.50, 0.82),
          Offset(0.58, 0.63),
          Offset(0.54, 0.23),
        ]),
        _CoachQuickStroke(_CoachStrokeType.movement, <Offset>[
          Offset(0.50, 0.54),
          Offset(0.45, 0.75),
        ]),
      ],
    ),
    _CoachQuickPlayTemplate(
      id: 'pick_roll',
      labelHe: 'פיק אנד רול',
      labelEn: 'Pick & Roll',
      descriptionHe:
          '1) הגבוה מציב חסימה למוביל.\n2) המוביל חודר סביב החסימה.\n3) הגבוה מתגלגל לסל לקבלת מסירה.',
      descriptionEn:
          '1) Big sets a screen for the ball handler.\n2) Handler drives off the screen.\n3) Big rolls to the basket for a pass.',
      markers: <_CoachQuickMarker>[
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.50, 0.81)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.58, 0.64)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.26, 0.71)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.76, 0.71)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.50, 0.74)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.58, 0.56)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.26, 0.64)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.76, 0.64)),
        _CoachQuickMarker(_CoachMarkerType.ball, Offset(0.50, 0.81)),
      ],
      strokes: <_CoachQuickStroke>[
        _CoachQuickStroke(_CoachStrokeType.dribble, <Offset>[
          Offset(0.50, 0.81),
          Offset(0.57, 0.73),
          Offset(0.64, 0.62),
        ]),
        _CoachQuickStroke(_CoachStrokeType.movement, <Offset>[
          Offset(0.58, 0.64),
          Offset(0.54, 0.50),
          Offset(0.52, 0.30),
        ]),
        _CoachQuickStroke(_CoachStrokeType.pass, <Offset>[
          Offset(0.64, 0.62),
          Offset(0.52, 0.30),
        ]),
      ],
    ),
    _CoachQuickPlayTemplate(
      id: 'backdoor',
      labelHe: 'בק דור',
      labelEn: 'Backdoor',
      descriptionHe:
          '1) שחקן אגף עושה הטעיה לקבל כדור החוצה.\n2) חותך מאחורי ההגנה לסל.\n3) מוביל הכדור מוסר ללייאפ קל.',
      descriptionEn:
          '1) Wing fakes high to receive.\n2) Cuts backdoor behind defense.\n3) Ball handler feeds for an easy layup.',
      markers: <_CoachQuickMarker>[
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.50, 0.82)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.72, 0.69)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.28, 0.69)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.50, 0.57)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.50, 0.75)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.70, 0.63)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.30, 0.62)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.50, 0.48)),
        _CoachQuickMarker(_CoachMarkerType.ball, Offset(0.50, 0.82)),
      ],
      strokes: <_CoachQuickStroke>[
        _CoachQuickStroke(_CoachStrokeType.movement, <Offset>[
          Offset(0.72, 0.69),
          Offset(0.62, 0.54),
          Offset(0.54, 0.22),
        ]),
        _CoachQuickStroke(_CoachStrokeType.pass, <Offset>[
          Offset(0.50, 0.82),
          Offset(0.54, 0.22),
        ]),
        _CoachQuickStroke(_CoachStrokeType.dribble, <Offset>[
          Offset(0.50, 0.82),
          Offset(0.45, 0.77),
        ]),
      ],
    ),
    _CoachQuickPlayTemplate(
      id: 'drive_kick',
      labelHe: 'דרייב וקיק',
      labelEn: 'Drive & Kick',
      descriptionHe:
          '1) מוביל הכדור חודר פנימה.\n2) ההגנה סוגרת עליו.\n3) מסירה החוצה לקלע הפנוי באגף.',
      descriptionEn:
          '1) Ball handler drives into the lane.\n2) Defense collapses.\n3) Kick out pass to the open wing shooter.',
      markers: <_CoachQuickMarker>[
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.50, 0.82)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.74, 0.67)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.26, 0.67)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.46, 0.44)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.50, 0.75)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.72, 0.60)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.28, 0.60)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.50, 0.37)),
        _CoachQuickMarker(_CoachMarkerType.ball, Offset(0.50, 0.82)),
      ],
      strokes: <_CoachQuickStroke>[
        _CoachQuickStroke(_CoachStrokeType.dribble, <Offset>[
          Offset(0.50, 0.82),
          Offset(0.51, 0.68),
          Offset(0.53, 0.55),
        ]),
        _CoachQuickStroke(_CoachStrokeType.pass, <Offset>[
          Offset(0.53, 0.55),
          Offset(0.74, 0.67),
        ]),
        _CoachQuickStroke(_CoachStrokeType.movement, <Offset>[
          Offset(0.26, 0.67),
          Offset(0.18, 0.56),
        ]),
      ],
    ),
    _CoachQuickPlayTemplate(
      id: 'high_low',
      labelHe: 'היי לו',
      labelEn: 'High-Low',
      descriptionHe:
          '1) הכדור נכנס לגבוה בעמדה גבוהה.\n2) השחקן בצבע משיג מיקום עמוק.\n3) מסירה גבוהה-נמוכה לסיום ליד הטבעת.',
      descriptionEn:
          '1) Enter to the high post.\n2) Low player seals deep.\n3) High-to-low pass for a finish near the rim.',
      markers: <_CoachQuickMarker>[
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.50, 0.82)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.50, 0.59)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.42, 0.37)),
        _CoachQuickMarker(_CoachMarkerType.offense, Offset(0.74, 0.70)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.50, 0.75)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.50, 0.52)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.44, 0.31)),
        _CoachQuickMarker(_CoachMarkerType.defense, Offset(0.72, 0.62)),
        _CoachQuickMarker(_CoachMarkerType.ball, Offset(0.50, 0.82)),
      ],
      strokes: <_CoachQuickStroke>[
        _CoachQuickStroke(_CoachStrokeType.pass, <Offset>[
          Offset(0.50, 0.82),
          Offset(0.50, 0.59),
        ]),
        _CoachQuickStroke(_CoachStrokeType.movement, <Offset>[
          Offset(0.42, 0.37),
          Offset(0.48, 0.25),
        ]),
        _CoachQuickStroke(_CoachStrokeType.pass, <Offset>[
          Offset(0.50, 0.59),
          Offset(0.48, 0.25),
        ]),
      ],
    ),
  ];

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
      if ((markerPoint - touchPoint).distance <= _markerDragHitRadius) {
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

  String _toolShortLabel(_CoachBoardTool tool) {
    switch (tool) {
      case _CoachBoardTool.move:
        return _isHebrew ? 'בחירה' : 'Select';
      case _CoachBoardTool.offenseMarker:
        return _isHebrew ? 'התקפה' : 'Offense';
      case _CoachBoardTool.defenseMarker:
        return _isHebrew ? 'הגנה' : 'Defense';
      case _CoachBoardTool.ballMarker:
        return _isHebrew ? 'כדור' : 'Ball';
      case _CoachBoardTool.movementArrow:
        return _isHebrew ? 'ריצה' : 'Cut';
      case _CoachBoardTool.passArrow:
        return _isHebrew ? 'מסירה' : 'Pass';
      case _CoachBoardTool.dribbleArrow:
        return _isHebrew ? 'כדרור' : 'Dribble';
      case _CoachBoardTool.eraser:
        return _isHebrew ? 'מחק' : 'Erase';
    }
  }

  String _quickPlayLabel(_CoachQuickPlayTemplate play) {
    // Play names are always shown in English for consistency.
    return play.labelEn;
  }

  String _quickPlayDescription(_CoachQuickPlayTemplate play) {
    return _isHebrew ? play.descriptionHe : play.descriptionEn;
  }

  double _infoPanelWidth(Size viewport) {
    return (viewport.width * 0.56).clamp(220.0, 330.0);
  }

  double _infoPanelHeight(Size viewport) {
    return (viewport.height * 0.34).clamp(160.0, 250.0);
  }

  Offset _clampInfoPanelOffset(Offset offset, Size viewport) {
    final panelWidth = _infoPanelWidth(viewport);
    final panelHeight = _infoPanelHeight(viewport);
    const minX = 8.0;
    const minY = 90.0;
    final maxX = math.max(minX, viewport.width - panelWidth - 8);
    final maxY = math.max(minY, viewport.height - panelHeight - 8);
    return Offset(
      offset.dx.clamp(minX, maxX),
      offset.dy.clamp(minY, maxY),
    );
  }

  void _openQuickPlayInfo(_CoachQuickPlayTemplate play) {
    final viewport = MediaQuery.sizeOf(context);
    final panelWidth = _infoPanelWidth(viewport);
    final defaultOffset = Offset(viewport.width - panelWidth - 10, 128);
    final baseOffset = _infoPlay == null ? defaultOffset : _infoPanelOffset;
    setState(() {
      _infoPlay = play;
      _infoPanelOffset = _clampInfoPanelOffset(baseOffset, viewport);
    });
  }

  Widget _buildQuickPlayInfoPanel(Size viewport) {
    final play = _infoPlay;
    if (play == null) {
      return const SizedBox.shrink();
    }

    final panelWidth = _infoPanelWidth(viewport);
    final panelHeight = _infoPanelHeight(viewport);
    final panelOffset = _clampInfoPanelOffset(_infoPanelOffset, viewport);
    final textDirection = _isHebrew ? TextDirection.rtl : TextDirection.ltr;

    return Positioned(
      left: panelOffset.dx,
      top: panelOffset.dy,
      child: SizedBox(
        width: panelWidth,
        height: panelHeight,
        child: Directionality(
          textDirection: textDirection,
          child: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: 0.96),
            child: Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) {},
                  onPanUpdate: (details) {
                    setState(() {
                      _infoPanelOffset = _clampInfoPanelOffset(
                        _infoPanelOffset + details.delta,
                        viewport,
                      );
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE0E6EE)),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.drag_indicator, size: 18, color: Colors.black54),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _quickPlayLabel(play),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isHebrew ? 'גרור' : 'Drag',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _infoPlay = null;
                            });
                          },
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: _isHebrew ? 'סגור הסבר' : 'Close info',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Text(
                      _quickPlayDescription(play),
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _applyQuickPlay(_CoachQuickPlayTemplate play) {
    if (_markers.isNotEmpty || _strokes.isNotEmpty) {
      _pushSnapshotForUndo();
    }

    int offenseLabel = 1;
    int defenseLabel = 1;
    final markers = <_CoachMarker>[];
    final strokes = <_CoachStroke>[];

    for (final marker in play.markers) {
      String label = '';
      if (marker.type == _CoachMarkerType.offense) {
        label = '${offenseLabel++}';
      } else if (marker.type == _CoachMarkerType.defense) {
        label = '${defenseLabel++}';
      }

      markers.add(
        _CoachMarker(
          id: markers.length + 1,
          type: marker.type,
          position: _safeMarkerPosition(marker.position),
          label: label,
        ),
      );
    }

    for (final stroke in play.strokes) {
      if (stroke.points.length < 2) continue;
      strokes.add(
        _CoachStroke(
          id: markers.length + strokes.length + 1,
          type: stroke.type,
          points: stroke.points
              .map((point) => _safeMarkerPosition(point))
              .toList(growable: false),
        ),
      );
    }

    setState(() {
      _markers
        ..clear()
        ..addAll(markers);
      _strokes
        ..clear()
        ..addAll(strokes);
      _activeStrokePoints = <Offset>[];
      _activeStrokeType = null;
      _draggingMarkerId = null;
      _selectedTool = _CoachBoardTool.move;
      _nextEntityId = markers.length + strokes.length + 1;
      _nextOffenseLabel = offenseLabel;
      _nextDefenseLabel = defenseLabel;
    });

    final text = _isHebrew
        ? 'נטען תרגיל: ${play.labelEn}'
        : 'Loaded play: ${play.labelEn}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  Widget _buildQuickPlayButton(_CoachQuickPlayTemplate play) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDCE0E5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _applyQuickPlay(play),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.playlist_add_check, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      _quickPlayLabel(play),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 2),
            Tooltip(
              message: _isHebrew ? 'הסבר לתרגיל' : 'Play explanation',
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _openQuickPlayInfo(play),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.info_outline, size: 17),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
            width: 102,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? color : const Color(0xFFDCE0E5),
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _toolIcon(tool),
                  color: color,
                  size: 19,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _toolShortLabel(tool),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
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
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _CoachBoardTool.values.map(_buildToolButton).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isHebrew ? 'תרגילים 4x4 מהירים' : 'Quick 4x4 Plays',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _quickPlayTemplates.map(_buildQuickPlayButton).toList(),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        return Stack(
          children: [
            Column(
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
            ),
            _buildQuickPlayInfoPanel(viewport),
          ],
        );
      },
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
    // Keep canvas updates reliable even when lists are mutated in-place.
    return true;
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

class _CoachQuickMarker {
  final _CoachMarkerType type;
  final Offset position;

  const _CoachQuickMarker(this.type, this.position);
}

class _CoachQuickStroke {
  final _CoachStrokeType type;
  final List<Offset> points;

  const _CoachQuickStroke(this.type, this.points);
}

class _CoachQuickPlayTemplate {
  final String id;
  final String labelHe;
  final String labelEn;
  final String descriptionHe;
  final String descriptionEn;
  final List<_CoachQuickMarker> markers;
  final List<_CoachQuickStroke> strokes;

  const _CoachQuickPlayTemplate({
    required this.id,
    required this.labelHe,
    required this.labelEn,
    required this.descriptionHe,
    required this.descriptionEn,
    required this.markers,
    required this.strokes,
  });
}

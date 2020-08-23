import 'dart:async';
import 'dart:ui' as ui;

import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:logging/logging.dart';
import 'package:static_translations/static_translations.dart';

class Testable extends StatefulWidget {
  Testable({
    @required this.child,
    this.gestures,
    @required this.id,
    this.onRequestError,
    this.onRequestValue,
    this.onSetValue,
    this.scrollableId,
  })  : assert(child != null),
        assert(id?.isNotEmpty == true),
        super(key: ValueKey(id));

  final Widget child;
  final TestableGestures gestures;
  final String id;
  final String Function() onRequestError;
  final dynamic Function() onRequestValue;
  final ValueChanged<dynamic> onSetValue;
  final String scrollableId;

  @override
  TestableState createState() => TestableState();
}

class TestableState extends State<Testable>
    with SingleTickerProviderStateMixin {
  static final Logger _logger = Logger('_TestableState');

  final List<StreamSubscription> _subscriptions = [];
  final Set<TestableType> _types = {TestableType.tappable};

  Animation<Color> _animation;
  AnimationController _animationController;
  dynamic Function() _onRequestError;
  dynamic Function() _onRequestValue;
  ValueChanged<dynamic> _onSetValue;
  TestableRenderController _renderController;
  GlobalKey _renderKey;
  String _scrollableId;
  GlobalKey _scrollKey;
  bool _showTestableOverlay = false;
  TestController _testController;
  TestRunnerState _testRunner;

  dynamic Function() get onRequestError => _onRequestError;
  dynamic Function() get onRequestValue => _onRequestValue;
  ValueChanged<dynamic> get onSetValue => _onSetValue;

  @override
  void initState() {
    super.initState();

    _testRunner = TestRunner.of(context);

    if (_testRunner?.enabled == true) {
      _renderController = TestableRenderController.of(context);
      _testController = TestController.of(context);
      _onRequestError =
          widget.onRequestError ?? _tryCommonGetErrorMethods(widget.child);
      if (_onRequestError != null) {
        _types.add(TestableType.error_requestable);
      }

      _onRequestValue =
          widget.onRequestValue ?? _tryCommonGetValueMethods(widget.child);
      if (_onRequestValue != null) {
        _types.add(TestableType.value_requestable);
      }

      _onSetValue =
          widget.onSetValue ?? _tryCommonSetValueMethods(widget.child);
      if (_onSetValue != null) {
        _types.add(TestableType.value_settable);
      }

      if (_renderController.testWidgetsEnabled == true) {
        _renderKey = GlobalKey();

        _subscriptions.add(_renderController.stream.listen((_) {
          if (mounted == true) {
            setState(() {});
          }
        }));
      }

      if (_renderController.flashCount > 0) {
        _animationController = AnimationController(
          duration: _renderController.flashDuration,
          vsync: this,
        );
        _animation = ColorTween(
          begin: Colors.transparent,
          end: _renderController.flashColor,
        ).animate(_animationController)
          ..addListener(() {
            if (mounted == true) {
              setState(() {});
            }
          });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (mounted == true) {
      _scrollableId = widget.scrollableId;
      var canBeScrolled = false;
      if (_scrollableId?.isNotEmpty != true) {
        try {
          var scrollable = Scrollable.of(context);
          canBeScrolled = scrollable != null;
          _scrollableId = scrollable?.widget?.key?.toString();
        } catch (e, stack) {
          _logger.severe(e, stack);
        }
      }

      if (canBeScrolled == true || _scrollableId?.isNotEmpty == true) {
        _types.add(TestableType.scrolled);
        _scrollKey = GlobalKey();
      }
    }
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _animationController = null;
    _subscriptions?.forEach((sub) => sub.cancel());

    super.dispose();
  }

  Future<void> flash() async {
    for (var i = 0; i < _renderController.flashCount; i++) {
      await _animationController.forward(from: 0.0);
      await _animationController.reverse(from: 1.0);
    }
  }

  VoidCallback _getGestureAction({
    TestableGestureAction widget,
    TestableGestureAction overlay,
  }) {
    VoidCallback result;

    if (_showTestableOverlay == true) {
      if (overlay != null) {
        result = () => _fireTestableAction(overlay);
      }
    } else {
      if (widget != null) {
        result = () => _fireTestableAction(widget);
      }
    }

    return result;
  }

  Future<void> _fireTestableAction(TestableGestureAction action) async {
    if (mounted == true) {
      switch (action) {
        case TestableGestureAction.open_test_actions_dialog:
          await _openTestActions(page: false);
          break;

        case TestableGestureAction.open_test_actions_page:
          await _openTestActions(page: true);
          break;

        case TestableGestureAction.toggle_global_overlay:
          _renderController.showGlobalOverlay =
              _renderController.showGlobalOverlay != true;
          break;

        case TestableGestureAction.toggle_overlay:
          _showTestableOverlay = !_showTestableOverlay;
          if (mounted == true) {
            setState(() {});
          }
          break;
      }
    }
  }

  Future<void> _openTestActions({@required bool page}) async {
    RenderRepaintBoundary boundary =
        _renderKey.currentContext.findRenderObject();
    _showTestableOverlay = false;
    if (mounted == true) {
      setState(() {});
    }
    try {
      await Future.delayed(Duration(milliseconds: 500));

      List<int> image;

      if (boundary?.debugNeedsPaint != true) {
        var img = await boundary.toImage(
          pixelRatio: MediaQuery.of(context).devicePixelRatio,
        );
        var byteData = await img.toByteData(
          format: ui.ImageByteFormat.png,
        );
        image = byteData.buffer.asUint8List();
      }
      if (mounted == true) {
        setState(() {});
      }

      if (page == true) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (BuildContext context) => TestableStepsPage(
              error: _onRequestError == null ? null : _onRequestError(),
              image: image,
              scrollableId: _scrollableId,
              testableId: widget.id,
              types: _types.toList(),
              value: _onRequestValue == null ? null : _onRequestValue(),
            ),
          ),
        );
      } else {
        var result = await showDialog<String>(
          context: context,
          useRootNavigator: false,
          builder: (BuildContext context) => TestableStepsDialog(
            error: _onRequestError == null ? null : _onRequestError(),
            image: image,
            scrollableId: _scrollableId,
            testableId: widget.id,
            types: _types.toList(),
            value: _onRequestValue == null ? null : _onRequestValue(),
          ),
        );

        if (result?.isNotEmpty == true) {
          var translator = Translator.of(context);
          try {
            var snackBar = SnackBar(
              content: Text(result),
              duration: Duration(seconds: 4),
              action: SnackBarAction(
                label: translator
                    .translate(TestTranslations.atf_button_view_steps),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (BuildContext context) => TestStepsPage(),
                  ),
                ),
              ),
            );
            Scaffold.of(context).showSnackBar(snackBar);
          } catch (e) {
            await showDialog(
              context: context,
              builder: (BuildContext context) => AlertDialog(
                actions: [
                  FlatButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      translator.translate(TestTranslations.atf_button_ok),
                    ),
                  ),
                ],
                content: Text(result),
              ),
            );
          }
        }
      }
    } finally {
      if (mounted == true) {
        setState(() {});
      }
    }
  }

  dynamic Function() _tryCommonGetErrorMethods(
    dynamic widget, {
    int depth = 0,
  }) {
    dynamic Function() result;

    if (depth < _testController.maxCommonSearchDepth) {
      if (widget is FormField) {
        var key = widget.key;
        if (key is GlobalKey) {
          var state = key.currentState;
          if (state is FormFieldState) {
            result = () => state.errorText;
          }
        }
      }

      try {
        if (result == null && widget?.child != null) {
          result = _tryCommonGetErrorMethods(widget.child, depth: depth + 1);
        }
      } catch (e) {
        // no-op
      }
    }

    return result;
  }

  dynamic Function() _tryCommonGetValueMethods(
    dynamic widget, {
    int depth = 0,
  }) {
    dynamic Function() result;

    if (depth < _testController.maxCommonSearchDepth) {
      if (widget is Text) {
        result = () => widget.data ?? widget.textSpan?.toPlainText();
      } else if ((widget is TextField ||
          widget is TextFormField ||
          widget is CupertinoTextField)) {
        dynamic text = widget;
        if (text?.controller != null) {
          result = () => text.controller.text;
        }
      } else if (widget is Checkbox) {
        result = () => widget.value;
      } else if (widget is CupertinoSwitch) {
        result = () => widget.value;
      } else if (widget is DropdownButton) {
        result = () => widget.value;
      } else if (widget is Radio) {
        result = () => widget.groupValue;
      } else if (widget is Switch) {
        result = () => widget.value;
      }

      try {
        if (result == null && widget?.child != null) {
          result = _tryCommonGetValueMethods(widget.child, depth: depth + 1);
        }
      } catch (e) {
        // no-op
      }
    }

    return result;
  }

  ValueChanged<dynamic> _tryCommonSetValueMethods(
    dynamic widget, {
    int depth = 0,
  }) {
    ValueChanged<dynamic> result;

    if (depth < _testController.maxCommonSearchDepth) {
      if ((widget is TextField ||
          widget is TextFormField ||
          widget is CupertinoTextField)) {
        dynamic text = widget;
        if (text?.controller != null) {
          result = (dynamic value) => text.controller.text = value?.toString();
        }
      }

      try {
        if (result == null && widget?.child != null) {
          result = _tryCommonSetValueMethods(widget.child, depth: depth + 1);
        }
      } catch (e) {
        // no-op
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    Widget result;

    if (_testRunner?.enabled == true &&
        _renderController.testWidgetsEnabled == true) {
      var gestures =
          widget.gestures ?? TestableRenderController.of(context).gestures;

      Widget overlay = _renderController.widgetOverlayBuilder(
        context: context,
        testable: widget,
      );

      overlay = Positioned.fill(
        child: IgnorePointer(
          ignoring: _showTestableOverlay != true,
          child: AnimatedOpacity(
            duration: Duration(milliseconds: 300),
            opacity: _showTestableOverlay == true ? 1.0 : 0.0,
            child: Material(
              color: _renderController.overlayColor ??
                  Theme.of(context).errorColor,
              child: InkWell(
                onDoubleTap: _getGestureAction(
                  overlay: gestures.overlayDoubleTap,
                ),
                onLongPress: _getGestureAction(
                  overlay: gestures.overlayLongPress,
                ),
                onTap: _getGestureAction(
                  overlay: gestures.overlayTap,
                ),
                child: overlay,
              ),
            ),
          ),
        ),
      );

      result = Stack(
        fit: StackFit.passthrough,
        key: _scrollKey,
        children: [
          IgnorePointer(
            ignoring: _showTestableOverlay == true,
            child: GestureDetector(
              onDoubleTap: _getGestureAction(
                widget: gestures.widgetDoubleTap,
              ),
              onForcePressEnd: gestures.widgetForcePressEnd == null
                  ? null
                  : (_) => _fireTestableAction(gestures.widgetForcePressEnd),
              onForcePressStart: gestures.widgetForcePressStart == null
                  ? null
                  : (_) => _fireTestableAction(gestures.widgetForcePressStart),
              onLongPress: _getGestureAction(
                widget: gestures.widgetLongPress,
              ),
              onTap: _getGestureAction(
                widget: gestures.widgetTap,
              ),
              child: RepaintBoundary(
                key: _renderKey,
                child: widget.child,
              ),
            ),
          ),
          if (_renderController.showGlobalOverlay == true)
            _renderController.globalOverlayBuilder(context),
          overlay,
          if (_renderController.flashCount > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(color: _animation.value),
              ),
            ),
        ],
      );
    } else {
      result = widget.child;
    }

    return result;
  }
}

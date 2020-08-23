import 'dart:async';
import 'dart:math';

import 'package:automated_testing_framework/automated_testing_framework.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' as test;
import 'package:json_class/json_class.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

abstract class TestRunnerStep extends JsonClass {
  static final Logger _logger = Logger('TestRunnerStep');

  static Function(Object) _console =
      (Object obj) => _logger.info(obj?.toString());
  static final OverrideWidgetTester _driver =
      OverrideWidgetTester(WidgetsBinding.instance);

  static Function(Object) get console => _console;
  static set console(Function(Object) printer) {
    assert(printer != null);
    _console = printer;
  }

  OverrideWidgetTester get driver => _driver;

  test.CommonFinders get find => test.find;

  Future<void> execute({
    @required TestReport report,
    @required TestController tester,
  });

  @protected
  void log(
    String message, {
    @required TestController tester,
  }) {
    _console(message);
    tester.status = message;
  }

  @protected
  Future<void> sleep(
    Duration duration, {
    Stream<void> cancelStream,
    bool error = false,
    String message,
    @required TestController tester,
  }) async {
    if (duration.inMilliseconds > 0) {
      // Let's reduce the number of log entries to 1 per 100ms or 10 per second.
      var calcSteps = duration.inMilliseconds / 100;

      // However, let's put sanity limits.  At lest 10 events and no more than
      // 50.
      var steps = max(5, min(50, calcSteps));

      tester.sleep = ProgressValue(max: steps, value: 0);
      var sleepMillis = duration.inMilliseconds ~/ steps;
      var canceled = false;

      var cancelListener = cancelStream?.listen((_) {
        canceled = true;
      });
      try {
        String buildString(int count) {
          var str = '[';
          for (var i = 0; i < count; i++) {
            str += String.fromCharCode(0x2588);
          }
          for (var i = count; i < steps; i++) {
            str += '_';
          }

          str += ']';
          return str;
        }

        if (message?.isNotEmpty == true) {
          _console(message);
        } else {
          _console('Sleeping for ${duration.inMilliseconds} millis...');
        }

        for (var i = 0; i < steps; i++) {
          _console(buildString(i));
          tester.sleep = ProgressValue(
            error: error,
            max: steps,
            value: i,
          );
          await Future.delayed(Duration(milliseconds: sleepMillis));

          if (canceled == true) {
            break;
          }
        }
        _console(buildString(steps));
      } finally {
        tester.sleep = ProgressValue(
          error: error,
          max: steps,
          value: steps,
        );
        await Future.delayed(Duration(milliseconds: 100));
        tester.sleep = null;
        await cancelListener?.cancel();
      }
    }
  }

  @protected
  Future<test.Finder> waitFor(
    dynamic testableId, {
    @required TestController tester,
    Duration timeout,
  }) async {
    timeout ??= tester.delays.defaultTimeout;

    var controller = StreamController<void>.broadcast();
    var name = "waitFor('$testableId')";
    try {
      var waiter = () async {
        var end =
            DateTime.now().millisecondsSinceEpoch + timeout.inMilliseconds;
        test.Finder finder;
        var found = false;
        while (found != true && DateTime.now().millisecondsSinceEpoch < end) {
          try {
            finder = test.find.byKey(Key(testableId));
            finder.evaluate().first;
            found = true;
          } catch (e) {
            await Future.delayed(Duration(milliseconds: 100));
          }
        }

        if (found != true) {
          throw Exception('testableId: [$testableId] -- Timeout exceeded.');
        }
        return finder;
      };

      var sleeper = sleep(
        timeout,
        cancelStream: controller.stream,
        error: true,
        message: '[$name]: ${timeout.inSeconds} seconds',
        tester: tester,
      );

      var result = await waiter();
      controller.add(null);
      await sleeper;

      try {
        var finder = result.evaluate()?.first;
        if (finder.widget is Testable) {
          StatefulElement element = finder;
          var state = element.state;
          if (state is TestableState) {
            _console('flash: [$testableId]');
            await state.flash();
          }
        }
      } catch (e) {
        // no-op
      }

      return result;
    } catch (e) {
      log(
        'ERROR: [$name] -- $e',
        tester: tester,
      );
      rethrow;
    } finally {
      await controller.close();
    }
  }
}
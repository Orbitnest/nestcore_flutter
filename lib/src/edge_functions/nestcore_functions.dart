import 'dart:async';
import 'package:flutter/foundation.dart';
import 'bloc/functions_bloc.dart';
import 'bloc/functions_event.dart';
import 'bloc/functions_state.dart';
import 'models/function_response.dart';
import 'exceptions/function_exception.dart';

/// Simplified Edge Functions API that wraps the BLoC pattern
/// Provides direct async methods for function invocation only
class NestCoreFunctions extends ChangeNotifier {
  final FunctionsBloc _functionsBloc;
  late final StreamSubscription _stateSubscription;

  FunctionsState _currentState = const FunctionsInitialState();
  final Map<String, Completer<dynamic>> _pendingOperations = {};
  // Tracks which operation key belongs to which function name so responses
  // are routed to the correct completer even under concurrent calls.
  final Map<String, String> _operationFunctionNames = {};
  int _operationCounter = 0;

  NestCoreFunctions(this._functionsBloc) {
    _stateSubscription = _functionsBloc.stream.listen(_handleStateChange);
    _currentState = _functionsBloc.state;
  }

  void _handleStateChange(FunctionsState state) {
    _currentState = state;
    notifyListeners();

    // Complete pending operations based on state changes
    switch (state) {
      case FunctionsInvokedState(
          response: final response,
          functionName: final funcName
        ):
        _completePendingOperationByName(funcName, response);
        break;
      case FunctionsErrorState(
          :final message,
          :final code,
          :final functionName
        ):
        // Route the failure to the ONE call it belongs to, mirroring the
        // success path above. Failing every pending operation meant a single
        // bad function (e.g. one that was deleted server-side and 404s) also
        // failed every unrelated call in flight beside it, so callers saw
        // healthy endpoints reported as broken under someone else's name.
        final error =
            FunctionException(message, code: code, functionName: functionName);
        _completePendingOperation(functionName, error, isError: true);
        break;
      case FunctionsInitialState():
        break;
      case FunctionsLoadingState():
        break;
    }
  }

  void _completePendingOperationByName(String functionName, dynamic result) =>
      _completePendingOperation(functionName, result);

  /// Settle the oldest pending operation registered for [functionName] with
  /// [result] — as a value, or as an error when [isError] is set.
  ///
  /// Falls back to FIFO when the name is unknown (the bloc leaves
  /// `functionName` null on some failures), which is the best available guess
  /// and still settles exactly one call rather than all of them.
  void _completePendingOperation(
    String? functionName,
    dynamic result, {
    bool isError = false,
  }) {
    if (_pendingOperations.isEmpty) return;

    // Find the oldest pending key registered for this function name.
    String? matchKey;
    if (functionName != null) {
      for (final entry in _operationFunctionNames.entries) {
        if (entry.value == functionName &&
            _pendingOperations.containsKey(entry.key)) {
          matchKey = entry.key;
          break;
        }
      }
    }

    // FIFO fallback – should not normally be reached.
    matchKey ??= _pendingOperations.keys.first;

    _operationFunctionNames.remove(matchKey);
    final completer = _pendingOperations.remove(matchKey);
    if (completer == null || completer.isCompleted) return;
    if (isError) {
      completer.completeError(result as Object);
    } else {
      completer.complete(result);
    }
  }

  String _generateOperationKey() {
    return 'op_${++_operationCounter}_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<T> _executeWithCompleter<T>(
    FunctionsEvent event, {
    String? functionName,
  }) async {
    final completer = Completer<T>();
    final operationKey = _generateOperationKey();
    _pendingOperations[operationKey] = completer;
    if (functionName != null) {
      _operationFunctionNames[operationKey] = functionName;
    }

    _functionsBloc.add(event);

    // No manual timeout - rely only on Dio client timeout
    return completer.future;
  }

  /// Get current functions state
  FunctionsState get state => _currentState;

  /// Stream of functions state changes
  Stream<FunctionsState> get onStateChange => _functionsBloc.stream;

  /// Invoke an edge function (main method for calling functions)
  Future<FunctionResponse> invoke(
    String functionName, {
    String method = 'POST',
    dynamic body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    return await _executeWithCompleter<FunctionResponse>(
      FunctionsInvokeEvent(
        functionName: functionName,
        method: method,
        body: body,
        headers: headers,
        queryParameters: queryParameters,
      ),
      functionName: functionName,
    );
  }

  /// Convenience method for calling functions (alias for invoke)
  Future<FunctionResponse> call(
    String functionName, {
    dynamic params,
    Map<String, String>? headers,
  }) async {
    return invoke(
      functionName,
      method: 'POST',
      body: params,
      headers: headers,
    );
  }

  /// GET request to a function
  Future<FunctionResponse> get(
    String functionName, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    return invoke(
      functionName,
      method: 'GET',
      headers: headers,
      queryParameters: queryParameters,
    );
  }

  /// POST request to a function
  Future<FunctionResponse> post(
    String functionName, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    return invoke(
      functionName,
      method: 'POST',
      body: body,
      headers: headers,
    );
  }

  /// PUT request to a function
  Future<FunctionResponse> put(
    String functionName, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    return invoke(
      functionName,
      method: 'PUT',
      body: body,
      headers: headers,
    );
  }

  /// DELETE request to a function
  Future<FunctionResponse> delete(
    String functionName, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    return invoke(
      functionName,
      method: 'DELETE',
      body: body,
      headers: headers,
    );
  }

  @override
  void dispose() {
    _stateSubscription.cancel();
    super.dispose();
  }
}

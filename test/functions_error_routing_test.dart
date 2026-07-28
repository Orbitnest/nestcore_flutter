// Regression test for the "one bad function fails every call" bug.
//
// OrbitNestFunctions multiplexes concurrent invocations onto a single bloc and
// resolves them from its state stream. The success path routed a result to the
// one pending operation registered for that function name, but the error path
// completed EVERY pending operation with whichever function happened to fail.
//
// Real-world symptom: an app whose dashboard fans out get-dashboard,
// get-groups, get-insights and one function that had been deleted server-side
// saw all four reported as broken, each carrying the deleted function's name —
// even though three of them returned 200.
//
// This pins the routing so a failure only settles its own caller.
import 'package:flutter_test/flutter_test.dart';
import 'package:orbitnest_studio_flutter/src/edge_functions/bloc/functions_bloc.dart';
import 'package:orbitnest_studio_flutter/src/edge_functions/exceptions/function_exception.dart';
import 'package:orbitnest_studio_flutter/src/edge_functions/models/function_response.dart';
import 'package:orbitnest_studio_flutter/src/edge_functions/orbitnest_functions.dart';
import 'package:orbitnest_studio_flutter/src/edge_functions/repositories/functions_repository.dart';

/// Repository stub: `missing` fails fast, everything else succeeds slowly so
/// the failure lands while the healthy call is still in flight. Only [invoke]
/// is exercised — the rest is covered by noSuchMethod forwarding.
class _FakeRepository implements FunctionsRepository {
  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    String method = 'POST',
    dynamic body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (functionName == 'missing') {
      throw const FunctionException('Function not found or inactive',
          code: 'NOT_FOUND', functionName: 'missing');
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return FunctionResponse(
      data: {'ok': functionName},
      status: 200,
      statusText: 'OK',
      headers: const {},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  group('OrbitNestFunctions error routing', () {
    late OrbitNestFunctions functions;

    setUp(() {
      functions = OrbitNestFunctions(
        FunctionsBloc(functionsRepository: _FakeRepository()),
      );
    });

    test('a failing function does not fail the calls running beside it',
        () async {
      final healthy = functions.get('get-dashboard');
      final broken = functions.get('missing');

      await expectLater(broken, throwsA(isA<FunctionException>()));

      final response = await healthy;
      expect(response.status, 200);
      expect(response.data, {'ok': 'get-dashboard'});
    });

    test('the failure carries its own function name', () async {
      try {
        await functions.get('missing');
        fail('expected the invocation to throw');
      } on FunctionException catch (e) {
        expect(e.functionName, 'missing');
      }
    });

    test('several healthy calls all resolve when one sibling fails', () async {
      final a = functions.get('get-groups');
      final b = functions.get('get-insights');
      final c = functions.get('manage-category');
      final broken = functions.get('missing');

      await expectLater(broken, throwsA(isA<FunctionException>()));

      final results = await Future.wait([a, b, c]);
      expect(results.map((r) => r.data), [
        {'ok': 'get-groups'},
        {'ok': 'get-insights'},
        {'ok': 'manage-category'},
      ]);
    });
  });
}

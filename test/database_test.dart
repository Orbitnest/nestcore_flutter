// Pins the database layer to the request shapes the NestCore data API
// actually reads (client-database.controller.ts / database-ops.service.ts):
//   GET  tables/:t/data   ?filter=col:op:val (repeatable) &sortBy &sortOrder &limit | from/to
//   POST tables/:t/rows   single insert
//   PUT  tables/:t/rows/bulk     [{where, data}]
//   DELETE tables/:t/rows/bulk   [{col: val, ...}]
//   POST sql              {sql, params}
import 'package:nestcore_flutter/src/database/services/query_builder.dart';
import 'package:nestcore_flutter/src/database/models/semantic_response.dart';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nestcore_flutter/src/client/http_client.dart';
import 'package:nestcore_flutter/src/database/bloc/database_bloc.dart';
import 'package:nestcore_flutter/src/database/nestcore_database.dart';
import 'package:nestcore_flutter/src/database/repositories/database_repository.dart';
import 'package:nestcore_flutter/src/database/services/database_service.dart';

class _Call {
  _Call(this.method, this.path, this.query, this.data);
  final String method;
  final String path;
  final Map<String, dynamic>? query;
  final dynamic data;
}

/// Records every request and answers with [reply] (optionally after [delay]).
class _FakeHttp implements NestCoreHttpClient {
  final calls = <_Call>[];
  dynamic Function(_Call call) reply = (_) => {'success': true};
  Duration Function(_Call call) delay = (_) => Duration.zero;

  Future<Response<T>> _send<T>(String method, String path,
      {Map<String, dynamic>? query, dynamic data}) async {
    final call = _Call(method, path, query, data);
    calls.add(call);
    await Future<void>.delayed(delay(call));
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: reply(call) as T,
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> get<T>(String path,
          {Map<String, dynamic>? queryParameters,
          Options? options,
          CancelToken? cancelToken,
          ProgressCallback? onReceiveProgress}) =>
      _send('GET', path, query: queryParameters);

  @override
  Future<Response<T>> post<T>(String path,
          {dynamic data,
          Map<String, dynamic>? queryParameters,
          Options? options,
          CancelToken? cancelToken,
          ProgressCallback? onSendProgress,
          ProgressCallback? onReceiveProgress}) =>
      _send('POST', path, query: queryParameters, data: data);

  @override
  Future<Response<T>> put<T>(String path,
          {dynamic data,
          Map<String, dynamic>? queryParameters,
          Options? options,
          CancelToken? cancelToken,
          ProgressCallback? onSendProgress,
          ProgressCallback? onReceiveProgress}) =>
      _send('PUT', path, query: queryParameters, data: data);

  @override
  Future<Response<T>> delete<T>(String path,
          {dynamic data,
          Map<String, dynamic>? queryParameters,
          Options? options,
          CancelToken? cancelToken}) =>
      _send('DELETE', path, query: queryParameters, data: data);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeHttp http;
  late DatabaseService service;
  late NestCoreDatabase db;

  setUp(() {
    http = _FakeHttp();
    service = DatabaseService(httpClient: http, projectSlug: 'demo');
    db = NestCoreDatabase(
      DatabaseBloc(databaseRepository: DatabaseRepository(databaseService: service)),
      service,
    );
  });

  group('query builder (B-03, B-04)', () {
    test('execute() sends filter/sortBy/sortOrder/from/to and projects columns', () async {
      http.reply = (_) => {
            'total_rows': 7,
            'data': [
              {'id': 1, 'title': 'a', 'secret': 'x'},
            ],
          };

      final res = await db
          .from('posts')
          .select('id, title')
          .eq('published', true)
          .gte('views', 10)
          .inFilter('tag', ['a', 'b'])
          .isNull('deleted_at')
          .order('created_at', ascending: false)
          .range(20, 29)
          .execute();

      final call = http.calls.single;
      expect(call.method, 'GET');
      expect(call.path, '/api/project/demo/database/tables/posts/data');
      expect(call.query, {
        'filter': [
          'published:eq:true',
          'views:gte:10',
          'tag:in:a,b',
          'deleted_at:is:null',
        ],
        'sortBy': 'created_at',
        'sortOrder': 'DESC',
        'from': '20',
        'to': '29',
      });
      expect(res.data, [
        {'id': 1, 'title': 'a'}
      ]);
      expect(res.count, 7);
    });

    test('filter values may contain ":"', () async {
      http.reply = (_) => {'data': []};
      await db.from('posts').eq('created_at', '2024-01-01T10:00:00Z').execute();
      expect(http.calls.single.query!['filter'],['created_at:eq:2024-01-01T10:00:00Z']);
    });

    test('limit without range sends limit only', () async {
      http.reply = (_) => {'data': []};
      await db.from('posts').limit(5).execute();
      expect(http.calls.single.query, {'limit': '5'});
    });

    test('unsupported filters and values throw before any request', () {
      final b = db.from('posts');
      expect(() => b.contains('tags', ['a']), throwsUnsupportedError);
      expect(() => b.or('a.eq.1,b.eq.2'), throwsUnsupportedError);
      expect(() => b.isNotNull('x'), throwsUnsupportedError);
      expect(() => b.inFilter('tag', ['a,b']), throwsArgumentError);
      b.order('a');
      expect(() => b.order('b'), throwsUnsupportedError);
      expect(http.calls, isEmpty);
    });

    test('update()/delete() use equality filters on the bulk routes', () async {
      http.reply = (_) => {'success': true, 'rows_affected': 2};

      final upd = await db.from('users').eq('team', 3).update({'tier': 'pro'});
      final del = await db.from('users').eq('id', 9).delete();

      expect(http.calls[0].method, 'PUT');
      expect(http.calls[0].path, '/api/project/demo/database/tables/users/rows/bulk');
      expect(http.calls[0].data, [
        {'where': {'team': 3}, 'data': {'tier': 'pro'}}
      ]);
      expect(upd.count, 2);
      expect(http.calls[1].method, 'DELETE');
      expect(http.calls[1].data, [
        {'id': 9}
      ]);
      expect(del.count, 2);
    });

    test('update()/delete() refuse no filter or a non-equality filter', () async {
      await expectLater(db.from('users').delete(), throwsArgumentError);
      await expectLater(db.from('users').update({'a': 1}), throwsArgumentError);
      await expectLater(db.from('users').gt('age', 3).delete(), throwsUnsupportedError);
      expect(http.calls, isEmpty);
    });

    test('insert(list) inserts every row; upsert throws (B-17)', () async {
      http.reply = (c) => {
            'rows_affected': 1,
            'data': [
              {...c.data as Map, 'id': http.calls.length}
            ],
          };
      final res = await db.from('users').insert([
        {'name': 'a'},
        {'name': 'b'},
      ]);
      expect(http.calls.map((c) => c.data), [
        {'name': 'a'},
        {'name': 'b'},
      ]);
      expect(res.data.map((r) => r['id']), [1, 2]);

      await expectLater(db.from('users').upsert({'id': 1}), throwsUnsupportedError);
      await expectLater(db.insert('users', {'id': 1}, upsert: true), throwsUnsupportedError);
    });
  });

  group('direct CRUD', () {
    test('select() maps filters/orderBy/offset to the API (B-04)', () async {
      http.reply = (_) => {'data': []};
      await db.select('users',
          columns: 'id,name',
          filters: {'status': 'active', 'deleted_at': null},
          orderBy: ['created_at.desc'],
          limit: 10,
          offset: 20);
      expect(http.calls.single.query, {
        'filter': ['status:eq:active', 'deleted_at:is:null'],
        'sortBy': 'created_at',
        'sortOrder': 'DESC',
        'from': '20',
        'to': '29',
      });
    });

    test('deleteMany deletes by the filter, never by filter-value-as-id (B-01)', () async {
      http.reply = (_) => {'success': true, 'rows_affected': 4};
      final res = await db.deleteMany('posts', filters: {'author_id': 12});
      expect(http.calls.single.data, [
        {'author_id': 12}
      ]);
      expect(res.count, 4);
    });

    test('updateMany sends its filters as the where clause (B-16)', () async {
      http.reply = (_) => {'success': true, 'rows_affected': 3};
      final res = await db.updateMany('users', {'tier': 'pro'}, filters: {'plan': 'paid'});
      expect(http.calls.single.data, [
        {'where': {'plan': 'paid'}, 'data': {'tier': 'pro'}}
      ]);
      expect(res.count, 3);
    });

    test('delete with empty or null filters is refused', () async {
      await expectLater(db.deleteMany('posts', filters: {}), throwsArgumentError);
      await expectLater(db.delete('posts', filters: {'id': null}), throwsArgumentError);
      expect(http.calls, isEmpty);
    });

    test('insertMany uses the single-row route, not the service-role bulk route (B-15)', () async {
      http.reply = (c) => {'data': [c.data]};
      await db.insertMany('users', [
        {'n': 1},
        {'n': 2},
      ]);
      expect(http.calls.map((c) => '${c.method} ${c.path}'), [
        'POST /api/project/demo/database/tables/users/rows',
        'POST /api/project/demo/database/tables/users/rows',
      ]);
    });

    test('sql() sends params and returns the rows (B-05, B-06)', () async {
      http.reply = (_) => {
            'success': true,
            'rows_affected': 2,
            'data': [
              {'name': 'a'},
              {'name': 'b'},
            ],
          };
      final res = await db.sql(r'SELECT name FROM t LIMIT $1', parameters: [2]);
      expect(http.calls.single.path, '/api/project/demo/database/sql');
      expect(http.calls.single.data, {
        'sql': r'SELECT name FROM t LIMIT $1',
        'params': [2],
      });
      expect(res.data, [
        {'name': 'a'},
        {'name': 'b'},
      ]);
      expect(res.count, 2);
    });

    test('vectorSearch() binds the vector as params', () async {
      http.reply = (_) => {'data': []};
      await db.vectorSearch('docs', 'embedding', [0.5, 1], metric: 'cosine', limit: 3);
      expect(http.calls.single.data, {
        'sql': r'SELECT * FROM "docs" ORDER BY "embedding" <=> $1::vector LIMIT 3',
        'params': ['[0.5,1.0]'],
      });
    });

    test('textSearch() chains with filters, order and range into one bound SELECT', () async {
      http.reply = (_) => {
            'rows_affected': 1,
            'data': [
              {'id': 1, 'title': 'a'}
            ],
          };
      final res = await db
          .from('posts')
          .select('id, title')
          .eq('published', true)
          .isNull('deleted_at')
          .inFilter('tag', ['a', 'b'])
          .textSearch('body', 'cats -dogs')
          .textSearch('title', 'red fox', config: 'simple', type: 'phrase')
          .order('created_at', ascending: false)
          .range(10, 19)
          .execute();
      final call = http.calls.single;
      expect(call.path, '/api/project/demo/database/sql');
      expect(call.data, {
        'sql': 'SELECT "id", "title" FROM "posts" WHERE "published" = \$1 AND "deleted_at" IS NULL '
            'AND "tag" IN (\$2, \$3) '
            "AND to_tsvector('english', \"body\"::text) @@ websearch_to_tsquery('english', \$4) "
            "AND to_tsvector('simple', \"title\"::text) @@ phraseto_tsquery('simple', \$5) "
            'ORDER BY "created_at" DESC LIMIT \$6 OFFSET \$7',
        'params': [true, 'a', 'b', 'cats -dogs', 'red fox', 10, 10],
      });
      expect(res.data.single['title'], 'a');
      expect(res.count, 1);
    });

    test('textSearch()/nearest() reject unsafe input before any request', () {
      expect(() => db.from('posts').textSearch('body; drop', 'x'), throwsArgumentError);
      expect(() => db.from('posts').textSearch('body', 'x', config: "english'"), throwsArgumentError);
      expect(() => db.from('posts').textSearch('body', 'x', type: 'fuzzy'), throwsArgumentError);
      expect(() => db.from('docs').nearest('embedding', [double.nan]), throwsArgumentError);
      expect(() => db.from('docs').nearest('embedding', [1], metric: 'dot'), throwsArgumentError);
      expect(http.calls, isEmpty);
    });

    test('nearest() orders by distance first, keeps filters, binds the vector', () async {
      http.reply = (_) => {'data': []};
      await db.from('docs').eq('team', 'a').nearest('embedding', [0.5, 1], metric: 'cosine', limit: 3).execute();
      expect(http.calls.single.data, {
        'sql': r'SELECT * FROM "docs" WHERE "team" = $1 ORDER BY "embedding" <=> $2::vector LIMIT $3',
        'params': ['a', '[0.5,1]', 3],
      });
    });

    test('update()/delete() refuse textSearch/nearest builders', () async {
      await expectLater(db.from('posts').eq('id', 1).textSearch('body', 'x').delete(), throwsUnsupportedError);
      expect(http.calls, isEmpty);
    });

    test('semantic() sends the builder filters, limit as k, and projects columns', () async {
      http.reply = (_) => {
            'model': 'mock-embed',
            'rows': [
              {'id': 1, 'title': 'a', 'body': 'x', '_similarity': 0.9, '_score': 0.03},
            ],
          };
      final res = await db
          .from('articles')
          .select('id, title')
          .eq('published', true)
          .gt('views', 10)
          .inFilter('tag', ['a', 'b'])
          .isNull('deleted_at')
          .isFilter('pinned', true)
          .limit(5)
          .semantic('body_embedding', 'reset password', hybridColumn: 'body', minSimilarity: 0.2);
      final call = http.calls.single;
      expect(call.method, 'POST');
      expect(call.path, '/api/project/demo/database/semantic');
      expect(call.data, {
        'table': 'articles',
        'column': 'body_embedding',
        'query': 'reset password',
        'k': 5,
        'filters': [
          {'column': 'published', 'op': 'eq', 'value': true},
          {'column': 'views', 'op': 'gt', 'value': 10},
          {'column': 'tag', 'op': 'in', 'value': ['a', 'b']},
          {'column': 'deleted_at', 'op': 'is', 'value': null},
          {'column': 'pinned', 'op': 'is', 'value': true},
        ],
        'hybridColumn': 'body',
        'minSimilarity': 0.2,
      });
      expect(res.model, 'mock-embed');
      expect(res.rows.single, {'id': 1, 'title': 'a', '_similarity': 0.9, '_score': 0.03});
      expect(SemanticResponse.similarityOf(res.rows.single), 0.9);
    });

    test('semantic() refuses textSearch/nearest/order/offset before any request', () async {
      await expectLater(db.from('a').textSearch('body', 'x').semantic('e', 'q'), throwsUnsupportedError);
      await expectLater(db.from('a').nearest('e', [1]).semantic('e', 'q'), throwsUnsupportedError);
      await expectLater(db.from('a').order('id').semantic('e', 'q'), throwsUnsupportedError);
      await expectLater(db.from('a').range(10, 19).semantic('e', 'q'), throwsUnsupportedError);
      expect(http.calls, isEmpty);
    });

    test('database.semantic() posts directly; k and filters optional', () async {
      http.reply = (_) => {'model': null, 'rows': []};
      final res = await db.semantic('articles', 'body_embedding', 'x', filters: const [SemanticFilter('views', 'gte', 3)]);
      expect(http.calls.single.data, {
        'table': 'articles',
        'column': 'body_embedding',
        'query': 'x',
        'filters': [
          {'column': 'views', 'op': 'gte', 'value': 3}
        ],
      });
      expect(res.rows, isEmpty);
      expect(res.model, isNull);
      await expectLater(db.semantic('articles', 'e', 'x', filters: const [SemanticFilter('a', 'contains', 1)]), throwsUnsupportedError);
    });

    test('concurrent calls each get their own result (B-07)', () async {
      http.reply = (c) => {
            'data': [
              {'table': c.path.split('/')[6]}
            ],
          };
      // The first call answers last.
      http.delay = (c) => c.path.contains('/a/')
          ? const Duration(milliseconds: 40)
          : Duration.zero;

      final results = await Future.wait([db.select('a'), db.select('b')])
          .timeout(const Duration(seconds: 2));
      expect(results[0].data.single['table'], 'a');
      expect(results[1].data.single['table'], 'b');
    });
  });

  test('Dio encodes the filter list as repeated query keys', () {
    final uri = RequestOptions(
      path: 'https://api.example.com/x',
      queryParameters: {
        'filter': ['a:eq:1', 'b:eq:2']
      },
    ).uri;
    expect(uri.queryParametersAll['filter'], ['a:eq:1', 'b:eq:2']);
  });
}

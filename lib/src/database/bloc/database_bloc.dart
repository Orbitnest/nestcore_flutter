import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../repositories/database_repository.dart';
import '../services/database_service.dart';
import '../exceptions/database_exception.dart';
import 'database_event.dart';
import 'database_state.dart';

/// BLoC for managing database operations
class DatabaseBloc extends Bloc<DatabaseEvent, DatabaseState> {
  final DatabaseRepository _databaseRepository;

  DatabaseBloc({
    required DatabaseRepository databaseRepository,
  })  : _databaseRepository = databaseRepository,
        super(const DatabaseInitialState()) {
    // Register event handlers for CRUD operations only
    on<DatabaseExecuteSqlEvent>(_onExecuteSql);
    on<DatabaseSelectEvent>(_onSelect);
    on<DatabaseInsertEvent>(_onInsert);
    on<DatabaseUpdateEvent>(_onUpdate);
    on<DatabaseDeleteEvent>(_onDelete);
    on<DatabaseBulkInsertEvent>(_onBulkInsert);
    on<DatabaseBulkUpdateEvent>(_onBulkUpdate);
    on<DatabaseBulkDeleteEvent>(_onBulkDelete);
  }

  Future<void> _onExecuteSql(
    DatabaseExecuteSqlEvent event,
    Emitter<DatabaseState> emit,
  ) async {
    emit(const DatabaseLoadingState());

    try {
      final result = await _databaseRepository.executeSql(
        sql: event.sql,
        parameters: event.parameters,
      );

      emit(DatabaseSqlExecutedState(
        result: result.data,
        rowsAffected: result.count,
      ));
    } catch (e) {
      emit(DatabaseErrorState(
        message: _getErrorMessage(e),
        code: _getErrorCode(e),
      ));
    }
  }

  Future<void> _onSelect(
    DatabaseSelectEvent event,
    Emitter<DatabaseState> emit,
  ) async {
    emit(const DatabaseLoadingState());

    try {
      final order = DatabaseService.parseOrder(event.orders);
      final result = await _databaseRepository.executeQuery(
        table: event.table,
        select: event.columns ?? '*',
        filters: event.filters?.entries
            .map((e) => DatabaseService.encodeFilter(e.key, 'eq', e.value))
            .toList(),
        orderBy: order?.column,
        ascending: order?.ascending ?? true,
        limit: event.limit,
        offset: event.offset,
      );

      emit(DatabaseDataSelectedState(
        table: event.table,
        response: result,
      ));
    } catch (e) {
      emit(DatabaseErrorState(
        message: _getErrorMessage(e),
        code: _getErrorCode(e),
        table: event.table,
      ));
    }
  }

  Future<void> _onInsert(
    DatabaseInsertEvent event,
    Emitter<DatabaseState> emit,
  ) async {
    emit(const DatabaseLoadingState());

    try {
      final result = await _databaseRepository.insert(
        table: event.table,
        values: event.values,
        upsert: event.upsert,
      );

      emit(DatabaseDataInsertedState(
        table: event.table,
        response: result,
      ));
    } catch (e) {
      emit(DatabaseErrorState(
        message: _getErrorMessage(e),
        code: _getErrorCode(e),
        table: event.table,
      ));
    }
  }

  Future<void> _onUpdate(
    DatabaseUpdateEvent event,
    Emitter<DatabaseState> emit,
  ) async {
    emit(const DatabaseLoadingState());

    try {
      final result = await _databaseRepository.update(
        table: event.table,
        values: event.values,
        match: event.filters ?? const {},
      );

      emit(DatabaseDataUpdatedState(
        table: event.table,
        response: result,
      ));
    } catch (e) {
      emit(DatabaseErrorState(
        message: _getErrorMessage(e),
        code: _getErrorCode(e),
        table: event.table,
      ));
    }
  }

  Future<void> _onDelete(
    DatabaseDeleteEvent event,
    Emitter<DatabaseState> emit,
  ) async {
    emit(const DatabaseLoadingState());

    try {
      final result = await _databaseRepository.delete(
        table: event.table,
        match: event.filters ?? const {},
      );

      emit(DatabaseDataDeletedState(
        table: event.table,
        response: result,
      ));
    } catch (e) {
      emit(DatabaseErrorState(
        message: _getErrorMessage(e),
        code: _getErrorCode(e),
        table: event.table,
      ));
    }
  }

  Future<void> _onBulkInsert(
    DatabaseBulkInsertEvent event,
    Emitter<DatabaseState> emit,
  ) async {
    emit(const DatabaseLoadingState());

    try {
      if (event.upsert) throw DatabaseService.upsertUnsupported();
      final result = await _databaseRepository.bulkInsert(
        table: event.table,
        values: event.values,
      );

      emit(DatabaseBulkInsertedState(
        table: event.table,
        count: result.count ?? 0,
      ));
    } catch (e) {
      emit(DatabaseErrorState(
        message: _getErrorMessage(e),
        code: _getErrorCode(e),
        table: event.table,
      ));
    }
  }

  Future<void> _onBulkUpdate(
    DatabaseBulkUpdateEvent event,
    Emitter<DatabaseState> emit,
  ) async {
    emit(const DatabaseLoadingState());

    try {
      final count = await _databaseRepository.bulkUpdate(
        table: event.table,
        values: event.values,
        matchColumn: event.matchColumn,
      );

      emit(DatabaseBulkUpdatedState(
        table: event.table,
        count: count,
      ));
    } catch (e) {
      emit(DatabaseErrorState(
        message: _getErrorMessage(e),
        code: _getErrorCode(e),
        table: event.table,
      ));
    }
  }

  Future<void> _onBulkDelete(
    DatabaseBulkDeleteEvent event,
    Emitter<DatabaseState> emit,
  ) async {
    emit(const DatabaseLoadingState());

    try {
      final count = await _databaseRepository.bulkDelete(
        table: event.table,
        ids: event.ids,
        idColumn: event.idColumn,
      );

      emit(DatabaseBulkDeletedState(
        table: event.table,
        count: count,
      ));
    } catch (e) {
      emit(DatabaseErrorState(
        message: _getErrorMessage(e),
        code: _getErrorCode(e),
        table: event.table,
      ));
    }
  }

  String _getErrorMessage(dynamic error) {
    if (error is DatabaseException) {
      return error.message;
    }
    return error.toString();
  }

  String? _getErrorCode(dynamic error) {
    if (error is DatabaseException) {
      return error.code;
    }
    return null;
  }
}

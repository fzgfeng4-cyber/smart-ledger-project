import '../../domain/models/ledger_transaction.dart';
import '../../domain/search/transaction_search_query.dart';
import '../sqlite/transaction_local_data_source.dart';

final class TransactionSearchRepository {
  const TransactionSearchRepository(this._dataSource);

  final TransactionLocalDataSource _dataSource;

  Future<List<LedgerTransaction>> search(
    TransactionSearchQuery query, {
    int limit = 50,
    int offset = 0,
  }) {
    if (limit <= 0 || offset < 0) {
      throw ArgumentError('搜索分页参数无效');
    }
    if (query.isEmpty) {
      return Future.value(const <LedgerTransaction>[]);
    }
    return _dataSource.search(
      categoryCode: query.categoryCode,
      keyword: query.keyword,
      startDateInclusive: query.startDateInclusive,
      endDateExclusive: query.endDateExclusive,
      limit: limit,
      offset: offset,
    );
  }
}

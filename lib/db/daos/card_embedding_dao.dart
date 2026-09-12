import 'dart:convert';

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'card_embedding_dao.g.dart';

@DriftAccessor(tables: [CardEmbeddings])
class CardEmbeddingDao extends DatabaseAccessor<AppDatabase>
    with _$CardEmbeddingDaoMixin {
  CardEmbeddingDao(super.db);

  /// Insert or update the embedding vector for a card.
  Future<void> upsert({
    required String factId,
    required List<double> vector,
    required String model,
  }) async {
    await into(cardEmbeddings).insertOnConflictUpdate(
      CardEmbeddingsCompanion.insert(
        factId: factId,
        dim: vector.length,
        vector: jsonEncode(vector),
        model: model,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
    );
  }

  /// Return all stored embeddings, decoding the JSON vector column.
  Future<List<({String factId, List<double> vector})>> all() async {
    final rows = await select(cardEmbeddings).get();
    return rows
        .map(
          (row) => (
            factId: row.factId,
            vector: (jsonDecode(row.vector) as List)
                .map((e) => (e as num).toDouble())
                .toList(),
          ),
        )
        .toList();
  }

  /// Delete the embedding for a given factId.
  Future<void> deleteByFactId(String factId) async {
    await (delete(cardEmbeddings)..where((tbl) => tbl.factId.equals(factId)))
        .go();
  }

  /// Remove all embeddings.
  Future<void> clear() async {
    await delete(cardEmbeddings).go();
  }

  /// Return the set of factIds that already have an embedding for [model].
  /// Used to determine which cards still need backfilling.
  Future<Set<String>> factIdsForModel(String model) async {
    final query = selectOnly(cardEmbeddings)
      ..addColumns([cardEmbeddings.factId])
      ..where(cardEmbeddings.model.equals(model));
    final rows = await query.get();
    return rows.map((row) => row.read(cardEmbeddings.factId)!).toSet();
  }
}

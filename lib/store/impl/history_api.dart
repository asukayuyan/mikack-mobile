import 'package:sqflite/sqflite.dart';

import '../../store.dart';
import '../models.dart';
import '../helper.dart';

Future<void> insertHistory(History history) async {
  final db = await database();
  await db.insert(History.tableName, history.toMap());
}

Future<void> insertHistories(List<History> histories) async {
  final db = await database();
  await db.transaction((tnx) async {
    var banch = tnx.batch();
    histories.forEach(
      (history) => banch.insert(History.tableName, history.toMap()),
    );
    banch.commit();
  });
}

Future<List<History>> findHistories(
    {forceDisplayed: true,
    String homeUrl,
    addressesIn = const <String>[]}) async {
  final db = await database();

  String where;
  List<dynamic> whereArgs = [];
  if (forceDisplayed) {
    where = 'displayed = ?';
    whereArgs = [1];
  }
  if (homeUrl != null) {
    if (where != null)
      where += ' AND ';
    else
      where = '';
    where += 'home_url = ?';
    whereArgs.add(homeUrl);
  }
  if (addressesIn.length > 0) {
    if (where != null)
      where += ' AND ';
    else
      where = '';
    where +=
        'address IN (${addressesIn.map((addr) => '\'$addr\'').toList().join(',')})';
  }
  final List<Map<String, dynamic>> maps = await db.query(
    History.tableName,
    orderBy: 'datetime(updated_at) DESC',
    where: where,
    whereArgs: whereArgs,
  );

  return maps.map((map) => History.fromMap(map)).toList();
}

Future<History> getHistory({int id, String address}) async {
  final db = await database();

  var cond = makeSingleCondition({'id': id, 'address': address});
  final List<Map<String, dynamic>> maps = await db.query(
    History.tableName,
    where: cond.item1,
    whereArgs: cond.item2,
    limit: 1,
  );
  if (maps.isEmpty) return null;

  return maps.map((map) => History.fromMap(map)).toList().first;
}

Future<History> getLastHistory(String homeUrl) async {
  final db = await database();
  final List<Map<String, dynamic>> maps = await db.query(
    History.tableName,
    where: 'home_url = ? AND displayed = 1',
    whereArgs: [homeUrl],
    limit: 1,
    orderBy: 'datetime(updated_at) DESC',
  );
  if (maps.isEmpty) return null;

  return maps.map((map) => History.fromMap(map)).toList().first;
}

Future<void> updateHistory(History history) async {
  final db = await database();

  history.updateAt = DateTime.now();
  await db.update(
    History.tableName,
    history.toMap(),
    where: 'id = ?',
    whereArgs: [history.id],
  );
}

Future<void> deleteHistory({int id, String address}) async {
  final db = await database();

  var cond = makeSingleCondition({'id': id, 'address': address});
  await db.delete(
    History.tableName,
    where: cond.item1,
    whereArgs: cond.item2,
  );
}

Future<void> deleteHistories({String homeUrl}) async {
  final db = await database();

  var cond = makeSingleCondition({'home_url': homeUrl});
  await db.delete(
    History.tableName,
    where: cond.item1,
    whereArgs: cond.item2,
  );
}

Future<void> deleteAllHistories() async {
  final db = await database();
  await db.delete(History.tableName);
}

Future<int> getHistoriesTotal() async {
  final db = await database();

  return Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM ${History.tableName} where displayed = 1'));
}

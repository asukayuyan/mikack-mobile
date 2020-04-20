import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:bloc/bloc.dart';
import 'package:mikack/models.dart' as models;
import 'package:quiver/iterables.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import 'package:tuple/tuple.dart';

import 'read_event.dart';
import 'read_state.dart';
import '../helper/compute_ext.dart';
import '../../store.dart';
import '../ext.dart';
import '../values.dart';

class ReadBloc extends Bloc<ReadEvent, ReadState> {
  final models.Platform platform;
  final models.Comic comic;

  ReadBloc({
    @required this.platform,
    @required this.comic,
  });

  @override
  ReadState get initialState => ReadLoadedState(
        isLeftHandMode: false,
        isShowToolbar: false,
        isLoading: true,
        currentPage: 0,
        pages: const [],
      );

  @override
  Stream<ReadState> mapEventToState(ReadEvent event) async* {
    switch (event.runtimeType) {
      case ReadSettingsRequestEvent: // 从存储中载入设置
        SharedPreferences prefs = await SharedPreferences.getInstance();
        // 读取：是否启用左后模式
        var isLeftHandMode = prefs.getBool(leftHandModeKey);
        if (isLeftHandMode == null) isLeftHandMode = false;
        yield (state as ReadLoadedState)
            .copyWith(isLeftHandMode: isLeftHandMode);
        break;
      case ReadCreatePageIteratorEvent: // 创建迭代器
        var castedEvent = event as ReadCreatePageIteratorEvent;
        _createPageIterator(platform, castedEvent.chapter)
            .then((createdPageIterator) {
          add(ReadChapterLoadedEvent(
            chapter: createdPageIterator.item2,
            pageIterator: createdPageIterator.item1.asPageIterator(),
          ));
        }).catchError((e) {
          print(e);
        });
        break;
      case ReadChapterLoadedEvent: // 章节数据装载
        var castedEvent = event as ReadChapterLoadedEvent;
        yield (state as ReadLoadedState).copyWith(
          isLoading: false,
          chapter: castedEvent.chapter,
          pageIterator: castedEvent.pageIterator,
          preFetchAt: 0,
        );
        // 载入第一页
        add(ReadNextPageEvent(page: 1));
        // 添加到阅读历史
        addHistory(castedEvent.chapter);
        break;
      case ReadNextPageEvent: // 请求下一页
        var castedEvent = event as ReadNextPageEvent;
        var stateSnapshot = state as ReadLoadedState;
        if (castedEvent.page > stateSnapshot.pages.length ||
            (castedEvent.isPreFetch &&
                castedEvent.page > stateSnapshot.preFetchAt - 2)) {
          // 载入后续页面（包括预加载）
          if (castedEvent.isPreFetch) {
            for (var _ in range(3)) {
              if (stateSnapshot.preFetchAt + 1 <=
                  stateSnapshot.chapter.pageCount) {
                // 自增预加载位置
                stateSnapshot = stateSnapshot.copyWith(
                    preFetchAt: stateSnapshot.preFetchAt + 1);
                yield stateSnapshot;
                // 获取下一页
                _fetchNextPage(stateSnapshot.pageIterator).then((address) {
                  add(ReadPageLoadedEvent(page: address));
                }).catchError((e) {
                  // TODO: 响应翻页错误
                  print(e);
                });
              }
            }
          } else {
            // 载入下一页（无预加载）
            if (stateSnapshot.preFetchAt < castedEvent.page) {
              _fetchNextPage(stateSnapshot.pageIterator).then((address) {
                add(ReadPageLoadedEvent(page: address));
              }).catchError((e) {
                // TODO: 响应翻页错误
                print(e);
              });
              stateSnapshot =
                  stateSnapshot.copyWith(preFetchAt: castedEvent.page);
              yield stateSnapshot;
            }
          }
        }
        // 修改页码
        if (castedEvent.isChangeCurrentPage)
          yield stateSnapshot.copyWith(
              currentPage: stateSnapshot.currentPage + 1);
        break;
      case ReadPrevPageEvent: // 请求上一页
        var stateSnapshot = state as ReadLoadedState;
        yield stateSnapshot.copyWith(
            currentPage: stateSnapshot.currentPage - 1);
        break;
      case ReadPageLoadedEvent: // 页面数据装载
        var castedEvent = event as ReadPageLoadedEvent;
        var castedState = state as ReadLoadedState;
        yield castedState
            .copyWith(pages: [...castedState.pages, castedEvent.page]);
        break;
      case ReadToolbarDisplayStatusChangedEvent: // 工具栏显示状态改变
        var stateSnapshot = state as ReadLoadedState;
        yield stateSnapshot.copyWith(
            isShowToolbar: !stateSnapshot.isShowToolbar);
        break;
      case ReadCurrentPageForceChangedEvent: // 强制修改当前页码
        var castedEvent = event as ReadCurrentPageForceChangedEvent;
        yield (state as ReadLoadedState)
            .copyWith(currentPage: castedEvent.page);
        break;
    }
  }

  // 添加阅读历史
  Future<void> addHistory(models.Chapter chapter) async {
    var history = await getHistory(address: chapter.url);
    if (history != null) {
      // 如果存在阅读历史，仅更新（并强制可见）
      history.title = chapter.title;
      history.homeUrl = comic.url;
      history.cover = comic.cover;
      history.displayed = true;
      await updateHistory(history);
    } else {
      // 创建阅读历史
      var source = await platform.toSavedSource();
      var history = History(
        sourceId: source.id,
        title: chapter.title,
        homeUrl: comic.url,
        address: chapter.url,
        cover: comic.cover,
        displayed: true,
      );
      await insertHistory(history);
    }
  }

  Future<Tuple2<ValuePageIterator, models.Chapter>> _createPageIterator(
    models.Platform platform,
    models.Chapter chapter,
  ) async {
    return await compute(_createPageIteratorTask, Tuple2(platform, chapter));
  }

  final lock = Lock(); // 同步调用迭代器（当前必须）

  Future<String> _fetchNextPage(models.PageIterator pageIterator) async {
    return lock.synchronized(() async {
      return await compute(
          _getNextAddressTask, pageIterator.asValuePageIterator());
    });
  }

  @override
  void onError(Object error, StackTrace stacktrace) {
    print(stacktrace);
    super.onError(error, stacktrace);
  }
}

Tuple2<ValuePageIterator, models.Chapter> _createPageIteratorTask(
    Tuple2<models.Platform, models.Chapter> args) {
  var platform = args.item1;
  var chapter = args.item2;

  var pageIterator = platform.createPageIter(chapter);

  return Tuple2(
    ValuePageIterator(
      pageIterator.createdIterPointer.address,
      pageIterator.iterPointer.address,
    ),
    chapter,
  );
}

String _getNextAddressTask(ValuePageIterator valuePageIterator) {
  return valuePageIterator.asPageIterator().next();
}
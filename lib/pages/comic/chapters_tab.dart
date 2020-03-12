import 'package:flutter/material.dart';
import 'package:mikack/models.dart' as models;

class ChaptersTab extends StatelessWidget {
  ChaptersTab(this.comic, {this.openReadPage});

  final models.Comic comic;
  final void Function(models.Chapter) openReadPage;

  @override
  Widget build(BuildContext context) {
    if (comic.chapters == null)
      return const Center(
        child: CircularProgressIndicator(),
      );
    return Scrollbar(
      child: ListView(
        children: comic.chapters
            .map((c) => ListTile(
                  title: Text(c.title),
                  trailing: IconButton(
                    icon: Icon(Icons.more_vert),
                    onPressed: () {},
                  ),
                  onTap: () => openReadPage(c),
                ))
            .toList(),
      ),
    );
  }
}
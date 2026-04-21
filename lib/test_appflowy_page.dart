// lib/test_appflowy_page.dart
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart' hide Document;

class TestAppFlowyPage extends StatefulWidget {
  const TestAppFlowyPage({super.key});

  @override
  State<TestAppFlowyPage> createState() => _TestAppFlowyPageState();
}

class _TestAppFlowyPageState extends State<TestAppFlowyPage> {
  late EditorState editorState;

  @override
  void initState() {
    super.initState();
    editorState = _buildInitialDocument();
  }

  @override
  void dispose() {
    editorState.dispose();
    super.dispose();
  }

  /// Build a document with CV-like sections to simulate real usage
  EditorState _buildInitialDocument() {
    final document = Document.blank()
      ..insert([0], [
        _heading('PERSONAL INFO'),
        _paragraph('John Doe | Flutter Developer | Lahore, Pakistan'),
        _divider(),
        _heading('SUMMARY'),
        _paragraph('Experienced Flutter developer with expertise in Firebase, REST APIs and clean architecture.'),
        _divider(),
        _heading('EXPERIENCE'),
        _paragraph('Incendios Solution — Flutter Developer (2024–Present)'),
        _divider(),
        _heading('EDUCATION'),
        _paragraph('BS Computer Science — Superior University (2021–2025)'),
        _divider(),
        _heading('SKILLS'),
        _paragraph('Flutter, Dart, Firebase, REST APIs, Riverpod, GetX, Provider'),
      ]);

    return EditorState(document: document);
  }

  Node _heading(String text) {
    final delta = Delta();
    delta.insert(text, attributes: {
      AppFlowyRichTextKeys.bold: true,
      AppFlowyRichTextKeys.textColor: '0xFF9E9E9E',
    });
    return Node(
      type: ParagraphBlockKeys.type,
      attributes: {
        ParagraphBlockKeys.delta: delta.toJson(),
      },
    );
  }

  Node _paragraph(String text) {
    final delta = Delta();
    delta.insert(text);
    return Node(
      type: ParagraphBlockKeys.type,
      attributes: {
        ParagraphBlockKeys.delta: delta.toJson(),
      },
    );
  }

  Node _divider() => Node(
    type: DividerBlockKeys.type,
    attributes: {},
  );

  @override
  Widget build(BuildContext context) {
    final editor = AppFlowyEditor(
      editorState: editorState,
      editorStyle: const EditorStyle.desktop(),
      blockComponentBuilders: {
        ...standardBlockComponentBuilderMap,
      },
      commandShortcutEvents: standardCommandShortcutEvents,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test: AppFlowy Editor Spike'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Print document JSON',
            onPressed: () {
              final json = editorState.document.toJson();
              debugPrint('Document JSON: $json');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Document JSON printed to console')),
              );
            },
          ),
        ],
      ),
      body: Container(
        color: Colors.grey.shade300,
        child: Center(
          child: Container(
            width: 595,
            // A4 height — fixed so appflowy_editor gets finite constraints
            height: 842,
            margin: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(40),
            // AppFlowy handles its own internal scrolling
            child: editor,
          ),
        ),
      ),
    );
  }
}
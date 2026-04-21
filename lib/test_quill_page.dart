// lib/test_quill_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';

class TestQuillPage extends StatefulWidget {
  final QuillController controller;
  const TestQuillPage({super.key, required this.controller});

  @override
  State<TestQuillPage> createState() => _TestQuillPageState();
}

class _TestQuillPageState extends State<TestQuillPage> {
  String _deltaJson = '';

  // Map: toolbar display name → Delta attribute value (what gets stored in Delta)
  static const Map<String, String> _fontFamilyValues = {
    'Arial': 'Arial',
    'Open Sans': 'OpenSans',
    'Poppins': 'Poppins',
    'Sekuya': 'Sekuya',
  };

  // Map: Delta attribute value → Flutter font family name (registered in pubspec.yaml)
  // These MUST match the "family:" keys in pubspec.yaml exactly.
  static const Map<String, String> _deltaValueToFlutterFamily = {
    'Arial': 'Arial',
    'OpenSans': 'OpenSans',
    'Poppins': 'Poppins',
    'Sekuya': 'Sekuya',
  };

  /// This is the critical fix for Test 1.
  /// Quill calls this for every text span. We inspect the 'font' attribute
  /// and return a TextStyle with the correct fontFamily.
  TextStyle _customStyleBuilder(Attribute attribute) {
    if (attribute.key == Attribute.font.key) {
      final deltaValue = attribute.value as String?;
      final flutterFamily = _deltaValueToFlutterFamily[deltaValue];
      if (flutterFamily != null) {
        return TextStyle(fontFamily: flutterFamily);
      }
    }
    return const TextStyle(); // return empty style for all other attributes
  }

  void _saveDocument() {
    final delta = widget.controller.document.toDelta();
    setState(() {
      _deltaJson = jsonEncode(delta.toJson()); // ← was delta.toJson().toString()
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Document Delta saved to memory')),
    );
  }

  void _loadDocument() {
    if (_deltaJson.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved Delta to load')),
      );
      return;
    }
    try {
      // FIX: _deltaJson is a String, not a List. We need to use jsonDecode.
      // Add this import at the top: import 'dart:convert';
      final List<dynamic> jsonList = jsonDecode(_deltaJson);
      final delta = Delta.fromJson(jsonList);
      widget.controller.document = Document.fromDelta(delta);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document loaded from Delta')),
      );
    } catch (e) {
      debugPrint('Delta is : $_deltaJson');
      debugPrint('Error loading Delta: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading Delta: $e')),
      );
    }
  }

  void _clearDocument() {
    widget.controller.clear();
    setState(() => _deltaJson = '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test 1: Quill Editor'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saveDocument, tooltip: 'Save'),
          IconButton(icon: const Icon(Icons.folder_open), onPressed: _loadDocument, tooltip: 'Load'),
          IconButton(icon: const Icon(Icons.clear), onPressed: _clearDocument, tooltip: 'Clear'),
        ],
      ),
      body: Column(
        children: [
          QuillSimpleToolbar(
            controller: widget.controller,
            config: QuillSimpleToolbarConfig(
              buttonOptions: QuillSimpleToolbarButtonOptions(
                fontFamily: QuillToolbarFontFamilyButtonOptions(
                  items: _fontFamilyValues,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: QuillEditor.basic(
                controller: widget.controller,
                config: QuillEditorConfig(
                  scrollable: true,
                  autoFocus: true,
                  expands: false,
                  padding: EdgeInsets.zero,
                  placeholder: 'Start writing your CV content...',
                  // ✅ THE FIX: wire up the custom style builder
                  customStyleBuilder: _customStyleBuilder,
                ),
              ),
            ),
          ),
          Container(
            height: 120,
            width: double.infinity,
            color: Colors.grey.shade200,
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Saved Delta JSON:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      _deltaJson.isEmpty ? '(No saved delta)' : _deltaJson,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
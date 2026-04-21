// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:kitaura/test_appflowy_page.dart';
import 'package:kitaura/test_canvas_page.dart';
import 'test_quill_page.dart';
import 'test_pdf_page.dart';

void main() {
  runApp(const TestBenchApp());
}

class TestBenchApp extends StatelessWidget {
  const TestBenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Craftlytix Test Bench',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'),
      ],
      home: const TestBenchHome(),
    );
  }
}

class TestBenchHome extends StatefulWidget {
  const TestBenchHome({super.key});

  @override
  State<TestBenchHome> createState() => _TestBenchHomeState();
}

class _TestBenchHomeState extends State<TestBenchHome> {
  // Shared QuillController for passing between tests
  late QuillController _sharedController;

  @override
  void initState() {
    super.initState();
    _sharedController = QuillController.basic();
  }

  @override
  void dispose() {
    _sharedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Craftlytix Module Testing')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TestQuillPage(controller: _sharedController),
                  ),
                );
              },
              child: const Text('Test 1: Quill Editor (Rich Text)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TestPdfPage(controller: _sharedController),
                  ),
                );
              },
              child: const Text('Test 2: PDF Generation'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TestCanvasPage()),
                );
              },
              child: const Text('Test 3: Drag-Drop Canvas'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Test 4: Claude AI Call
              },
              child: const Text('Test 4: Claude API (Streaming)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TestAppFlowyPage()),
                );
              },
              child: const Text('Test: AppFlowy Spike'),
            ),
          ],
        ),
      ),
    );
  }
}
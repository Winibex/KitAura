# KitAura — Testing & Memory Leak Detection Guide

> Created: May 17, 2026
> For: Auth flow tests + general testing knowledge

---

## 1. PROJECT SETUP

### Add dev dependencies to pubspec.yaml:

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  mockito: ^5.4.4
  build_runner: ^2.4.8
  # Optional — for Firebase mock tests later:
  # fake_cloud_firestore: ^3.1.0
  # firebase_auth_mocks: ^0.14.1
```

### File structure:

```
test/
  unit/
    auth/
      validators_test.dart         ← Pure validation logic
      user_model_test.dart         ← Model serialization
      auth_controller_test.dart    ← Controller state & validation
```

---

## 2. HOW TO RUN TESTS

```bash
# Run ALL tests
flutter test

# Run a specific test file
flutter test test/unit/auth/validators_test.dart

# Run tests with verbose output (see each test name)
flutter test --reporter expanded

# Run only tests matching a name pattern
flutter test --name "password"

# Run tests with coverage report
flutter test --coverage
# Then view: genhtml coverage/lcov.info -o coverage/html
# Open: coverage/html/index.html
```

---

## 3. TEST ANATOMY — READ THIS

Every test file follows this pattern:

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  // group() organizes related tests
  group('SubscriptionModel', () {

    // setUp() runs BEFORE each test in this group
    late SubscriptionModel model;
    setUp(() {
      model = SubscriptionModel();
    });

    // test() is ONE test case with ONE assertion focus
    test('free plan has 3 export limit', () {
      expect(model.canExport, true);
      expect(model.exportsRemaining, 3);
    });

    // Naming convention: describe the EXPECTED behavior
    test('returns false when export count reaches 3', () {
      final full = SubscriptionModel(exportCount: 3);
      expect(full.canExport, false);
    });
  });
}
```

### Key functions:
| Function | Purpose |
|---|---|
| `group('name', () {})` | Groups related tests. Can nest. |
| `test('name', () {})` | One test case. |
| `setUp(() {})` | Runs before EACH test in the group. |
| `tearDown(() {})` | Runs after EACH test (cleanup). |
| `setUpAll(() {})` | Runs once before ALL tests in group. |
| `expect(actual, matcher)` | The assertion. Test fails if it doesn't match. |

### Common matchers:
| Matcher | What it checks |
|---|---|
| `equals(x)` or just `x` | Exact equality |
| `isNull` | Value is null |
| `isNotNull` | Value is not null |
| `isTrue` / `isFalse` | Boolean check |
| `contains('text')` | String/list contains |
| `isA<Type>()` | Type check |
| `isEmpty` / `isNotEmpty` | Collection check |
| `hasLength(n)` | Collection length |
| `throwsA(isA<TypeError>())` | Expected exception |
| `isNot(matcher)` | Negates any matcher |

---

## 4. WHAT EACH TEST FILE COVERS

### validators_test.dart (12 tests)
- Tests the `Validators` utility class directly
- No Firebase, no state, pure input → output
- Covers: email format, password length, required fields, confirm match
- **Why it matters:** These validations prevent wasted Firebase API calls

### user_model_test.dart (30+ tests)
- Tests every model's `toJson()` / `fromJson()` round-trip
- Tests default values, computed properties (`isPro`, `canExport`)
- Tests `copyWith()` only changes specified fields
- **Why it matters:** If serialization breaks, Firestore saves/loads corrupt data silently

### auth_controller_test.dart (25+ tests)
- Tests validation order (name → email → password → confirm)
- Tests state transitions (isLoading, error, navigate)
- Tests `clearError()` behavior
- Tests `AuthState.copyWith()` auto-reset logic
- **Why it matters:** The controller is the brain of auth — bugs here = locked out users

---

## 5. NEXT LEVEL: TESTING WITH MOCK FIREBASE

Once you're comfortable with unit tests, add Firebase mocks for full flow testing:

```yaml
dev_dependencies:
  firebase_auth_mocks: ^0.14.1
  fake_cloud_firestore: ^3.1.0
```

```dart
// Example: mock sign-in flow
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

final mockUser = MockUser(
  uid: 'test-uid',
  email: 'test@example.com',
  displayName: 'Test User',
);

final mockAuth = MockFirebaseAuth(
  mockUser: mockUser,
  signedIn: false,
);

// Now you can test the full sign-in flow:
test('signInWithEmail sets navigate to dashboard', () async {
  // This requires refactoring FirebaseService to accept injected
  // FirebaseAuth instance instead of using the static singleton.
  // That's the "make FirebaseService testable" item from the audit.
});
```

**This is Issue #10 from the audit** — FirebaseService being static blocks full mock testing. When you refactor it to accept injected dependencies, you unlock these tests. For now, the validation-level tests catch 80% of bugs.

---

## 6. MEMORY LEAK DETECTION IN FLUTTER WEB

### Method 1: Chrome DevTools (Recommended — no packages needed)

This is the most reliable approach for Flutter Web:

1. **Run your app in Chrome debug mode:**
   ```bash
   flutter run -d chrome --web-renderer html
   ```

2. **Open Chrome DevTools** → Memory tab

3. **Take a heap snapshot:**
    - Click "Take snapshot" at the start
    - Navigate around your app (open auth → dashboard → editor → back)
    - Take another snapshot
    - Compare: any objects growing that shouldn't be?

4. **Key things to look for:**
    - **Timer objects** that keep incrementing (your verify email polling!)
    - **StreamSubscription** objects that aren't cancelled
    - **TextEditingController / ScrollController / FocusNode** that aren't disposed
    - **QuillController** objects surviving after editor is closed

5. **Allocation timeline:**
    - Switch to "Allocation instrumentation on timeline"
    - Record while navigating
    - Blue bars = allocated, grey = freed
    - Persistent blue bars = potential leaks

### Method 2: Flutter DevTools Memory Tab

```bash
# Run with observatory
flutter run -d chrome --observatory-port=9100

# Open Flutter DevTools
flutter pub global run devtools
```

- Go to the **Memory** tab
- Click **Track widget rebuilds** (bottom toolbar)
- Navigate your app
- Watch the memory graph:
    - Steady line = good
    - Steadily climbing = leak
    - Sawtooth pattern = normal (GC cycles)

### Method 3: Manual Leak Detection (add to code temporarily)

```dart
// Add this to any StatefulWidget to detect if it leaks:
class _MyWidgetState extends State<MyWidget> {
  @override
  void dispose() {
    debugPrint('🗑️ _MyWidgetState disposed');
    super.dispose();
  }
}

// If you navigate away and DON'T see the dispose print,
// the widget is leaking (still held in memory).
```

### Common Flutter Web Memory Leaks:

| Leak Source | How to Detect | Fix |
|---|---|---|
| **Timer not cancelled** | Timer count grows in heap | Cancel in `dispose()` |
| **StreamSubscription not cancelled** | Subscription objects grow | Cancel in `dispose()` |
| **TextEditingController not disposed** | Controller objects accumulate | Call `.dispose()` |
| **FocusNode not disposed** | FocusNode count grows | Call `.dispose()` |
| **Riverpod listener not cleaning up** | Provider stays alive | Use `autoDispose` providers |
| **GoRouter keeping old screens** | Screen widgets pile up | Check route config |
| **Image cache growing** | Memory climbs with images | `PaintingBinding.instance.imageCache.clear()` |
| **QuillController not disposed** | Delta objects accumulate | Call `.dispose()` |

### Your Specific Leak Risks (from audit):

1. **VerifyEmailScreen** — `_pollingTimer` and `_cooldownTimer` must cancel in `dispose()` ✅ (already fixed in optimized code)

2. **AuthScreen** — 6 TextEditingControllers must all dispose ✅ (already fixed)

3. **Canvas editor** — QuillController per text section must dispose when item is deleted ✅ (already handled per project context)

### Method 4: Automated Leak Detection (Advanced)

```dart
// Add to your test setup for automated detection:
// This catches undisposed controllers in tests.

import 'package:leak_tracker/leak_tracker.dart';

void main() {
  // Only works in debug/test mode
  LeakTracking.start();

  // ... your tests ...

  tearDownAll(() async {
    await LeakTracking.stop();
    // Will print warnings about any detected leaks
  });
}
```

Note: `leak_tracker` is experimental and works best with native platforms. For Flutter Web, Chrome DevTools heap snapshots are more reliable.

---

## 7. TESTING WORKFLOW (do this every time)

```
1. Write the feature code
2. Write tests for it
3. Run: flutter test
4. All green? → commit
5. Red? → fix the code (not the test!)
6. Before PR/merge: flutter test --coverage
```

### Golden rule:
- Tests should test BEHAVIOR, not implementation
- "canExport returns false at limit" ✓
- "canExport checks if exportCount < 3" ✗ (tests implementation detail)

---

## 8. WHAT TO TEST NEXT

After these auth tests, here's the priority order:

| Feature | Test Type | What to Test |
|---|---|---|
| Canvas CanvasItem model | Unit | Serialization, dispose, default values |
| Template JSON parsing | Unit | Round-trip export/import, malformed JSON handling |
| Subscription paywall logic | Unit | All limit checks, pro bypass, edge cases |
| FirebaseService (after refactor) | Unit + Mock | Batch operations, error handling |
| Auth screen UI | Widget | Tab switching, error display, button states |
| Canvas editor | Widget | Add/delete/select items, undo/redo |
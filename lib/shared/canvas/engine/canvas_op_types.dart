// lib/shared/canvas/engine/canvas_op_types.dart
//
// Data types for natural-language editor commands (command-K AI editor).
//
// These classes are PURE DATA — no logic, no Firebase, no Quill. They define
// the vocabulary the Cloud Function returns and the executor consumes.
//
// LAYOUT:
//   1. CanvasOp base class + 11 concrete op subclasses (sealed family)
//   2. AiEditEnvelope — what the Cloud Function returns
//   3. OpResult / OpFailure — what applyOps returns to the UI
//   4. Enums for constrained string fields (modes, scopes, actions)
//
// USAGE:
//   final envelope = AiEditEnvelope.fromJson(response['envelope']);
//   final result = await canvasController.applyOps(envelope.ops);

import 'package:flutter/foundation.dart';

// ════════════════════════════════════════════════════════════════════════
// 1. ENUMS for constrained string fields
// ════════════════════════════════════════════════════════════════════════

/// updateText.mode
enum TextEditMode {
  replaceLine,
  deleteLine,
  insertLine,
  replaceRange,
  unknown;

  static TextEditMode fromString(String? s) {
    switch (s) {
      case 'replaceLine':
        return TextEditMode.replaceLine;
      case 'deleteLine':
        return TextEditMode.deleteLine;
      case 'insertLine':
        return TextEditMode.insertLine;
      case 'replaceRange':
        return TextEditMode.replaceRange;
      default:
        return TextEditMode.unknown;
    }
  }
}

/// formatText.scope
enum FormatScope {
  whole,
  line,
  range,
  unknown;

  static FormatScope fromString(String? s) {
    switch (s) {
      case 'whole':
        return FormatScope.whole;
      case 'line':
        return FormatScope.line;
      case 'range':
        return FormatScope.range;
      default:
        return FormatScope.unknown;
    }
  }
}

/// moveItem.align
enum MoveAlign {
  centerH,
  centerV,
  left,
  right,
  top,
  bottom,
  none;

  static MoveAlign fromString(String? s) {
    switch (s) {
      case 'centerH':
        return MoveAlign.centerH;
      case 'centerV':
        return MoveAlign.centerV;
      case 'left':
        return MoveAlign.left;
      case 'right':
        return MoveAlign.right;
      case 'top':
        return MoveAlign.top;
      case 'bottom':
        return MoveAlign.bottom;
      default:
        return MoveAlign.none;
    }
  }
}

/// updateCanvas.pageAction
enum PageAction {
  add,
  removeLast,
  removeAt,
  none;

  static PageAction fromString(String? s) {
    switch (s) {
      case 'add':
        return PageAction.add;
      case 'removeLast':
        return PageAction.removeLast;
      case 'removeAt':
        return PageAction.removeAt;
      default:
        return PageAction.none;
    }
  }
}

/// generateContent.mode
enum GenerateMode {
  replace,
  append,
  rewrite,
  unknown;

  static GenerateMode fromString(String? s) {
    switch (s) {
      case 'replace':
        return GenerateMode.replace;
      case 'append':
        return GenerateMode.append;
      case 'rewrite':
        return GenerateMode.rewrite;
      default:
        return GenerateMode.unknown;
    }
  }
}

/// updateTable.action
enum TableAction {
  setCell,
  setRow,
  setColumn,
  addRow,
  addColumn,
  deleteRow,
  deleteColumn,
  setHeaderStyle,
  setBorderStyle,
  unknown;

  static TableAction fromString(String? s) {
    switch (s) {
      case 'setCell':
        return TableAction.setCell;
      case 'setRow':
        return TableAction.setRow;
      case 'setColumn':
        return TableAction.setColumn;
      case 'addRow':
        return TableAction.addRow;
      case 'addColumn':
        return TableAction.addColumn;
      case 'deleteRow':
        return TableAction.deleteRow;
      case 'deleteColumn':
        return TableAction.deleteColumn;
      case 'setHeaderStyle':
        return TableAction.setHeaderStyle;
      case 'setBorderStyle':
        return TableAction.setBorderStyle;
      default:
        return TableAction.unknown;
    }
  }
}

// ════════════════════════════════════════════════════════════════════════
// 2. SEALED OP FAMILY
//
// Every op has a `kind` string for debug logging. Concrete subclasses carry
// their own typed fields. The factory `CanvasOp.fromJson` dispatches to the
// right subclass based on the "op" field.
// ════════════════════════════════════════════════════════════════════════

@immutable
sealed class CanvasOp {
  /// The "op" string from the JSON envelope. Used for logging only — type
  /// dispatch is via the sealed family.
  final String kind;
  const CanvasOp(this.kind);

  /// Routes raw JSON to the right concrete op class.
  /// Returns an UnknownOp if the kind isn't recognized (executor logs it
  /// as a failure rather than crashing).
  factory CanvasOp.fromJson(Map<String, dynamic> json) {
    final kind = json['op'] as String? ?? '';
    switch (kind) {
      case 'updateText':
        return UpdateTextOp.fromJson(json);
      case 'formatText':
        return FormatTextOp.fromJson(json);
      case 'updateItem':
        return UpdateItemOp.fromJson(json);
      case 'moveItem':
        return MoveItemOp.fromJson(json);
      case 'deleteItem':
        return DeleteItemOp.fromJson(json);
      case 'duplicateItem':
        return DuplicateItemOp.fromJson(json);
      case 'addItem':
        return AddItemOp.fromJson(json);
      case 'updateCanvas':
        return UpdateCanvasOp.fromJson(json);
      case 'generateContent':
        return GenerateContentOp.fromJson(json);
      case 'updateTable':
        return UpdateTableOp.fromJson(json);
      case 'updateReflow':
        return UpdateReflowOp.fromJson(json);
      default:
        return UnknownOp(kind: kind, raw: json);
    }
  }
}

// ─── 1. updateText ──────────────────────────────────────────────────────
class UpdateTextOp extends CanvasOp {
  final String itemId;
  final TextEditMode mode;
  final int? lineIndex;
  final List<int>? range; // [start, end] absolute delta offsets
  final String? newText;

  const UpdateTextOp({
    required this.itemId,
    required this.mode,
    this.lineIndex,
    this.range,
    this.newText,
  }) : super('updateText');

  factory UpdateTextOp.fromJson(Map<String, dynamic> json) => UpdateTextOp(
    itemId: json['itemId'] as String? ?? '',
    mode: TextEditMode.fromString(json['mode'] as String?),
    lineIndex: (json['lineIndex'] as num?)?.toInt(),
    range: (json['range'] as List?)?.map((e) => (e as num).toInt()).toList(),
    newText: json['newText'] as String?,
  );
}

// ─── 2. formatText ──────────────────────────────────────────────────────
class FormatTextOp extends CanvasOp {
  final String itemId;
  final FormatScope scope;
  final int? lineIndex;
  final List<int>? range;

  /// Quill attribute map. Keys present with non-null value = SET. Keys
  /// present with null value = CLEAR. Keys absent = LEAVE ALONE.
  /// Supported keys: bold, italic, underline, color, size, font, align.
  final Map<String, dynamic>? attrs;

  const FormatTextOp({
    required this.itemId,
    required this.scope,
    this.lineIndex,
    this.range,
    this.attrs,
  }) : super('formatText');

  factory FormatTextOp.fromJson(Map<String, dynamic> json) => FormatTextOp(
    itemId: json['itemId'] as String? ?? '',
    scope: FormatScope.fromString(json['scope'] as String?),
    lineIndex: (json['lineIndex'] as num?)?.toInt(),
    range: (json['range'] as List?)?.map((e) => (e as num).toInt()).toList(),
    attrs: json['attrs'] is Map
        ? Map<String, dynamic>.from(json['attrs'] as Map)
        : null,
  );
}

// ─── 3. updateItem ──────────────────────────────────────────────────────
class UpdateItemOp extends CanvasOp {
  final String itemId;

  /// Item visual props. Same semantics as FormatTextOp.attrs (null = clear,
  /// absent = leave alone).
  /// Supported keys: color, borderColor, borderWidth, rotation, flipX, flipY,
  /// w, h.
  final Map<String, dynamic> props;

  const UpdateItemOp({
    required this.itemId,
    required this.props,
  }) : super('updateItem');

  factory UpdateItemOp.fromJson(Map<String, dynamic> json) => UpdateItemOp(
    itemId: json['itemId'] as String? ?? '',
    props: json['props'] is Map
        ? Map<String, dynamic>.from(json['props'] as Map)
        : const {},
  );
}

// ─── 4. moveItem ────────────────────────────────────────────────────────
class MoveItemOp extends CanvasOp {
  final String itemId;
  final int? toPage; // 1-based
  final MoveAlign align;
  final double? x;
  final double? y;
  final double? dx;
  final double? dy;

  const MoveItemOp({
    required this.itemId,
    this.toPage,
    this.align = MoveAlign.none,
    this.x,
    this.y,
    this.dx,
    this.dy,
  }) : super('moveItem');

  factory MoveItemOp.fromJson(Map<String, dynamic> json) => MoveItemOp(
    itemId: json['itemId'] as String? ?? '',
    toPage: (json['toPage'] as num?)?.toInt(),
    align: MoveAlign.fromString(json['align'] as String?),
    x: (json['x'] as num?)?.toDouble(),
    y: (json['y'] as num?)?.toDouble(),
    dx: (json['dx'] as num?)?.toDouble(),
    dy: (json['dy'] as num?)?.toDouble(),
  );
}

// ─── 5. deleteItem ──────────────────────────────────────────────────────
class DeleteItemOp extends CanvasOp {
  final String itemId;
  const DeleteItemOp({required this.itemId}) : super('deleteItem');

  factory DeleteItemOp.fromJson(Map<String, dynamic> json) =>
      DeleteItemOp(itemId: json['itemId'] as String? ?? '');
}

// ─── 6. duplicateItem ───────────────────────────────────────────────────
class DuplicateItemOp extends CanvasOp {
  final String itemId;
  final int? toPage;
  final double? offsetY;

  const DuplicateItemOp({
    required this.itemId,
    this.toPage,
    this.offsetY,
  }) : super('duplicateItem');

  factory DuplicateItemOp.fromJson(Map<String, dynamic> json) =>
      DuplicateItemOp(
        itemId: json['itemId'] as String? ?? '',
        toPage: (json['toPage'] as num?)?.toInt(),
        offsetY: (json['offsetY'] as num?)?.toDouble(),
      );
}

// ─── 7. addItem ─────────────────────────────────────────────────────────
class AddItemOp extends CanvasOp {
  /// CanvasItemType string — "textSection", "rectangle", "line", etc.
  final String type;
  final int? page; // 1-based
  final double? x;
  final double? y;
  final double? w;
  final double? h;
  final String? color;
  final String? sectionType;
  final String? title;
  final String? initialText;
  final String? role;
  final String? group;

  const AddItemOp({
    required this.type,
    this.page,
    this.x,
    this.y,
    this.w,
    this.h,
    this.color,
    this.sectionType,
    this.title,
    this.initialText,
    this.role,
    this.group,
  }) : super('addItem');

  factory AddItemOp.fromJson(Map<String, dynamic> json) => AddItemOp(
    type: json['type'] as String? ?? '',
    page: (json['page'] as num?)?.toInt(),
    x: (json['x'] as num?)?.toDouble(),
    y: (json['y'] as num?)?.toDouble(),
    w: (json['w'] as num?)?.toDouble(),
    h: (json['h'] as num?)?.toDouble(),
    color: json['color'] as String?,
    sectionType: json['sectionType'] as String?,
    title: json['title'] as String?,
    initialText: json['initialText'] as String?,
    role: json['role'] as String?,
    group: json['group'] as String?,
  );
}

// ─── 8. updateCanvas ────────────────────────────────────────────────────
class UpdateCanvasOp extends CanvasOp {
  final String? canvasBackground;
  final PageAction pageAction;
  final int? pageIndex; // 0-based, for removeAt

  const UpdateCanvasOp({
    this.canvasBackground,
    this.pageAction = PageAction.none,
    this.pageIndex,
  }) : super('updateCanvas');

  factory UpdateCanvasOp.fromJson(Map<String, dynamic> json) => UpdateCanvasOp(
    canvasBackground: json['canvasBackground'] as String?,
    pageAction: PageAction.fromString(json['pageAction'] as String?),
    pageIndex: (json['pageIndex'] as num?)?.toInt(),
  );
}

// ─── 9. generateContent ─────────────────────────────────────────────────
class GenerateContentOp extends CanvasOp {
  final String itemId;
  final String? sectionType;
  final GenerateMode mode;
  final String instruction;
  final String? tone;

  const GenerateContentOp({
    required this.itemId,
    this.sectionType,
    required this.mode,
    required this.instruction,
    this.tone,
  }) : super('generateContent');

  factory GenerateContentOp.fromJson(Map<String, dynamic> json) =>
      GenerateContentOp(
        itemId: json['itemId'] as String? ?? '',
        sectionType: json['sectionType'] as String?,
        mode: GenerateMode.fromString(json['mode'] as String?),
        instruction: json['instruction'] as String? ?? '',
        tone: json['tone'] as String?,
      );
}

// ─── 10. updateTable ────────────────────────────────────────────────────
class UpdateTableOp extends CanvasOp {
  final String itemId;
  final TableAction action;
  final int? row;
  final int? col;
  final String? value;
  final List<String>? rowValues;
  final Map<String, dynamic>? style;

  const UpdateTableOp({
    required this.itemId,
    required this.action,
    this.row,
    this.col,
    this.value,
    this.rowValues,
    this.style,
  }) : super('updateTable');

  factory UpdateTableOp.fromJson(Map<String, dynamic> json) => UpdateTableOp(
    itemId: json['itemId'] as String? ?? '',
    action: TableAction.fromString(json['action'] as String?),
    row: (json['row'] as num?)?.toInt(),
    col: (json['col'] as num?)?.toInt(),
    value: json['value'] as String?,
    rowValues: (json['rowValues'] as List?)
        ?.map((e) => e?.toString() ?? '')
        .toList(),
    style: json['style'] is Map
        ? Map<String, dynamic>.from(json['style'] as Map)
        : null,
  );
}

// ─── 11. updateReflow ───────────────────────────────────────────────────
class UpdateReflowOp extends CanvasOp {
  final String itemId;

  /// One of: hero, top_band, pinned, heading, underline, signature, or null
  /// (null clears the role).
  /// Sentinel: present in fromJson with `null` value means "clear". Absent
  /// means "leave alone". We distinguish via [hasRole].
  final String? role;
  final bool hasRole;

  final String? group;
  final bool hasGroup;

  final double? beforeHeadingGap;

  const UpdateReflowOp({
    required this.itemId,
    this.role,
    this.hasRole = false,
    this.group,
    this.hasGroup = false,
    this.beforeHeadingGap,
  }) : super('updateReflow');

  factory UpdateReflowOp.fromJson(Map<String, dynamic> json) => UpdateReflowOp(
    itemId: json['itemId'] as String? ?? '',
    role: json['role'] as String?,
    hasRole: json.containsKey('role'),
    group: json['group'] as String?,
    hasGroup: json.containsKey('group'),
    beforeHeadingGap: (json['beforeHeadingGap'] as num?)?.toDouble(),
  );
}

// ─── Unknown / fallback ─────────────────────────────────────────────────
/// Catches any op the AI invents that we don't recognize. Executor logs it
/// as a failure but doesn't crash. Useful for graceful forward-compat.
class UnknownOp extends CanvasOp {
  final Map<String, dynamic> raw;
  const UnknownOp({required String kind, required this.raw}) : super(kind);
}

// ════════════════════════════════════════════════════════════════════════
// 3. ENVELOPE — Cloud Function response
// ════════════════════════════════════════════════════════════════════════

class AiEditEnvelope {
  /// The ordered list of ops to apply. Empty if [refusal] is non-null.
  final List<CanvasOp> ops;

  /// Human-readable one-line summary. Shown in the result strip.
  /// For refusals, this is also the user-facing message.
  final String summary;

  /// AI's own warnings (e.g. "Couldn't find a 'skills' section to delete").
  /// Shown alongside the result strip.
  final List<String> warnings;

  /// If non-null, the AI declined the request. Possible values:
  ///   - "off-topic" — request wasn't an editing task
  ///   - "unsafe" — content policy refusal
  ///   - "unsupported" — couldn't express in any op
  /// When set, [ops] is always empty.
  final String? refusal;

  const AiEditEnvelope({
    required this.ops,
    required this.summary,
    required this.warnings,
    this.refusal,
  });

  bool get isRefusal => refusal != null && refusal!.isNotEmpty;

  factory AiEditEnvelope.fromJson(Map<String, dynamic> json) {
    final rawOps = (json['ops'] as List?) ?? const [];
    return AiEditEnvelope(
      ops: rawOps
          .whereType<Map>()
          .map((m) => CanvasOp.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      summary: json['summary'] as String? ?? '',
      warnings: (json['warnings'] as List?)
          ?.map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList() ??
          const [],
      refusal: json['refusal'] as String?,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// 4. RESULT — what applyOps returns to the UI
// ════════════════════════════════════════════════════════════════════════

/// Why a single op failed. Code drives analytics; message is shown to user.
class OpFailure {
  /// One of: itemNotFound, wrongItemType, invalidIndex, notImplemented,
  /// executionError, unknownOp.
  final String code;
  final String message;

  /// Which op this failure relates to (kind string + index in the original
  /// ops list, for debug logs).
  final String opKind;
  final int opIndex;

  const OpFailure({
    required this.code,
    required this.message,
    required this.opKind,
    required this.opIndex,
  });

  @override
  String toString() => '[$opIndex/$opKind] $code: $message';
}

/// Outcome of running an ops list. The UI uses this to render the result
/// strip ("Made 4 edits. 1 couldn't be applied: ..."), to commit the AI
/// edit to undo history, and to schedule async generateContent calls.
class OpResult {
  /// How many ops ran successfully.
  final int appliedCount;

  /// Per-op failures, in original order. Empty list = full success.
  final List<OpFailure> failures;

  /// Warnings forwarded from the AI envelope (not generated by the executor).
  final List<String> warnings;

  /// AI's one-line summary, copied from the envelope for convenience.
  final String summary;

  /// True if [summary] is a refusal message and no ops ran.
  final bool isRefusal;

  /// generateContent ops that are still running async. The UI shows per-op
  /// spinners on these; resolved as they complete.
  final List<Future<void>> pendingGenerations;

  const OpResult({
    required this.appliedCount,
    required this.failures,
    required this.warnings,
    required this.summary,
    required this.isRefusal,
    required this.pendingGenerations,
  });

  bool get hasFailures => failures.isNotEmpty;
  bool get isFullSuccess => !isRefusal && failures.isEmpty && appliedCount > 0;
}
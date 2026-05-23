// =============================================================================
// TRANSACTION LOG
// Firestore path: users/{uid}/transactions/{txId}
//
// An append-only audit trail of every significant user action. Each document
// records what happened, when, and which CV was involved (if any).
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

/// Enumeration of all recordable event types.
/// Stored as a string in Firestore for readability (use `.name`).
enum TransactionType {
  export,
  aiFill,
  cvCreated,
  cvDeleted,
  planUpgrade,
  planDowngrade,
}

class TransactionModel {
  final String id;                        // Firestore document ID
  final String type;                      // TransactionType.name string
  final String? cvId;                     // associated CV (if applicable)
  final String? cvTitle;                  // snapshot of CV title at event time
  final Map<String, dynamic>? metadata;   // arbitrary extra context
  final DateTime createdAt;

  TransactionModel({
    required this.id,
    required this.type,
    this.cvId,
    this.cvTitle,
    this.metadata,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'id':        id,
    'type':      type,
    'cvId':      cvId,
    'cvTitle':   cvTitle,
    'metadata':  metadata,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id:        json['id']      ?? '',
      type:      json['type']    ?? '',
      cvId:      json['cvId'],
      cvTitle:   json['cvTitle'],
      metadata:  json['metadata'],
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
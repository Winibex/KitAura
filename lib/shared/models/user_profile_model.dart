// =============================================================================
// USER PROFILE
// Firestore path: users/{uid}
//
// The root document for every registered user. Created atomically alongside
// the subscription, AI profile, and preferences documents on first sign-up.
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfileModel {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;   // nullable — not all providers supply a photo
  final String? phone;
  final String? location;
  final String? bio;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfileModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.phone,
    this.location,
    this.bio,
    required this.createdAt,
    DateTime? updatedAt,
    // Default updatedAt to createdAt on first construction so the field is
    // always populated without requiring the caller to pass both timestamps.
  }) : updatedAt = updatedAt ?? createdAt;

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// Converts the data to a Firestore-compatible map.
  /// [DateTime] values are stored as [Timestamp] so Firestore can index them.
  Map<String, dynamic> toJson() => {
    'uid': uid,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'phone': phone,
    'location': location,
    'bio': bio,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  /// Constructs a [UserProfileModel] from a raw Firestore document map.
  /// Provides safe defaults for every field in case of missing data.
  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      uid:         json['uid']         ?? '',
      email:       json['email']       ?? '',
      displayName: json['displayName'] ?? '',
      photoUrl:    json['photoUrl'],
      phone:       json['phone'],
      location:    json['location'],
      bio:         json['bio'],
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // ---------------------------------------------------------------------------
  // Immutable update
  // ---------------------------------------------------------------------------

  /// Returns a new [UserProfileModel] with the given fields replaced.
  /// [updatedAt] is automatically set to now so callers don't have to.
  /// [uid] and [email] are intentionally excluded — they must not change
  /// after account creation.
  UserProfileModel copyWith({
    String? displayName,
    String? photoUrl,
    String? phone,
    String? location,
    String? bio,
  }) {
    return UserProfileModel(
      uid:         uid,
      email:       email,
      displayName: displayName ?? this.displayName,
      photoUrl:    photoUrl   ?? this.photoUrl,
      phone:       phone      ?? this.phone,
      location:    location   ?? this.location,
      bio:         bio        ?? this.bio,
      createdAt:   createdAt,
      updatedAt:   DateTime.now(), // always stamp the update time
    );
  }
}
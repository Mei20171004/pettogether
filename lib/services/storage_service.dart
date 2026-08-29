import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../models/health.dart';
import '../utils/id.dart';
import 'care_service.dart';

/// Uploads pet photos and health-record attachments to Firebase Storage and
/// returns downloadable URLs.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  Future<String> uploadPetPhoto({
    required String householdID,
    required String petID,
    required Uint8List bytes,
  }) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('households/$householdID/pets/$petID.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Uploads one photo for a health record — a lab printout, a prescription,
  /// a picture of the affected paw.
  ///
  /// The object path keeps the record id so deleting a record can clean up its
  /// files, and so the Storage rules can gate on household membership.
  Future<HealthAttachment> uploadHealthAttachment({
    required String householdID,
    required String recordID,
    required Uint8List bytes,
  }) async {
    if (bytes.lengthInBytes > HealthAttachment.maxBytes) {
      throw const CareServiceError(CareServiceErrorType.attachmentTooLarge);
    }
    final id = uuid();
    final path = 'households/$householdID/records/$recordID/$id.jpg';
    try {
      final ref = FirebaseStorage.instance.ref().child(path);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      return HealthAttachment(
        id: id,
        url: await ref.getDownloadURL(),
        storagePath: path,
        sizeBytes: bytes.lengthInBytes,
        uploadedAt: DateTime.now(),
      );
    } on FirebaseException {
      throw const CareServiceError(
          CareServiceErrorType.attachmentUploadFailed);
    }
  }

  /// Best-effort removal. A file that is already gone (or was never uploaded,
  /// as in mock mode) must not block deleting the record that referenced it.
  Future<void> deleteHealthAttachment(String storagePath) async {
    if (storagePath.isEmpty) return;
    try {
      await FirebaseStorage.instance.ref().child(storagePath).delete();
    } on FirebaseException {
      return;
    }
  }
}

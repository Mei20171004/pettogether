import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Uploads pet photos to Firebase Storage and returns a downloadable URL.
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
}

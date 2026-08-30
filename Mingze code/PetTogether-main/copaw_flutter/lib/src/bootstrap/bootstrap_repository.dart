import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum BootstrapResult { noHousehold }

enum BootstrapFailureKind {
  configuration,
  network,
  permission,
  malformedData,
  service,
  unknown,
}

class BootstrapException implements Exception {
  const BootstrapException({required this.kind, required this.code});

  final BootstrapFailureKind kind;
  final String code;
}

abstract interface class BootstrapRepository {
  Future<BootstrapResult> initialize();
}

final bootstrapRepositoryProvider = Provider<BootstrapRepository>((ref) {
  throw StateError('BootstrapRepository must be provided at the app boundary.');
});

class FirebaseBootstrapRepository implements BootstrapRepository {
  FirebaseBootstrapRepository({this.options});

  final FirebaseOptions? options;

  @override
  Future<BootstrapResult> initialize() async {
    try {
      final configuration = options;
      if (configuration == null) {
        throw const BootstrapException(
          kind: BootstrapFailureKind.configuration,
          code: 'missing-production-options',
        );
      }
      await Firebase.initializeApp(options: configuration);
      return BootstrapResult.noHousehold;
    } on BootstrapException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _safeFailure(error.code);
    } on PlatformException catch (error) {
      throw _safeFailure(error.code);
    } on MissingPluginException {
      throw _safeFailure('missing-plugin');
    } on Object {
      throw _safeFailure('unknown');
    }
  }

  BootstrapException _safeFailure(String unsafeCode) {
    final code = unsafeCode
        .replaceAll(RegExp('[^a-zA-Z0-9._-]'), '_')
        .substring(0, unsafeCode.length.clamp(0, 64));
    final normalized = code.toLowerCase();
    final kind =
        normalized.contains('config') ||
            normalized.contains('option') ||
            normalized.contains('no-app') ||
            normalized.contains('missing-plugin')
        ? BootstrapFailureKind.configuration
        : normalized == 'unknown'
        ? BootstrapFailureKind.unknown
        : BootstrapFailureKind.service;
    debugPrint(
      'CoPaw bootstrap failed phase=firebase_core '
      'category=${kind.name} code=$code platform=${defaultTargetPlatform.name}',
    );
    return BootstrapException(kind: kind, code: code);
  }
}

class FakeBootstrapRepository implements BootstrapRepository {
  FakeBootstrapRepository([Iterable<Object?> outcomes = const []])
    : _outcomes = List<Object?>.of(outcomes);

  final List<Object?> _outcomes;
  int attempts = 0;

  @override
  Future<BootstrapResult> initialize() async {
    attempts += 1;
    if (_outcomes.isEmpty) {
      return BootstrapResult.noHousehold;
    }

    final outcome = _outcomes.removeAt(0);
    if (outcome is BootstrapResult) {
      return outcome;
    }
    if (outcome is Error) {
      throw outcome;
    }
    if (outcome is Exception) {
      throw outcome;
    }
    return BootstrapResult.noHousehold;
  }
}

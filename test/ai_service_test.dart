import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pettogether/services/ai_service.dart';

void main() {
  group('AiService failure classification', () {
    test('keeps the supported model pinned', () {
      expect(AiService.modelName, 'gemini-3.8-flash');
    });

    test('classifies missing or invalid service configuration', () {
      expect(
        AiService.classifyFailure(InvalidApiKey('bad key')).kind,
        AiFailureKind.configuration,
      );
      expect(
        AiService.classifyFailure(
          ServiceApiNotEnabled('projects/pettogether-76452'),
        ).kind,
        AiFailureKind.configuration,
      );
    });

    test('classifies network failures separately', () {
      expect(
        AiService.classifyFailure(TimeoutException('timed out')).kind,
        AiFailureKind.network,
      );
    });

    test('classifies App Check and permission failures as authorization', () {
      final error = ServerException(
        'PERMISSION_DENIED: Firebase App Check token is invalid.',
      );
      expect(
        AiService.classifyFailure(error).kind,
        AiFailureKind.authorization,
      );
    });

    test('classifies a disabled App Check API as configuration', () {
      final error = FirebaseException(
        plugin: 'firebase_app_check',
        code: 'unknown',
        message: '403 SERVICE_DISABLED: firebaseappcheck.googleapis.com is not enabled',
      );
      expect(
        AiService.classifyFailure(error).kind,
        AiFailureKind.configuration,
      );
    });

    test('distinguishes quota, region, response, and server failures', () {
      expect(
        AiService.classifyFailure(QuotaExceeded('quota exceeded')).kind,
        AiFailureKind.quota,
      );
      expect(
        AiService.classifyFailure(UnsupportedUserLocation()).kind,
        AiFailureKind.unsupportedRegion,
      );
      expect(
        AiService.classifyFailure(const FormatException('bad JSON')).kind,
        AiFailureKind.invalidResponse,
      );
      expect(
        AiService.classifyFailure(ServerException('internal error')).kind,
        AiFailureKind.server,
      );
    });
  });
}

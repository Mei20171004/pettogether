import 'package:flutter_test/flutter_test.dart';
import 'package:pettogether/services/web_auth_bridge_policy.dart';

void main() {
  test('passes a token only to the exact Pro Hosting origin', () {
    final trusted = Uri.parse(
      'https://pettogether-pro.web.app/historyreport.html',
    );
    expect(isTrustedWebAuthPage(trusted, trusted), isTrue);
    expect(
      isTrustedWebAuthPage(
        trusted,
        Uri.parse('https://pettogether-pro.web.app/other.html'),
      ),
      isTrue,
    );
    expect(
      isTrustedWebAuthPage(
        trusted,
        Uri.parse('https://pettogether-pro.web.app.evil.example/'),
      ),
      isFalse,
    );
    expect(
      isTrustedWebAuthPage(
        Uri.parse('http://pettogether-pro.web.app/historyreport.html'),
        trusted,
      ),
      isFalse,
    );
    expect(isTrustedWebAuthPage(trusted, Uri.parse('about:blank')), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';

void main() {
  test('Success хранит значение', () {
    final r = Success<int>(42);
    expect(r, isA<Success<int>>());
    expect((r as Success<int>).value, 42);
  });

  test('Failure хранит ApiError', () {
    final r = Failure<int>(const AuthError());
    expect(r, isA<Failure<int>>());
    expect((r as Failure<int>).error, isA<AuthError>());
  });

  test('maybeWhen: Success → onValue', () {
    final r = Success<int>(5);
    final out = r.maybeWhen(onValue: (v) => v * 2, orElse: (err) => -1);
    expect(out, 10);
  });

  test('maybeWhen: Failure → orElse', () {
    final r = Failure<int>(const NetworkError());
    final out = r.maybeWhen(onValue: (v) => v * 2, orElse: (err) => -1);
    expect(out, -1);
  });
}

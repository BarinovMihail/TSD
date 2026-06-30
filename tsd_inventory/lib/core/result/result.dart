import 'package:tsd_inventory/core/network/api_error.dart';

/// Результат операции: успех со значением или провал с типизированной ошибкой.
sealed class Result<T> {
  const Result();

  /// Свёртка: успех → onValue, провал → orElse.
  R maybeWhen<R>({
    required R Function(T value) onValue,
    required R Function(ApiError error) orElse,
  });
}

class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);

  @override
  R maybeWhen<R>({
    required R Function(T value) onValue,
    required R Function(ApiError error) orElse,
  }) =>
      onValue(value);
}

class Failure<T> extends Result<T> {
  final ApiError error;
  const Failure(this.error);

  @override
  R maybeWhen<R>({
    required R Function(T value) onValue,
    required R Function(ApiError error) orElse,
  }) =>
      orElse(error);
}

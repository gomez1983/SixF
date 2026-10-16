import 'dart:async';
import 'dart:io';

import 'network_security_utils.dart';

typedef WebSocketConnector = Future<WebSocket> Function(
  String url,
  HttpClient client,
);

/// Recursos de uma operação de rede. Cancelar fecha clientes e libera esperas;
/// recursos que chegarem depois do cancelamento também são descartados.
class NetworkOperation {
  static final Object _zoneKey = Object();
  static NetworkOperation? get current =>
      Zone.current[_zoneKey] as NetworkOperation?;
  bool _cancelled = false;
  final Set<void Function()> _waiters = {};
  final Set<HttpClient> _clients = {};
  final List<void Function()> _cleanup = [];
  bool get isCancelled => _cancelled;

  void check() {
    if (isCancelled) throw const OperationCancelled();
  }

  void onCancel(void Function() cleanup) {
    if (isCancelled) {
      cleanup();
    } else {
      _cleanup.add(cleanup);
    }
  }

  static HttpClient httpClient() {
    final operation = current;
    operation?.check();
    final client = HttpClient();
    operation?._clients.add(client);
    return client;
  }

  static void closeClient(HttpClient client) {
    current?._clients.remove(client);
    client.close(force: true);
  }

  Future<WebSocket> openWebSocket(
    String url,
    Duration timeout, {
    WebSocketConnector? connector,
  }) async {
    check();
    final attempt = NetworkOperation();
    onCancel(attempt.cancel);
    try {
      return await attempt
          .run(() async {
            final client = httpClient()
              ..connectionTimeout = timeout
              ..badCertificateCallback = (cert, host, port) =>
                  NetworkSecurityUtils.isLocalNetworkHost(host);
            final socket = await attempt.wait(
              connector != null
                  ? connector(url, client)
                  : WebSocket.connect(url, customClient: client),
              onDiscard: (socket) {
                socket.close();
              },
            );
            attempt.onCancel(() {
              socket.close();
            });
            return socket;
          })
          .timeout(
            timeout,
            onTimeout: () {
              attempt.cancel();
              throw TimeoutException('Tempo limite ao abrir conexão');
            },
          );
    } catch (_) {
      attempt.cancel();
      rethrow;
    }
  }

  Future<T> run<T>(Future<T> Function() action) {
    check();
    return runZoned(() => wait(action()), zoneValues: {_zoneKey: this});
  }

  Future<T> wait<T>(Future<T> future, {void Function(T)? onDiscard}) async {
    final result = Completer<T>();
    void cancelled() {
      if (!result.isCompleted) result.completeError(const OperationCancelled());
    }

    if (isCancelled) {
      cancelled();
    } else {
      _waiters.add(cancelled);
    }
    future.then(
      (value) {
        if (result.isCompleted) {
          onDiscard?.call(value);
        } else {
          result.complete(value);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    try {
      final value = await result.future;
      if (isCancelled) {
        onDiscard?.call(value);
        throw const OperationCancelled();
      }
      return value;
    } finally {
      _waiters.remove(cancelled);
    }
  }

  void cancel() {
    if (isCancelled) return;
    _cancelled = true;
    for (final waiter in _waiters.toList()) {
      waiter();
    }
    _waiters.clear();
    for (final cleanup in _cleanup.toList()) {
      cleanup();
    }
    _cleanup.clear();
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

class OperationCancelled implements Exception {
  const OperationCancelled();
}

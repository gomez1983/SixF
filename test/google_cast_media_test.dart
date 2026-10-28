import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/services/google_cast_media.dart';
import 'package:sixf_remote/services/drivers/google_tv/credentials.dart';
import 'package:sixf_remote/services/drivers/google_tv/wire.dart';

void main() {
  test('Cast launches receiver, loads URL with MIME and controls its media session', () async {
    final identity = GoogleTvCredentials.generate();
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      identity.context(),
    );
    final sockets = <SecureSocket>[];
    final commands = <Map<String, dynamic>>[];
    final subscription = server.listen((socket) {
      sockets.add(socket);
      final buffer = <int>[];
      socket.listen((data) {
        buffer.addAll(data);
        while (buffer.length >= 4) {
          final length = ByteData.sublistView(
            Uint8List.fromList(buffer.sublist(0, 4)),
          ).getUint32(0);
          if (buffer.length < length + 4) return;
          final fields = TvWire.decode(buffer.sublist(4, 4 + length));
          buffer.removeRange(0, 4 + length);
          final message =
              jsonDecode(TvWire.string(fields, 6)) as Map<String, dynamic>;
          commands.add(message);
          if (message['requestId'] == null) continue;
          final Map<String, dynamic> reply = message['type'] == 'LAUNCH'
              ? {
                  'type': 'RECEIVER_STATUS',
                  'requestId': message['requestId'],
                  'status': {
                    'applications': [
                      {'appId': 'CC1AD845', 'transportId': 'transport-test'},
                    ],
                  },
                }
              : {
                  'type': 'MEDIA_STATUS',
                  'requestId': message['requestId'],
                  'status': [
                    {'mediaSessionId': 42, 'playerState': 'PLAYING'},
                  ],
                };
          if (message['type'] == 'LOAD') {
            expect(TvWire.string(fields, 3), 'transport-test');
          }
          final payload = [
            ...TvWire.number(1, 0),
            ...TvWire.text(2, 'receiver-0'),
            ...TvWire.text(3, 'sender-sixf'),
            ...TvWire.text(4, TvWire.string(fields, 4)),
            ...TvWire.number(5, 0),
            ...TvWire.text(6, jsonEncode(reply)),
          ];
          final prefix = ByteData(4)..setUint32(0, payload.length);
          socket.add([...prefix.buffer.asUint8List(), ...payload]);
        }
      });
    });
    final cast = GoogleCastMedia(port: server.port);
    addTearDown(() async {
      cast.close();
      for (final socket in sockets) {
        socket.destroy();
      }
      await subscription.cancel();
      await server.close();
    });
    await cast.load(
      '127.0.0.1',
      'http://192.168.1.2:8080/token/photo.jpg',
      'Foto',
      'image/jpeg',
    );
    expect(
      commands.firstWhere((c) => c['type'] == 'LOAD')['media']['contentType'],
      'image/jpeg',
    );
    await cast.command('PAUSE');
    expect(commands.last['mediaSessionId'], 42);
    await cast.command('SEEK', currentTime: 12.5);
    expect(commands.last['currentTime'], 12.5);
    await cast.refresh();
    expect(commands.last['type'], 'GET_STATUS');
    await cast.reload();
    expect(commands.where((c) => c['type'] == 'LOAD').length, 2);
    for (var i = 0; i < 30; i++) {
      await cast.reload();
      await cast.refresh();
    }
    expect(commands.where((c) => c['type'] == 'LOAD').length, 32);
    await cast.command('STOP');
    expect(commands.last['type'], 'STOP');
    cast.close();
    await expectLater(cast.refresh(), throwsStateError);
  });
}

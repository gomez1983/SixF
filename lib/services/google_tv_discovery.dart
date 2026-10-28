import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import 'drivers/tv_driver.dart';
import 'network_operation.dart';
import 'ssdp_discovery_service.dart';

class GoogleTvDiscovery {
  /// Only Remote Service v2; _googlecast._tcp also advertises non-remote devices.
  static const service = '_androidtvremote2._tcp.local';
  static Future<List<DiscoveredTv>> discover(Duration timeout) async {
    final client = MDnsClient(
      rawDatagramSocketFactory:
          (host, port, {reuseAddress = true, reusePort = true, ttl = 1}) =>
              RawDatagramSocket.bind(
                host,
                port,
                reuseAddress: reuseAddress,
                reusePort: Platform.isWindows ? false : reusePort,
                ttl: ttl,
              ),
    );
    final operation = NetworkOperation.current;
    var closed = false;
    final found = <String, DiscoveredTv>{};
    operation?.onCancel(() {
      closed = true;
      client.stop();
    });
    try {
      await client.start();
      if (closed || operation?.isCancelled == true) return [];
      Future<void> resolve(PtrResourceRecord ptr) async {
        await for (final srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
          timeout: timeout,
        )) {
          if (closed) return;
          if (srv.port != 6466) continue;
          await for (final addr in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: timeout,
          )) {
            if (closed) return;
            final name = ptr.domainName.split('.$service').first;
            found[addr.address.address] = DiscoveredTv(
              ip: addr.address.address,
              name: name.isEmpty ? 'Chromecast / Google TV' : name,
              brand: TvBrand.googleTv,
            );
          }
        }
      }

      Future<void> scan() async {
        final pending = <Future<void>>[];
        await for (final ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(service),
          timeout: timeout,
        )) {
          if (closed) break;
          pending.add(resolve(ptr));
        }
        await Future.wait(pending);
      }

      await scan().timeout(timeout, onTimeout: () {});
    } catch (_) {
      // Manual IP entry remains available when multicast is blocked.
    } finally {
      closed = true;
      client.stop();
    }
    return found.values.toList();
  }

  static Future<DiscoveredTv?> probe(String ip, Duration timeout) async {
    try {
      for (final port in [6466, 6467]) {
        NetworkOperation.current?.check();
        final socket = await Socket.connect(ip, port, timeout: timeout);
        socket.destroy();
      }
      NetworkOperation.current?.check();
      return DiscoveredTv(
        ip: ip,
        name: 'Chromecast / Google TV',
        brand: TvBrand.googleTv,
      );
    } catch (_) {
      return null;
    }
  }
}

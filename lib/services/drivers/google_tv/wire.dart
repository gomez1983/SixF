import 'dart:convert';

/// Subset of protobuf wire types used by Android TV Remote v2.
/// Field numbers follow androidtvremote2/remotemessage.proto and polo.proto.
class TvWire {
  static List<int> varint(int value) {
    final out = <int>[];
    while (value < 0 || value >= 128) {
      out.add((value & 127) | 128);
      value = value >>> 7;
    }
    return out..add(value);
  }

  static List<int> number(int field, int value) => [
    ...varint(field << 3),
    ...varint(value),
  ];
  static List<int> bytes(int field, List<int> value) => [
    ...varint((field << 3) | 2),
    ...varint(value.length),
    ...value,
  ];
  static List<int> text(int field, String value) =>
      bytes(field, utf8.encode(value));
  static List<int> frame(List<int> message) => [
    ...varint(message.length),
    ...message,
  ];
  static Map<int, Object> decode(List<int> data) {
    var offset = 0;
    int read() {
      var value = 0;
      for (var shift = 0; shift < 70; shift += 7) {
        if (offset >= data.length) {
          throw const FormatException('Truncated protobuf');
        }
        final byte = data[offset++];
        if (shift == 63 && byte > 1) {
          throw const FormatException('Varint exceeds 64 bits');
        }
        value |= (byte & 127) << shift;
        if (byte < 128) return value;
      }
      throw const FormatException('Invalid varint');
    }

    final fields = <int, Object>{};
    while (offset < data.length) {
      final tag = read();
      final field = tag >> 3;
      if (field == 0) throw const FormatException('Invalid field');
      switch (tag & 7) {
        case 0:
          fields[field] = read();
          break;
        case 2:
          final size = read();
          if (size > data.length - offset) {
            throw const FormatException('Truncated field');
          }
          fields[field] = data.sublist(offset, offset + size);
          offset += size;
          break;
        case 1:
          offset += 8;
          break;
        case 5:
          offset += 4;
          break;
        default:
          throw const FormatException('Unsupported wire type');
      }
      if (offset > data.length) {
        throw const FormatException('Truncated fixed field');
      }
    }
    return fields;
  }

  static Map<int, Object> message(Map<int, Object> fields, int key) =>
      decode((fields[key] as List<int>?) ?? []);
  static int integer(Map<int, Object> fields, int key) =>
      (fields[key] as int?) ?? 0;
  static String string(Map<int, Object> fields, int key) =>
      utf8.decode((fields[key] as List<int>?) ?? [], allowMalformed: true);
}

/// TCP reads may contain half a prefix, half a message, or several messages.
class TvFrameDecoder {
  final List<int> _buffer = [];
  Iterable<List<int>> add(List<int> data) sync* {
    _buffer.addAll(data);
    while (_buffer.isNotEmpty) {
      var size = 0;
      var prefix = 0;
      var complete = false;
      for (final byte in _buffer) {
        size |= (byte & 127) << (7 * prefix++);
        if (prefix > 3 || size > 65536) {
          throw const FormatException('Frame too large');
        }
        if (byte < 128) {
          complete = true;
          break;
        }
      }
      if (!complete || _buffer.length < prefix + size) return;
      final message = _buffer.sublist(prefix, prefix + size);
      _buffer.removeRange(0, prefix + size);
      yield message;
    }
  }
}

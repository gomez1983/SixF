import '../services/drivers/tv_driver.dart';

/// Modelo de representação de um dispositivo ou Smart TV configurado e salvo no app.
class SavedDevice {
  final String id;
  final String name;
  final String ip;
  final String mac;
  final TvBrand brand;
  final String? modelName;
  final bool isDefault;

  const SavedDevice({
    required this.id,
    required this.name,
    required this.ip,
    this.mac = '',
    this.brand = TvBrand.lgWebOs,
    this.modelName,
    this.isDefault = false,
  });

  /// Gera um identificador único estável a partir da marca e do endereço IP.
  static String generateId(TvBrand brand, String ip) {
    final sanitizedIp = ip.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '_');
    return '${brand.id}_$sanitizedIp';
  }

  SavedDevice copyWith({
    String? id,
    String? name,
    String? ip,
    String? mac,
    TvBrand? brand,
    String? modelName,
    bool? isDefault,
  }) {
    return SavedDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      mac: mac ?? this.mac,
      brand: brand ?? this.brand,
      modelName: modelName ?? this.modelName,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ip': ip,
    'mac': mac,
    'brand': brand.name,
    if (modelName != null) 'modelName': modelName,
    'isDefault': isDefault,
  };

  factory SavedDevice.fromJson(Map<String, dynamic> json) {
    final brandRaw = json['brand'] as String?;
    final brand = TvBrand.values.firstWhere(
      (b) => b.name == brandRaw || b.id == brandRaw,
      orElse: () => TvBrand.lgWebOs,
    );
    final ip = json['ip'] as String? ?? '';
    final id = json['id'] as String? ?? generateId(brand, ip);
    return SavedDevice(
      id: id,
      name: json['name'] as String? ?? 'Smart TV',
      ip: ip,
      mac: json['mac'] as String? ?? '',
      brand: brand,
      modelName: json['modelName'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedDevice &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => '$name ($ip - ${brand.displayName}) [id: $id]';
}

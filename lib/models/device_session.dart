import '../services/drivers/tv_driver.dart';
import 'saved_device.dart';

/// Representa a sessão ativa de conexão e estado individual de uma Smart TV ou dispositivo.
class DeviceSession {
  SavedDevice device;
  final TvDriver driver;
  bool isPoweredOn;
  int volumeLevel;
  int currentChannel;
  bool isMuted;
  List<TvAppInfo> installedApps;
  bool isLoadingApps;
  String? appsError;
  bool shouldMaintainConnection;

  DeviceSession({
    required this.device,
    required this.driver,
    this.isPoweredOn = false,
    this.volumeLevel = 18,
    this.currentChannel = 5,
    this.isMuted = false,
    this.installedApps = const [],
    this.isLoadingApps = false,
    this.appsError,
    this.shouldMaintainConnection = false,
  });

  bool get isConnected => driver.isConnected;
  bool get isConnecting => driver.connectionState == DeviceConnectionState.connecting;
  bool get isWaitingPairing => driver.connectionState == DeviceConnectionState.pairingPrompt;
  DeviceConnectionState get connectionState => driver.connectionState;
}

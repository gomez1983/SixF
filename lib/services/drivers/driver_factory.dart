import 'android_tv_driver.dart';
import 'lg_webos_driver.dart';
import 'samsung_tizen_driver.dart';
import 'tv_driver.dart';

/// Fábrica responsável por instanciar drivers correspondentes a cada marca/plataforma.
class DriverFactory {
  /// Cria uma nova instância de [TvDriver] para a [brand] especificada.
  static TvDriver create(TvBrand brand) {
    switch (brand) {
      case TvBrand.lgWebOs:
        return LgWebOsDriver();
      case TvBrand.androidTv:
        return AndroidTvDriver();
      case TvBrand.samsungTizen:
        return SamsungTizenDriver();
    }
  }
}

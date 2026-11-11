import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/ui/views/media_library.dart';

/// Os controles do media_kit pedem ~148 px (56 + 56 + 36). Em celular deitado
/// o card do vídeo é mais baixo e estourava por frações de pixel; as barras
/// agora encolhem para sempre caber na altura disponível.
void main() {
  test('alturas folgadas mantêm os controles padrão', () {
    expect(compactVideoControlSizes(200), isNull);
    expect(compactVideoControlSizes(320), isNull);
  });

  test('barras sempre cabem na altura do card (S23 Ultra deitado e menores)', () {
    // 147,2 era a faixa do S23 Ultra: o padrão (148) estourava 0,8 px.
    for (var h = 88.0; h < 200; h += 0.25) {
      final sizes = compactVideoControlSizes(h)!;
      expect(
        sizes.bar * 2 + sizes.seek + 4,
        lessThanOrEqualTo(h),
        reason: 'altura $h',
      );
      expect(sizes.bar, lessThanOrEqualTo(56));
      expect(sizes.seek, lessThanOrEqualTo(36));
    }
  });

  test('a altura padrão (56 + 56 + 36) estouraria na faixa do S23', () {
    const defaultNeed = 56 + 56 + 36.0;
    expect(147.2 < defaultNeed, isTrue);
    final sizes = compactVideoControlSizes(147.2)!;
    expect(sizes.bar * 2 + sizes.seek, lessThan(147.2));
  });
}

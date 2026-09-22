import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/voice_service.dart';

void main() {
  group('VoiceService Intent Classification Tests', () {
    test('Classifica comandos de Aumentar Volume (+5)', () {
      final variations = [
        'Aumentar volume',
        'aumenta o volume',
        'mais volume',
        'sobe o volume',
        'subir volume',
        'volume mais',
        'volume up',
        'aumentar o som',
      ];

      for (final phrase in variations) {
        final intent = VoiceService.classifyIntent(phrase);
        expect(
          intent.type,
          VoiceIntentType.volumeUp,
          reason: 'Falhou ao classificar: "$phrase"',
        );
        expect(intent.isCommand, isTrue);
      }
    });

    test('Classifica comandos de Diminuir Volume (-5)', () {
      final variations = [
        'Diminuir volume',
        'diminui o volume',
        'menos volume',
        'baixar volume',
        'baixa o volume',
        'abaixar volume',
        'volume menos',
        'volume down',
        'diminuir som',
      ];

      for (final phrase in variations) {
        final intent = VoiceService.classifyIntent(phrase);
        expect(
          intent.type,
          VoiceIntentType.volumeDown,
          reason: 'Falhou ao classificar: "$phrase"',
        );
        expect(intent.isCommand, isTrue);
      }
    });

    test('Classifica comandos de Mudo / Tirar mudo', () {
      final variations = [
        'Mudo',
        'mutar',
        'muta a tv',
        'tirar mudo',
        'tira o mudo',
        'desmutar',
        'sem som',
        'mute',
      ];

      for (final phrase in variations) {
        final intent = VoiceService.classifyIntent(phrase);
        expect(
          intent.type,
          VoiceIntentType.toggleMute,
          reason: 'Falhou ao classificar: "$phrase"',
        );
        expect(intent.isCommand, isTrue);
      }
    });

    test('Classifica comandos de Desligar TV', () {
      final variations = [
        'Desligar TV',
        'desliga a tv',
        'desligar a tv',
        'desliga tv',
        'desligar televisao',
        'power off',
      ];

      for (final phrase in variations) {
        final intent = VoiceService.classifyIntent(phrase);
        expect(
          intent.type,
          VoiceIntentType.powerOff,
          reason: 'Falhou ao classificar: "$phrase"',
        );
        expect(intent.isCommand, isTrue);
      }
    });

    test('Classifica comandos de Abrir Aplicativos padrão', () {
      final intentYoutube = VoiceService.classifyIntent('abrir youtube');
      expect(intentYoutube.type, VoiceIntentType.openApp);
      expect(intentYoutube.targetApp, 'YouTube');
      expect(intentYoutube.targetAppId, 'youtube.leanback.v4');

      final intentNetflix = VoiceService.classifyIntent('abre a netflix');
      expect(intentNetflix.type, VoiceIntentType.openApp);
      expect(intentNetflix.targetApp, 'Netflix');

      final intentSpotify = VoiceService.classifyIntent('iniciar spotify');
      expect(intentSpotify.type, VoiceIntentType.openApp);
      expect(intentSpotify.targetApp, 'Spotify');

      final intentPrime = VoiceService.classifyIntent('abrir prime video');
      expect(intentPrime.type, VoiceIntentType.openApp);
      expect(intentPrime.targetApp, 'Prime Video');
    });

    test('Classifica comando de Abrir Aplicativo com lista instalada', () {
      const installed = [
        TvAppInfo(id: 'crunchyroll.app', name: 'Crunchyroll'),
        TvAppInfo(id: 'disney.plus', name: 'Disney Plus'),
      ];

      final intent = VoiceService.classifyIntent(
        'abrir crunchyroll',
        installedApps: installed,
      );
      expect(intent.type, VoiceIntentType.openApp);
      expect(intent.targetApp, 'Crunchyroll');
      expect(intent.targetAppId, 'crunchyroll.app');
    });

    test('Classifica buscas livres e frases longas como textSearch para injeção na TV', () {
      final searches = [
        'como fazer bolo de cenoura com cobertura de chocolate',
        'rock internacional anos 80',
        'iron maiden the trooper ao vivo',
        'melhores momentos futebol',
        'trailer novo filme marvel',
      ];

      for (final query in searches) {
        final intent = VoiceService.classifyIntent(query);
        expect(
          intent.type,
          VoiceIntentType.textSearch,
          reason: 'Deveria ser busca livre: "$query"',
        );
        expect(intent.isCommand, isFalse);
        expect(intent.rawText, query);
      }
    });

    test('Normalização de texto remove acentuação e pontuações', () {
      expect(VoiceService.normalizeText('Aumentar o volume!'), 'aumentar o volume');
      expect(VoiceService.normalizeText('Televisão ligada?'), 'televisao ligada');
      expect(VoiceService.normalizeText('Você, eu e nós.'), 'voce eu e nos');
    });
  });
}

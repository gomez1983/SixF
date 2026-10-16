```markdown
# SixF Remote — Windows e Android

Controle de TVs LG webOS e Samsung Tizen pela rede local, desenvolvido com Flutter/Provider. Android TV/Google Cast está descontinuado. Não há projeto iOS neste repositório.

## Recursos implementados

- Dispositivos salvos, conexão por aparelho e alternância entre sessões.
- Descoberta SSDP, pareamento na TV e diagnóstico de conexão: toque no status do cabeçalho.
- D-Pad, volume e canais com repetição ao segurar quando conectado. Setas e teclas de volume numéricas aceitam repetição do teclado; comandos como Power e Mute não repetem.
- Apps: lista LG e catálogo Samsung, pesquisa e favoritos separados por aparelho. Toque na estrela para favoritar; use o filtro Favoritos.
- Windows: bandeja, atalhos com a janela em foco e modo compacto sempre visível. O botão Modo compacto fica no cabeçalho; Sair do modo compacto restaura a janela.
- Mobile: Controle, Teclas & Mídia, Apps e, somente na LG, Magic Trackpad. HDMI 1 e TV Digital aparecem apenas onde implementados.
- Transmissão de arquivos locais (fotos, vídeos e áudio). Isto não captura nem espelha a tela.
- Tema claro/escuro, feedback háptico e voz conforme suporte da plataforma.

## Primeiro uso

1. Ligue a TV e mantenha TV e computador/celular na mesma rede local.
2. Abra a busca de TVs, selecione o aparelho e aceite o pedido exibido na TV. Se solicitado, informe o PIN.
3. Confira o IP nas configurações se a descoberta não encontrar o aparelho. No Windows, permita o SixF em redes privadas no firewall.
4. Para ligar por Wake-on-LAN, configure o MAC real e habilite a função correspondente na TV. Disponibilidade depende do modelo/rede.

## Mídia e limites

“Mídia enviada” significa aceitação do comando, não reprodução comprovada. No DLNA, reprodução e pausa são confirmadas pela TV quando ela informa o estado. No canal nativo, Play/Pause são comandos enviados.

Progresso, avanço e repetição só aparecem conforme as informações da TV. Modelos que não informam ações suportadas podem ter controles indisponíveis. Fotos não recebem Play. Codecs e compatibilidade precisam de validação nos modelos físicos.

As chaves de pareamento permanecem em SharedPreferences, separadas por marca/IP. A URL de cada transmissão tem token aleatório e é revogada ao parar ou trocar o arquivo; use rede local confiável. Troca de IP pode exigir novo pareamento. O cadastro legado predefinido ainda pode existir: revise os dados antes de conectar.

## Desenvolvimento e validação

Ambiente validado: Flutter 3.47.3 / Dart 3.13.3.

    flutter pub get
    dart run tool/check_release.dart
    flutter analyze --no-pub
    flutter test --no-pub
    flutter run -d windows

Versão canônica: pubspec.yaml. Distribuição, assinatura e homologação: docs/DISTRIBUTION.md. Estado e escopo futuro: ROADMAP.md. A CI verifica análise, testes e builds Windows/Android; só executa no GitHub após envio das alterações.
```

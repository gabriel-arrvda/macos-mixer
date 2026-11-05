# Mixer

Mixer de volume por app para macOS 14.4+, na barra de menu. Slider e mudo por app, usando *Core Audio process taps* (sem driver virtual). Uso pessoal, assinatura ad-hoc.

## Comandos

```
swift build                  # debug
swift test                   # testes do MixerCore
scripts/build_app.sh         # build/Mixer.app (release, assinatura ad-hoc)
scripts/make_dmg.sh          # build/Mixer.dmg
```

Variáveis do `build_app.sh`: `APP_NAME` (Mixer), `BUNDLE_ID` (com.glarruda.mixer), `VERSION` (1.0), `SIGN_IDENTITY` (`-` = ad-hoc).
O nome mostrado na UI está em `Sources/Mixer/App/AppConstants.swift`.

## Primeira abertura (sem assinatura da Apple)

Arraste o app do DMG para Aplicativos. Se o macOS bloquear: Ajustes do Sistema › Privacidade e Segurança › "Abrir assim mesmo", ou:

```
xattr -d com.apple.quarantine /Applications/Mixer.app
```

O macOS pede "Gravação de Áudio do Sistema" quando o primeiro app começar a tocar.

## Estrutura

- `Sources/MixerCore`: áudio (descoberta, `TapSession`, `SessionManager`, `GainControl`, `DeviceWatcher`) e modelo (`VolumeStore`, `SilenceDetector`). Sem UI, testável.
- `Sources/Mixer`: app SwiftUI (`MenuBarExtra`).
- `Sources/Spike`, `Sources/EngineDemo`: CLIs de teste do áudio, sem UI.
- `Sources/CAtomics`: atômicos em C, pra thread de áudio ficar sem lock (o módulo `Synchronization` só existe no macOS 15+).

## Salvaguardas

- O app ignora qualquer processo do próprio executável e só roda uma instância (senão uma capturaria a outra e o som entra em loop).
- A saída é cortada em ±1 depois do ganho.

## Permissão entre rebuilds (etapa 9): NÃO TESTADO

Com assinatura ad-hoc o macOS pode pedir a permissão de novo a cada build. O script já fixa `--identifier`. Pra testar com um certificado local fixo:
1. Acesso às Chaves › Assistente de Certificado › Criar certificado… › tipo "Assinatura de código", nome `Mixer Local`.
2. `SIGN_IDENTITY="Mixer Local" scripts/build_app.sh`, conceda a permissão, rebuild e veja se ela se mantém.
Anote o resultado aqui.

## Pendências de validação

- Links de Ajustes (`x-apple.systempreferences:...`) não conferidos; o app cai pros Ajustes do Sistema se o link falhar.
- Fluxo com `tccutil reset` e permissão negada (etapa 7), e o teste com DRM/Bluetooth, não foram exercitados.

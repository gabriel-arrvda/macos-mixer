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
- `Tools/` (pacote separado, fora do build padrão): CLIs `Spike` e `EngineDemo` pra testar o áudio sem UI. Rode com `cd Tools && swift build`.
- `Sources/CAtomics`: atômicos em C, pra thread de áudio ficar sem lock (o módulo `Synchronization` só existe no macOS 15+).

## Salvaguardas

- O app ignora qualquer processo do próprio executável e só roda uma instância (senão uma capturaria a outra e o som entra em loop).
- A saída é cortada em ±1 depois do ganho.

## Como o tap protege contra mudo por permissão negada

Cada sessão começa em `probing`: tap `.unmuted`, que só mede o pico e não escreve na saída. Quando chega pico > 0 a permissão está confirmada (`permissionConfirmed`, só em memória) e as sessões são recriadas em `active` (`.mutedWhenTapped` + escrita na saída). Se tudo vier zerado por 5 s, volta a `probing` e o app original deixa de ficar mudo. O tap é recriado (não confirmei se `muteBehavior` pode mudar depois de criado), então o primeiro app de cada execução pode ter um corte curto.

## Riscos conhecidos

- **API privada:** `responsibility_get_pid_responsible_for_pid`, via `dlsym`, só resolve o app dono de um processo auxiliar. Se não existir, o app cai na cadeia de processos pai e no prefixo do bundle ID. Não usa a API privada do TCC.
- **AirPods/fone com microfone ativo:** o buffer do tap é escolhido pelo formato, não pela posição. Se o layout for ambíguo (ex.: tap estéreo + microfone estéreo), a sessão falha com erro em vez de mandar o buffer errado. Não testado com hardware real.
- **DRM:** conteúdo protegido chega zerado e pode mostrar "Não está chegando som".
- Sessão que falha tenta de novo após 1, 2 e 4 s antes de mostrar "tentar de novo".

## Permissão entre rebuilds (etapa 9): NÃO TESTADO

Com assinatura ad-hoc o macOS pode pedir a permissão de novo a cada build. O script já fixa `--identifier`. Pra testar com um certificado local fixo:
1. Acesso às Chaves › Assistente de Certificado › Criar certificado… › tipo "Assinatura de código", nome `Mixer Local`.
2. `SIGN_IDENTITY="Mixer Local" scripts/build_app.sh`, conceda a permissão, rebuild e veja se ela se mantém.
Anote o resultado aqui.

## Pendências de validação

- Links de Ajustes (`x-apple.systempreferences:...`) não conferidos; o app cai pros Ajustes do Sistema se o link falhar.
- Fluxo com `tccutil reset` e permissão negada (etapa 7), e o teste com DRM/Bluetooth, não foram exercitados.

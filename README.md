# PartilhaEcra

Partilha de ecrã rápida em rede local entre **Android** e **Windows** — Wi-Fi ou cabo, sem servidores externos.

- **Host**: partilha o ecrã deste dispositivo (no Windows podes escolher um ecrã ou uma janela).
- **Recetor**: vê o ecrã de outro dispositivo. Os Hosts na mesma rede aparecem sozinhos.
- Código de 4 dígitos para aceitar cada ligação, até 4 recetores ao mesmo tempo.
- Vídeo por **WebRTC** (aceleração por hardware, encriptado ponto a ponto), latência típica de poucos ms em rede local.
- Qualidade Auto / Poupança / Máxima, 30 ou 60 fps no Windows, estatísticas em direto (latência, fps, Mbps).
- Ecrã completo (F11), captura de imagem, expulsar recetores.
- **Atualizações dentro da app**: ao abrir, a app verifica as Releases deste repositório e instala a nova versão.

## Instalar

Vai a **Releases** e descarrega:

| Ficheiro | Para |
|---|---|
| `PartilhaEcra.apk` | Android 6.0+ |
| `PartilhaEcra-Setup.exe` | Windows 10/11 (recomendado — permite atualizações automáticas) |
| `PartilhaEcra-Windows-Portatil.zip` | Windows sem instalar |

Na primeira vez que partilhares no Windows, aceita o aviso da firewall para **Redes privadas**.

## Como funciona

1. **Descoberta** — o Host anuncia-se por broadcast UDP (porta `45454`) a cada segundo.
2. **Ligação** — o Recetor liga-se por WebSocket (porta `45455`) e envia o código de 4 dígitos.
3. **Vídeo** — Host e Recetor negoceiam uma ligação WebRTC direta na rede local (sem STUN/TURN).

Se a descoberta não funcionar (alguns routers bloqueiam broadcast), usa **Ligar por IP**.

## Atualizações automáticas

A app consulta `https://api.github.com/repos/opaxpk/PartilhaEcra/releases/latest`:

- **Windows** — descarrega `PartilhaEcra-Setup.exe`, instala em silêncio e volta a abrir a app.
- **Android** — descarrega `PartilhaEcra.apk` e abre o instalador do sistema. O Android pede sempre uma confirmação (e, na primeira vez, autorização para "Instalar apps desconhecidas"); não existe forma de o evitar sem a Play Store.

> O repositório tem de ser **público** para a app conseguir ler as Releases sem login.

## Publicar uma nova versão

```bash
git tag v1.0.1
git push origin v1.0.1
```

O workflow **Release** compila o APK e o EXE, cria a Release, e todas as apps instaladas passam a oferecer a atualização.

### Segredos necessários (Settings → Secrets and variables → Actions)

O APK tem de ser assinado sempre com a **mesma chave**, senão as atualizações não instalam por cima.

| Segredo | Valor |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | o ficheiro `.jks` em base64 |
| `ANDROID_KEYSTORE_PASSWORD` | palavra-passe do keystore |
| `ANDROID_KEY_ALIAS` | alias da chave |
| `ANDROID_KEY_PASSWORD` | palavra-passe da chave |

Guarda uma cópia do `.jks` num sítio seguro — se o perderes, os utilizadores têm de desinstalar e instalar de novo.

## Compilar localmente

```bash
flutter create --platforms=android,windows --org com.opaxpk --project-name partilha_ecra .
python scripts/setup_platforms.py
flutter pub get
dart run flutter_launcher_icons
flutter run            # ou: flutter build apk / flutter build windows
```

As pastas `android/` e `windows/` são geradas (não estão no repositório); as alterações próprias da app
estão em `platform_overrides/` e são aplicadas pelo `scripts/setup_platforms.py`.

## Estrutura

```
lib/
  main.dart                  arranque e janela (Windows)
  config.dart                portas, repositório GitHub
  screens/                   Início, Host, Recetor, Visualizador, Definições
  services/
    discovery.dart           anúncio e descoberta UDP
    host_service.dart        servidor, código, WebRTC (envio)
    receiver_service.dart    ligação, WebRTC (receção), estatísticas
    capture.dart             captura de ecrã Android/Windows
    updater.dart             atualizações via GitHub Releases
platform_overrides/android/  serviço de captura em primeiro plano, MainActivity
installer/PartilhaEcra.iss   instalador Windows (Inno Setup)
.github/workflows/           compilação e publicação automáticas
```

## Planeado

- Partilha de áudio do sistema
- Controlar o Host com rato/teclado a partir do Recetor
- Gravação do ecrã recebido

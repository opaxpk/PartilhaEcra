#!/usr/bin/env python3
"""
Prepara as pastas android/ e windows/ da PartilhaEcra.

Uso (na raiz do projeto):
    flutter create --platforms=android,windows --org com.opaxpk --project-name partilha_ecra .
    python scripts/setup_platforms.py

O `flutter create` gera os ficheiros-base; este script aplica as alterações
próprias da app (permissões, serviço de captura, assinatura, nome do .exe...).
Pode ser corrido várias vezes sem problema.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OVR = ROOT / "platform_overrides"


def read(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8")


def write(p: pathlib.Path, s: str) -> None:
    p.write_text(s, encoding="utf-8", newline="\n")


def patch_android() -> None:
    android = ROOT / "android"
    if not android.exists():
        print("android/ não existe — corre primeiro o flutter create.")
        sys.exit(1)

    # --- AndroidManifest.xml ---
    manifest = android / "app/src/main/AndroidManifest.xml"
    m = read(manifest)
    permissions = [
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.ACCESS_WIFI_STATE",
        "android.permission.CHANGE_WIFI_MULTICAST_STATE",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.REQUEST_INSTALL_PACKAGES",
        "android.permission.WAKE_LOCK",
    ]
    missing = [p for p in permissions if p not in m]
    if missing:
        block = "".join(f'\n    <uses-permission android:name="{p}"/>' for p in missing)
        m = re.sub(r"(<manifest[^>]*>)", lambda mo: mo.group(1) + block, m, count=1)
    m = re.sub(r'android:label="[^"]*"', 'android:label="PartilhaEcra"', m, count=1)
    if "usesCleartextTraffic" not in m:
        m = m.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
    if "ScreenCaptureService" not in m:
        service = (
            '        <service\n'
            '            android:name=".ScreenCaptureService"\n'
            '            android:exported="false"\n'
            '            android:foregroundServiceType="mediaProjection" />\n'
        )
        m = m.replace("    </application>", service + "    </application>", 1)
    # Projetores / Android TV: aparecer no launcher e não exigir ecrã tátil.
    if "LEANBACK_LAUNCHER" not in m:
        m = m.replace(
            '<category android:name="android.intent.category.LAUNCHER"/>',
            '<category android:name="android.intent.category.LAUNCHER"/>\n'
            '                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
            1,
        )
    if "android.software.leanback" not in m:
        features = (
            '\n    <uses-feature android:name="android.software.leanback" android:required="false"/>'
            '\n    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>'
        )
        m = re.sub(r"(<manifest[^>]*>)", lambda mo: mo.group(1) + features, m, count=1)
    if "android:banner" not in m:
        m = m.replace("<application", '<application\n        android:banner="@drawable/banner"', 1)
    write(manifest, m)
    drawable = android / "app/src/main/res/drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    (drawable / "banner.png").write_bytes((OVR / "android/banner.png").read_bytes())

    # --- Kotlin: MainActivity + serviço ---
    activities = list((android / "app/src/main").rglob("MainActivity.kt"))
    if not activities:
        print("MainActivity.kt não encontrado.")
        sys.exit(1)
    activity = activities[0]
    package = re.search(r"^package\s+([\w.]+)", read(activity), re.M).group(1)
    for name in ("MainActivity.kt", "ScreenCaptureService.kt", "PcmPlayer.kt"):
        src = read(OVR / "android" / name).replace("__PACKAGE__", package)
        write(activity.parent / name, src)

    # --- build.gradle.kts: minSdk, assinatura e regras R8 ---
    gradle = android / "app/build.gradle.kts"
    g = read(gradle)
    g = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", g)
    if "keystorePropertiesFile" not in g:
        loader = (
            'val keystoreProperties = Properties()\n'
            'val keystorePropertiesFile = rootProject.file("key.properties")\n'
            'if (keystorePropertiesFile.exists()) {\n'
            '    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n'
            '}\n\n'
        )
        # Em .kts, "java" no topo resolve para a extensão do Gradle: é preciso importar.
        g = "import java.io.FileInputStream\nimport java.util.Properties\n\n" + g
        g = g.replace("android {", loader + "android {", 1)
        signing = (
            '    signingConfigs {\n'
            '        create("release") {\n'
            '            if (keystorePropertiesFile.exists()) {\n'
            '                keyAlias = keystoreProperties["keyAlias"] as String\n'
            '                keyPassword = keystoreProperties["keyPassword"] as String\n'
            '                storeFile = file(keystoreProperties["storeFile"] as String)\n'
            '                storePassword = keystoreProperties["storePassword"] as String\n'
            '            }\n'
            '        }\n'
            '    }\n\n'
            '    buildTypes {'
        )
        g = g.replace("    buildTypes {", signing, 1)
        g = g.replace(
            'signingConfig = signingConfigs.getByName("debug")',
            'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") '
            'else signingConfigs.getByName("debug")\n'
            '            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")',
            1,
        )
    write(gradle, g)
    write(android / "app/proguard-rules.pro", read(OVR / "android/proguard-rules.pro"))

    # No Windows o projeto (D:) e as bibliotecas (C:) ficam em discos diferentes e a
    # compilação incremental de Kotlin falha ("different roots"). Desligada.
    props = android / "gradle.properties"
    p_text = read(props) if props.exists() else ""
    if "kotlin.incremental" not in p_text:
        write(props, p_text.rstrip("\n") + "\nkotlin.incremental=false\n")
    print(f"Android preparado (package {package}).")


def patch_windows() -> None:
    win = ROOT / "windows"
    if not win.exists():
        print("windows/ não existe — a saltar.")
        return
    cmake = win / "CMakeLists.txt"
    write(cmake, re.sub(r'set\(BINARY_NAME "[^"]*"\)', 'set(BINARY_NAME "PartilhaEcra")', read(cmake)))

    main_cpp = win / "runner/main.cpp"
    s = read(main_cpp)
    s = re.sub(r'window\.Create\(L"[^"]*"', 'window.Create(L"PartilhaEcra"', s)
    write(main_cpp, s)

    # --- Som do PC para os recetores (WASAPI loopback) ---
    runner = win / "runner"
    for name in ("audio_loopback.h", "audio_loopback.cpp"):
        write(runner / name, read(OVR / "windows" / name))

    runner_cmake = runner / "CMakeLists.txt"
    rc_text = read(runner_cmake)
    if "audio_loopback.cpp" not in rc_text:
        rc_text = rc_text.replace('  "flutter_window.cpp"\n', '  "flutter_window.cpp"\n  "audio_loopback.cpp"\n', 1)
        rc_text = rc_text.rstrip("\n") + '\ntarget_link_libraries(${BINARY_NAME} PRIVATE "ole32.lib")\n'
        write(runner_cmake, rc_text)

    fw_h = runner / "flutter_window.h"
    h = read(fw_h)
    if "audio_loopback.h" not in h:
        h = h.replace('#include "win32_window.h"', '#include "audio_loopback.h"\n#include "win32_window.h"', 1)
        h = h.replace(
            "  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;",
            "  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;\n\n"
            "  // Captura do som do PC (enviado aos recetores).\n"
            "  std::unique_ptr<AudioLoopback> audio_loopback_;",
            1,
        )
        write(fw_h, h)

    fw_cpp = runner / "flutter_window.cpp"
    c = read(fw_cpp)
    if "audio_loopback_" not in c:
        c = c.replace(
            "  RegisterPlugins(flutter_controller_->engine());",
            "  RegisterPlugins(flutter_controller_->engine());\n"
            "  audio_loopback_ = std::make_unique<AudioLoopback>(\n"
            "      flutter_controller_->engine()->messenger(), GetHandle());",
            1,
        )
        c = c.replace(
            "void FlutterWindow::OnDestroy() {\n",
            "void FlutterWindow::OnDestroy() {\n  audio_loopback_ = nullptr;\n",
            1,
        )
        c = c.replace(
            "  // Give Flutter, including plugins, an opportunity to handle window messages.",
            "  if (message == AudioLoopback::kFlushMessage) {\n"
            "    if (audio_loopback_) audio_loopback_->Flush();\n"
            "    return 0;\n"
            "  }\n\n"
            "  // Give Flutter, including plugins, an opportunity to handle window messages.",
            1,
        )
        for marker in ("audio_loopback_ = std::make_unique", "audio_loopback_ = nullptr", "kFlushMessage"):
            if marker not in c:
                print(f"AVISO: não consegui aplicar '{marker}' em flutter_window.cpp")
                sys.exit(1)
        write(fw_cpp, c)

    rc = win / "runner/Runner.rc"
    r = read(rc)
    r = r.replace('"partilha_ecra.exe"', '"PartilhaEcra.exe"').replace('"partilha_ecra"', '"PartilhaEcra"')
    write(rc, r)
    print("Windows preparado.")


if __name__ == "__main__":
    patch_android()
    patch_windows()
    # O flutter create gera um teste de exemplo que não se aplica a esta app.
    sample = ROOT / "test/widget_test.dart"
    if sample.exists() and "MyApp" in read(sample):
        sample.unlink()

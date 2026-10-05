#!/usr/bin/env python3
"""
Correção à flutter_webrtc (Android) aplicada depois do `flutter pub get`.

Em alguns projetores/TV boxes (ex.: Rockchip), o descodificador de vídeo por
hardware crasha o WebRTC quando entrega as imagens por "textura"
("Rendered texture metadata was null in onTextureFrameAvailable").
Com esta correção, se a app definir a propriedade de sistema
`partilhaecra.hwByteBuffer=1` antes de iniciar o WebRTC, o descodificador por
hardware passa a entregar as imagens em memória (sem textura) — continua a
ser hardware (imagem nítida e leve), mas sem o caminho que crasha.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OLD = "this.wrappedVideoDecoderFactory = new WrappedVideoDecoderFactory(sharedContext);"
NEW = (
    'this.wrappedVideoDecoderFactory = new WrappedVideoDecoderFactory('
    '"1".equals(System.getProperty("partilhaecra.hwByteBuffer")) ? null : sharedContext);'
)


def package_root(name: str) -> pathlib.Path:
    config = json.loads((ROOT / ".dart_tool/package_config.json").read_text(encoding="utf-8"))
    for pkg in config["packages"]:
        if pkg["name"] == name:
            uri = pkg["rootUri"]
            if uri.startswith("file://"):
                uri = uri[len("file://"):]
                if sys.platform == "win32" and uri.startswith("/"):
                    uri = uri[1:]
                return pathlib.Path(uri)
            return (ROOT / ".dart_tool" / uri).resolve()
    raise SystemExit(f"Pacote {name} não encontrado — corre primeiro flutter pub get.")


def main() -> None:
    src = package_root("flutter_webrtc") / "android/src/main/java/org/webrtc/video/CustomVideoDecoderFactory.java"
    text = src.read_text(encoding="utf-8")
    if NEW in text:
        print("flutter_webrtc já corrigida.")
        return
    if OLD not in text:
        raise SystemExit(f"Não encontrei o código a corrigir em {src} (versão da flutter_webrtc mudou?).")
    src.write_text(text.replace(OLD, NEW, 1), encoding="utf-8")
    print(f"flutter_webrtc corrigida: {src}")


if __name__ == "__main__":
    main()

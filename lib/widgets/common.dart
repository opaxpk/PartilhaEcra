import 'package:flutter/material.dart';

import '../services/network_info.dart';
import '../theme.dart';

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor = AppColors.border,
    this.color = AppColors.surface,
    this.radius = 16,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color borderColor;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: AppColors.muted,
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.accent, this.background = AppColors.accentDim});
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(Icons.screen_share_outlined, color: AppColors.onAccent, size: size * 0.55),
    );
  }
}

/// Cartão clicável que mostra um contorno branco quando é selecionado com o
/// comando do projetor/TV ou com o teclado (setas + OK/Enter).
class FocusCard extends StatefulWidget {
  const FocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.radius = 16,
    this.borderSide = const BorderSide(color: AppColors.border),
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final double radius;
  final BorderSide borderSide;
  final bool autofocus;

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final showRing =
        _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return AnimatedScale(
      scale: showRing ? 1.02 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: Material(
        color: showRing ? AppColors.surface2 : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.radius),
          side: showRing ? focusRing : widget.borderSide,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: widget.autofocus,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Cartão grande de escolha de modo (Host / Recetor).
class ModeCard extends StatelessWidget {
  const ModeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onColor,
    required this.onTap,
    this.highlighted = false,
    this.footer,
    this.autofocus = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color onColor;
  final VoidCallback onTap;
  final bool highlighted;
  final String? footer;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FocusCard(
      radius: 20,
      autofocus: autofocus,
      borderSide: BorderSide(color: highlighted ? color : AppColors.border, width: highlighted ? 1.5 : 1),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: onColor, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
            if (footer != null) ...[
              const SizedBox(height: 14),
              Text(footer!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label, this.valueColor = AppColors.text});
  final String value;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(12),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: valueColor)),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// Mostra a rede atual (Wi-Fi/cabo e IP).
class NetworkBanner extends StatefulWidget {
  const NetworkBanner({super.key});

  @override
  State<NetworkBanner> createState() => _NetworkBannerState();
}

class _NetworkBannerState extends State<NetworkBanner> {
  LocalNetwork? _net;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final net = await getPrimaryNetwork();
    if (!mounted) return;
    setState(() {
      _net = net;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final net = _net;
    final ok = net != null;
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 14,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: ok ? AppColors.accent : AppColors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  !_loaded
                      ? 'A verificar a rede…'
                      : ok
                          ? 'Ligado por ${net.type.label}'
                          : 'Sem rede local',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  ok
                      ? 'IP ${net.ip}${net.type == LinkType.cable ? ' · baixa latência' : ''}'
                      : 'Liga-te ao Wi-Fi ou a um cabo de rede',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: AppColors.muted, size: 20),
          ),
        ],
      ),
    );
  }
}

IconData platformIcon(String platform) {
  final p = platform.toLowerCase();
  if (p.contains('android')) return Icons.smartphone;
  if (p.contains('windows')) return Icons.desktop_windows_outlined;
  return Icons.devices_other;
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

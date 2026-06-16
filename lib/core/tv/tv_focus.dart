import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';

/// TV 端焦点环颜色 — 朱砂 (Cinnabar)
const Color kTvFocusColor = Color(0xFFE24A1A);

/// TV 焦点包裹器 — 4dp 朱砂焦点环
class TvFocus extends StatefulWidget {
  const TvFocus({
    super.key,
    required this.child,
    this.autofocus = false,
    this.onTap,
    this.onKeyEvent,
    this.focusNode,
    this.borderRadius = 12,
  });

  final Widget child;
  final bool autofocus;
  final VoidCallback? onTap;
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;
  final FocusNode? focusNode;
  final double borderRadius;

  @override
  State<TvFocus> createState() => _TvFocusState();
}

class _TvFocusState extends State<TvFocus> {
  late FocusNode _node;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _node.dispose();
    } else {
      _node.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _focused = _node.hasFocus);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (widget.onKeyEvent != null) {
      final result = widget.onKeyEvent!(event);
      if (result == KeyEventResult.handled) return result;
    }
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.select) {
        widget.onTap?.call();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border:
                _focused ? Border.all(color: kTvFocusColor, width: 4) : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// TV 焦点遍历组 — 包裹整个页面, 自动管理方向键导航
class TvFocusGroup extends StatelessWidget {
  const TvFocusGroup({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: child,
    );
  }
}

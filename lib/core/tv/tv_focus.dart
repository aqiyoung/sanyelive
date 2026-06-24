import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';

/// TV 端焦点环颜色 — 朱砂 (Cinnabar) — 用于 [kTvFocusColor] 常量与
/// 单元测试断言. TvFocus widget 实际渲染用的是 [IptvColors.accentTerracotta]
/// (P2-1: 老板 6/18 拍板 1.05 scale + 2px 暖色边,  看起来更明显但不刺眼).
const Color kTvFocusColor = Color(0xFFE24A1A);

/// TV 焦点包裹器 — 1.05 scale + 2px 赤陶焦点边 (P2-1 6/18 老板拍板).
///
/// 高亮态: scale 1.0 → 1.05, 2px IptvColors.accentTerracotta 0.6 alpha 边.
/// 非高亮态: 无变换无边. 动画 150ms ease.
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
        child: AnimatedScale(
          // P2-1 (6/18 老板拍): 高亮态 scale 1.03 → 1.05, 远距离更明显.
          // ChatGPT 6/17 21:18 建议, 1.05 是"明显但不夸张"的上限.
          scale: _focused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              // P2-1: 焦点边 4dp 朱砂 → 2px 赤陶 0.6 alpha.
              //  4dp 太厚遮卡片内容,  2px + scale 1.05 远距离也清晰.
              border: _focused
                  ? Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.6),
                      width: 2,
                    )
                  : null,
            ),
            child: widget.child,
          ),
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

/// P2-1: 一屏焦点上限 — ChatGPT 6/17 建议
///
/// TV 遥控器场景下, 一屏可聚焦项应限制在 7-9 个 (不能自由漂移).
/// 超出时 Row 自动折行, Column 自动截断.
///
/// 使用方式: 包裹 children 列表, 超出 [maxFocusable] 时在 debug 模式报 assert.
/// [TvFocusCapWrap] 提供 Row→Wrap 自动折行.
const int kTvMaxFocusablePerScreen = 9;

/// 包裹多个子组件, debug 模式下 assert 焦点项 <= [kTvMaxFocusablePerScreen].
///
/// 布局行为: 超出上限时截断 (只渲染前 N 项).
/// 如果需要折行, 用 [TvFocusCapWrap] 代替 Row.
class TvFocusCap extends StatelessWidget {
  const TvFocusCap({
    super.key,
    required this.children,
    this.maxFocusable = kTvMaxFocusablePerScreen,
  });

  final List<Widget> children;
  final int maxFocusable;

  @override
  Widget build(BuildContext context) {
    assert(
      children.length <= maxFocusable,
      'TV 一屏焦点项 ${children.length} 超出上限 $maxFocusable, '
      '请分页或用 Wrap 折行. '
      '(P2-1: ChatGPT 6/17 建议, 老板拍板)',
    );
    // 截断超出上限的项
    final visible = children.length <= maxFocusable
        ? children
        : children.sublist(0, maxFocusable);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: visible,
    );
  }
}

/// TV 焦点 Wrap 布局 — Row 超出上限时自动折行
///
/// 替代 Row + Expanded 组合, 当 children 超出 [maxPerRow] 时自动换行.
/// 每行最多 [maxPerRow] 个焦点项 (默认 9).
class TvFocusCapWrap extends StatelessWidget {
  const TvFocusCapWrap({
    super.key,
    required this.children,
    this.maxPerRow = kTvMaxFocusablePerScreen,
    this.spacing = 8,
    this.runSpacing = 8,
  });

  final List<Widget> children;
  final int maxPerRow;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    assert(
      children.length <= maxPerRow,
      'TV 焦点项 ${children.length} 超出单行上限 $maxPerRow, '
      '会自动折行. 建议分页控制在 $maxPerRow 以内.',
    );
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: children,
    );
  }
}

/// P2-1: 一屏焦点项上限守卫 (用于复杂布局, 仅断言不改布局).
///
/// 不同于 [TvFocusCap] / [TvFocusCapWrap] 只能用于 flat children list,
/// 本 widget 只做断言, 不改变布局. 适合 CustomScrollView / GridView 这种
/// children 不是 flat list 的场景. 调用方提供实际焦点项数, debug 模式下
/// 超出上限时报 assert 警告 (生产运行时无效果).
class TvFocusScope extends StatelessWidget {
  const TvFocusScope({
    super.key,
    required this.actualFocusableCount,
    required this.child,
    this.maxFocusable = kTvMaxFocusablePerScreen,
  });

  /// 当前布局中实际可聚焦项数 (调用方在 build 阶段填).
  final int actualFocusableCount;

  /// 最大可聚焦项数 (默认 [kTvMaxFocusablePerScreen] = 9).
  final int maxFocusable;

  /// 被守卫的子组件 (布局不变).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    assert(
      actualFocusableCount <= maxFocusable,
      'TV 一屏焦点项 $actualFocusableCount 超出上限 $maxFocusable, '
      '请分页或减少焦点项. '
      '(P2-1: ChatGPT 6/17 建议, 老板拍板)',
    );
    return child;
  }
}

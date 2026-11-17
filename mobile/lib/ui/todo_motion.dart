import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:prism_ui/icons/icons.dart';

Route<T> todoPageRoute<T>(BuildContext context, WidgetBuilder builder) {
  if (!MediaQuery.disableAnimationsOf(context)) {
    return p.CardPageRoute<T>(builder: builder);
  }
  return PageRouteBuilder<T>(
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => builder(context),
  );
}

Future<T?> showTodoFormSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  p.SheetProps props = const p.SheetProps(),
}) {
  if (!MediaQuery.disableAnimationsOf(context)) {
    return p.showFormSheet<T>(context: context, builder: builder, props: props);
  }
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: p.UiLocalizations.of(context).close,
      barrierColor: p.Theme.of(context).colorScheme.modalScrim,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => p.ElevatedSurfaceTheme(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              8,
              24,
              8,
              8 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: 0.94,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: p.Surface(
                    color: p.SurfaceLevel.page.colorOf(
                      p.Theme.of(context).colorScheme,
                    ),
                    shape: p.AppShape.xxl,
                    clipBehavior: Clip.antiAlias,
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      removeBottom: true,
                      child: p.SheetProvider(
                        type: p.SheetType.bottomSheet,
                        child: Builder(
                          builder: (context) => MediaQuery.removeViewInsets(
                            context: context,
                            removeBottom: true,
                            child: builder(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class TodoDock extends StatelessWidget {
  const TodoDock({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });
  final List<p.NavigationDockDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    if (!MediaQuery.disableAnimationsOf(context)) {
      return p.NavigationDock(
        destinations: destinations,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
      );
    }
    final colors = p.Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: p.Surface(
          color: p.SurfaceLevel.floatingOf(colors).colorOf(colors),
          shape: p.AppShape.full,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: Semantics(
                      excludeSemantics: true,
                      button: true,
                      selected: i == selectedIndex,
                      label: destinations[i].label,
                      child: p.PressRegion(
                        onTap: () => onSelected(i),
                        shape: p.AppShape.full,
                        child: p.Surface(
                          color: i == selectedIndex
                              ? colors.onSurface.withValues(alpha: 0.08)
                              : const Color(0x00000000),
                          shape: p.AppShape.full,
                          child: SizedBox(
                            height: 54,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                GlyphIcon(
                                  destinations[i].glyph,
                                  color: i == selectedIndex
                                      ? colors.primary
                                      : colors.onSurfaceVariant,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  destinations[i].label,
                                  style: p.AppTextStyle.caption2
                                      .of(context, emphasized: true)
                                      .copyWith(
                                        color: i == selectedIndex
                                            ? colors.primary
                                            : colors.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TodoSidebar extends StatelessWidget {
  const TodoSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.expanded,
    required this.onSelected,
  });
  final List<p.SidebarDestination> destinations;
  final int selectedIndex;
  final bool expanded;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    if (!MediaQuery.disableAnimationsOf(context)) {
      return p.NavigationSidebar(
        destinations: destinations,
        selectedIndex: selectedIndex,
        expanded: expanded,
        onSelected: onSelected,
      );
    }
    final colors = p.Theme.of(context).colorScheme;
    return SizedBox(
      width: expanded ? 220 : 64,
      child: p.Surface(
        color: p.SurfaceLevel.page.colorOf(colors),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            8,
            MediaQuery.paddingOf(context).top + 20,
            8,
            12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: expanded
                    ? Text(
                        'Todo',
                        style: p.AppTextStyle.title2.of(
                          context,
                          emphasized: true,
                        ),
                      )
                    : GlyphIcon(destinations.first.glyph),
              ),
              for (var i = 0; i < destinations.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: p.PressRegion(
                    onTap: () => onSelected(i),
                    shape: p.AppShape.sm,
                    child: p.Surface(
                      color: i == selectedIndex
                          ? colors.onSurface.withValues(alpha: 0.08)
                          : const Color(0x00000000),
                      shape: p.AppShape.sm,
                      child: SizedBox(
                        height: 48,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GlyphIcon(
                              destinations[i].glyph,
                              color: i == selectedIndex
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                            if (expanded) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  destinations[i].label,
                                  style: p.AppTextStyle.body.of(context),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

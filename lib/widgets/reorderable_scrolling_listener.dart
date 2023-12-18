import 'dart:async';

import 'package:flutter/cupertino.dart';

/// Uses [Listener] to indicate position updates while dragging a child and enables an autoscroll functionality.
class ReorderableScrollingListener extends StatefulWidget {
  final Widget child;
  final bool isDragging;
  final double automaticScrollExtent;
  final bool enableScrollingWhileDragging;

  final PointerMoveEventListener onDragUpdate;
  final VoidCallback onDragEnd;

  /// Called when the current scrolling position changes.
  final void Function(double scrollPixels) onScrollUpdate;

  /// Should be the key of the added [GridView].
  final GlobalKey? reorderableChildKey;

  /// Should be the [ScrollController] of the [GridView].
  final ScrollController? scrollController;

  const ReorderableScrollingListener({
    required this.child,
    required this.isDragging,
    required this.enableScrollingWhileDragging,
    required this.automaticScrollExtent,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onScrollUpdate,
    required this.reorderableChildKey,
    required this.scrollController,
    Key? key,
  }) : super(key: key);

  @override
  State<ReorderableScrollingListener> createState() =>
      _ReorderableScrollingListenerState();
}

class _ReorderableScrollingListenerState
    extends State<ReorderableScrollingListener> {
  /// If true, ta widget outside of [ReorderableBuilder] is scrollable and not the widget inside ([GridView])
  bool _isScrollableOutside = false;

  /// Describes current scroll position in pixels.
  double _scrollPositionPixels = 0.0;

  /// Repeating timer to ensure that autoscroll also works when the user doesn't the dragged child.
  Timer? _scrollCheckTimer;

  /// [Size] of the child that was found in [widget.reorderableChildKey].
  Size? _childSize;

  /// [Offset] of the child that was found in [widget.reorderableChildKey].
  Offset? _childOffset;

  @override
  void didUpdateWidget(covariant ReorderableScrollingListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDragging != oldWidget.isDragging) {
      if (widget.isDragging) {
        _updateChildSizeAndOffset();
        setState(() {
          _scrollPositionPixels = _scrollPixels;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerMove: (details) {
        if (widget.isDragging) {
          _handleDragUpdate(details);
        }
      },
      onPointerUp: (details) {
        if (widget.isDragging) {
          widget.onDragEnd();
        }
      },
      child: widget.child,
    );
  }

  /// Always called when the user moves the dragged child around.
  ///
  /// If there is a [widget.reorderableChildKey] and [widget.scrollController],
  /// then the autoscroll is starting by creating a repeating timer that calls
  /// himself every 10 ms to check if widget of [widget.reorderableChildKey]
  /// can be scrolled up or down.
  ///
  /// The timer cancels himself before recreating a new one and to ensure that
  /// no timer is ongoing when the [widget.isDragging] stopped, it checks also himself
  /// if it has to be canceled.
  void _handleDragUpdate(PointerMoveEvent details) {
    if (widget.enableScrollingWhileDragging &&
        widget.reorderableChildKey != null &&
        widget.scrollController != null) {
      final position = details.position;

      _scrollCheckTimer?.cancel();
      _scrollCheckTimer = Timer.periodic(
        const Duration(milliseconds: 10),
        (timer) {
          if (widget.isDragging) {
            _checkToScrollWhileDragging(dragPosition: position);
          } else {
            timer.cancel();
          }
        },
      );
    }

    widget.onDragUpdate(details);
  }

  /// Checks if [widget.scrollController] can scrolling up or down depending on [widget.automaticScrollExtent].
  ///
  /// This only works if [widget.reorderableChildKey] is not null. By defining
  /// a range ([widget.automaticScrollExtent]) that should trigger the autoscroll,
  /// it is checked whether to scroll down or up depending on the current [dragPosition].
  void _checkToScrollWhileDragging({required Offset dragPosition}) {
    final childSize = _childSize;
    final childOffset = _childOffset;

    if (childSize != null && childOffset != null) {
      final allowedRange = widget.automaticScrollExtent;
      late double minDy;
      final maxDy = childOffset.dy + childSize.height - allowedRange;

      // minDy can be different when having the scrollable outside ReorderableBuilder
      // at the beginning the childOffset dy would be the correct minDy
      // but while scrolling this would lead to 0 and is important to trigger the automatic scroll at the right moment
      if (_isScrollableOutside) {
        minDy = childOffset.dy - _scrollPositionPixels;
        if (minDy < 0) {
          minDy = 0;
        }
        minDy += allowedRange;
      } else {
        minDy = childOffset.dy + allowedRange;
      }

      const variance = 5.0;

      if(widget.scrollController?.hasClients ?? false){
        // scroll to top
        if (dragPosition.dy <= minDy && _scrollPositionPixels > 0) {
          _scrollPositionPixels -= variance;
          _scrollTo(dy: _scrollPositionPixels);
        } else if (dragPosition.dy >= maxDy &&
            _scrollPositionPixels <
                widget.scrollController!.position.maxScrollExtent) {
          _scrollPositionPixels += variance;
          _scrollTo(dy: _scrollPositionPixels);
        }
      }
    }
  }

  /// Scrolling to the specified [dy] using [widget.scrollController].
  void _scrollTo({required double dy}) {
    final scrollController = widget.scrollController;

    if (scrollController != null && scrollController.hasClients) {
      scrollController.jumpTo(dy);

      widget.onScrollUpdate(dy);
    }
  }

  /// Updates [_childOffset] and [_childSize] using the values defined in [widget.reorderableChildKey].
  ///
  /// There are two ways when scrolling. It is possible that the [GridView] is scrollable
  /// or a parent widget.
  /// To ensure that the parent widget is the scrollable part, the [GridView] has
  /// to have more height than the screen size. This is an indicator that the [GridView]
  /// is not scrollable.
  /// If that is the case, then the size of the [GridView] is calculated with the
  /// height of the screen and the current offset.dy of the [GridView].
  void _updateChildSizeAndOffset() {
    _ambiguate(WidgetsBinding.instance)!.addPostFrameCallback((_) {
      final reorderableChildRenderBox =
          widget.reorderableChildKey?.currentContext?.findRenderObject()
              as RenderBox?;
      final screenSize = MediaQuery.of(context).size;

      if (reorderableChildRenderBox != null) {
        var reorderableChildOffset =
            reorderableChildRenderBox.localToGlobal(Offset.zero);

        // a scrollable widget is outside when there was found one, probably not the best solution to detect that
        _isScrollableOutside =
            Scrollable.maybeOf(context)?.position.pixels != null;

        if (_isScrollableOutside) {
          reorderableChildOffset = Offset(
            reorderableChildOffset.dx,
            reorderableChildOffset.dy + _scrollPositionPixels,
          );
        }

        final reorderableChildDy = reorderableChildOffset.dy;
        final reorderableChildSize = reorderableChildRenderBox.size;

        if (reorderableChildDy + reorderableChildSize.height >
            screenSize.height) {
          _childSize = Size(0, screenSize.height - reorderableChildDy);
        } else {
          _childSize = reorderableChildSize;
        }
        _childOffset = reorderableChildOffset;
      }
    });
  }

  /// Returning the current scroll position depending on [widget.scrollController] and [context].
  ///
  /// If the scroll position of [context] or [widget.scrollController] is accessible,
  /// then the value of the current position is returned.
  ///
  /// Otherwise 0.0.
  double get _scrollPixels {
    var pixels = Scrollable.maybeOf(context)?.position.pixels;
    final scrollController = widget.scrollController;

    if (pixels != null) {
      return pixels;
    } else if (scrollController != null && scrollController.hasClients) {
      return scrollController.position.pixels;
    } else {
      return 0.0;
    }
  }
}

/// This allows a value of type T or T?
/// to be treated as a value of type T?.
///
/// We use this so that APIs that have become
/// non-nullable can still be used with `!` and `?`
/// to support older versions of the API as well.
T? _ambiguate<T>(T? value) => value;

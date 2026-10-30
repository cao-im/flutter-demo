import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const MethodChannel _appChannel = MethodChannel('com.clb.caoim/app');

void hideKeyboard() {
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}

bool keyboardVisibleOf(BuildContext context) {
  return MediaQuery.viewInsetsOf(context).bottom > 0;
}

bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// 点在输入框外面时收起输入法。按钮仍会收到这次点击。
void dismissKeyboardIfOutsideField(PointerDownEvent event) {
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null || !focus.hasFocus) return;
  final object = focus.context?.findRenderObject();
  if (object is RenderBox && object.attached && object.hasSize) {
    final rect = object.localToGlobal(Offset.zero) & object.size;
    if (rect.inflate(12).contains(event.position)) return;
  }
  hideKeyboard();
}

class KeyboardDismissOnBlank extends StatelessWidget {
  final Widget child;

  const KeyboardDismissOnBlank({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: dismissKeyboardIfOutsideField,
      child: child,
    );
  }
}

/// 输入法弹出时，返回只收起输入法。安卓根页面再返回则退到后台。
class AppBackScope extends StatelessWidget {
  final Widget child;

  const AppBackScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final keyboard = keyboardVisibleOf(context);
    final isRoot = ModalRoute.of(context)?.isFirst ?? false;
    final holdRoot = isRoot && _isAndroid;
    return PopScope(
      canPop: !keyboard && !holdRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (keyboardVisibleOf(context)) {
          hideKeyboard();
          return;
        }
        if (holdRoot) {
          moveAppToBackground();
        }
      },
      child: child,
    );
  }
}

class AppRoute<T> extends MaterialPageRoute<T> {
  AppRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
  }) : super(builder: (context) => AppBackScope(child: builder(context)));
}

/// 系统返回键。注册要早于 Navigator，这样会先于页面弹出被调用。
class KeyboardBackObserver extends WidgetsBindingObserver {
  KeyboardBackObserver(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Future<bool> didPopRoute() async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return false;
    final context = navigator.context;
    if (keyboardVisibleOf(context)) {
      hideKeyboard();
      return true;
    }
    if (!navigator.canPop() && _isAndroid) {
      await moveAppToBackground();
      return true;
    }
    return false;
  }
}

Future<void> moveAppToBackground() async {
  if (!_isAndroid) return;
  try {
    await _appChannel.invokeMethod<void>('moveToBackground');
  } catch (error) {
    debugPrint('退到后台失败: $error');
  }
}

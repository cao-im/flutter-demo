import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../providers/call_provider.dart';

/// 盖在当前页面上的一对一语音或视频通话。
class CallOverlay extends StatelessWidget {
  final Widget child;

  const CallOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Consumer<CallProvider>(
          builder: (context, call, _) {
            if (!call.visible) return const SizedBox.shrink();
            return const Positioned.fill(child: CallPage());
          },
        ),
      ],
    );
  }
}

class CallPage extends StatefulWidget {
  const CallPage({super.key});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  @override
  void initState() {
    super.initState();
    _hideInput();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hideInput());
  }

  void _hideInput() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallProvider>();
    final incoming = call.phase == CallPhase.incoming;
    final showRemoteVideo = call.video && call.remoteVideoReady;
    return Material(
      color: const Color(0xFF1F2329),
      child: SafeArea(
        child: Stack(
          children: [
            if (showRemoteVideo)
              const Positioned.fill(child: _RemoteVideo())
            else if (call.rendererReady)
              const SizedBox(width: 1, height: 1, child: _RemoteAudio()),
            if (!showRemoteVideo)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 48,
                      backgroundColor: Color(0xFF3A3F47),
                      child: Icon(Icons.person, size: 52, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      call.peerName,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Text(call.statusText, style: const TextStyle(color: Color(0xFFB7BDC6), fontSize: 15)),
                  ],
                ),
              ),
            if (showRemoteVideo)
              Positioned(
                left: 20,
                top: 16,
                right: 132,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      call.peerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(call.statusText, style: const TextStyle(color: Color(0xFFE6E8EB), fontSize: 14)),
                  ],
                ),
              ),
            if (call.video && call.localPreviewReady && (call.phase == CallPhase.connecting || call.phase == CallPhase.active))
              const Positioned(top: 16, right: 16, child: _LocalPreview()),
            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (incoming) ...[
                    _roundButton(
                      color: const Color(0xFF07C160),
                      icon: call.video ? Icons.videocam : Icons.call,
                      label: '接听',
                      onTap: () => context.read<CallProvider>().accept(),
                    ),
                    const SizedBox(width: 48),
                  ],
                  if (call.video && (call.phase == CallPhase.connecting || call.phase == CallPhase.active)) ...[
                    _roundButton(
                      color: const Color(0xFF3A3F47),
                      icon: Icons.cameraswitch_outlined,
                      label: '翻转',
                      onTap: () => context.read<CallProvider>().switchCamera(),
                    ),
                    const SizedBox(width: 48),
                  ],
                  _roundButton(
                    color: const Color(0xFFFA5151),
                    icon: Icons.call_end,
                    label: call.phase == CallPhase.failed ? '关闭' : (incoming ? '拒绝' : '挂断'),
                    onTap: () {
                      if (call.phase == CallPhase.failed) {
                        context.read<CallProvider>().dismissError();
                      } else {
                        context.read<CallProvider>().decline();
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundButton({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 68, height: 68, child: Icon(icon, color: Colors.white, size: 30)),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ],
    );
  }
}

class _RemoteAudio extends StatelessWidget {
  const _RemoteAudio();

  @override
  Widget build(BuildContext context) {
    final renderer = context.read<CallProvider>().remoteRenderer;
    return RTCVideoView(renderer);
  }
}

class _RemoteVideo extends StatelessWidget {
  const _RemoteVideo();

  @override
  Widget build(BuildContext context) {
    final renderer = context.read<CallProvider>().remoteRenderer;
    return RTCVideoView(renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
  }
}

class _LocalPreview extends StatelessWidget {
  const _LocalPreview();

  @override
  Widget build(BuildContext context) {
    final renderer = context.read<CallProvider>().localRenderer;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 104,
        height: 156,
        child: RTCVideoView(
          renderer,
          mirror: true,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      ),
    );
  }
}

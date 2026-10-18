import 'dart:async';

import 'package:cao_im_sdk_flutter/cao_im_sdk_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../sdk/im_sdk_manager.dart';
import '../services/call_ringtone.dart';

enum CallPhase { idle, outgoing, incoming, connecting, active, failed }

/// 一对一语音或视频。信令走现有 WebSocket，音视频在两端之间直连。
class CallProvider extends ChangeNotifier {
  CallProvider() {
    _signals = EventBus().on<CallSignalEvent>().listen(_onEvent);
    _ensureRenderer();
  }

  late final StreamSubscription<CallSignalEvent> _signals;

  final IMSdkManager _sdk = IMSdkManager();
  final CallRingtone _ringtone = CallRingtone();

  CallPhase phase = CallPhase.idle;
  bool video = false;
  String peerName = '';
  String errorText = '';
  int elapsedSeconds = 0;

  String? _callId;
  bool _caller = false;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  bool _rendererReady = false;
  bool _localRendererReady = false;
  bool _localPreviewReady = false;
  bool remoteVideoReady = false;
  bool _remoteReady = false;
  MediaStream? _remoteStream;
  final List<RTCIceCandidate> _pendingCandidates = [];
  Timer? _ticker;

  bool get visible => phase != CallPhase.idle;

  bool get rendererReady => _rendererReady;

  bool get localPreviewReady => _localPreviewReady;

  String get statusText {
    switch (phase) {
      case CallPhase.outgoing:
        return '正在呼叫';
      case CallPhase.incoming:
        return video ? '邀请你视频通话' : '邀请你语音通话';
      case CallPhase.connecting:
        return '正在连接';
      case CallPhase.active:
        final minute = elapsedSeconds ~/ 60;
        final second = elapsedSeconds % 60;
        return '${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
      case CallPhase.failed:
        return errorText.isEmpty ? '呼叫失败' : errorText;
      case CallPhase.idle:
        return '';
    }
  }

  Future<void> invite(int peerId, String name, {bool withVideo = false}) async {
    if (phase != CallPhase.idle || peerId <= 0) return;
    _caller = true;
    video = withVideo;
    _callId = '${DateTime.now().microsecondsSinceEpoch}';
    peerName = name;
    phase = CallPhase.outgoing;
    errorText = '';
    notifyListeners();
    _ringtone.playOutgoing();
    try {
      _sdk.client.inviteCall(peerId, _callId!, video: withVideo);
    } catch (e) {
      _fail('网络未连接');
    }
  }

  Future<void> accept() async {
    if (phase != CallPhase.incoming || _callId == null) return;
    phase = CallPhase.connecting;
    notifyListeners();
    await _ringtone.stop();
    try {
      await _preparePeer();
      _sdk.client.acceptCall(_callId!);
    } catch (e) {
      debugPrint('接听失败: $e');
      if (_callId != null) {
        _safe(() => _sdk.client.rejectCall(_callId!));
      }
      _fail(video ? '无法使用摄像头' : '无法使用麦克风');
    }
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (e) {
      debugPrint('切换摄像头失败: $e');
    }
  }

  void decline() {
    final id = _callId;
    if (phase == CallPhase.incoming && id != null) {
      _safe(() => _sdk.client.rejectCall(id));
    } else if (phase == CallPhase.outgoing && id != null) {
      _safe(() => _sdk.client.cancelCall(id));
    } else if (id != null && (phase == CallPhase.connecting || phase == CallPhase.active)) {
      _safe(() => _sdk.client.hangupCall(id));
    }
    _reset();
  }

  void _onEvent(CallSignalEvent event) {
    switch (event.action) {
      case 'ringing':
        if (phase == CallPhase.outgoing) {
          _callId = event.callId ?? _callId;
          if ((event.name ?? '').isNotEmpty) peerName = event.name!;
          notifyListeners();
        }
      case 'incoming':
        if (phase != CallPhase.idle) return;
        _caller = false;
        _callId = event.callId;
        video = event.video;
        peerName = (event.name ?? '').isEmpty ? (event.video ? '视频通话' : '语音通话') : event.name!;
        phase = CallPhase.incoming;
        notifyListeners();
        _ringtone.playIncoming();
      case 'accepted':
        if (_caller && _same(event.callId)) {
          _beginCallerMedia();
        }
      case 'signal':
        if (_same(event.callId)) {
          _onSignal(event.payload);
        }
      case 'rejected':
      case 'cancelled':
      case 'hangup':
      case 'ended':
        if (_same(event.callId)) _reset();
      case 'failed':
        if (_same(event.callId) &&
            (phase == CallPhase.outgoing || phase == CallPhase.incoming || phase == CallPhase.connecting)) {
          _fail(event.reason ?? '呼叫失败');
        }
    }
  }

  bool _same(String? id) => id == null || _callId == null || id == _callId;

  Future<void> _beginCallerMedia() async {
    if (phase != CallPhase.outgoing && phase != CallPhase.connecting) return;
    phase = CallPhase.connecting;
    notifyListeners();
    await _ringtone.stop();
    try {
      await _preparePeer();
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      _sdk.client.sendCallSignal(_callId!, {'kind': 'offer', 'sdp': offer.sdp});
    } catch (e) {
      debugPrint('发起通话失败: $e');
      if (_callId != null) {
        _safe(() => _sdk.client.cancelCall(_callId!));
      }
      _fail(video ? '无法使用摄像头' : '无法使用麦克风');
    }
  }

  Future<void> _preparePeer() async {
    await _ensureRenderer();
    if (video) {
      await _ensureLocalRenderer();
    }
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video
          ? {
              'facingMode': 'user',
              'width': 640,
              'height': 480,
            }
          : false,
    });
    if (video && _localRendererReady) {
      localRenderer.srcObject = _localStream;
      _localPreviewReady = true;
      notifyListeners();
    }
    _pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
    _pc!.onIceCandidate = (candidate) {
      final id = _callId;
      if (id == null || candidate.candidate == null || candidate.candidate!.isEmpty) return;
      _safe(() => _sdk.client.sendCallSignal(id, {
            'kind': 'candidate',
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }));
    };
    _pc!.onTrack = (event) {
      _attachRemoteTrack(event);
    };
    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (_) {}
  }

  Future<void> _attachRemoteTrack(RTCTrackEvent event) async {
    try {
      event.track.enabled = true;
      MediaStream? stream = event.streams.isNotEmpty ? event.streams.first : null;
      if (event.track.kind == 'video') {
        if (stream == null || stream.getVideoTracks().isEmpty) {
          _remoteStream ??= await createLocalMediaStream('remote');
          await _remoteStream!.addTrack(event.track);
          stream = _remoteStream;
        }
        await remoteRenderer.setSrcObject(stream: stream, trackId: event.track.id);
        remoteVideoReady = true;
        notifyListeners();
      } else if (remoteRenderer.srcObject == null && stream != null) {
        remoteRenderer.srcObject = stream;
      }
    } catch (e) {
      debugPrint('挂载对方画面失败: $e');
    }
  }

  Future<void> _ensureRenderer() async {
    if (_rendererReady) return;
    try {
      await remoteRenderer.initialize();
      _rendererReady = true;
      if (visible) notifyListeners();
    } catch (e) {
      debugPrint('音频渲染初始化失败: $e');
    }
  }

  Future<void> _ensureLocalRenderer() async {
    if (_localRendererReady) return;
    try {
      await localRenderer.initialize();
      _localRendererReady = true;
    } catch (e) {
      debugPrint('本地画面初始化失败: $e');
    }
  }

  Future<void> _onSignal(Map<String, dynamic> payload) async {
    final kind = payload['kind']?.toString();
    if (_pc == null || kind == null) return;
    try {
      if (kind == 'offer' || kind == 'answer') {
        final sdp = payload['sdp']?.toString() ?? '';
        if (sdp.isEmpty) return;
        await _pc!.setRemoteDescription(RTCSessionDescription(sdp, kind));
        _remoteReady = true;
        await _flushCandidates();
        if (kind == 'offer') {
          final answer = await _pc!.createAnswer();
          await _pc!.setLocalDescription(answer);
          _sdk.client.sendCallSignal(_callId!, {'kind': 'answer', 'sdp': answer.sdp});
        }
        _markActive();
      } else if (kind == 'candidate') {
        final text = payload['candidate']?.toString() ?? '';
        if (text.isEmpty) return;
        final index = payload['sdpMLineIndex'];
        final candidate = RTCIceCandidate(
          text,
          payload['sdpMid']?.toString(),
          index is int ? index : int.tryParse('$index'),
        );
        if (!_remoteReady) {
          _pendingCandidates.add(candidate);
        } else {
          await _pc!.addCandidate(candidate);
        }
      }
    } catch (e) {
      debugPrint('处理通话信令失败: $e');
    }
  }

  Future<void> _flushCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    final queued = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final candidate in queued) {
      await pc.addCandidate(candidate);
    }
  }

  void _markActive() {
    if (phase == CallPhase.active) return;
    phase = CallPhase.active;
    elapsedSeconds = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedSeconds += 1;
      notifyListeners();
    });
    notifyListeners();
  }

  void _fail(String reason) {
    _disposeMedia();
    phase = CallPhase.failed;
    errorText = reason;
    _callId = null;
    notifyListeners();
  }

  void dismissError() {
    if (phase == CallPhase.failed) _reset();
  }

  void _reset() {
    _disposeMedia();
    phase = CallPhase.idle;
    errorText = '';
    peerName = '';
    elapsedSeconds = 0;
    video = false;
    remoteVideoReady = false;
    _localPreviewReady = false;
    _callId = null;
    _caller = false;
    notifyListeners();
  }

  void _disposeMedia() {
    _ringtone.stop();
    _ticker?.cancel();
    _ticker = null;
    _pendingCandidates.clear();
    _remoteReady = false;
    remoteVideoReady = false;
    _localPreviewReady = false;
    final remote = _remoteStream;
    _remoteStream = null;
    remote?.dispose();
    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
      stream.dispose();
    }
    final pc = _pc;
    _pc = null;
    pc?.close();
    remoteRenderer.srcObject = null;
    if (_localRendererReady) {
      localRenderer.srcObject = null;
    }
  }

  void _safe(void Function() action) {
    try {
      action();
    } catch (e) {
      debugPrint('通话信令发送失败: $e');
    }
  }

  @override
  void dispose() {
    _signals.cancel();
    _disposeMedia();
    _ringtone.dispose();
    if (_rendererReady) {
      remoteRenderer.dispose();
    }
    if (_localRendererReady) {
      localRenderer.dispose();
    }
    super.dispose();
  }
}

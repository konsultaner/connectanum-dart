import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wamp_app/src/application/call_controller.dart';
import 'package:wamp_app/src/infrastructure/call_media.dart';
import 'package:wamp_app/src/infrastructure/flutter_webrtc_call_media.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

class CallOverlay extends StatelessWidget {
  const CallOverlay({super.key, required this.controller});

  final CallController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: switch (controller.phase) {
          CallUiPhase.incomingRinging => _IncomingCallCard(
            key: const ValueKey('incoming-call'),
            controller: controller,
          ),
          CallUiPhase.outgoingRinging ||
          CallUiPhase.connecting ||
          CallUiPhase.active ||
          CallUiPhase.ending => _ActiveCallSurface(
            key: const ValueKey('active-call'),
            controller: controller,
          ),
          CallUiPhase.ended ||
          CallUiPhase.answeredElsewhere ||
          CallUiPhase.failed => _CallResultCard(
            key: const ValueKey('call-result'),
            controller: controller,
          ),
          CallUiPhase.idle => const SizedBox.shrink(key: ValueKey('no-call')),
        },
      ),
    );
  }
}

class _IncomingCallCard extends StatelessWidget {
  const _IncomingCallCard({super.key, required this.controller});

  final CallController controller;

  @override
  Widget build(BuildContext context) {
    final video = controller.call?.media == CallMediaKind.video;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.58),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Card(
            margin: const EdgeInsets.all(24),
            elevation: 20,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.88, end: 1),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: CircleAvatar(
                      radius: 42,
                      child: Icon(
                        video ? Icons.videocam_rounded : Icons.call_rounded,
                        size: 38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '@${controller.peerUsername ?? 'unknown'}',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    video
                        ? 'Incoming encrypted video call'
                        : 'Incoming encrypted voice call',
                    textAlign: TextAlign.center,
                  ),
                  if (controller.errorMessage case final error?) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      key: const Key('call-error'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _RoundCallAction(
                        key: const Key('call-decline'),
                        label: 'Decline',
                        icon: Icons.call_end_rounded,
                        color: Theme.of(context).colorScheme.error,
                        onPressed: controller.busy ? null : controller.endCall,
                      ),
                      _RoundCallAction(
                        key: const Key('call-accept'),
                        label: 'Accept',
                        icon: video
                            ? Icons.videocam_rounded
                            : Icons.call_rounded,
                        color: const Color(0xFF16805B),
                        onPressed: controller.busy
                            ? null
                            : controller.acceptIncoming,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveCallSurface extends StatelessWidget {
  const _ActiveCallSurface({super.key, required this.controller});

  final CallController controller;

  @override
  Widget build(BuildContext context) {
    final media = controller.mediaSession;
    final video = controller.call?.media == CallMediaKind.video;
    final remoteVideo = video && media != null
        ? _videoView(media.remoteRenderer, mirror: false)
        : null;
    final localVideo = video && media != null
        ? _videoView(media.localRenderer, mirror: true)
        : null;
    return Material(
      color: const Color(0xFF071713),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (remoteVideo != null)
            remoteVideo
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.4),
                  radius: 1.15,
                  colors: [Color(0xFF24594A), Color(0xFF071713)],
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.48),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.72),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    '@${controller.peerUsername ?? 'unknown'}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _phaseLabel(controller.phase),
                    key: const Key('call-phase'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const Spacer(),
                  if (!video)
                    const CircleAvatar(
                      radius: 64,
                      backgroundColor: Color(0xFF2F6C5A),
                      child: Icon(
                        Icons.person_rounded,
                        size: 70,
                        color: Colors.white,
                      ),
                    ),
                  const Spacer(),
                  if (controller.errorMessage case final error?) ...[
                    Container(
                      key: const Key('call-error'),
                      margin: const EdgeInsets.only(bottom: 18),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.54),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 18,
                    runSpacing: 12,
                    children: [
                      _RoundCallAction(
                        key: const Key('call-mute'),
                        label: media?.muted ?? false ? 'Unmute' : 'Mute',
                        icon: media?.muted ?? false
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        color: Colors.white24,
                        onPressed: media == null || controller.busy
                            ? null
                            : () => controller.setMuted(!media.muted),
                      ),
                      if (video)
                        _RoundCallAction(
                          key: const Key('call-camera'),
                          label: media?.cameraEnabled ?? false
                              ? 'Camera off'
                              : 'Camera on',
                          icon: media?.cameraEnabled ?? false
                              ? Icons.videocam_rounded
                              : Icons.videocam_off_rounded,
                          color: Colors.white24,
                          onPressed: media == null || controller.busy
                              ? null
                              : () => controller.setCameraEnabled(
                                  !media.cameraEnabled,
                                ),
                        ),
                      if (media?.speakerRoutingSupported ?? false)
                        _RoundCallAction(
                          key: const Key('call-speaker'),
                          label: media!.speakerEnabled ? 'Earpiece' : 'Speaker',
                          icon: media.speakerEnabled
                              ? Icons.volume_up_rounded
                              : Icons.hearing_rounded,
                          color: Colors.white24,
                          onPressed: controller.busy
                              ? null
                              : () => controller.setSpeakerEnabled(
                                  !media.speakerEnabled,
                                ),
                        ),
                      _RoundCallAction(
                        key: const Key('call-end'),
                        label: 'End',
                        icon: Icons.call_end_rounded,
                        color: const Color(0xFFD83B43),
                        onPressed: controller.busy ? null : controller.endCall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (localVideo != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Container(
                  key: const Key('call-local-video'),
                  width: 126,
                  height: 176,
                  margin: const EdgeInsets.fromLTRB(0, 84, 18, 0),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: localVideo,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CallResultCard extends StatelessWidget {
  const _CallResultCard({super.key, required this.controller});

  final CallController controller;

  @override
  Widget build(BuildContext context) {
    final title = switch (controller.phase) {
      CallUiPhase.answeredElsewhere => 'Answered on another device',
      CallUiPhase.failed => 'Call unavailable',
      _ => 'Call ended',
    };
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.call_end_rounded, size: 42),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  if (controller.errorMessage case final error?) ...[
                    const SizedBox(height: 10),
                    Text(
                      error,
                      key: const Key('call-error'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    key: const Key('call-dismiss'),
                    onPressed: controller.dismiss,
                    child: const Text('Back to chats'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundCallAction extends StatelessWidget {
  const _RoundCallAction({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: color.withValues(alpha: 0.45),
            minimumSize: const Size.square(58),
          ),
          icon: Icon(icon, size: 27),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}

Widget? _videoView(CallVideoRendererHandle handle, {required bool mirror}) {
  if (handle is! FlutterWebRtcVideoRendererHandle) return null;
  return RTCVideoView(
    handle.renderer,
    mirror: mirror,
    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  );
}

String _phaseLabel(CallUiPhase phase) => switch (phase) {
  CallUiPhase.outgoingRinging => 'Calling securely...',
  CallUiPhase.connecting => 'Connecting media...',
  CallUiPhase.active => 'End-to-end encrypted signaling',
  CallUiPhase.ending => 'Ending call...',
  _ => '',
};

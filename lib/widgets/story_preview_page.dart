import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

class StoryPreviewPage extends StatefulWidget {
  final XFile file;
  final bool isVideo;
  final Function(XFile editFile, double startSeconds, double endSeconds) onShare;

  const StoryPreviewPage({
    super.key,
    required this.file,
    required this.isVideo,
    required this.onShare,
  });

  @override
  State<StoryPreviewPage> createState() => _StoryPreviewPageState();
}

class _StoryPreviewPageState extends State<StoryPreviewPage> {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;

  double _startValue = 0.0;
  double _endValue = 20.0; 
  double _maxDuration = 20.0;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _initVideo();
    }
  }

  void _initVideo() {
    _videoController = VideoPlayerController.file(File(widget.file.path))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            // 🌟 ໃຊ້ Milliseconds ແລ້ວຫານເພື່ອໃຫ້ໄດ້ທົດສະນິຍົມທີ່ລະອຽດແທ້ຈິງ ປ້ອງກັນບັກ Slider
            double maxDur = _videoController!.value.duration.inMilliseconds.toDouble() / 1000.0;
            if (maxDur <= 0.0) maxDur = 1.0; // ກັນ Error ຖ້າວິດີໂອຜິດປົກກະຕິ
            _maxDuration = maxDur;
            
            _endValue = _maxDuration > 20.0 ? 20.0 : _maxDuration;
            _isInitialized = true;
          });
          _videoController!.setLooping(true);
          _videoController!.play();
        }
      });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("ແກ້ໄຂສະຕໍຣີ່", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: widget.isVideo
                  ? (_isInitialized
                      ? AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          // child: VideoPlayer(_videoController!),
                        )
                      : const CircularProgressIndicator(color: Colors.white))
                  : Image.file(File(widget.file.path), fit: BoxFit.contain),
            ),
          ),

          Positioned(
            bottom: 40,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isVideo && _isInitialized) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12, width: 1),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "ເລີ່ມ: ${_startValue.toStringAsFixed(1)}ສ",
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            Text(
                              "ຄວາມຍາວ: ${(_endValue - _startValue).toStringAsFixed(1)} ວິນາທີ",
                              style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              "ຈົບ: ${_endValue.toStringAsFixed(1)}ສ",
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 🌟 ເອົາ divisions ອອກເພື່ອໃຫ້ເລື່ອນແຖບໄດ້ແບບອິດສະຫຼະ (Smooth Continuous Sliding)
                        RangeSlider(
                          values: RangeValues(_startValue, _endValue),
                          min: 0.0,
                          max: _maxDuration,
                          activeColor: Colors.tealAccent,
                          inactiveColor: Colors.white24,
                          labels: RangeLabels(
                            '${_startValue.toStringAsFixed(1)}s',
                            '${_endValue.toStringAsFixed(1)}s',
                          ),
                          onChanged: (RangeValues values) {
                            if (values.end - values.start <= 20.0) {
                              setState(() {
                                _startValue = values.start;
                                _endValue = values.end;
                              });
                              _videoController!.seekTo(Duration(milliseconds: (_startValue * 1000).toInt()));
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 4,
                  ),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text(
                    "ແແຊຣ໌ເລີຍ (Share Now)",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    Navigator.pop(context); 
                    widget.onShare(widget.file, _startValue, _endValue);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
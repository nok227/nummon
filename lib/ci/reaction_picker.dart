// ci/reaction_picker.dart
import 'package:flutter/material.dart';
import '../models/emoji_storage.dart';

class ReactionPicker extends StatefulWidget {
  final String postId;
  final String placeId;
  final LayerLink layerLink;
  final Function(String emoji) onEmojiSelected;
  final VoidCallback onDismiss;

  const ReactionPicker({
    super.key,
    required this.postId,
    required this.placeId,
    required this.layerLink,
    required this.onEmojiSelected,
    required this.onDismiss,
  });

  @override
  State<ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends State<ReactionPicker> {
  String? _hoveredEmoji;
  bool _isDismissed = false;

  @override
  Widget build(BuildContext context) {
    return CompositedTransformFollower(
      link: widget.layerLink,
      showWhenUnlinked: false,
      offset: const Offset(25, -75),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...EmojiStorage.getFirstFour().map((reaction) {
                final emoji = reaction['emoji']!;
                final isHovered = _hoveredEmoji == emoji;
                
                return MouseRegion(
                  onEnter: (_) {
                    if (mounted) {
                      setState(() => _hoveredEmoji = emoji);
                    }
                  },
                  onExit: (_) {
                    if (mounted) {
                      setState(() => _hoveredEmoji = null);
                    }
                  },
                  child: GestureDetector(
                    onTap: () {
                      if (_isDismissed || !mounted) return;
                      _isDismissed = true;
                      widget.onEmojiSelected(emoji);
                      Future.delayed(const Duration(milliseconds: 50), () {
                        if (mounted) {
                          widget.onDismiss();
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      transform: Matrix4.identity()
                        ..scale(isHovered ? 1.4 : 1.0)
                        ..translate(
                          isHovered ? 4.0 : 0.0,
                          isHovered ? -8.0 : 0.0,
                          0.0,
                        ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          emoji,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
              
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    if (_isDismissed || !mounted) return;
                    _isDismissed = true;
                    _openAllEmojis(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(left: 4, right: 2),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add,
                      size: 18,
                      color: Colors.grey,
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

  void _openAllEmojis(BuildContext context) {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '🗃️ ຄັງອີ່ໂມຈິ (${EmojiStorage.totalEmojis})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: GridView.builder(
                          controller: scrollController,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 6,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1,
                          ),
                          itemCount: EmojiStorage.allEmojis.length,
                          itemBuilder: (context, index) {
                            final item = EmojiStorage.allEmojis[index];
                            return GestureDetector(
                              onTap: () {
                                // 🛠️ แก้ไขเรียบร้อย: เอา 'if (!mounted) return;' ออก 
                                // เพื่อให้กดเลือกอีโมจิจากคลังด้านในส่งขึ้นระบบได้ทันที
                                widget.onEmojiSelected(item['emoji']!);
                                Navigator.pop(context);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey[200]!,
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      item['emoji']!,
                                      style: const TextStyle(fontSize: 28),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item['label']!,
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: Colors.grey[600],
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    ).whenComplete(() {
      widget.onDismiss();
    });
  }
}
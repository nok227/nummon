import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/place_model.dart';
import 'place_detail.dart';

class ExplorePage extends StatelessWidget {
  final ScrollController scrollController;
  final Function(Place) onAddToPlan;

  const ExplorePage(
      {super.key, required this.scrollController, required this.onAddToPlan});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ສຳຫຼວດສະຖານທີ່ທັງໝົດ',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance.collection('places').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.teal));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
                child: Text("ບໍ່ມີຂໍ້ມູນສະຖານທີ່ທ່ອງທ່ຽວໃນຕອນນີ້"));
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            controller: scrollController,
            itemCount: docs.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              final place = Place(
                id: doc.id,
                name: data['name'] ?? '',
                district: data['district'] ?? '',
                description: data['description'] ?? '',
                imageUrl: data['imageUrl'] ?? '',
                imageUrls: (data['imageUrls'] as List?)
                    ?.map((e) => e.toString())
                    .toList(),
                latitude:
                    double.tryParse(data['latitude'].toString()) ?? 0.0,
                longitude:
                    double.tryParse(data['longitude'].toString()) ?? 0.0,
              );

              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(8),
                  leading: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          place.imageUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const Icon(
                              Icons.broken_image,
                              size: 60),
                        ),
                      ),
                      // badge จำนวนรูป
                      if ((place.imageUrls?.length ?? 0) > 1)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '+${place.imageUrls!.length - 1}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 9),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(place.name,
                      style:
                          const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(place.district,
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PlaceDetailPage(
                            place: place, onAddToPlan: onAddToPlan),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
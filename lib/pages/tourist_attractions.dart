import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/place_model.dart';
import 'place_detail.dart';

class TouristAttractionsPage extends StatefulWidget {
  final ScrollController scrollController;
  final VoidCallback onMenuPressed;
  final Function(Place) onAddToPlan;

  const TouristAttractionsPage({
    super.key,
    required this.scrollController,
    required this.onMenuPressed,
    required this.onAddToPlan,
  });

  @override
  State<TouristAttractionsPage> createState() =>
      _TouristAttractionsPageState();
}

class _TouristAttractionsPageState extends State<TouristAttractionsPage> {
  String selectedDistrict = 'ທັງໝົດ';

  @override
  Widget build(BuildContext context) {
    final uniqueDistricts = [
      'ທັງໝົດ',
      'ເມືອງໄຊຍະບູລີ',
      'ເມືອງຂອບ',
      'ເມືອງຫົງສາ',
      'ເມືອງເງິນ',
      'ເມືອງຊຽງຮ່ອນ',
      'ເມືອງພຽງ',
      'ເມືອງປາກລາຍ',
      'ເມືອງແກ່ນທ້າວ',
      'ເມືອງບໍ່ແຕນ',
      'ເມືອງທົ່ງມີໄຊ',
      'ເມືອງໄຊສະຖານ',
    ].toSet().toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ເມືອງທັງໝົດ',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: widget.onMenuPressed,
        ),
      ),
      body: Column(
        children: [
          // District filter chips
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: uniqueDistricts.length,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemBuilder: (context, index) {
                final district = uniqueDistricts[index];
                final isSelected = selectedDistrict == district;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(district),
                    selected: isSelected,
                    selectedColor: Colors.teal,
                    labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87),
                    onSelected: (bool selected) {
                      if (selected) {
                        setState(() {
                          selectedDistrict = district;
                        });
                      }
                    },
                  ),
                );
              },
            ),
          ),

          // Place list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('places')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: Colors.teal));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                      child: Text("ບໍ່ມີຂໍ້ມູນສະຖານທີ່ທ່ອງທ່ຽວ"));
                }

                final docs = snapshot.data!.docs;

                final allPlaces = docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return Place(
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
                }).toList();

                final filteredPlaces = allPlaces.where((place) {
                  if (selectedDistrict == 'ທັງໝົດ') return true;
                  return place.district.trim() == selectedDistrict.trim();
                }).toList();

                if (filteredPlaces.isEmpty) {
                  return const Center(
                      child: Text("ບໍ່ມີຂໍ້ມູນສະຖານທີ່ໃນເມືອງນີ້"));
                }

                return ListView.builder(
                  controller: widget.scrollController,
                  itemCount: filteredPlaces.length,
                  itemBuilder: (context, index) {
                    final place = filteredPlaces[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      child: ListTile(
                        leading: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                place.imageUrl,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.broken_image, size: 60),
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
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(place.district),
                        trailing:
                            const Icon(Icons.arrow_forward_ios, size: 14),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PlaceDetailPage(
                                place: place,
                                onAddToPlan: widget.onAddToPlan,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
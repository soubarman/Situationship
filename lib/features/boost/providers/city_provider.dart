import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_state_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final citiesProvider = Provider<List<Map<String, String>>>((ref) {
  // Hardcoded for v1
  return [
    {'id': 'city_delhi', 'name': 'Delhi'},
    {'id': 'city_mumbai', 'name': 'Mumbai'},
    {'id': 'city_bangalore', 'name': 'Bangalore'},
    {'id': 'city_jorhat', 'name': 'Jorhat'},
    {'id': 'city_guwahati', 'name': 'Guwahati'},
  ];
});

final campusListProvider = Provider.family<List<Map<String, String>>, String>((ref, cityId) {
  // Hardcoded mapping for v1
  final map = {
    'city_delhi': [
      {'id': 'camp_du', 'name': 'Delhi University'},
      {'id': 'camp_jnu', 'name': 'JNU'},
    ],
    'city_mumbai': [
      {'id': 'camp_mu', 'name': 'Mumbai University'},
    ],
    'city_bangalore': [
      {'id': 'camp_iisc', 'name': 'IISc'},
    ],
    'city_jorhat': [
      {'id': 'camp_jist', 'name': 'JIST'},
      {'id': 'camp_jec', 'name': 'JEC'},
    ],
    'city_guwahati': [
      {'id': 'camp_gu', 'name': 'Gauhati University'},
      {'id': 'camp_cotton', 'name': 'Cotton University'},
    ],
  };
  return map[cityId] ?? [];
});

final changeCityProvider = Provider((ref) {
  return ChangeCityService(ref);
});

class ChangeCityService {
  final ProviderRef ref;
  ChangeCityService(this.ref);

  Future<void> updateCurrentCity(String cityId, {String? campusId, String? homeCityId}) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final updates = <String, dynamic>{
      'currentCityId': cityId,
    };
    if (campusId != null) updates['campusId'] = campusId;
    if (homeCityId != null) updates['homeCityId'] = homeCityId;

    await FirebaseFirestore.instance.collection('users').doc(user.id).update(updates);
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

String? _nonEmptyRouteId(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  return s;
}

Future<String?> resolveManagedRouteId() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;

  final firestore = FirebaseFirestore.instance;

  final rmSnap = await firestore.collection('route_manger').doc(uid).get();
  final fromRM = _nonEmptyRouteId(rmSnap.data()?['routeId']);
  if (fromRM != null) return fromRM;

  final userSnap = await firestore.collection('users').doc(uid).get();
  return _nonEmptyRouteId(userSnap.data()?['routeId']);
}

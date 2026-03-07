// import 'package:hive/hive.dart';

// class MenuLocalService {
//   static const String boxName = "menuBox";
//   static const String key = "menuData";

//   static Future<void> saveMenu(List data) async {
//     final box = Hive.box(boxName);
//     await box.put(key, data);
//   }

//   static List getMenu() {
//     final box = Hive.box(boxName);
//     return box.get(key, defaultValue: []);
//   }
// }

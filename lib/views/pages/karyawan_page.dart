import 'package:flutter/material.dart';
import 'package:pos_panglima_app/utils/convert.dart';

class KaryawanPage extends StatefulWidget {
  const KaryawanPage({super.key});

  @override
  State<KaryawanPage> createState() => _KaryawanPageState();
}

class _KaryawanPageState extends State<KaryawanPage> {
  int idKaryawan = 1;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: Container(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.black26)),
            ),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.0),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.black26)),
                  ),
                  child: TextField(
                    // controller: searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      icon: Icon(Icons.search),
                      hintText: 'Cari Karyawan...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 6,
                      ),
                    ),
                  ),
                ),
                Column(
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          idKaryawan = 1;
                        });
                      },
                      child: Container(
                        color: Colors.white,
                        padding: EdgeInsets.all(14.0),
                        child: Row(
                          spacing: 16.0,
                          children: [
                            Container(
                              height: 80.0,
                              width: 80.0,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    secondColor('Amanda'),
                                    baseColor('Amanda'),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.all(
                                  Radius.circular(20.0),
                                ),
                              ),
                              padding: EdgeInsets.all(18.0),
                              child: Text(
                                getInitials('Amanda'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 25.0,
                                ),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Amanda',
                                  style: TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'Roti Gembung Panglima',
                                  style: TextStyle(fontSize: 16.0),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          idKaryawan = 1;
                        });
                      },
                      child: Container(
                        color: Colors.amber[100],
                        padding: EdgeInsets.all(14.0),
                        child: Row(
                          spacing: 16.0,
                          children: [
                            Container(
                              height: 80.0,
                              width: 80.0,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    secondColor('Ria Ricis'),
                                    baseColor('Ria Ricis'),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.all(
                                  Radius.circular(20.0),
                                ),
                              ),
                              padding: EdgeInsets.all(18.0),
                              child: Text(
                                getInitials('Ria Ricis'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 25.0,
                                ),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ria Ricis',
                                  style: TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'Roti Gembung Panglima',
                                  style: TextStyle(fontSize: 16.0),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                color: Colors.grey[200],
                padding: EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      spacing: 20.0,
                      children: [
                        Container(
                          height: 80.0,
                          width: 80.0,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                secondColor('Ria Ricis'),
                                baseColor('Ria Ricis'),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.all(
                              Radius.circular(20.0),
                            ),
                          ),
                          padding: EdgeInsets.all(18.0),
                          child: Text(
                            getInitials('Ria Ricis'),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 25.0,
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ria Ricis',
                              style: TextStyle(
                                fontSize: 18.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Roti Gembung Panglima',
                              style: TextStyle(fontSize: 16.0),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(spacing: 20.0, children: [Icon(Icons.more_vert)]),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  spacing: 20.0,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10.0,
                      children: [
                        Text(
                          'Shift Berjalan',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18.0,
                          ),
                        ),
                        Text('Mulai Kamis, 09 Jan 2025, 06:00'),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10.0,
                      children: [
                        Text(
                          'Shift Berakhir',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18.0,
                          ),
                        ),
                        Text('Mulai Kamis, 09 Jan 2025, 06:00'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

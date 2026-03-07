import 'package:flutter/material.dart';
import 'package:pos_panglima_app/utils/convert.dart';

class PelangganPage extends StatefulWidget {
  const PelangganPage({super.key});

  @override
  State<PelangganPage> createState() => _PelangganPageState();
}

class _PelangganPageState extends State<PelangganPage> {
  int idPelanggan = 1;

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
                      hintText: 'Cari Pelanggan...',
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
                          idPelanggan = 1;
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
                                    secondColor('Abah Budi'),
                                    baseColor('Abah Budi'),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.all(
                                  Radius.circular(50.0),
                                ),
                              ),
                              padding: EdgeInsets.all(18.0),
                              child: Text(
                                getInitials('Abah Budi'),
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
                                  'Abah Budi',
                                  style: TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '082233445566',
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
                          idPelanggan = 1;
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
                                    secondColor('Mamat Abdur'),
                                    baseColor('Mamat Abdur'),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.all(
                                  Radius.circular(50.0),
                                ),
                              ),
                              padding: EdgeInsets.all(18.0),
                              child: Text(
                                getInitials('Mamat Abdur'),
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
                                  'Mamat Abdur',
                                  style: TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '082233445566',
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
                                secondColor('Mamat Abdur'),
                                baseColor('Mamat Abdur'),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.all(
                              Radius.circular(50.0),
                            ),
                          ),
                          padding: EdgeInsets.all(18.0),
                          child: Text(
                            getInitials('Mamat Abdur'),
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
                              'Mamat Abdur',
                              style: TextStyle(
                                fontSize: 18.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '08223345566',
                              style: TextStyle(fontSize: 16.0),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      spacing: 20.0,
                      children: [
                        Icon(Icons.call),
                        Icon(Icons.mail),
                        Icon(Icons.more_vert),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  spacing: 10.0,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Member Kategori',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      spacing: 10.0,
                      children: [
                        Icon(Icons.discount),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [Text('Kategori Diskon'), Text('Umum')],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(),
              Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  spacing: 10.0,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catatan',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      spacing: 10.0,
                      children: [
                        Icon(Icons.article),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [Text('Catatan Pelanggan'), Text('-')],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(),
            ],
          ),
        ),
      ],
    );
  }
}

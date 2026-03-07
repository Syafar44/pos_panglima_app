import 'package:flutter/material.dart';
import 'package:pos_panglima_app/utils/convert.dart';

class OpenBillPage extends StatelessWidget {
  const OpenBillPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20.0),
      child: Expanded(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Card(
                color: Colors.white,
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black26),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            spacing: 20.0,
                            children: [
                              Row(
                                spacing: 10.0,
                                children: [
                                  Icon(Icons.article),
                                  Text('OPOP134 - Tanpa Nama'),
                                ],  
                              ),
                              Row(
                                spacing: 10.0,
                                children: [
                                  Icon(Icons.group),
                                  Text('Tanpa Pelanggan'),
                                ],
                              ),
                              Row(
                                spacing: 10.0,
                                children: [Icon(Icons.person), Text('Kasir')],
                              ),
                              Row(
                                spacing: 10.0,
                                children: [
                                  Icon(Icons.calendar_month),
                                  Text('2023-10-10, 12:34'),
                                ],
                              ),
                            ],
                          ),
                          Icon(Icons.more_vert),
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(color: Colors.black26),
                              ),
                            ),
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              spacing: 20.0,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Takeaway (12)',
                                  style: TextStyle(fontSize: 16.0),
                                ),
                                Column(
                                  spacing: 10.0,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          spacing: 20.0,
                                          children: [
                                            Container(
                                              width: 80,
                                              height: 80,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    secondColor(
                                                      'Gembung Coklat',
                                                    ),
                                                    baseColor('Gembung Coklat'),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                'GA',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 35,
                                                ),
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Gembung Coklat',
                                                  style: TextStyle(
                                                    fontSize: 16.0,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text('9 PCS'),
                                              ],
                                            ),
                                          ],
                                        ),
                                        Text(
                                          convertIDR(30000),
                                          style: TextStyle(
                                            fontSize: 16.0,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          spacing: 20.0,
                                          children: [
                                            Container(
                                              width: 80,
                                              height: 80,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    secondColor(
                                                      'Gembung Coklat',
                                                    ),
                                                    baseColor('Gembung Coklat'),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                'GA',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 35,
                                                ),
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Gembung Coklat',
                                                  style: TextStyle(
                                                    fontSize: 16.0,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text('9 PCS'),
                                              ],
                                            ),
                                          ],
                                        ),
                                        Text(
                                          convertIDR(30000),
                                          style: TextStyle(
                                            fontSize: 16.0,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Subtotal',
                                      style: TextStyle(
                                        fontSize: 18.0,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      convertIDR(999912),
                                      style: TextStyle(
                                        fontSize: 18.0,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Subtotal',
                                      style: TextStyle(
                                        fontSize: 16.0,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      convertIDR(20017),
                                      style: TextStyle(
                                        fontSize: 16.0,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Divider(),
                              Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Total Tagihan',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          convertIDR(60000),
                                          style: TextStyle(
                                            fontSize: 16.0,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    ElevatedButton(
                                      onPressed: () {},
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.amber,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        'Bayar',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

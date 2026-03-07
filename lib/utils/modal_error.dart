import 'package:flutter/material.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';

class ModalError extends StatefulWidget {
  const ModalError({super.key});

  @override
  State<ModalError> createState() => _ModalErrorState();
}

class _ModalErrorState extends State<ModalError> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: EdgeInsets.all(50),
        width: 500.0,
        height: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 100,
                color: Colors.orange,
              ),
              Text(
                'Terjadi Kesalahan',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Jika Kesalahan Ini terjadi berulang silahkan Hubungi SVP atau Departmen IT',
                style: const TextStyle(
                  fontSize: 16,
                  overflow: TextOverflow.fade,
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amber,
                    ),
                    onPressed: () {
                      selectedPageNotifier.value = 0;
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (context) {
                            return WidgetTree();
                          },
                        ),
                        (route) => false,
                      );
                    },
                    child: Text(
                      '   OK, Tutup   ',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

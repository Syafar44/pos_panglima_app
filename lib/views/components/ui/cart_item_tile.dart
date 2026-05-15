import 'package:flutter/material.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/utils/convert.dart';

class CartItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onDelete, onIncrease, onDecrease, onUpdate;
  final bool isBusy;

  const CartItemTile({
    super.key,
    required this.item,
    required this.onDelete,
    required this.onIncrease,
    required this.onDecrease,
    required this.onUpdate,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 16, left: 16, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: item['price'] != 0 ? onUpdate : null,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // 1. Info Produk & Detail (Kiri)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['pos_menus_name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),

                      Row(
                        spacing: 5,
                        children: [
                          Text(
                            convertIDR(item['total']),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          // if ((item['discount'] ?? 0) +
                          //         (item['discount_val'] ?? 0) >
                          //     0)
                          //   Text(
                          //     '( - ${convertIDR(item['discount'])} )',
                          //     style: const TextStyle(
                          //       color: Colors.redAccent,
                          //       fontWeight: FontWeight.w800,
                          //       fontSize: 13,
                          //     ),
                          //   ),
                          if ((item['discount'] ?? 0) > 0 ||
                              (item['discount_val'] ?? 0) > 0)
                            Text(
                              (item['discount_val'] ?? 0) > 0
                                  ? '( - ${item['discount_val']}% )'
                                  : '( - ${convertIDR(item['discount'])} )',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),

                      // Kondisi jika ada Add-ons/Catatan (Lebih rapi dengan Chips)
                      if (item['pos_cart_props'] != null &&
                          (item['pos_cart_props'] as List).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Wrap(
                            spacing: 4,
                            children: (item['pos_cart_props'] as List)
                                .map<Widget>((p) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    margin: const EdgeInsets.only(bottom: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "+ ${p['quantity']} ${p['pos_menus_name']}",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  );
                                })
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // 2. Aksi & Quantity Selector (Kanan)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // Tombol Hapus (Kecil di pojok)
                    GestureDetector(
                      onTap: isBusy ? null : onDelete,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isBusy ? Colors.grey[100] : Colors.red[50],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: isBusy ? Colors.grey[400] : Colors.redAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Stepper Modern
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          _buildStepButton(Icons.remove, isBusy ? () {} : onDecrease, disabled: isBusy),
                          Container(
                            constraints: const BoxConstraints(minWidth: 40),
                            alignment: Alignment.center,
                            child: isBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primary,
                                    ),
                                  )
                                : Text(
                                    "${item['quantity']}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                          _buildStepButton(
                            Icons.add,
                            isBusy ? () {} : onIncrease,
                            isPrimary: true,
                            disabled: isBusy,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepButton(
    IconData icon,
    VoidCallback onTap, {
    bool isPrimary = false,
    bool disabled = false,
  }) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: disabled
              ? Colors.grey[300]
              : isPrimary
                  ? AppColors.primary
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          size: 18,
          color: disabled
              ? Colors.grey[500]
              : isPrimary
                  ? Colors.white
                  : Colors.black87,
        ),
      ),
    );
  }
}

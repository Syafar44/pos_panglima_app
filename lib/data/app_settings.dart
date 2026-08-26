/// Pengaturan debug/pengembang — SATU tempat.
///
/// Ubah nilai di bawah langsung di kode (lalu hot restart). Sengaja tanpa UI
/// supaya tidak bisa diubah dari aplikasi yang sudah dirilis.
class AppSettings {
  AppSettings._();

  /// Saklar fitur transaksi offline.
  /// true  = transaksi offline DIIZINKAN (perilaku normal).
  /// false = transaksi offline DIMATIKAN → saat offline user tidak bisa
  ///         menambah item ke keranjang maupun membayar.
  static bool offlineMode = false;

  /// true  = izinkan rotasi portrait.
  /// false = terkunci landscape.
  static bool portraitMode = false;
}

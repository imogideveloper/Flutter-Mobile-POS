import '../../../core/database/app_database.dart';
import 'produk.dart';

extension ProdukRowMapper on ProdukRow {
  Produk toDomain() => Produk(
        id: id,
        tokoId: tokoId,
        kategoriId: kategoriId,
        satuanId: satuanId,
        sku: sku,
        barcode: barcode,
        nama: nama,
        deskripsi: deskripsi,
        gambarUrl: gambarUrl,
        tipe: tipe,
        lacakStok: lacakStok,
        punyaVarian: punyaVarian,
        pakaiResep: pakaiResep,
        hpp: hpp,
        hargaJual: hargaJual,
        dijual: dijual,
        aktif: aktif,
      );
}

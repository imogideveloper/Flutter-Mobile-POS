import '../data/local/stok_dao.dart';
import 'mutasi_item.dart';
import 'stok_item.dart';

extension StokDenganProdukMapper on StokDenganProduk {
  StokItem toDomain() => StokItem(
        id: stok.id,
        outletId: stok.outletId,
        produkId: stok.produkId,
        varianId: stok.varianId,
        produkNama: produk.nama,
        jumlah: stok.jumlah,
        batasMinimum: stok.batasMinimum,
        hppRataRata: stok.hppRataRata,
      );
}

extension MutasiDenganProdukMapper on MutasiDenganProduk {
  MutasiItem toDomain() => MutasiItem(
        id: mutasi.id,
        produkNama: produk.nama,
        jenis: mutasi.jenis,
        qty: mutasi.qty,
        catatan: mutasi.catatan,
        createdAt: mutasi.createdAt,
      );
}

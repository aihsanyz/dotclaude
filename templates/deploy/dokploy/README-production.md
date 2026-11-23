## Production (Dokploy)
Production ayrı bir sunucuda Dokploy ile çalışır. Proje türü **Compose**, dosya `compose.prod.yaml`.

İlk kurulum:
1. Dokploy'da **Create → Compose** seç. Kaynak bu repo, compose yolu `compose.prod.yaml`.
2. **Environment** sekmesinde `.env.production.example`'daki anahtarları tanımla. Gizli değerler (parolalar) burada girilir; repoya yazılmaz.
3. **Domains** sekmesinde domain ekle: servis `{{APP_SERVICE}}`, container portu `{{APP_PORT}}`, HTTPS açık. Uygulama host'a port yayınlamaz (`expose`); dış erişim yalnızca bu domain üzerinden gelir. Domain tanımlanmazsa deploy başarılı görünür ama uygulamaya ulaşılamaz.
4. **Deploy**. Sıra kendiliğinden işler: veritabanı sağlıklı olunca `backup` döküm alır, `migrate` migration'ları (ve varsa `postdeploy` işlerini) çalıştırır, uygulama yalnızca bunlar başarılıysa başlar.

Sürüm güncelleme:
1. `releases/vX.Y.Z.md` dosyasındaki **Upgrade Notes**'u oku. Yeni ortam değişkeni varsa önce Environment sekmesine ekle.
2. **General** sekmesinde kaynak referansını `vX.Y.Z` etiketi yap.
3. **Deploy**. Migration'lar `migrate` servisiyle kendiliğinden çalışır.

Geri dönüş:
- **Yalnızca kod:** Kaynak referansını önceki etikete çekip tekrar deploy et. Migration'lar geriye uyumlu yazıldığı için eski sürüm yeni şemayla çalışır. Çoğu durumda bu yeterlidir.
- **Veriyle birlikte:** Sıra önemlidir, çünkü her deploy `backup` servisini çalıştırıp yeni bir döküm alır.
  1. Geri dönüş deploy'undan **önce**, `backups` volume'unda sorunlu güncellemenin aldığı dökümü belirle: adı güncelleme deploy'unun saatini taşıyan `pre-migrate-<tarih-saat>.sql`. Ondan sonra alınmış dökümler sorunlu sürümün verisini içerir.
  2. Uygulama servisinin container'ını durdur (sunucuda `docker stop <container>`); `db` ayakta kalmalı.
  3. Veritabanını boşaltıp (drop/create) bu dökümü `psql` ile yükle.
  4. Önceki etikete dön ve deploy et.
  - Güncellemeden sonra yazılan veri kaybolur.

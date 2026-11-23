---
paths:
  - "**/migrations/**"
  - "**/migrate/**"
  - "**/prisma/schema.prisma"
  - "**/db/schema.*"
  - "**/*seed*"
  - "**/seeders/**"
---

# Migration ve seed kuralları

- **Merge edilmiş migration düzenlenmez.** `origin/main`'de bulunan bir migration'ın düzeltmesi yeni bir migration'la yapılır. Henüz merge edilmemiş branch'in kendi migration'ları düzenlenebilir.
- **Geriye uyumluluk:**
  - Production'da migration çalışırken kısa bir süre eski uygulama yeni şemayla çalışabilir. Bu yüzden değişiklik iki adımda yapılır: önce genişlet (yeni kolon/tablo eklenir, eski yerinde kalır), sonra sonraki sürümde daralt (eskisi kaldırılır).
  - Dolu bir tabloya varsayılan değeri olmayan `NOT NULL` kolon ekleme.
- **Seed:**
  - Her tabloda birkaç gerçekçi örnek satır bulunur.
  - Tekrar çalıştırıldığında hata vermez.
  - Yeni tablo eklendiğinde aynı branch'te seed'e örnek satır eklenir. CI'daki yükseltme provası veriye bağlı migration hatalarını ancak bu sayede yakalar.
- **Komutlar:** Migration, seed veya migration dizini değişirse `AGENTS.md`'deki `## Komutlar` aynı commit'te güncellenir.
- **Yarım kalan migration:** MySQL'de yarım kalmış bir migration için nasıl ilerleneceğini kullanıcıya sor.

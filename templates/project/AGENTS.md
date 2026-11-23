# {{PROJECT}}

{{DESCRIPTION}}

## Stack
- Henüz belirlenmedi.

## Komutlar
<!-- devenv.sh ve CI bu bölümü okur. Biçim: "- anahtar: `değer`". Anahtarlar: service, migrate, postdeploy, lint, test, seed, migrations. Komutlar container içinde çalışır: docker compose run --rm <service> sh -c "<komut>". -->

## İlkeler
<!-- Projeye özgü kurallar: mimari kararlar, isimlendirme, yasaklar. Kısa tut. -->

## Çalışma düzeni
Bu bölüm Claude ve Codex için ortaktır.
- **İletişim:** Kullanıcıyla Türkçe konuşulur. Kod, yorumlar, commit mesajları ve PR'lar İngilizce olur.
- **Branch:**
  - Kalıcı branch yalnızca `main`'dir; doğrudan `main`'e commit veya push yapılmaz.
  - Her iş `origin/main`'den açılan bir worktree branch'inde (`<tür>/<kısa-ad>`) yapılır ve PR + squash merge ile `main`'e girer.
  - Commit ve PR başlıkları Conventional Commits biçiminde, 1-2 maddelik açıklamayla yazılır.
- **Docker:**
  - Tüm proje komutları container içinde çalışır; host'a hiçbir şey kurulmaz.
  - `compose.dev.yaml` development içindir, `compose.prod.yaml` production içindir. Hangisinin kullanılacağını `.env`'deki `COMPOSE_FILE` seçer.
- **Kanıt:** "Geçti" veya "çalışıyor" denmeden önce ilgili komut çalıştırılır. Arayüz değişiklikleri tarayıcıda kontrol edilir.
- **Migration:** Merge edilmiş bir migration düzenlenmez; değişiklik yeni bir migration'la yapılır. Migration'lar geriye uyumlu yazılır (önce genişlet, sonra daralt). Seed gerçekçi olur ve tekrar çalıştırılabilir.
- **Dokümanlar:** `docs/` sunucuda servis edilmez. Spec'ler `docs/specs/`, planlar `docs/plans/`, raporlar `docs/reports/<agent>/` altında durur.
- **CI:** `lint`, `test`, `rehearse` ve `scan` job'larının hepsi geçmeden merge yapılmaz. Kontroller zayıflatılmaz.

---
paths:
  - "**/.github/workflows/**"
  - "**/.github/actions/**"
---

# CI kuralları (GitHub Actions)

- **Job'lar:** CI, PR'larda ve `main`'de çalışır. Job adları sabittir: `lint`, `test`, `rehearse`, `build`, `scan`. `/land` bu adları bekler.
- **Prova:**
  - `rehearse` temiz veritabanında migration + seed çalıştırır.
  - Ardından **yükseltme provası** yapar: son `v*` etiketinin şeması ve seed'i üzerine HEAD migration'larını uygular.
  - İkisi de `compose.prod.yaml`'daki `migrate` servisini kullanır. Böylece prova, production'da çalışacak adımın aynısı olur.
- **Kontrolleri zayıflatma:** Bir kontrolü geçirmek için job'u, adımı veya kuralı kapatma, `continue-on-error` ekleme, eşiği düşürme. Kök nedeni düzelt. Zorunluysa kullanıcıya sor.
- **Action'lar:**
  - Tam commit SHA'sıyla sabitlenir, yanına sürüm yorumu yazılır.
  - `permissions:` en dar haliyle tanımlanır; varsayılan `contents: read`.
- **Gizli bilgi:** Gizli değerler yalnızca `secrets.*` ile gelir. Log'a yazdırılmaz, `set -x` kullanılmaz.
- **Taramalar:** `gitleaks` ve `trivy` sabit sürümlü image'larla çalışır. Trivy yalnızca düzeltmesi olan orta ve üstü bulguları raporlar.

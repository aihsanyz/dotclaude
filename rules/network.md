---
paths:
  - "**/vite.config.*"
  - "**/next.config.*"
  - "**/nuxt.config.*"
  - "**/astro.config.*"
  - "**/svelte.config.*"
  - "**/angular.json"
  - "**/package.json"
  - "**/settings.py"
  - "**/config/app.php"
---

# Ağ erişimi kuralları

- **Dinleme adresi:** Container içindeki dev server `0.0.0.0` üzerinde dinler (ör. `vite --host 0.0.0.0`, `next dev -H 0.0.0.0`).
- **Host kontrolü:**
  - Dev server host kontrolüne makinenin Tailscale DNS adı ve yerel ağ IP aralıkları eklenir (`local.md`).
  - Vite: `server.allowedHosts`.
  - Next.js: `allowedDevOrigins`. Eksikse sayfa açılır ama tarayıcıda dev kaynakları engellenir ve etkileşim çalışmaz.
  - Django: `ALLOWED_HOSTS`.
- **Portlar:** Portlar `.env` değişkeniyle verilir. Development ortamı varsayılan portları, worktree'ler 4100–4999 aralığını kullanır.
- **Doğrulama:** Ortamı ayağa kaldırdıktan sonra `local.md`'deki yerel ağ ve Tailscale adreslerini `curl` ile, arayüzü T3 tarayıcısıyla doğrula.

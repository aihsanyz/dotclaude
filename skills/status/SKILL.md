---
name: status
description: Bu makinedeki projelerin, worktree'lerin, compose ortamlarının ve PR'ların salt okunur özetini çıkarır. Bayat ortamları, sahipsiz compose projelerini ve merge edilmiş ama temizlenmemiş işleri işaretler, yapılabilecekleri önerir. Kullanıcı /status, "ne açık", "neler çalışıyor" dediğinde kullan.
argument-hint: "[repo yolu...]"
---

# /status

Bu skill hiçbir şeyi değiştirmez; yalnızca durumu gösterir ve öneri sunar.

1. `~/.claude/scripts/status.sh [repo...]` çalıştır (Bash `timeout: 300000`).
2. Çıktıyı Türkçe ve kısa bir tabloyla özetle: proje, worktree/branch, ortam, PR ve işaretler. Bir kayıtta işaret varsa:
   - **`PR-MERGED` veya `PR-CLOSED`:** İş bitmiş ama temizlenmemiş. O worktree'de `/land` (merge edildiyse temizlik adımlarından devam eder) veya thread'in arşivlenmesini öner.
   - **`STALE`:** Ortam günlerdir açık ama işte commit yok. Ortamı veriyi silmeden durdurmayı öner: `devenv.sh stop <worktree>`.
   - **`ORPHAN`:** Checkout'u olmayan bir compose projesi çalışıyor. `docker compose -p <ad> down` ile kaldırılmasını öner. Volume'lar dahil silinecekse kullanıcıya sor.
   - **Ana klasör `main`'de değil veya `origin/main`'in gerisinde:** `/land` sonrası eşitleme yapılmamış olabilir. Eşitlemeyi öner.
   - **Bellek 700 MB'ın altında:** Durdurulabilecek ortamları say.
3. Önerileri uygulamak için kullanıcının onayını bekle; uygulama ayrı bir istektir.

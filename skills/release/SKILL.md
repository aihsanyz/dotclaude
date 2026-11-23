---
name: release
description: main'den yeni bir sürüm çıkarır. Son etiketten bu yana değişiklikleri toplar, semver önerir, security agent'ını sürüm aralığında çalıştırır, releases/vX.Y.Z.md notunu hazırlayıp onay ister, notu PR ile main'e alır, vX.Y.Z etiketini atar ve Dokploy'da production güncellemesi için yükseltme notlarını verir. Yalnızca kullanıcı sürüm çıkarmak istediğinde (/release) kullan.
disable-model-invocation: true
argument-hint: "[vX.Y.Z]"
---

# /release

Sürüm yalnızca kullanıcı istediğinde çıkar. Kullanıcının sürüm notunu onaylaması bu sürümün tüm adımlarının onayıdır: notun PR'ı, merge ve etiketin push'u. Adım adım ayrıca onay isteme. Production'ı kullanıcı Dokploy'da elle günceller.

Genel kurallar:
- Git komutlarında `git -C <mutlak yol>` kullan.
- Bir adım başarısız olursa dur ve bildir.

## 1. Hazırlık
- Ana repoda `~/.claude/scripts/release-info.sh` çalıştır. Çıkış kodları:
  - `1`: "Yayınlanacak değişiklik yok" de ve dur.
  - `2`: engelleri bildir ve dur.
- **Sürüm numarası:** Kullanıcı bir sürüm verdiyse onu kullan, yoksa script'in önerisini. Kendin hesaplama.
- **Release worktree'si:** `git -C <ana repo> worktree add --no-track -b release/vX.Y.Z <ana repo>.worktrees/release-vX.Y.Z origin/main`.

## 2. Denetim ve not
- **Security agent'ı:** Release worktree'sinde, `<son etiket>..HEAD` kapsamıyla ve `full` modda çalıştır. İlk sürümde kapsam `HEAD`'dir.
  - Sonuç "Engellendi" ise engelleri ve yapılması gerekenleri kısa maddelerle özetle ve dur. Kendiliğinden düzeltme. Worktree'yi bırak ve yolunu söyle.
- **CI:** `origin/main`'in son commit'i için CI yeşil olmalı (`gh run list --branch main -L1`). Değilse dur.
- **Sürüm notu:** `releases/vX.Y.Z.md` içeriğini commit'lerden İngilizce olarak hazırla. Varsa önceki sürüm notlarının biçimini koru. Boş başlıkları yazma.

```
# vX.Y.Z (YYYY-MM-DD)

## Breaking Changes
- <change> — <what to do>
## Features
## Fixes
## Other
## Upgrade Notes
- <new env variables (with Dokploy action), migrations, compose or port changes>
```

- **Yükseltme notları:**
  - `changed_upgrade_files` listesindeki dosyaların diff'ine bak.
  - Yeni `.env.production.example` anahtarlarını "Dokploy'da tanımla" diye yaz.
  - Yeni migration'ları yaz.
- **Onay iste:** Sürüm numarasını, gerekçeyi, security sonucunu ve notu `send_to_user` ile göster. Onay iste ve turu bitir.

## 3. Onaydan sonra
- Notu yaz. Kullanıcı düzeltme istediyse uygula.
- Not ve rapor dosyalarını tek commit'te ekle: `releases/vX.Y.Z.md` ve `docs/reports/security/` altındaki yeni raporlar, mesajı `docs(release): add vX.Y.Z notes`.
- **Push ve PR:**
  - `git push -u origin release/vX.Y.Z`.
  - PR'ı aç: başlık `docs(release): vX.Y.Z`, gövde 1-3 madde öne çıkanlar ve `See releases/vX.Y.Z.md`.
  - `link_pull_request` ve `watch_pull_request` kullan.
  - Bu PR yalnızca doküman içerdiği için reviewer çalışmaz. CI çalışır ve yükseltme provası bu PR'da da yapılır.
- **Merge:** CI yeşilse `/land`'in 3. adımındaki yöntemle squash merge et. CI bekliyorsa turu bitir; kullanıcı `/release` dediğinde bu adımdan devam et.

## 4. Etiket
- `git -C <ana repo> fetch origin --prune`.
- Merge commit'i `origin/main`'de olmalı.
- Etiketi oluştur ve gönder:
  - `git -C <ana repo> tag -a vX.Y.Z <merge commit> -m "vX.Y.Z"`
  - `git -C <ana repo> push origin vX.Y.Z`

## 5. Ana klasör ve temizlik
- **Ana klasör:** `merge --ff-only origin/main`, ardından `~/.claude/scripts/devenv.sh apply <ana repo>` (Bash `timeout: 600000`).
- **Release worktree'si:** `git worktree remove <yol>`; `--force` kullanma.
- **Release branch'i:** Yerelde ve uzakta sil. Uzakta yoksa hatayı yok say.

## 6. Bildir
Kısa özet:
- sürüm ve etiket
- PR
- security rapor yolu
- **Production'da yapılacaklar:** `AGENTS.md` → `## Deploy` hedefine göre, `README.md`'nin Production bölümündeki "Sürüm güncelleme" adımları:
  - Dokploy: Environment'a yeni değişkenler, kaynak referansı `vX.Y.Z`, Deploy.
  - Portainer: stack'e yeni değişkenler, referans `refs/tags/vX.Y.Z`, Pull and redeploy.
  - Hedef `belirlenmedi` ise bunu belirt ve hedefin seçilmesini öner.
  - Her iki hedefte migration'lar deploy sırasında `migrate` servisiyle çalışır.
- yapılan temizlik

---
name: release
description: origin/development'tan main'e yeni bir sürüm çıkarır; release worktree'sinde auditor ve releaser'ı çalıştırır, kullanıcı onayından sonra sürüm notunu development'a alır, development'ı main'e merge commit ile birleştirir ve vX.Y.Z etiketini atar. Kullanıcı sürüm çıkarmak istediğinde (/release) kullan.
---

# /release

Sürüm yalnızca kullanıcı istediğinde çıkar. Kullanıcının releaser raporunu onaylaması `development` → `main` merge onayıdır. Bu onay sürümün tüm adımlarını kapsar (release branch push'u, `development`'a PR ve merge, `main`'e PR ve merge, tag push); adım adım ayrıca onay isteme. Bir adım başarısız olursa dur ve bildir.

Tüm git komutlarında `git -C <mutlak yol>` kullan; shell değişkeniyle yol kurma.

## 1. Hazırlık
- Ana repoda `git fetch origin --tags --prune`; yerel `main` ve `development`'ı eşitle (`start-task` skill'inin 3. adımındaki yöntem).
- `~/.claude/scripts/release-info.sh` çıkış kodu 1 ise "Yayınlanacak değişiklik yok" de ve dur.
- Release worktree'si aç: `git -C <ana repo> worktree add --detach <ana repo dizini>.worktrees/release-<YYYYMMDD> origin/development`.

## 2. Denetim ve hazırlık raporu
- `auditor`'ü release worktree'sinde `origin/main..HEAD` kapsamıyla çalıştır.
- Ardından `releaser`'ı aynı worktree'de çalıştır.
- Releaser raporunu (sürüm numarası, gerekçe, `releases/vX.Y.Z.md` içeriği, release PR metni) `send_to_user` ile kullanıcıya göster ve onay iste; turu bitir.
- Rapor "Engellendi" ise engelleri bildir ve dur. Worktree'yi raporlar incelenebilsin diye bırak ve yolunu söyle.

## 3. Onaydan sonra: sürüm notu development'a
- `git -C <release worktree> switch -c release/vX.Y.Z`
- `releases/vX.Y.Z.md` dosyasını releaser raporundaki içerikle oluştur. Kullanıcı düzeltme istediyse uygula.
- `releases/vX.Y.Z.md` ve `docs/reports/` altındaki yeni raporları `docs(release): add vX.Y.Z notes` ile commit'le.
- `push` skill'inin adımlarını uygula (reviewer kapısı dahil).
- `development`'a PR: başlık `docs(release): add vX.Y.Z notes`, squash merge. Auditor kapısı bu branch için uygulanmaz, çünkü 2. adımda denetlendi.
- PR'ı `merge` skill'inin 3. adımındaki yöntemle aç ve merge et.
- Merge sonrası yerel `development`'ı eşitle.

## 4. development → main
- PR: kaynak `development`, hedef `main`; başlık ve açıklama releaser raporundaki release PR metni.
- Yöntem: **merge commit**. Squash veya rebase kullanma, `main` ile `development`'ın geçmişi ayrışır.
- PR'ı `merge` skill'inin 3. adımındaki `gh` yöntemiyle aç (`--base main --head development`); merge'de `--squash` yerine `gh pr merge <PR> --merge` kullan.

## 5. Etiket
- `git -C <ana repo> fetch origin --prune`; yerel `main` ve `development`'ı eşitle.
- `origin/main`'in son commit'i `development`'ı içeren merge commit olmalı (`git merge-base --is-ancestor origin/development origin/main`); değilse dur.
- `git -C <ana repo> tag -a vX.Y.Z origin/main -m "vX.Y.Z"`
- `git -C <ana repo> push origin vX.Y.Z`

## 6. Temizlik
- Release worktree'sini kaldır (`git worktree remove`, `--force` yok).
- `release/vX.Y.Z` branch'ini yerelde ve uzakta sil (uzakta yoksa hatayı yok say).
- Release worktree'sinde Docker ortamı ayağa kaldırıldıysa `docker compose down --rmi local`.

## 7. Bildir
Kısa özet: sürüm, etiket, PR'lar, rapor yolları, yapılan temizlik.

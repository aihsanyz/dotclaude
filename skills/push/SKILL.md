---
name: push
description: Mevcut worktree branch'ini reviewer kapısından geçirip uzağa gönderir; branch'i origin/development ile günceller, reviewer raporunu commit'ler ve push eder. Kullanıcı push istediğinde ("push et", /push) kullan. Kullanıcının bunu istemesi push onayıdır.
---

# /push

Kullanıcının `/push` yazması veya push istemesi push onayıdır; ayrıca onay isteme. Reviewer kapısı atlanmaz. Bir adım başarısız olursa dur ve bildir.

Tüm git komutlarında `git -C <worktree mutlak yolu>` kullan; shell değişkeniyle yol kurma.

## 1. Ön kontroller
- Mevcut branch `main` veya `development` ise dur: iş bir worktree branch'inde olmalı (`/start-task`).
- Commit edilmemiş değişiklik varsa (`git status --short`, `docs/reports/` hariç) listele ve kullanıcıya sor: işin parçasıysa uygun Conventional Commits mesajıyla commit'le, değilse dur.
- `git fetch origin`

## 2. origin/development ile güncelle
- `git merge-base --is-ancestor origin/development HEAD` başarısızsa: `git merge --no-edit origin/development`.
  - Rebase kullanma (push edilmiş branch'te force push gerektirir). Squash merge sonunda bu merge commit'leri zaten görünmez.
  - Çakışma çıkarsa çözmeye çalış; emin olmadığın çakışmada `git merge --abort` yap ve kullanıcıya bildir.

## 3. Reviewer kapısı
- **Atlama kuralı:** Son reviewer raporu bu branch için "Hazır" ise ve o raporun eklendiği commit'ten (`git log -1 --format=%H -- docs/reports/reviewer/`) bu yana yalnızca `docs/reports/` altı değiştiyse reviewer'ı çalıştırma, 5. adıma geç.
- Aksi halde `reviewer` agent'ını worktree yolu ve branch adıyla çalıştır.
- Sonuç "Düzeltme gerekli" ise:
  - Bulguları kullanıcıya kısaca bildir, düzelt, değişiklikleri commit'le ve reviewer'ı tekrar çalıştır.
  - İki düzeltme turundan sonra hâlâ geçmiyorsa dur ve kullanıcıya sor.

## 4. Raporu commit'le
- `git add docs/reports/reviewer/<rapor dosyası>`
- `git commit -m "docs(reports): add reviewer report"`

## 5. Push
- `git push -u origin <branch>`
- Guard hook engellerse kuralı aşmaya çalışma; nedenini bildir.

## 6. Bildir
Kısa özet: reviewer sonucu (veya neden atlandığı), rapor yolu, push edilen commit sayısı ve HEAD.

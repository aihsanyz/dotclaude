# Bu Makineye Özel Ayarlar

Bu dosyayı `~/.claude/local.md` olarak kopyalayıp makineye göre doldurun. `local.md` git'e girmez.

## Sunucu Ortamı
- <işletim sistemi>, hostname `<hostname>`, kullanıcı `<kullanıcı>` (`sudo` ve `docker` gruplarında).
- Host'ta mevcut: git, gh, docker + docker compose, curl, jq, tailscale.
- Çalışan servisler: docker, containerd, tailscaled.

## Ağ Adresleri
- Yerel ağ: `http://<LAN IP>:<port>` (`ip -4 -br addr show <arayüz>`)
- Tailscale: `http://<makine>.<tailnet>.ts.net:<port>` veya `http://<Tailscale IP>:<port>` (`tailscale ip -4`)
- Dev server host kontrolüne eklenecek Tailscale DNS adı: `<makine>.<tailnet>.ts.net`

# Lomba Indonesia — Vue 3 + Supabase + GitHub Pages

Template pendaftaran lomba 17 Agustus dengan desain merah-putih yang mengikuti referensi landing page: hero Independence Day, bentuk wave merah-putih, countdown, kartu lomba, tabel peserta, pengurus, anggota, dan footer modern.

## Fitur utama
- Vue 3 + Vite
- Supabase PostgreSQL sebagai database bersama
- GitHub Pages ready
- Countdown real-time setiap detik
- CRUD perlombaan
- **Alamat lengkap perlombaan** pada data event
- Pendaftaran peserta dari publik
- Kuota lomba dengan RPC atomic agar tidak mudah oversubscribe saat pendaftaran bersamaan
- Login admin via Supabase Auth
- Data peserta private untuk admin melalui RLS
- Search peserta
- Server-side pagination 20 peserta/halaman
- Export / Import JSON
- List pengurus dan anggota
- Responsive mobile, tablet, desktop
- Modern web UI dengan card, shadow, rounded UI, responsive navigation
- Footer kredit: **Dibuat oleh Trisna N.S**

## Alamat perlombaan
Setiap perlombaan mempunyai dua informasi lokasi:
- Nama lokasi, contoh: `Lapangan Utama`
- Alamat lengkap, contoh: `Jl. Anggrek Kp. Tegalwaru `

Kolom alamat juga tampil pada kartu perlombaan dan dapat diedit admin.

## Setup Supabase
1. Buat project Supabase.
2. Buka SQL Editor.
3. Jalankan `supabase/schema.sql`.
4. Jika database versi lama sudah pernah dibuat, file tersebut memiliki migration `alter table ... add column if not exists address`.
5. Buat user admin pada Authentication → Users.
6. Salin `.env.example` menjadi `.env` untuk development lokal.

Contoh:
```env
VITE_SUPABASE_URL=https://PROJECT_ID.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Untuk GitHub Actions, masukkan kedua nilai tersebut pada Repository → Settings → Secrets and variables → Actions.

## Jalankan lokal
```bash
npm install
npm run dev
```

## Build
```bash
npm run build
```

## GitHub Pages
Workflow deployment sudah disediakan pada `.github/workflows/deploy.yml`. Push ke branch `main`, lalu GitHub Actions akan melakukan build dan deploy ke GitHub Pages.

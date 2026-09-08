# Product Requirements Document (PRD)
## Aplikasi Screen Recorder Berbasis AI untuk macOS
**Nama kerja proyek:** ClipFocus *(placeholder — ganti sesuai nama produk final)*  
**Versi dokumen:** 1.0  
**Tanggal:** 7 September 2026  
**Status:** Draft untuk direview  
**Referensi kompetitor utama:** FocuSee (imobie.com), Screen Studio, Loom, Camtasia, Cursorful  

---

## 1. Ringkasan Eksekutif

ClipFocus adalah aplikasi native macOS untuk merekam layar, webcam, dan audio, yang secara otomatis "mempercantik" hasil rekaman dengan efek zoom-pan, highlight kursor, penghilang jeda/kata pengisi ("um", "eh"), peningkatan kualitas audio berbasis AI, dan subtitle otomatis — tanpa perlu skill editing video.

Masalah inti yang diselesaikan: membuat video demo produk, tutorial, atau konten marketing biasanya butuh software rekam + software edit terpisah, jam kerja editing manual (keyframe zoom, potong jeda, bersihkan noise), dan skill yang tidak dimiliki kebanyakan pengguna (developer, desainer, customer support, educator). ClipFocus memindahkan seluruh proses "post-production" itu menjadi otomatis, sehingga dari "stop recording" ke "video siap upload" hanya butuh hitungan menit.

## 2. Latar Belakang & Masalah

| Masalah pengguna saat ini | Dampak |
|---|---|
| Screen recorder standar (QuickTime, OBS) hanya menghasilkan rekaman mentah | Perlu software edit tambahan (Final Cut, Premiere, Camtasia) |
| Zoom-in manual saat highlight klik/ketikan butuh keyframing manual | Memakan waktu berjam-jam per video pendek |
| Audio mic laptop/headset kualitasnya jelek, ada noise & jeda | Video terasa tidak profesional |
| Subtitle harus dibuat manual atau pakai tool terpisah | Konten tidak accessible & memperlambat publishing |
| Setiap platform (TikTok, YouTube, IG) butuh rasio video berbeda | Rekam ulang / crop manual berkali-kali |

**Peluang:** Kategori "auto-editing screen recorder" (FocuSee, Screen Studio) terbukti diminati (rating 4.8/5 dari ribuan review, viral di Product Hunt), tapi API macOS terbaru (ScreenCaptureKit, on-device ML lewat Apple Neural Engine) belum banyak dimanfaatkan pemain lama seperti OBS/Camtasia — ini celah diferensiasi untuk aplikasi native Apple Silicon yang cepat & hemat baterai.

## 3. Tujuan Produk

### 3.1 Business Goals
- Meluncurkan MVP dalam 1 kuartal, App Store + direct download (notarized DMG).
- Mencapai konversi free-to-paid ≥ 5% dalam 90 hari setelah instal.
- Membangun basis pengguna awal dari komunitas indie hacker, content creator, dan tim support/produk B2B SaaS.

### 3.2 User Goals
- Menghasilkan video "siap posting" tanpa membuka software editing terpisah.
- Video terlihat profesional meski direkam dengan mic/webcam laptop biasa.
- Proses dari rekam → ekspor selesai dalam < 5 menit untuk video 2–3 menit.

### 3.3 Non-Goals (di luar cakupan awal)
- Bukan full NLE (non-linear editor) multi-track seperti Premiere/Final Cut.
- Bukan platform hosting video (fitur share link hanya "nice to have" fase lanjut).
- Tidak menargetkan tim produksi film/broadcast profesional.

## 4. Target Pengguna & Persona

| Persona | Kebutuhan Utama | Fitur Prioritas |
|---|---|---|
| **Indie developer / founder** | Demo produk cepat untuk landing page atau Product Hunt | Auto zoom, background custom, watermark |
| **Content creator / educator** | Tutorial & kursus online yang engaging | Teleprompter, subtitle AI, virtual avatar |
| **Tim customer support** | Rekam bug report / cara pakai fitur | Perekaman cepat, blur data sensitif, area kustom |
| **Tim marketing/sales** | Video promosi & pitch dengan branding konsisten | Preset brand, watermark, ekspor multi-platform |

## 5. Lanskap Kompetitor (Singkat)

| Produk | Kekuatan | Celah yang bisa dimanfaatkan |
|---|---|---|
| FocuSee | Fitur AI lengkap (avatar, subtitle, audio enhancement), lintas platform Win+Mac | Performa cross-platform kadang dikompromikan; peluang untuk versi macOS-native yang lebih ringan & terintegrasi Apple Silicon |
| Screen Studio | UI sangat clean, fokus ke auto-zoom cinematic | Fitur AI (subtitle, avatar) lebih terbatas |
| Loom | Simple, cloud-first, kolaborasi tim kuat | Auto-editing/zoom minim, kurang cocok untuk video marketing polished |
| Camtasia/OBS | Kontrol manual sangat dalam | Kurva belajar tinggi, tidak otomatis |

*(Catatan: bagian ini untuk konteks internal tim, bukan klaim pemasaran ke pengguna akhir.)*

## 6. Ruang Lingkup Rilis

### MVP (Fase 1)
Fokus: alur inti "rekam → auto-polish → ekspor" berjalan mulus di macOS native.

### Fase 2
Fitur AI lanjutan (avatar, background removal, smart cut) + ekspor multi-platform.

### Fase 3
Kolaborasi, sharing online, integrasi mobile recording, custom preset/brand kit.

Detail fitur per fase ada di tabel prioritas Bagian 8 dan roadmap Bagian 14.

## 7. Alur Pengguna Utama (User Flow)

1. **Setup awal** — pengguna membuka app, diberi izin macOS (Screen Recording, Microphone, Camera, Accessibility) lewat onboarding yang menjelaskan kenapa tiap izin dibutuhkan.
2. **Pilih mode rekam** — Full Screen / Window / Area kustom, opsional aktifkan webcam & mic, pilih layout kamera (PiP / full).
3. **(Opsional) Aktifkan Teleprompter** — tempel skrip, atur ukuran font & kecepatan scroll.
4. **Rekam** — indikator kecil menampilkan status rekam, shortcut keyboard untuk stop/pause.
5. **Auto-processing** — setelah stop, sistem otomatis mendeteksi klik/ketikan untuk zoom, mendeteksi jeda/filler word, menstabilkan audio.
6. **Editor review** — pengguna melihat timeline, bisa sesuaikan titik zoom, tambah anotasi (teks/panah/spotlight/blur), ganti gaya kursor, tambah subtitle/musik latar.
7. **Ekspor** — pilih rasio (16:9, 9:16, 1:1), resolusi (hingga 4K), format (MP4/GIF), atau bagikan via link.

## 8. Functional Requirements

Prioritas menggunakan MoSCoW: **M**ust have, **S**hould have, **C**ould have, **W**on't have (rilis ini).

### 8.1 Perekaman
| Requirement | Prioritas |
|---|---|
| Rekam full screen, window tertentu, atau area custom | Must |
| Rekam webcam + mic + audio sistem secara bersamaan | Must |
| Multi-monitor support | Must |
| Deteksi & tampilkan keyboard shortcut yang ditekan saat rekam | Should |
| Rekam perangkat mobile (iOS/Android) via kabel USB | Could |
| Countdown timer & indikator rekam yang tidak mengganggu (floating pill) | Must |
| Import video lokal untuk diedit dengan fitur yang sama | Should |

### 8.2 Auto Zoom & Efek Kursor
| Requirement | Prioritas |
|---|---|
| Auto zoom-in mengikuti posisi klik & area pengetikan | Must |
| Transisi pan/zoom yang smooth (bukan hard cut) | Must |
| Kustomisasi gaya kursor (bentuk, ukuran, animasi klik, suara klik) | Should |
| Kursor otomatis "menyembunyikan diri" saat tidak ada aksi penting | Could |
| Efek 3D motion / tilt & motion blur mengikuti pergerakan kursor | Could |

### 8.3 Annotation Suite
| Requirement | Prioritas |
|---|---|
| Teks, panah, kotak/shape, callout | Must |
| Spotlight (menyorot area, meredupkan sisanya) | Should |
| Blur manual untuk menyembunyikan data sensitif | Must |
| Stack/layer multi-anotasi dalam satu adegan | Could |

### 8.4 Fitur Berbasis AI
| Requirement | Prioritas |
|---|---|
| Subtitle otomatis (speech-to-text) multi-bahasa + editor subtitle (edit teks, timing, split/merge, import SRT) | Must |
| Smart cut: deteksi & hapus otomatis jeda hening dan kata pengisi ("um", "eh") | Must |
| Audio enhancement: noise reduction & voice clarity | Must |
| Background removal/replace untuk webcam (tanpa green screen) | Should |
| AI virtual avatar sebagai pengganti wajah presenter | Could |
| Camera beautification (smoothing kulit, brightness) | Could |

> **Catatan teknis:** untuk fitur ini, tentukan sejak awal mana yang diproses **on-device** (pakai Core ML / Apple Neural Engine, lebih privat & offline) vs **cloud-based** (lebih akurat tapi butuh koneksi & biaya server). Rekomendasi MVP: noise reduction & background removal on-device (real-time), subtitle & avatar generation via cloud API karena butuh model lebih besar.

### 8.5 Teleprompter
| Requirement | Prioritas |
|---|---|
| Tampilkan skrip di layar saat rekam, transparan/overlay | Must |
| Atur ukuran font, kecepatan scroll, posisi | Must |
| Kontrol scroll manual (keyboard/remote) selain auto-scroll | Should |

### 8.6 Kamera & Layout
| Requirement | Prioritas |
|---|---|
| Layout Picture-in-Picture & full-screen webcam | Must |
| Ganti layout on-the-fly saat editing | Should |
| Custom shape/rounded corner/shadow untuk frame kamera | Could |

### 8.7 Tools Editing Tambahan
| Requirement | Prioritas |
|---|---|
| Trim/potong bagian video | Must |
| Ubah kecepatan playback (speed up bagian mengetik otomatis) | Should |
| Tambah musik latar (preset atau import) | Could |
| Simpan preset (kombinasi style, watermark, layout) untuk dipakai ulang | Should |

### 8.8 Ekspor & Sharing
| Requirement | Prioritas |
|---|---|
| Ekspor MP4 hingga 4K 60fps, dan GIF | Must |
| Preset rasio otomatis per platform (TikTok 9:16, YouTube 16:9, IG 1:1, dst.) | Should |
| Watermark kustom (logo, posisi, transparansi) | Must |
| Bagikan via link online dengan proteksi password & kontrol akses | Could |

### 8.9 Privasi & Keamanan
| Requirement | Prioritas |
|---|---|
| Rekaman disimpan lokal secara default | Must |
| Upload cloud bersifat opsional, terenkripsi (TLS/SSL) | Must |
| Pemrosesan deteksi kursor/klik/shortcut dilakukan on-device, tidak dikirim ke server | Must |
| Transparansi penggunaan izin macOS (Screen Recording, Accessibility, Mic, Camera) dijelaskan di onboarding | Must |

## 9. Non-Functional Requirements

- **Platform:** macOS 13 (Ventura) ke atas, dukungan penuh Apple Silicon (M1–M4) dengan build universal binary (arm64 + x86_64 jika tetap mendukung Intel).
- **Performa:** overhead rekaman ≤ 10–15% CPU saat idle recording di layar 1080p; preview real-time tetap 30fps+ minimum saat live-processing efek.
- **Baterai:** optimasi untuk laptop (hindari full-load GPU terus-menerus saat idle).
- **Aksesibilitas:** dukungan VoiceOver di UI aplikasi, kontras warna sesuai HIG (Human Interface Guidelines).
- **Ukuran file & storage:** kompresi efisien tanpa penurunan kualitas signifikan; peringatan storage rendah sebelum rekam durasi panjang.
- **Reliabilitas:** auto-save/recovery jika app crash saat rekaman berlangsung.

## 10. Pertimbangan Teknis / Arsitektur (macOS-spesifik)

| Kebutuhan | Framework/Teknologi yang relevan |
|---|---|
| Capture layar performa tinggi | `ScreenCaptureKit` (macOS 12.3+) — lebih efisien dari API lama `CGDisplayStream` |
| Capture webcam & audio | `AVFoundation` |
| Rendering efek real-time (zoom, blur, motion) | `Metal` / `Core Animation` |
| AI on-device (background removal, noise reduction, deteksi kursor/typing) | `Core ML`, `Vision` (person segmentation), `Apple Neural Engine` |
| Speech-to-text untuk subtitle | `Speech` framework (on-device) sebagai baseline, atau API cloud (mis. Whisper-based) untuk akurasi lebih tinggi & bahasa lebih luas |
| Global cursor/keyboard event untuk shortcut capture | `Accessibility API` (butuh izin eksplisit dari pengguna) |
| Distribusi | Tentukan sejak awal: **App Store (sandboxed)** vs **direct download & notarized DMG** — ini akan sangat memengaruhi desain arsitektur karena sandbox membatasi akses Accessibility API dan beberapa capture API |

## 11. Model Monetisasi (Usulan)

- **Free tier:** akses fitur rekam dasar + auto zoom, ekspor terbatas (mis. 1 video watermark-free per bulan, resolusi dibatasi).
- **Pro (langganan bulanan/tahunan):** semua fitur editing, ekspor 4K unlimited, tanpa watermark.
- **AI Credits (add-on):** fitur berat komputasi (avatar generation, cloud subtitle akurasi tinggi) memakai sistem kredit terpisah — mengikuti pola industri karena biaya inferensi model AI cloud bervariasi.
- **Diskon edukasi** untuk pelajar/institusi.

## 12. Metrik Keberhasilan (KPI)

| Metrik | Target Awal |
|---|---|
| Activation rate (ekspor video pertama < 24 jam setelah instal) | ≥ 40% |
| Retensi D7 | ≥ 25% |
| Retensi D30 | ≥ 12% |
| Konversi free → paid (90 hari) | ≥ 5% |
| Rata-rata waktu dari "stop rekam" ke "video siap ekspor" | < 3 menit untuk video 2–3 menit |
| Crash-free session rate | ≥ 99.5% |
| App Store rating | ≥ 4.5/5 |

## 13. Risiko & Asumsi

| Risiko | Mitigasi |
|---|---|
| Model AI on-device kurang akurat dibanding kompetitor yang pakai cloud besar | Mulai dengan hybrid (on-device untuk real-time, cloud opsional untuk akurasi) |
| Sandbox App Store membatasi fitur Accessibility (shortcut capture) | Evaluasi rilis non-App-Store sebagai jalur distribusi paralel |
| Biaya inferensi cloud AI (avatar, subtitle) membengkak seiring pertumbuhan pengguna | Sistem kredit/pembatasan pemakaian di free tier sejak awal |
| Performa buruk di Mac Intel lama | Tentukan minimum spec jelas, uji di hardware representatif sebelum GA |
| Kekhawatiran privasi soal rekaman layar (data sensitif) | Fitur blur otomatis/manual, pemrosesan lokal, kebijakan privasi transparan |

## 14. Roadmap & Milestone (Usulan)

| Fase | Fokus | Estimasi |
|---|---|---|
| **Fase 1 – MVP** | Rekam (screen/webcam/audio), auto zoom & cursor, trim dasar, ekspor MP4/GIF, watermark, izin macOS onboarding | 10–12 minggu |
| **Fase 2 – AI Enhancement** | Subtitle AI + editor, smart cut (filler/silence), audio enhancement, background removal, teleprompter | +8–10 minggu |
| **Fase 3 – Skala & Kolaborasi** | Virtual avatar, ekspor multi-platform preset, sharing link online, preset/brand kit, mobile device recording | +8–10 minggu |

## 15. Pertanyaan Terbuka (Perlu Keputusan Stakeholder)

1. Distribusi utama: Mac App Store, direct download, atau keduanya sejak awal?
2. Apakah mendukung Mac Intel lama, atau Apple Silicon-only untuk memaksimalkan performa AI on-device?
3. Model harga final: subscription murni, kredit AI terpisah, atau lisensi perpetual (pola umum produk iMobie lain)?
4. Bahasa/lokal apa yang jadi prioritas untuk subtitle AI di rilis awal?
5. Apakah fitur cloud sharing/collab masuk MVP atau memang ditunda ke Fase 3?

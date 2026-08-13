<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { Home, CalendarDays, Users, UserRound, Trophy, Search, Download, Upload, Plus, X, ChevronLeft, ChevronRight, Clock3, MapPin, CheckCircle2, Trash2, Edit3, Database, ShieldCheck, LogIn, LogOut, RefreshCw } from 'lucide-vue-next';
import { supabase } from './supabase';

const activeTab = ref('home');
const search = ref('');
const participantPage = ref(1);
const pageSize = 20;
const totalParticipants = ref(0);
const participantRows = ref([]);
const participantLoading = ref(false);
const eventCounts = ref({});
const loading = ref(true);
const errorMessage = ref('');
const toast = ref('');
const now = ref(new Date());
const session = ref(null);
const showRegistration = ref(false);
const showEventForm = ref(false);
const showLogin = ref(false);
const editingEvent = ref(null);
const loginForm = ref({ email: '', password: '' });
const authLoading = ref(false);
const timer = ref(null);

const events = ref([]);
const organizers = ref([]);
const members = ref([]);

const registration = ref({ name: '', phone: '', group: '', age: '', address: '', eventId: '' });
const eventForm = ref({ name: '', category: 'Umum', date: '2026-08-17', startTime: '10:00', location: 'Lapangan Utama', address: 'Jl. Kemerdekaan No. 17, Kelurahan Setempat', quota: 20, status: 'open' });

const isAdmin = computed(() => !!session.value?.user);
const totalPages = computed(() => Math.max(1, Math.ceil(totalParticipants.value / pageSize)));

const dashboardStats = computed(() => ({
  events: events.value.length,
  participants: totalParticipants.value,
  organizers: organizers.value.length,
  members: members.value.length,
}));

function notify(message) {
  toast.value = message;
  window.clearTimeout(notify._timer);
  notify._timer = window.setTimeout(() => (toast.value = ''), 2800);
}

function handleError(error, fallback = 'Terjadi kesalahan.') {
  console.error(error);
  const message = error?.message || fallback;
  notify(message);
  return message;
}

function mapEvent(row) {
  return { ...row, startTime: row.start_time, address: row.address || row.location || '' };
}
function mapParticipant(row) {
  return { ...row, group: row.group_name, eventId: row.event_id, registeredAt: row.registered_at };
}
function mapOrganizer(row) {
  return row;
}
function mapMember(row) {
  return { ...row, group: row.group_name };
}

async function loadPublicData() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const [ev, org, mem] = await Promise.all([
      supabase.from('events').select('*').order('date', { ascending: true }).order('start_time', { ascending: true }),
      supabase.from('organizers').select('*').order('name'),
      supabase.from('members').select('*').order('name'),
    ]);
    if (ev.error) throw ev.error;
    if (org.error) throw org.error;
    if (mem.error) throw mem.error;
    events.value = (ev.data || []).map(mapEvent);
    organizers.value = (org.data || []).map(mapOrganizer);
    members.value = (mem.data || []).map(mapMember);
    await loadEventCounts();
  } catch (e) {
    errorMessage.value = e?.message || 'Supabase belum terhubung.';
    console.error(e);
  } finally {
    loading.value = false;
  }
}

async function loadEventCounts() {
  const { data, error } = await supabase.rpc('get_event_counts');
  if (error) {
    console.error(error);
    eventCounts.value = {};
    return;
  }
  eventCounts.value = Object.fromEntries((data || []).map((row) => [row.event_id, Number(row.participant_count)]));
}

async function loadParticipants() {
  if (!isAdmin.value) return;
  participantLoading.value = true;
  try {
    const from = (participantPage.value - 1) * pageSize;
    const to = from + pageSize - 1;
    let query = supabase.from('participants').select('id,name,phone,group_name,age,address,event_id,registered_at,events(name)', { count: 'exact' }).order('registered_at', { ascending: false }).range(from, to);

    const q = search.value.trim().replace(/[,%()]/g, ' ');
    if (q) {
      const eventMatches = events.value.filter((e) => e.name.toLowerCase().includes(q.toLowerCase())).map((e) => e.id);
      const clauses = [`name.ilike.%${q}%`, `phone.ilike.%${q}%`, `group_name.ilike.%${q}%`];
      if (eventMatches.length) clauses.push(`event_id.in.(${eventMatches.join(',')})`);
      query = query.or(clauses.join(','));
    }

    const { data, count, error } = await query;
    if (error) throw error;
    participantRows.value = (data || []).map(mapParticipant);
    totalParticipants.value = count || 0;
  } catch (e) {
    handleError(e);
  } finally {
    participantLoading.value = false;
  }
}

// function getEvent(id) {
//   return events.value.find((e) => e.id === id);
// }
// function eventDateTime(event) {
//   return new Date(`${event.date}T${event.startTime}:00`);
// }
// function countdown(event) {
//   const diff = eventDateTime(event).getTime() - now.value.getTime();
//   if (diff <= 0) return { expired: true, days: 0, hours: 0, minutes: 0, seconds: 0 };
//   const s = Math.floor(diff / 1000);
//   return { expired: false, days: Math.floor(s / 86400), hours: Math.floor((s % 86400) / 3600), minutes: Math.floor((s % 3600) / 60), seconds: s % 60 };
// }
// function countdownText(event) {
//   const c = countdown(event);
//   if (c.expired) return 'DIMULAI';
//   return `${c.days}h ${String(c.hours).padStart(2, '0')}j ${String(c.minutes).padStart(2, '0')}m ${String(c.seconds).padStart(2, '0')}d`;
// }
// function formatDate(date) {
//   return new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium' }).format(new Date(date + 'T00:00:00'));
// }

function getEvent(id) {
  return events.value.find((e) => String(e.id) === String(id));
}

function eventDateTime(event) {
  if (!event) return null;

  // Support dua format:
  // Supabase : start_time
  // Vue      : startTime
  const dateValue = event.date;
  const timeValue = event.startTime ?? event.start_time;

  if (!dateValue || !timeValue) {
    console.warn('Tanggal/jam lomba tidak tersedia:', event);
    return null;
  }

  // Pastikan tanggal hanya YYYY-MM-DD
  const dateText = String(dateValue).substring(0, 10);

  // Pastikan jam hanya HH:mm
  const timeText = String(timeValue).substring(0, 5);

  const dateParts = dateText.split('-').map(Number);
  const timeParts = timeText.split(':').map(Number);

  const year = dateParts[0];
  const month = dateParts[1];
  const day = dateParts[2];

  const hour = timeParts[0];
  const minute = timeParts[1];

  // Validasi
  if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day) || !Number.isInteger(hour) || !Number.isInteger(minute)) {
    console.error('Format tanggal/jam tidak valid:', {
      dateValue,
      timeValue,
    });

    return null;
  }

  // Validasi range
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    console.error('Nilai tanggal/jam tidak valid:', {
      year,
      month,
      day,
      hour,
      minute,
    });

    return null;
  }

  /*
   * Indonesia WIB = UTC+7.
   *
   * Date.UTC menggunakan UTC,
   * jadi jam WIB dikurangi 7 jam.
   */
  const timestamp = Date.UTC(year, month - 1, day, hour - 7, minute, 0);

  const result = new Date(timestamp);

  if (Number.isNaN(result.getTime())) {
    console.error('Gagal membuat tanggal:', {
      dateText,
      timeText,
    });

    return null;
  }

  return result;
}

function countdown(event) {
  const target = eventDateTime(event);

  // Jangan pernah menghasilkan NaN
  if (!target) {
    return {
      expired: false,
      invalid: true,
      days: 0,
      hours: 0,
      minutes: 0,
      seconds: 0,
    };
  }

  const current = now.value instanceof Date ? now.value : new Date();

  const currentTime = current.getTime();
  const targetTime = target.getTime();

  if (Number.isNaN(currentTime) || Number.isNaN(targetTime)) {
    return {
      expired: false,
      invalid: true,
      days: 0,
      hours: 0,
      minutes: 0,
      seconds: 0,
    };
  }

  const diff = targetTime - currentTime;

  if (diff <= 0) {
    return {
      expired: true,
      invalid: false,
      days: 0,
      hours: 0,
      minutes: 0,
      seconds: 0,
    };
  }

  const totalSeconds = Math.floor(diff / 1000);

  return {
    expired: false,
    invalid: false,

    days: Math.floor(totalSeconds / 86400),

    hours: Math.floor((totalSeconds % 86400) / 3600),

    minutes: Math.floor((totalSeconds % 3600) / 60),

    seconds: totalSeconds % 60,
  };
}

function countdownText(event) {
  const c = countdown(event);

  if (c.invalid) {
    return 'WAKTU BELUM DIATUR';
  }

  if (c.expired) {
    return 'DIMULAI';
  }

  return `${c.days}h ${String(c.hours).padStart(2, '0')}j ${String(c.minutes).padStart(2, '0')}m ${String(c.seconds).padStart(2, '0')}d`;
}

function formatDate(date) {
  if (!date) return '-';

  const dateText = String(date).substring(0, 10);

  const parts = dateText.split('-').map(Number);

  if (parts.length !== 3 || parts.some((value) => !Number.isInteger(value))) {
    return '-';
  }

  const [year, month, day] = parts;

  const localDate = new Date(year, month - 1, day);

  if (Number.isNaN(localDate.getTime())) {
    return '-';
  }

  return new Intl.DateTimeFormat('id-ID', {
    dateStyle: 'medium',
  }).format(localDate);
}

function openRegistration(event = null) {
  registration.value = { name: '', phone: '', group: '', age: '', address: '', eventId: event?.id || events.value[0]?.id || '' };
  showRegistration.value = true;
}

async function submitRegistration() {
  const r = registration.value;
  if (!r.name.trim() || !r.phone.trim() || !r.eventId) return notify('Nama, nomor HP, dan lomba wajib diisi.');
  authLoading.value = true;
  try {
    const { error } = await supabase.rpc('register_participant', {
      p_name: r.name.trim(),
      p_phone: r.phone.trim(),
      p_group_name: r.group.trim(),
      p_age: r.age ? Number(r.age) : null,
      p_address: r.address.trim(),
      p_event_id: r.eventId,
    });
    if (error) throw error;
    showRegistration.value = false;
    notify('Pendaftaran berhasil masuk database.');
    await loadEventCounts();
    if (isAdmin.value) await loadParticipants();
  } catch (e) {
    handleError(e);
  } finally {
    authLoading.value = false;
  }
}

function openEventForm(event = null) {
  if (!isAdmin.value) return (showLogin.value = true);
  editingEvent.value = event;
  eventForm.value = event ? { ...event } : { name: '', category: 'Umum', date: '2026-08-17', startTime: '10:00', location: 'Lapangan Utama', address: 'Jl. Kemerdekaan No. 17, Kelurahan Setempat', quota: 20, status: 'open' };
  showEventForm.value = true;
}

async function saveEvent() {
  const f = eventForm.value;
  if (!f.name || !f.date || !f.startTime || !f.location) return notify('Lengkapi data perlombaan.');
  try {
    const payload = { name: f.name.trim(), category: f.category, date: f.date, start_time: f.startTime, location: f.location.trim(), address: f.address.trim(), quota: Number(f.quota), status: f.status };
    const result = editingEvent.value ? await supabase.from('events').update(payload).eq('id', editingEvent.value.id).select().single() : await supabase.from('events').insert(payload).select().single();
    if (result.error) throw result.error;
    showEventForm.value = false;
    notify('Data lomba tersimpan di Supabase.');
    await loadPublicData();
  } catch (e) {
    handleError(e);
  }
}

async function deleteEvent(event) {
  if (!isAdmin.value) return (showLogin.value = true);
  if (!confirm(`Hapus lomba "${event.name}"? Peserta lomba ini juga akan terhapus.`)) return;
  try {
    const { error } = await supabase.from('events').delete().eq('id', event.id);
    if (error) throw error;
    notify('Lomba dihapus.');
    await loadPublicData();
    if (isAdmin.value) await loadParticipants();
  } catch (e) {
    handleError(e);
  }
}

async function deleteParticipant(p) {
  if (!isAdmin.value) return (showLogin.value = true);
  if (!confirm(`Hapus peserta ${p.name}?`)) return;
  try {
    const { error } = await supabase.from('participants').delete().eq('id', p.id);
    if (error) throw error;
    notify('Peserta dihapus.');
    await loadParticipants();
    await loadEventCounts();
  } catch (e) {
    handleError(e);
  }
}

async function login() {
  authLoading.value = true;
  try {
    const { data, error } = await supabase.auth.signInWithPassword({ email: loginForm.value.email.trim(), password: loginForm.value.password });
    if (error) throw error;
    session.value = data.session;
    showLogin.value = false;
    loginForm.value = { email: '', password: '' };
    notify('Login admin berhasil.');
    await loadParticipants();
  } catch (e) {
    handleError(e, 'Login gagal.');
  } finally {
    authLoading.value = false;
  }
}

async function logout() {
  await supabase.auth.signOut();
  session.value = null;
  participantRows.value = [];
  totalParticipants.value = 0;
  notify('Anda sudah logout.');
  if (activeTab.value === 'participants') activeTab.value = 'home';
}

async function exportJSON() {
  if (!isAdmin.value) return (showLogin.value = true);
  try {
    const [ev, org, mem] = await Promise.all([supabase.from('events').select('*').order('date').order('start_time'), supabase.from('organizers').select('*').order('name'), supabase.from('members').select('*').order('name')]);
    if (ev.error) throw ev.error;
    if (org.error) throw org.error;
    if (mem.error) throw mem.error;

    let all = [],
      from = 0;
    while (true) {
      const { data, error } = await supabase
        .from('participants')
        .select('*')
        .order('registered_at', { ascending: false })
        .range(from, from + 999);
      if (error) throw error;
      all.push(...(data || []));
      if (!data || data.length < 1000) break;
      from += 1000;
    }

    const payload = {
      version: 2,
      exportedAt: new Date().toISOString(),
      events: (ev.data || []).map(mapEvent),
      organizers: org.data || [],
      members: (mem.data || []).map(mapMember),
      participants: all.map(mapParticipant),
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob),
      a = document.createElement('a');
    a.href = url;
    a.download = `data-lomba-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
    notify(`Export ${all.length} peserta berhasil.`);
  } catch (e) {
    handleError(e);
  }
}

async function importJSON(event) {
  if (!isAdmin.value) {
    event.target.value = '';
    return (showLogin.value = true);
  }
  const file = event.target.files?.[0];
  if (!file) return;
  try {
    const parsed = JSON.parse(await file.text());
    if (!Array.isArray(parsed.events) || !Array.isArray(parsed.participants)) throw new Error('Format JSON tidak sesuai.');

    const evRows = parsed.events.map((e) => ({
      id: e.id,
      name: e.name,
      category: e.category || 'Umum',
      date: e.date,
      start_time: e.start_time || e.startTime,
      location: e.location,
      address: e.address || e.location,
      quota: Number(e.quota || 20),
      status: e.status || 'open',
    }));
    const orgRows = (parsed.organizers || []).map((o) => ({ id: o.id, name: o.name, role: o.role, phone: o.phone || null }));
    const memRows = (parsed.members || []).map((m) => ({ id: m.id, name: m.name, group_name: m.group_name || m.group || 'Umum', phone: m.phone || null }));
    const pRows = parsed.participants.map((p) => ({
      id: p.id,
      name: p.name,
      phone: p.phone,
      group_name: p.group_name || p.group || '-',
      age: p.age ? Number(p.age) : null,
      address: p.address || '-',
      event_id: p.event_id || p.eventId,
      registered_at: p.registered_at || p.registeredAt || new Date().toISOString(),
    }));

    for (let i = 0; i < evRows.length; i += 500) {
      const { error } = await supabase.from('events').upsert(evRows.slice(i, i + 500));
      if (error) throw error;
    }
    for (let i = 0; i < orgRows.length; i += 500) {
      const { error } = await supabase.from('organizers').upsert(orgRows.slice(i, i + 500));
      if (error) throw error;
    }
    for (let i = 0; i < memRows.length; i += 500) {
      const { error } = await supabase.from('members').upsert(memRows.slice(i, i + 500));
      if (error) throw error;
    }
    for (let i = 0; i < pRows.length; i += 500) {
      const { error } = await supabase.from('participants').upsert(pRows.slice(i, i + 500));
      if (error) throw error;
    }

    await loadPublicData();
    await loadParticipants();
    notify('JSON berhasil diimpor ke Supabase.');
  } catch (e) {
    handleError(e);
  } finally {
    event.target.value = '';
  }
}

function resetPage() {
  participantPage.value = 1;
  loadParticipants();
}
function previousPage() {
  if (participantPage.value > 1) {
    participantPage.value--;
    loadParticipants();
  }
}
function nextPage() {
  if (participantPage.value < totalPages.value) {
    participantPage.value++;
    loadParticipants();
  }
}

onMounted(async () => {
  timer.value = window.setInterval(() => (now.value = new Date()), 1000);
  const { data } = await supabase.auth.getSession();
  session.value = data.session;
  supabase.auth.onAuthStateChange((_event, nextSession) => {
    session.value = nextSession;
  });
  await loadPublicData();
  if (isAdmin.value) await loadParticipants();
});

onBeforeUnmount(() => window.clearInterval(timer.value));

const mobileMenuOpen = ref(false);

function closeMobileMenu() {
  mobileMenuOpen.value = false;
}

function goTo(tab) {
  activeTab.value = tab;
  if (tab === 'participants' && isAdmin.value) loadParticipants();
  closeMobileMenu();
}

// Kunci scroll body saat menu mobile terbuka + tutup dengan tombol Escape
watch(mobileMenuOpen, (open) => {
  document.body.style.overflow = open ? 'hidden' : '';
});

function handleKeydown(e) {
  if (e.key === 'Escape') closeMobileMenu();
}
onMounted(() => window.addEventListener('keydown', handleKeydown));
onBeforeUnmount(() => {
  window.removeEventListener('keydown', handleKeydown);
  document.body.style.overflow = '';
});
</script>

<template>
  <div class="app">
    <header class="hero">
      <nav class="nav container mobile-nav">
        <div class="brand">
          <div class="brand-mark">17</div>
          <div>
            <b>INDONESIA</b>
            <small>INDEPENDENCE DAY</small>
          </div>
        </div>

        <!-- DESKTOP MENU -->
        <div class="nav-links desktop-menu">
          <button :class="{ active: activeTab === 'home' }" @click="goTo('home')">Home</button>
          <button :class="{ active: activeTab === 'events' }" @click="goTo('events')">Lomba</button>
          <button :class="{ active: activeTab === 'participants' }" @click="goTo('participants')">Peserta</button>
          <button :class="{ active: activeTab === 'organizers' }" @click="goTo('organizers')">Pengurus</button>
          <button :class="{ active: activeTab === 'members' }" @click="goTo('members')">Anggota</button>
        </div>

        <button v-if="!isAdmin" class="mobile-reg desktop-register" @click="openRegistration()">Daftar Lomba</button>
        <button v-else class="mobile-reg desktop-register" @click="logout"><LogOut :size="15" /> Logout</button>

        <!-- HAMBURGER (animasi 3 garis -> X) -->
        <button type="button" class="hamburger-btn" :class="{ open: mobileMenuOpen }" @click="mobileMenuOpen = !mobileMenuOpen" aria-label="Buka menu" :aria-expanded="mobileMenuOpen"><span></span><span></span><span></span></button>

        <!-- OVERLAY BACKDROP -->
        <Transition name="backdrop-fade">
          <div v-if="mobileMenuOpen" class="mobile-backdrop" @click="closeMobileMenu"></div>
        </Transition>

        <!-- MOBILE MENU (slide + fade) -->
        <Transition name="menu-slide">
          <div v-if="mobileMenuOpen" class="mobile-menu">
            <button :class="{ active: activeTab === 'home' }" @click="goTo('home')"><Home :size="17" /> Home</button>
            <button :class="{ active: activeTab === 'events' }" @click="goTo('events')"><Trophy :size="17" /> Lomba</button>
            <button :class="{ active: activeTab === 'participants' }" @click="goTo('participants')"><Users :size="17" /> Peserta</button>
            <button :class="{ active: activeTab === 'organizers' }" @click="goTo('organizers')"><ShieldCheck :size="17" /> Pengurus</button>
            <button :class="{ active: activeTab === 'members' }" @click="goTo('members')"><UserRound :size="17" /> Anggota</button>
            <div class="mobile-menu-divider"></div>
            <button
              v-if="!isAdmin"
              class="mobile-menu-cta"
              @click="
                openRegistration();
                closeMobileMenu();
              "
            >
              <CheckCircle2 :size="17" /> Daftar Lomba
            </button>
            <button
              v-else
              class="mobile-menu-cta"
              @click="
                logout();
                closeMobileMenu();
              "
            >
              <LogOut :size="17" /> Logout
            </button>
          </div>
        </Transition>
      </nav>

      <section class="hero-content container">
        <div class="hero-copy">
          <p class="eyebrow">HEROIC EVENT • FREE ENTRY</p>
          <h1>MERDEKA<br /><span>INDONESIA</span></h1>
          <h2>INDEPENDENCE DAY</h2>
          <p>Daftarkan diri untuk mengikuti perlombaan 17 Agustus. Pendaftaran langsung tersimpan di database dan dapat dikelola panitia.</p>
          <div class="hero-meta">
            <span><MapPin :size="14" /> Lokasi & alamat lengkap tersedia di setiap lomba</span>
            <!-- <span><ShieldCheck :size="14" /> Aman • Supabase</span> -->
          </div>
          <button class="primary" @click="openRegistration()"><CheckCircle2 :size="17" /> Daftar Sekarang</button>
        </div>
        <div class="hero-date">
          <div class="big17">17<sup>TH</sup></div>
          <div>AGUSTUS 2026</div>
        </div>
        <div class="ball ball1"></div>
        <div class="ball ball2"></div>
        <div class="ball ball3"></div>
      </section>
    </header>

    <main class="container main">
      <div v-if="errorMessage" class="connection-warning">
        <Database :size="17" /><span>{{ errorMessage }} Pastikan URL dan key Supabase sudah diatur.</span><button class="outline" @click="loadPublicData"><RefreshCw :size="14" /> Coba Lagi</button>
      </div>

      <section v-if="activeTab === 'home'" class="tab-fade">
        <div class="section-head">
          <div>
            <span class="eyebrow">LIVE COUNTDOWN</span>
            <h2>Lomba Terdekat</h2>
          </div>
          <button class="outline" @click="activeTab = 'events'">Lihat Semua</button>
        </div>
        <div v-if="loading" class="loading">Memuat data dari Supabase...</div>
        <div v-else class="event-grid">
          <article v-for="event in events" :key="event.id" class="event-card">
            <div class="event-top">
              <span class="tag">{{ event.category }}</span
              ><span>{{ formatDate(event.date) }}</span>
            </div>
            <h3>{{ event.name }}</h3>
            <p><MapPin :size="15" /> {{ event.location }} • {{ event.startTime }}</p>
            <p class="event-address"><MapPin :size="14" /> {{ event.address }}</p>
            <div class="countdown">
              <Clock3 :size="18" /><strong>{{ countdownText(event) }}</strong>
            </div>
            <div class="quota">{{ eventCounts[event.id] ?? 0 }} / {{ event.quota }} peserta</div>
            <button class="primary full" @click="openRegistration(event)" :disabled="event.status !== 'open' || (eventCounts[event.id] || 0) >= event.quota">{{ event.status === 'open' ? 'Daftar' : 'Ditutup' }}</button>
          </article>
        </div>
        <div class="stats">
          <div>
            <Trophy /><strong>{{ dashboardStats.events }}</strong
            ><span>Perlombaan</span>
          </div>
          <div>
            <Users /><strong>{{ dashboardStats.participants || '—' }}</strong
            ><span>Peserta{{ isAdmin ? ' Terdaftar' : '' }}</span>
          </div>
          <div>
            <ShieldCheck /><strong>{{ dashboardStats.organizers }}</strong
            ><span>Pengurus</span>
          </div>
          <div>
            <UserRound /><strong>{{ dashboardStats.members }}</strong
            ><span>Anggota</span>
          </div>
        </div>
      </section>

      <section v-if="activeTab === 'events'" class="tab-fade">
        <div class="section-head">
          <div>
            <span class="eyebrow">MANAGEMENT</span>
            <h2>Daftar Perlombaan</h2>
          </div>
          <button class="primary" @click="openEventForm()"><Plus :size="17" /> Tambah Lomba</button>
        </div>
        <div class="event-grid">
          <article v-for="event in events" :key="event.id" class="event-card">
            <div class="event-top">
              <span class="tag">{{ event.category }}</span
              ><span :class="['status', event.status]">{{ event.status === 'open' ? 'Dibuka' : 'Ditutup' }}</span>
            </div>
            <h3>{{ event.name }}</h3>
            <p><CalendarDays :size="15" /> {{ formatDate(event.date) }} • {{ event.startTime }}</p>
            <p><MapPin :size="15" /> {{ event.location }}</p>
            <p class="event-address"><MapPin :size="14" /> {{ event.address }}</p>
            <div class="countdown">
              <Clock3 :size="18" /><strong>{{ countdownText(event) }}</strong>
            </div>
            <div class="quota">{{ eventCounts[event.id] ?? 0 }} / {{ event.quota }} peserta</div>
            <div class="card-actions">
              <button v-if="isAdmin" class="outline" @click="openEventForm(event)"><Edit3 :size="15" /> Edit</button><button v-if="isAdmin" class="danger" @click="deleteEvent(event)"><Trash2 :size="15" /> Hapus</button
              ><button class="primary" @click="openRegistration(event)">Daftar</button>
            </div>
          </article>
        </div>
      </section>

      <section v-if="activeTab === 'participants'" class="tab-fade">
        <div v-if="!isAdmin" class="admin-gate">
          <ShieldCheck :size="34" />
          <h2>Data peserta adalah area panitia</h2>
          <p>Login admin untuk melihat, mencari, menghapus, export, dan import data peserta.</p>
          <button class="primary" @click="showLogin = true"><LogIn :size="16" /> Login Admin</button>
        </div>
        <template v-else>
          <div class="section-head">
            <div>
              <span class="eyebrow">REGISTRATION DATABASE</span>
              <h2>Data Peserta</h2>
            </div>
            <div class="head-actions">
              <button class="outline" @click="logout"><LogOut :size="15" /> Logout</button><button class="primary" @click="openRegistration()"><Plus :size="17" /> Pendaftaran</button>
            </div>
          </div>
          <div class="toolbar">
            <div class="search"><Search :size="18" /><input v-model="search" @input="resetPage" placeholder="Cari nama, HP, kelompok, atau lomba..." /></div>
            <div class="data-actions">
              <button class="outline" @click="exportJSON"><Download :size="16" /> Export JSON</button
              ><label class="outline file-btn"><Upload :size="16" /> Import JSON<input type="file" accept=".json,application/json" @change="importJSON" /></label>
            </div>
          </div>
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>Nama</th>
                  <th>No. HP</th>
                  <th>Kelompok</th>
                  <th>Lomba</th>
                  <th>Usia</th>
                  <th>Waktu Daftar</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr v-if="participantLoading">
                  <td colspan="8" class="empty">Memuat peserta...</td>
                </tr>
                <tr v-for="(p, i) in participantRows" :key="p.id">
                  <td>{{ (participantPage - 1) * pageSize + i + 1 }}</td>
                  <td>
                    <b>{{ p.name }}</b>
                  </td>
                  <td>{{ p.phone }}</td>
                  <td>{{ p.group }}</td>
                  <td>{{ p.events?.name || getEvent(p.eventId)?.name || '-' }}</td>
                  <td>{{ p.age || '-' }}</td>
                  <td>{{ new Date(p.registeredAt).toLocaleString('id-ID') }}</td>
                  <td>
                    <button class="icon-btn danger-text" @click="deleteParticipant(p)"><Trash2 :size="16" /></button>
                  </td>
                </tr>
                <tr v-if="!participantLoading && !participantRows.length">
                  <td colspan="8" class="empty">Belum ada peserta.</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="pagination">
            <span>{{ totalParticipants }} peserta • 20 data per halaman</span>
            <div>
              <button class="icon-btn" :disabled="participantPage === 1 || participantLoading" @click="previousPage"><ChevronLeft /></button><b>Halaman {{ participantPage }} / {{ totalPages }}</b
              ><button class="icon-btn" :disabled="participantPage === totalPages || participantLoading" @click="nextPage"><ChevronRight /></button>
            </div>
          </div>
        </template>
      </section>

      <section v-if="activeTab === 'organizers'" class="tab-fade">
        <div class="section-head">
          <div>
            <span class="eyebrow">TEAM</span>
            <h2>Pengurus</h2>
          </div>
        </div>
        <div class="people-grid">
          <div v-for="p in organizers" :key="p.id" class="person-card">
            <div class="avatar">{{ p.name.charAt(0) }}</div>
            <div>
              <h3>{{ p.name }}</h3>
              <p>{{ p.role }}</p>
              <small>{{ p.phone }}</small>
            </div>
          </div>
        </div>
      </section>
      <section v-if="activeTab === 'members'" class="tab-fade">
        <div class="section-head">
          <div>
            <span class="eyebrow">COMMUNITY</span>
            <h2>Daftar Anggota</h2>
          </div>
        </div>
        <div class="people-grid">
          <div v-for="p in members" :key="p.id" class="person-card">
            <div class="avatar">{{ p.name.charAt(0) }}</div>
            <div>
              <h3>{{ p.name }}</h3>
              <p>{{ p.group }}</p>
              <small>{{ p.phone }}</small>
            </div>
          </div>
        </div>
      </section>
    </main>

    <footer>
      <div class="container footer-main">
        <div><b>MERDEKA INDONESIA</b><span>Sistem Pendaftaran Lomba 17 Agustus 2026, Kp. Anggrek Tegalwaru Rt 02 Rw 05 Desa Tegalwaru Ciampea Bogor</span></div>
        <div class="footer-credit">
          <span>Dibuat oleh <strong>Trisna Nadi Selamet</strong></span>
          <span class="footer-badge">Responsive</span>
          <span class="footer-badge">Modern Web</span>
        </div>
      </div>
    </footer>

    <Transition name="modal-fade">
      <div v-if="showRegistration" class="modal-backdrop" @click.self="showRegistration = false">
        <form class="modal" @submit.prevent="submitRegistration">
          <button type="button" class="close" @click="showRegistration = false"><X /></button><span class="eyebrow">FORM PENDAFTARAN</span>
          <h2>Daftar Perlombaan</h2>
          <label>Nama Lengkap<input v-model="registration.name" required maxlength="80" placeholder="Nama peserta" /></label
          ><label>No. HP<input v-model="registration.phone" required maxlength="20" inputmode="tel" placeholder="08xxxxxxxxxx" /></label>
          <div class="two">
            <label>Kelompok/RT<input v-model="registration.group" maxlength="50" placeholder="RT 01" /></label><label>Usia<input v-model="registration.age" type="number" min="1" max="120" /></label>
          </div>
          <label
            >Lomba<select v-model="registration.eventId" required>
              <option v-for="e in events" :value="e.id" :key="e.id" :disabled="e.status !== 'open' || (eventCounts[e.id] || 0) >= e.quota">{{ e.name }} — {{ formatDate(e.date) }} {{ e.status !== 'open' ? '(Ditutup)' : '' }}</option>
            </select></label
          >
          <label>Alamat<textarea v-model="registration.address" maxlength="200" rows="2"></textarea></label
          ><button class="primary full" type="submit" :disabled="authLoading"><CheckCircle2 :size="17" /> {{ authLoading ? 'Menyimpan...' : 'Simpan Pendaftaran' }}</button>
        </form>
      </div>
    </Transition>

    <Transition name="modal-fade">
      <div v-if="showEventForm" class="modal-backdrop" @click.self="showEventForm = false">
        <form class="modal" @submit.prevent="saveEvent">
          <button type="button" class="close" @click="showEventForm = false"><X /></button><span class="eyebrow">MANAGEMENT LOMBA</span>
          <h2>{{ editingEvent ? 'Edit' : 'Tambah' }} Perlombaan</h2>
          <label>Nama Lomba<input v-model="eventForm.name" required maxlength="80" /></label>
          <div class="two">
            <label
              >Kategori<select v-model="eventForm.category">
                <option>Anak-anak</option>
                <option>Remaja</option>
                <option>Dewasa</option>
                <option>Keluarga</option>
                <option>Umum</option>
              </select></label
            ><label>Kuota<input v-model="eventForm.quota" type="number" min="1" max="10000" /></label>
          </div>
          <div class="two">
            <label>Tanggal<input v-model="eventForm.date" type="date" required /></label><label>Jam Mulai<input v-model="eventForm.startTime" type="time" required /></label>
          </div>
          <label>Nama Lokasi<input v-model="eventForm.location" required maxlength="100" placeholder="Lapangan Utama" /></label
          ><label>Alamat Lengkap Perlombaan<input v-model="eventForm.address" required maxlength="180" placeholder="Jl. Kemerdekaan No. 17, Kelurahan..." /></label
          ><label
            >Status<select v-model="eventForm.status">
              <option value="open">Dibuka</option>
              <option value="closed">Ditutup</option>
            </select></label
          ><button class="primary full" type="submit">Simpan Lomba</button>
        </form>
      </div>
    </Transition>

    <Transition name="modal-fade">
      <div v-if="showLogin" class="modal-backdrop" @click.self="showLogin = false">
        <form class="modal login-modal" @submit.prevent="login">
          <button type="button" class="close" @click="showLogin = false"><X /></button><span class="eyebrow">PANITIA</span>
          <h2>Login Admin</h2>
          <p class="modal-note">Akun admin dibuat Khusus Dengan Methode Authentication. Data peserta tidak dibuka untuk pengunjung umum.</p>
          <label>Email<input v-model="loginForm.email" type="email" autocomplete="email" required placeholder="admin@email.com" /></label
          ><label>Password<input v-model="loginForm.password" type="password" autocomplete="current-password" required /></label
          ><button class="primary full" type="submit" :disabled="authLoading"><LogIn :size="16" /> {{ authLoading ? 'Login...' : 'Login Admin' }}</button>
        </form>
      </div>
    </Transition>

    <Transition name="toast-pop">
      <div v-if="toast" class="toast">{{ toast }}</div>
    </Transition>
  </div>
</template>

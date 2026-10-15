/* public-health-quiz client-side app (Vanilla JS, no build step) */

const CFG = window.QUIZ_CONFIG || {};
const SUPABASE_URL = CFG.url || '';
const SUPABASE_KEY = CFG.key || '';
const BATCH_SIZE = 500;
const DRAFT_CHUNK = 50;

// State
let supabase = null;
let currentTab = 'play';
let activeQuiz = null;
let activeQuestions = [];
let currentIndex = 0;
let userAnswers = []; // { question_id, chosen_index, is_correct, answered_at }
let quizStartTime = null;
let timerInterval = null;

// Init
window.addEventListener('DOMContentLoaded', async () => {
  if (window.supabase && SUPABASE_URL && SUPABASE_KEY) {
    supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
  }
  setupRouting();
  setupTheme();
  setupAdminTabs();
  setupAdminForms();
  await loadLeaderboardFilters();
  navigate(getRoute());
});

function getRoute() {
  const hash = window.location.hash.replace('#', '') || 'play';
  return hash;
}

function setRoute(r) {
  window.location.hash = r;
}

function setupRouting() {
  window.addEventListener('hashchange', () => {
    navigate(getRoute());
  });
  document.querySelectorAll('nav a[data-route]').forEach(a => {
    a.addEventListener('click', (e) => {
      e.preventDefault();
      setRoute(a.getAttribute('data-route'));
    });
  });
}

function navigate(route) {
  currentTab = route;
  document.querySelectorAll('nav a').forEach(a => {
    a.classList.toggle('active', a.getAttribute('data-route') === route);
  });
  document.querySelectorAll('.tab-view').forEach(v => v.classList.remove('active'));

  const view = document.getElementById(`view-${route}`) || document.getElementById('view-play');
  if (view) view.classList.add('active');

  clearInterval(timerInterval);

  if (route === 'play') renderCatalog();
  else if (route === 'leaderboard') renderLeaderboard();
  else if (route === 'admin') renderAdmin();
  else if (route.startsWith('quiz/')) {
    const quizId = route.split('/')[1];
    startQuiz(quizId);
  }
}

function setupTheme() {
  const btn = document.getElementById('theme-toggle');
  const saved = localStorage.getItem('phq_theme') || 'dark';
  document.documentElement.setAttribute('data-theme', saved);
  btn?.addEventListener('click', () => {
    const cur = document.documentElement.getAttribute('data-theme');
    const next = cur === 'light' ? 'dark' : 'light';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('phq_theme', next);
  });
}

// ---------------- Catalog ----------------
async function renderCatalog() {
  const grid = document.getElementById('catalog-grid');
  const searchInput = document.getElementById('catalog-search');
  const themeSelect = document.getElementById('catalog-theme-filter');
  const dailyBox = document.getElementById('daily-quiz-box');
  if (!grid) return;

  grid.innerHTML = '<div class="catalog

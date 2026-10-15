/* public-health-quiz frontend - zero dependencies, plain ES */
(function() {
  'use strict';

  const cfg = window.QUIZ_CONFIG || {};
  let currentQuiz = null;
  let currentQuestions = [];
  let currentIndex = 0;
  let score = 0;
  let startTime = 0;
  let userAnswers = [];

  function $(id) { return document.getElementById(id); }

  async function api(path, opts) {
    const res = await fetch(path, opts);
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: res.statusText }));
      throw new Error(err.error || res.statusText);
    }
    return res.json();
  }

  function showView(viewId) {
    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
    const target = $(viewId);
    if (target) target.classList.add('active');
    window.scrollTo(0, 0);
  }

  async function loadCatalog() {
    showView('view-catalog');
    const list = $('quiz-list');
    if (!list) return;
    list.innerHTML = '<div class="loading">იტვირთება...</div>';

    try {
      const quizzes = await api('/api/quizzes');
      if (!quizzes || !quizzes.length) {
        list.innerHTML = '<div class="empty">ქუიზები ჯერ არ არის დამატებული.</div>';
        return;
      }

      list.innerHTML = '';
      quizzes.forEach(q => {
        const card = document.createElement('div');
        card.className = 'quiz-card';
        card.innerHTML = `
          <div class="quiz-theme">${q.theme || ''}</div>
          <h3 class="quiz-title">${q.title}</h3>
          <div class="quiz-meta">${q.question_count || 15} კითხვა</div>
          <button class="btn btn-primary start-btn">დაწყება →</button>
        `;
        card.querySelector('.start-btn').addEventListener('click', () => startQuiz(q.id));
        list.appendChild(card);
      });
    } catch (e) {
      list.innerHTML = `<div class="error">შეცდომა: ${e.message}</div>`;
    }
  }

  async function startQuiz(quizId) {
    try {
      const data = await api(`/api/quizzes/${quizId}`);
      currentQuiz = data.quiz;
      currentQuestions = data.questions || [];

      if (!currentQuestions.length) {
        alert('ქუიზში კითხვები ვერ მოიძებნა!');
        return;
      }

      currentIndex = 0;
      score = 0;
      userAnswers = [];
      startTime = Date.now();

      showView('view-play');
      renderQuestion();
    } catch (e) {
      alert('ვერ ჩაიტვირთა ქუიზი: ' + e.message);
    }
  }

  function renderQuestion() {
    const q = currentQuestions[currentIndex];
    const total = currentQuestions.length;

    $('play-theme').textContent = currentQuiz.theme \vert{}\vert{} '';$('play-counter').textContent = `კითხვა ${currentIndex + 1} / ${total}`;
    $('play-prompt').textContent = q.prompt;

    const optContainer = $('play-options');
    optContainer.innerHTML = '';

    q.options.forEach((opt, idx) => {
      const btn = document.createElement('button');
      btn.className = 'option-btn';
      btn.textContent = opt;
      btn.addEventListener('click', () => handleAnswer(idx));
      optContainer.appendChild(btn);
    });

    $('play-explanation').style.display = 'none';$('play-next-btn').style.display = 'none';
  }

  function handleAnswer(choiceIdx) {
    const q = currentQuestions[currentIndex];
    const isCorrect = Number(choiceIdx) === Number(q.answer_index);
    if (isCorrect) score += 100;

    userAnswers.push({ question_id: q.id, choice: choiceIdx, isCorrect });

    const buttons = $('play-options').querySelectorAll('.option-btn');
    buttons.forEach((b, idx) => {
      b.disabled = true;
      if (idx === Number(q.answer_index)) b.classList.add('correct');
      if (idx === Number(choiceIdx) && !isCorrect) b.classList.add('incorrect');
    });

    const exp = $('play-explanation');
    exp.innerHTML = `
      <div class="exp-title">${isCorrect ? 'სწორია!' : 'არასწორია!'}</div>
      <div class="exp-text">${q.explanation || ''}</div>
      ${q.source_url ? `<a class="exp-link" href="${q.source_url}" target="_blank" rel="noopener">წყარო: ${q.source_title || 'გადასვლა'}</a>` : ''}
    `;
    exp.style.display = 'block';

    const nextBtn = $('play-next-btn');
    nextBtn.style.display = 'block';
    nextBtn.textContent = (currentIndex + 1 < currentQuestions.length) ? 'შემდეგი კითხვა →' : 'შედეგის ნახვა →';
  }

  $('play-next-btn')?.addEventListener('click', () => {
    currentIndex++;
    if (currentIndex < currentQuestions.length) {
      renderQuestion();
    } else {
      finishQuiz();
    }
  });

  function finishQuiz() {
    showView('view-result');
    const totalPossible = currentQuestions.length * 100;
    $('result-score').textContent = score;
    $('result-total').textContent = `${totalPossible} შესაძლო ქულიდან`;
  }

  // Navigation tabs
  $('nav-play')?.addEventListener('click', () => loadCatalog());
  $('nav-home')?.addEventListener('click', () => loadCatalog());$('result-home-btn')?.addEventListener('click', () => loadCatalog());

  // Init
  loadCatalog();
})();

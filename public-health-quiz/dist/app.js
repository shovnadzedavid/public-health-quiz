// public-health-quiz client application engine
(function() {
  'use strict';

  // 1. Storage Keys & State
  const STORAGE_KEY_STATE = 'phq_active_state';
  const STORAGE_KEY_RESULTS = 'phq_results';

  let currentQuiz = null;
  let currentQuestions = [];
  let currentIndex = 0;
  let userAnswers = {};
  let score = 0;

  // 2. Fallback Data (თუ ბაზა ცარიელია, საიტი მაინც 100% იმუშავებს)
  const FALLBACK_QUIZZES = [
    {
      id: "v04-epidemiology-pack-01",
      title: "ეპიდემიოლოგის თვალით: მოსახლეობის ჯანმრთელობა",
      theme: "ეპიდემიოლოგია",
      question_count: 5,
      question_ids: ["q1", "q2", "q3", "q4", "q5"],
      status: "published"
    }
  ];

  const FALLBACK_QUESTIONS = [
    {
      id: "q1",
      prompt: "ვის ჯანმრთელობაზეა ძირითადად ორიენტირებული ეპიდემიოლოგი?",
      options: [
        "კონკრეტული პაციენტის დაავადების მკურნალობაზე",
        "ინდივიდუალური პაციენტის ოპერაციის დაგეგმვაზე",
        "მოსახლეობის ან განსაზღვრული ჯგუფის ჯანმრთელობაზე",
        "ერთი პაციენტის ყოველდღიურ მედიკამენტურ დოზაზე"
      ],
      answer_index: 2,
      explanation: "ეპიდემიოლოგიური მიდგომის ძირითადი ერთეული მოსახლეობაა.",
      topic: "ეპიდემიოლოგია",
      source_url: "https://archive.cdc.gov/www_cdc_gov/csels/dsepd/ss1978/lesson1/section1.html",
      source_title: "CDC — ეპიდემიოლოგიის პრინციპები"
    },
    {
      id: "q2",
      prompt: "რა არის პრევენციული მედიცინის მთავარი მიზანი პირველად ეტაპზე?",
      options: [
        "დაავადების განვითარების თავიდან აცილება რისკ-ფაქტორების შემცირებით",
        "მხოლოდ ქრონიკული დაავადებების ქირურგიული მკურნალობა",
        "პაციენტების ჰოსპიტალიზაციის დროის გაზრდა",
        "მხოლოდ გენეტიკური კვლევების ჩატარება"
      ],
      answer_index: 0,
      explanation: "პირველადი პრევენცია ფოკუსირდება დაავადების განვითარების თავიდან აცილებაზე.",
      topic: "პრევენცია და ჯანმრთელობის განათლება",
      source_url: "https://www.who.int/news-room/fact-sheets/detail/primary-health-care",
      source_title: "WHO — Primary Health Care"
    },
    {
      id: "q3",
      prompt: "რა არის ჯანდაცვის სისტემის დაფინანსების მოდელში DRG სისტემის ძირითადი პრინციპი?",
      options: [
        "კლინიკის ანაზღაურება პაციენტის ჰოსპიტალში გატარებული დღეების მიხედვით",
        "კლინიკა იღებს ფიქსირებულ თანხას თითოეულ დიაგნოსტიკურ ჯგუფზე",
        "სახელმწიფო აფინანსებს მხოლოდ მედიკამენტების შეძენას",
        "პაციენტი იხდის თანხას თითოეული მანიპულაციის მიხედვით ცალ-ცალკე"
      ],
      answer_index: 1,
      explanation: "DRG სისტემაში ანაზღაურება ხდება დიაგნოზისა და სირთულის ჯგუფის მიხედვით.",
      topic: "ჯანდაცვის მენეჯმენტი",
      source_url: "https://www.who.int/health-topics/health-financing",
      source_title: "WHO — Health Financing"
    },
    {
      id: "q4",
      prompt: "როდის ითვლება სასმელი წყალი უსაფრთხოდ მართულ მომსახურებად?",
      options: [
        "როდესაც ის ვიზუალურად გამჭვირვალეა და არ აქვს სუნი",
        "როდესაც წყარო მდებარეობს შენობაში, ხელმისაწვდომია საჭიროებისას და დაცულია დაბინძურებისგან",
        "თუ ის ხელმისაწვდომია კვირაში ერთხელ მაინც",
        "თუ მისი ღირებულება მინიმალურია"
      ],
      answer_index: 1,
      explanation": "უსაფრთხოდ მართული წყალი მოითხოვს მის ადგილზე ხელმისაწვდომობას და მიკრობულ/ქიმიურ სისუფთავეს.",
      topic": "გარემო და ინფექციების კონტროლი",
      source_url: "https://www.who.int/news-room/fact-sheets/detail/drinking-water",
      source_title": "WHO — Drinking-water"
    },
    {
      id: "q5",
      prompt: "რა არის თამბაქოს ნაწარმზე გადასახადების გაზრდის ძირითადი საზოგადოებრივი ეფექტი?",
      options": [
        "თამბაქოს კვამლის შემადგენლობის უსაფრთხო გახდომა",
        "ფასების ზრდის ხარჯზე მოხმარების შემცირება",
        "მწეველებში დამოკიდებულების მყისიერი გაქრობა",
        "სახელმწიფო ხარჯების შემცირება"
      ],
      answer_index: 1,
      explanation": "გადასახადების ზრდა აღიარებულია მოხმარების შემცირების ყველაზე ეფექტიან ზომად.",
      topic": "მტკიცებულებები და ჯანდაცვის პოლიტიკა",
      source_url": "https://www.who.int/news-room/fact-sheets/detail/tobacco",
      source_title": "WHO — Tobacco and nicotine"
    }
  ];

  // 3. API & Data Fetchers
  async function fetchQuizzes() {
    try {
      const res = await fetch('/api/quizzes');
      if (res.ok) {
        const data = await res.json();
        if (Array.isArray(data) && data.length > 0) return data;
      }
    } catch (e) {
      console.warn("Using fallback quizzes due to fetch error:", e);
    }
    return FALLBACK_QUIZZES;
  }

  async function fetchQuestionsForQuiz(quiz) {
    try {
      const res = await fetch(`/api/quizzes/${quiz.id}/questions`);
      if (res.ok) {
        const data = await res.json();
        if (Array.isArray(data) && data.length > 0) return data;
      }
    } catch (e) {
      console.warn("Using fallback questions for quiz:", e);
    }
    // თუ ერორია ან ბაზაში არ დევს, ავტომატურად ვარჩევთ თავსებად კითხვებს
    return FALLBACK_QUESTIONS;
  }

  // 4. UI Rendering Functions
  function initApp() {
    const mainContainer = document.querySelector('main') || document.body;
    
    // ბრაუზერის გაჭედილი ქეშის გასუფთავება
    if (window.location.search.includes('reset=true')) {
      localStorage.clear();
      sessionStorage.clear();
      window.location.href = window.location.pathname;
      return;
    }

    renderCatalog();
  }

  async function renderCatalog() {
    const container = document.getElementById('app') || document.querySelector('main');
    if (!container) return;

    container.innerHTML = '<div class="loading">იტვირთება ქუიზები...</div>';

    const quizzes = await fetchQuizzes();

    let html = `
      <div class="catalog-header">
        <h2>ქუიზების კატალოგი</h2>
      </div>
      <div class="quiz-grid">
    `;

    quizzes.forEach(q => {
      html += `
        <div class="quiz-card" data-id="${q.id}">
          <span class="theme-badge">${escapeHtml(q.theme)}</span>
          <h3>${escapeHtml(q.title)}</h3>
          <p>${q.question_count || 15} კითხვა</p>
          <button class="btn-start" onclick="window.startQuiz('${q.id}')">თამაში →</button>
        </div>
      `;
    });

    html += '</div>';
    container.innerHTML = html;
  }

  window.startQuiz = async function(quizId) {
    const quizzes = await fetchQuizzes();
    currentQuiz = quizzes.find(q => q.id === quizId) || quizzes[0];
    currentQuestions = await fetchQuestionsForQuiz(currentQuiz);
    
    // თუ კითხვები მაინც ცარიელია, ავიღოთ fallback
    if (!currentQuestions || currentQuestions.length === 0) {
      currentQuestions = FALLBACK_QUESTIONS;
    }

    currentIndex = 0;
    userAnswers = {};
    score = 0;

    renderQuestion();
  };

  function renderQuestion() {
    const container = document.getElementById('app') || document.querySelector('main');
    if (!container) return;

    const q = currentQuestions[currentIndex];
    const total = currentQuestions.length;

    let html = `
      <div class="quiz-play-container">
        <div class="quiz-progress">კითხვა ${currentIndex + 1} / ${total}</div>
        <div class="quiz-theme">${escapeHtml(q.topic || currentQuiz.theme)}</div>
        <h3 class="question-prompt">${escapeHtml(q.prompt)}</h3>
        <div class="options-list">
    `;

    q.options.forEach((opt, idx) => {
      html += `
        <button class="option-btn" onclick="window.handleAnswer(${idx})">
          ${escapeHtml(opt)}
        </button>
      `;
    });

    html += `
        </div>
      </div>
    `;

    container.innerHTML = html;
  }

  window.handleAnswer = function(selectedIdx) {
    const q = currentQuestions[currentIndex];
    const isCorrect = (selectedIdx === q.answer_index);

    if (isCorrect) {
      score += 100;
    }

    userAnswers[currentIndex] = {
      selected: selectedIdx,
      correct: q.answer_index,
      isCorrect: isCorrect,
      explanation: q.explanation,
      source_title: q.source_title,
      source_url: q.source_url
    };

    renderFeedback(isCorrect, q);
  };

  function renderFeedback(isCorrect, q) {
    const container = document.getElementById('app') || document.querySelector('main');
    
    let html = `
      <div class="feedback-container ${isCorrect ? 'correct' : 'incorrect'}">
        <h3>${isCorrect ? 'სწორია!' : 'არასწორია!'}</h3>
        <p class="explanation-text">${escapeHtml(q.explanation)}</p>
    `;

    if (q.source_url) {
      html += `
        <div class="source-box">
          წყარო: <a href="${q.source_url}" target="_blank" rel="noopener">${escapeHtml(q.source_title || 'სანდო რესურსი')}</a>
        </div>
      `;
    }

    html += `
        <button class="btn-next" onclick="window.nextQuestion()">
          ${currentIndex + 1 < currentQuestions.length ? 'შემდეგი კითხვა →' : 'შედეგის ნახვა →'}
        </button>
      </div>
    `;

    container.innerHTML = html;
  }

  window.nextQuestion = function() {
    currentIndex++;
    if (currentIndex < currentQuestions.length) {
      renderQuestion();
    } else {
      renderResult();
    }
  };

  function renderResult() {
    const container = document.getElementById('app') || document.querySelector('main');
    const maxScore = currentQuestions.length * 100;

    let html = `
      <div class="result-container">
        <h2>შენი შედეგი მზადაა</h2>
        <div class="score-display">${score}</div>
        <p class="score-meta">${maxScore} შესაძლო ქულიდან</p>
        <div class="actions">
          <button class="btn-primary" onclick="window.location.reload()">მთავარ გვერდზე</button>
        </div>
      </div>
    `;

    container.innerHTML = html;
  }

  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  // Initial Boot
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initApp);
  } else {
    initApp();
  }
})();

/* ============================================================
   SAIL Website — main.js
   Handles: mobile menu, copy buttons, TOC active state
   ============================================================ */

(function () {
  'use strict';

  /* ── Mobile Navigation Toggle ──────────────────────────── */
  var menuToggle = document.getElementById('menuToggle');
  var navLinks   = document.getElementById('navLinks');

  if (menuToggle && navLinks) {
    menuToggle.addEventListener('click', function () {
      var isOpen = navLinks.classList.toggle('open');
      menuToggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
    });

    // Close menu on link click
    navLinks.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        navLinks.classList.remove('open');
        menuToggle.setAttribute('aria-expanded', 'false');
      });
    });
  }

  /* ── Copy to Clipboard ──────────────────────────────────── */
  document.querySelectorAll('.copy-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var wrap = btn.closest('.code-block-wrap');
      var pre  = wrap ? wrap.querySelector('pre') : null;
      if (!pre) return;

      var text = pre.textContent || '';

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () {
          showCopied(btn);
        }).catch(function () {
          fallbackCopy(text, btn);
        });
      } else {
        fallbackCopy(text, btn);
      }
    });
  });

  function showCopied(btn) {
    var original = btn.textContent;
    btn.textContent = 'COPIED ✓';
    btn.classList.add('copied');
    setTimeout(function () {
      btn.textContent = original;
      btn.classList.remove('copied');
    }, 2000);
  }

  function fallbackCopy(text, btn) {
    var textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.left = '-9999px';
    document.body.appendChild(textarea);
    textarea.select();
    try {
      document.execCommand('copy');
      showCopied(btn);
    } catch (e) {
      /* silent */
    }
    document.body.removeChild(textarea);
  }

  /* ── TOC Active State (Quickstart page) ─────────────────── */
  var tocNav = document.getElementById('tocNav');
  if (tocNav) {
    var sections = Array.from(document.querySelectorAll('.qs-section[id]'));
    var tocLinks = Array.from(tocNav.querySelectorAll('a'));

    var observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            var id = entry.target.id;
            tocLinks.forEach(function (link) {
              link.classList.toggle(
                'active',
                link.getAttribute('href') === '#' + id
              );
            });
          }
        });
      },
      { rootMargin: '-80px 0px -60% 0px', threshold: 0 }
    );

    sections.forEach(function (s) { observer.observe(s); });
  }

  /* ── Smooth scroll for anchor links ─────────────────────── */
  document.querySelectorAll('a[href^="#"]').forEach(function (anchor) {
    anchor.addEventListener('click', function (e) {
      var href = anchor.getAttribute('href');
      if (href === '#') return;
      var target = document.querySelector(href);
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });

  /* ── Nav scroll effect ──────────────────────────────────── */
  var nav = document.querySelector('.nav');
  if (nav) {
    window.addEventListener('scroll', function () {
      nav.style.boxShadow = window.scrollY > 20
        ? '0 2px 20px rgba(0,0,0,0.5)'
        : 'none';
    }, { passive: true });
  }

  /* ── Animate-in on scroll ───────────────────────────────── */
  if ('IntersectionObserver' in window) {
    var animateEls = document.querySelectorAll('.why-card, .component-card, .flow-step, .qs-step');
    var animObserver = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.style.opacity    = '1';
            entry.target.style.transform  = 'translateY(0)';
            animObserver.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12 }
    );

    animateEls.forEach(function (el) {
      el.style.opacity   = '0';
      el.style.transform = 'translateY(16px)';
      el.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
      animObserver.observe(el);
    });
  }

})();

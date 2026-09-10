// Interactive notch: expand on hover (desktop) or tap (touch).
const notch = document.getElementById("notch");
let collapseTimer;
notch.addEventListener("mouseenter", () => {
  clearTimeout(collapseTimer);
  notch.classList.add("open");
});
notch.addEventListener("mouseleave", () => {
  collapseTimer = setTimeout(() => notch.classList.remove("open"), 250);
});
notch.addEventListener("click", () => notch.classList.toggle("open"));

// Demo video: if none of the sources can play, show the placeholder. Listen on
// the LAST source only — the browser walks the list in order, so an error on
// the first (WebM) just means it is moving on to the MP4 fallback.
const video = document.getElementById("demoVideo");
const placeholder = document.getElementById("demoPlaceholder");
const sources = [...video.querySelectorAll("source")];
sources[sources.length - 1].addEventListener("error", () => {
  video.style.display = "none";
  placeholder.classList.add("show");
});

// Scroll reveal: IntersectionObserver, plus a manual sweep fallback so
// sections never stay invisible in browsers where the observer misses
// programmatic scrolls.
const revealEls = [...document.querySelectorAll(".reveal")];
function sweepReveals() {
  const vh = Math.max(innerHeight, document.documentElement.clientHeight);
  for (const el of revealEls) {
    if (!el.classList.contains("in") &&
        (vh <= 0 || el.getBoundingClientRect().top < vh * 0.92)) {
      el.classList.add("in");
    }
  }
}
const observer = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add("in");
        observer.unobserve(entry.target);
      }
    }
  },
  { threshold: 0.15 }
);
revealEls.forEach((el) => observer.observe(el));
addEventListener("scroll", sweepReveals, { passive: true });
addEventListener("resize", sweepReveals);
sweepReveals();

document.getElementById("year").textContent = new Date().getFullYear();

/* ---------- Feature-card clips ----------
   Each card's clip plays on hover and rewinds when the pointer leaves, so the
   grid is still at rest and only the card you are on is moving. Ten clips
   playing at once would be noise, not a demo.

   Nothing is fetched until it is needed: the markup carries `preload="none"`,
   so the page loads ten poster images and no video at all.

   Touch devices have no hover, so there a clip plays while its card is the one
   in view. */
(() => {
  const cards = [...document.querySelectorAll(".card-clip")];
  if (!cards.length) return;

  const stillPreferred = matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (stillPreferred) return;   // the poster is the whole experience

  const play = (video) => {
    // Safari rejects play() on a video whose source has not loaded yet; the
    // rejection is expected and means the next hover will succeed.
    const p = video.play();
    if (p) p.catch(() => {});
  };
  const stop = (video) => {
    video.pause();
    video.currentTime = 0;
  };

  const hoverCapable = matchMedia("(hover: hover)").matches;

  for (const box of cards) {
    const video = box.querySelector("video");
    if (!video) continue;

    if (hoverCapable) {
      const card = box.closest(".card") || box;
      card.addEventListener("pointerenter", () => play(video));
      card.addEventListener("pointerleave", () => stop(video));
    }
  }

  if (!hoverCapable) {
    // One at a time, whichever card is most centred.
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          const video = e.target.querySelector("video");
          if (!video) continue;
          e.isIntersecting ? play(video) : stop(video);
        }
      },
      { threshold: 0.65 }
    );
    cards.forEach((c) => io.observe(c));
  }
})();

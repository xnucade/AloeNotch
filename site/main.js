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

// Demo video: if assets/demo.mp4 isn't there yet, show the placeholder.
const video = document.getElementById("demoVideo");
const placeholder = document.getElementById("demoPlaceholder");
video.querySelector("source").addEventListener("error", () => {
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

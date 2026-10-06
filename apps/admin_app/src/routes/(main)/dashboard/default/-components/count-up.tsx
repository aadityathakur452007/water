import { useEffect, useRef, useState } from "react";

/** Phase 9 §9.1: cheap KPI count-up. Animates value *changes* (fresh data
 * landing on refetch) over 500ms via rAF — mount renders the final number
 * immediately (SSR-safe, no hydration flash). Collapses to instant under
 * `prefers-reduced-motion`. Numbers only: pass raw paise/counts + the same
 * `rupees`/`num` formatter the static render used. */
export function CountUp({
  value,
  format,
}: {
  value: number;
  format: (n: number) => string;
}) {
  const [display, setDisplay] = useState(value);
  const prev = useRef(value);

  useEffect(() => {
    const from = prev.current;
    prev.current = value;
    if (from === value) return;
    if (
      typeof window === "undefined" ||
      window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches
    ) {
      setDisplay(value);
      return;
    }
    let raf = 0;
    const start = performance.now();
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / 500);
      setDisplay(Math.round(from + (value - from) * t));
      if (t < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [value]);

  return <>{format(display)}</>;
}

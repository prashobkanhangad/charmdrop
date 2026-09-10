export type CharmId = "nimbu-mirchi" | "nazar" | "bell" | "diya";

type Point = {
  x: number;
  y: number;
  px: number;
  py: number;
  pinned: boolean;
};

export type CharmStageHandle = {
  setCharm: (id: CharmId) => void;
  destroy: () => void;
};

const CHARMS: CharmId[] = ["nimbu-mirchi", "nazar", "bell", "diya"];

export function mountCharmStage(
  canvas: HTMLCanvasElement,
  initial: CharmId = "nimbu-mirchi",
): CharmStageHandle {
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const ctx = canvas.getContext("2d");
  if (!ctx) {
    return { setCharm() {}, destroy() {} };
  }

  const points: Point[] = [];
  const segmentCount = 14;
  let charm: CharmId = initial;
  let variant = 0;
  let lit = false;
  let glow = 0;
  let scale = 1;
  let flame = 0;
  let dragging = false;
  let grabX = 0;
  let grabY = 0;
  let lastX = 0;
  let lastY = 0;
  let lastT = 0;
  let velX = 0;
  let velY = 0;
  let frame = 0;
  let running = true;
  let width = 0;
  let height = 0;
  let dpr = 1;
  let audio: AudioContext | null = null;

  const resize = () => {
    const rect = canvas.getBoundingClientRect();
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    width = rect.width;
    height = rect.height;
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    resetRope(false);
  };

  const anchorX = () => (width < 840 ? width * 0.5 : width * 0.72);
  const ropeLength = () => Math.min(height * 0.42, 280);

  const resetRope = (keepCharm = true) => {
    const ax = anchorX();
    const spacing = ropeLength() / (segmentCount - 1);
    points.length = 0;
    for (let i = 0; i < segmentCount; i++) {
      const y = spacing * i;
      points.push({ x: ax, y, px: ax, py: y, pinned: i === 0 });
    }
    if (!keepCharm) {
      variant = 0;
      lit = false;
      glow = 0;
    }
  };

  const step = () => {
    if (reduced && !dragging) return;

    const gravity = 1800;
    const dt = 1 / 60;
    const damping = 0.986;

    for (const point of points) {
      if (point.pinned) {
        point.x = anchorX();
        point.y = 0;
        point.px = point.x;
        point.py = point.y;
        continue;
      }
      const vx = (point.x - point.px) * damping;
      const vy = (point.y - point.py) * damping;
      point.px = point.x;
      point.py = point.y;
      point.x += vx;
      point.y += vy + gravity * dt * dt;
    }

    if (dragging) {
      const last = points[points.length - 1];
      last.x = grabX;
      last.y = grabY;
      last.px = grabX - velX * dt;
      last.py = grabY - velY * dt;
    }

    const rest = ropeLength() / (segmentCount - 1);
    for (let pass = 0; pass < 8; pass++) {
      points[0].x = anchorX();
      points[0].y = 0;
      for (let i = 0; i < points.length - 1; i++) {
        const a = points[i];
        const b = points[i + 1];
        let dx = b.x - a.x;
        let dy = b.y - a.y;
        const dist = Math.hypot(dx, dy) || 0.0001;
        const diff = (dist - rest) / dist;
        const ox = dx * diff * 0.5;
        const oy = dy * diff * 0.5;
        if (!a.pinned) {
          a.x += ox;
          a.y += oy;
        }
        if (!b.pinned) {
          b.x -= ox;
          b.y -= oy;
        }
      }
    }

    const last = points[points.length - 1];
    last.x = clamp(last.x, 36, width - 36);
    last.y = clamp(last.y, 70, height - 24);

    glow *= 0.94;
    scale += (1 - scale) * 0.12;
    if (lit) flame = 0.55 + Math.sin(frame * 0.35) * 0.2 + Math.sin(frame * 0.91) * 0.08;
    else flame *= 0.9;
  };

  const draw = () => {
    ctx.clearRect(0, 0, width, height);
    if (points.length < 2) return;

    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.strokeStyle = "rgba(214, 186, 120, 0.92)";
    ctx.lineWidth = 2.4;
    ctx.beginPath();
    ctx.moveTo(points[0].x, points[0].y);
    for (let i = 1; i < points.length - 1; i++) {
      const midX = (points[i].x + points[i + 1].x) / 2;
      const midY = (points[i].y + points[i + 1].y) / 2;
      ctx.quadraticCurveTo(points[i].x, points[i].y, midX, midY);
    }
    // Run the last segment a few pixels into the charm so the round cap
    // does not leave a hairline between rope and artwork.
    const tip = points[points.length - 1];
    const prev = points[points.length - 2];
    const rdx = tip.x - prev.x;
    const rdy = tip.y - prev.y;
    const rlen = Math.hypot(rdx, rdy) || 1;
    ctx.lineTo(tip.x + (rdx / rlen) * 6, tip.y + (rdy / rlen) * 6);
    ctx.stroke();

    // Canvas Y grows downward. The Mac app is y-up, so the same atan2
    // arguments would rotate every charm 180° and hang them upside down.
    const angle = Math.atan2(tip.x - prev.x, tip.y - prev.y);

    ctx.save();
    ctx.translate(tip.x, tip.y);
    ctx.rotate(angle);
    ctx.scale(scale, scale);
    if (glow > 0.02) {
      ctx.shadowColor = charm === "nazar" ? `rgba(70, 160, 230, ${glow})` : `rgba(255, 190, 70, ${glow})`;
      ctx.shadowBlur = 28 * glow;
    }
    drawCharm(ctx, charm, { variant, flame, lit });
    ctx.restore();
  };

  const loop = () => {
    if (!running) return;
    frame += 1;
    step();
    draw();
    requestAnimationFrame(loop);
  };

  const syncClickThrough = (x: number, y: number) => {
    canvas.style.pointerEvents = dragging || hit(x, y) ? "auto" : "none";
  };

  const eventPoint = (event: PointerEvent) => {
    const rect = canvas.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  };

  const hit = (x: number, y: number) => {
    const tip = points[points.length - 1];
    return Math.hypot(x - tip.x, y - tip.y) < 54;
  };

  const onDown = (event: PointerEvent) => {
    const p = eventPoint(event);
    if (!hit(p.x, p.y)) return;
    dragging = true;
    grabX = p.x;
    grabY = p.y;
    lastX = p.x;
    lastY = p.y;
    lastT = event.timeStamp;
    velX = 0;
    velY = 0;
    canvas.setPointerCapture(event.pointerId);
    canvas.style.cursor = "grabbing";
    event.preventDefault();
  };

  const onMove = (event: PointerEvent) => {
    const p = eventPoint(event);
    syncClickThrough(p.x, p.y);
    canvas.style.cursor = dragging || hit(p.x, p.y) ? "grab" : "default";
    if (!dragging) return;
    const dt = Math.max(0.008, (event.timeStamp - lastT) / 1000);
    velX = (p.x - lastX) / dt;
    velY = (p.y - lastY) / dt;
    grabX = p.x;
    grabY = p.y;
    lastX = p.x;
    lastY = p.y;
    lastT = event.timeStamp;
  };

  const onUp = (_event: PointerEvent) => {
    if (!dragging) return;
    dragging = false;
    canvas.style.cursor = "grab";
    const last = points[points.length - 1];
    const dt = 1 / 60;
    last.px = last.x - clamp(velX, -2200, 2200) * dt * 0.55;
    last.py = last.y - clamp(velY, -2200, 2200) * dt * 0.55;

    const travel = Math.hypot(velX, velY);
    if (travel < 80) performRitual();
  };

  const performRitual = () => {
    scale = 1.16;
    if (charm === "nimbu-mirchi") {
      variant = 1 - variant;
      glow = 0.4;
    } else if (charm === "nazar") {
      glow = 1;
    } else if (charm === "bell") {
      glow = 0.55;
      const last = points[points.length - 1];
      last.px -= 18;
      ringBell();
    } else {
      lit = !lit;
      glow = lit ? 0.8 : 0.2;
    }
  };

  const ringBell = () => {
    try {
      audio ??= new AudioContext();
      const now = audio.currentTime;
      const osc = audio.createOscillator();
      const gain = audio.createGain();
      osc.type = "sine";
      osc.frequency.setValueAtTime(523, now);
      osc.frequency.exponentialRampToValueAtTime(392, now + 0.8);
      gain.gain.setValueAtTime(0.0001, now);
      gain.gain.exponentialRampToValueAtTime(0.09, now + 0.01);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + 1.2);
      osc.connect(gain);
      gain.connect(audio.destination);
      osc.start(now);
      osc.stop(now + 1.25);
    } catch {
      /* audio is optional */
    }
  };

  const onWindowMove = (event: PointerEvent) => {
    const p = eventPoint(event);
    syncClickThrough(p.x, p.y);
    canvas.style.cursor = dragging || hit(p.x, p.y) ? "grab" : "";
  };

  const observer = new ResizeObserver(resize);
  observer.observe(canvas);
  canvas.style.pointerEvents = "none";
  canvas.addEventListener("pointerdown", onDown);
  canvas.addEventListener("pointermove", onMove);
  canvas.addEventListener("pointerup", onUp);
  canvas.addEventListener("pointercancel", onUp);
  canvas.addEventListener("lostpointercapture", onUp);
  window.addEventListener("pointermove", onWindowMove, { passive: true });

  resize();
  if (reduced) {
    draw();
  } else {
    requestAnimationFrame(loop);
  }

  return {
    setCharm(id: CharmId) {
      if (!CHARMS.includes(id)) return;
      charm = id;
      variant = 0;
      lit = id === "diya" ? false : lit;
      glow = 0.35;
      scale = 1.08;
      resetRope(true);
    },
    destroy() {
      running = false;
      observer.disconnect();
      canvas.removeEventListener("pointerdown", onDown);
      canvas.removeEventListener("pointermove", onMove);
      canvas.removeEventListener("pointerup", onUp);
      canvas.removeEventListener("pointercancel", onUp);
      canvas.removeEventListener("lostpointercapture", onUp);
      window.removeEventListener("pointermove", onWindowMove);
    },
  };
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function drawCharm(
  ctx: CanvasRenderingContext2D,
  id: CharmId,
  state: { variant: number; flame: number; lit: boolean },
) {
  if (id === "nazar") return drawNazar(ctx);
  if (id === "bell") return drawBell(ctx);
  if (id === "diya") return drawDiya(ctx, state.lit, state.flame);
  drawNimbu(ctx, state.variant === 1);
}

function joinRope(ctx: CanvasRenderingContext2D, toY: number) {
  ctx.strokeStyle = "rgba(214, 186, 120, 0.92)";
  ctx.lineWidth = 2.4;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(0, -2);
  ctx.lineTo(0, toY);
  ctx.stroke();
}

function drawNimbu(ctx: CanvasRenderingContext2D, fresh: boolean) {
  const light = fresh ? "#84cc60" : "#5a9a54";
  const mid = fresh ? "#3a9642" : "#2f6e3c";
  const dark = fresh ? "#1a4a26" : "#163820";

  joinRope(ctx, 8);

  const pods = [
    { y: 6, len: 34, right: true, tilt: 0.12 },
    { y: 16, len: 40, right: false, tilt: 0.08 },
    { y: 26, len: 44, right: true, tilt: 0.1 },
    { y: 36, len: 40, right: false, tilt: 0.07 },
    { y: 46, len: 34, right: true, tilt: 0.1 },
  ];

  for (const pod of pods) {
    ctx.save();
    ctx.translate(0, pod.y);
    ctx.rotate(pod.right ? pod.tilt : -pod.tilt);
    if (!pod.right) ctx.scale(-1, 1);
    const body = new Path2D();
    body.moveTo(-pod.len, 0);
    body.bezierCurveTo(-pod.len * 0.4, 6.5, pod.len * 0.35, 5, pod.len, 1.5);
    body.bezierCurveTo(pod.len * 0.35, -5, -pod.len * 0.4, -6.5, -pod.len, 0);
    const shade = ctx.createLinearGradient(0, -7, 0, 7);
    shade.addColorStop(0, light);
    shade.addColorStop(0.55, mid);
    shade.addColorStop(1, dark);
    ctx.fillStyle = shade;
    ctx.fill(body);
    ctx.strokeStyle = dark;
    ctx.lineWidth = 1;
    ctx.stroke(body);
    ctx.restore();
  }

  const lemon = ctx.createRadialGradient(-10, 60, 3, 2, 72, 26);
  lemon.addColorStop(0, "#fff8c8");
  lemon.addColorStop(0.35, fresh ? "#ffe34a" : "#e6c84a");
  lemon.addColorStop(1, "#b8860c");
  ctx.fillStyle = lemon;
  ctx.beginPath();
  ctx.arc(0, 72, 23, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = "#8a6408";
  ctx.lineWidth = 1.2;
  ctx.stroke();
}

function drawNazar(ctx: CanvasRenderingContext2D) {
  joinRope(ctx, 2);
  const rings: [number, string][] = [
    [28, "#163f86"],
    [20, "#f4f6fa"],
    [13, "#2e86c1"],
    [6, "#121826"],
  ];
  for (const [r, color] of rings) {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(0, 28, r, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.fillStyle = "rgba(255,255,255,0.55)";
  ctx.beginPath();
  ctx.ellipse(-8, 18, 7, 4, -0.5, 0, Math.PI * 2);
  ctx.fill();
}

function drawBell(ctx: CanvasRenderingContext2D) {
  joinRope(ctx, 4);
  ctx.strokeStyle = "#8c6a22";
  ctx.lineWidth = 2.2;
  ctx.beginPath();
  ctx.arc(0, 6, 5, Math.PI, 0);
  ctx.stroke();

  const metal = ctx.createLinearGradient(0, 6, 0, 68);
  metal.addColorStop(0, "#f0c45c");
  metal.addColorStop(1, "#8c6a22");
  ctx.fillStyle = metal;
  ctx.beginPath();
  ctx.moveTo(-22, 60);
  ctx.bezierCurveTo(-24, 28, -12, 8, 0, 6);
  ctx.bezierCurveTo(12, 8, 24, 28, 22, 60);
  ctx.closePath();
  ctx.fill();
  ctx.fillStyle = "#c49a3e";
  ctx.fillRect(-24, 58, 48, 8);
  ctx.beginPath();
  ctx.arc(0, 72, 6, 0, Math.PI * 2);
  ctx.fill();
}

function drawDiya(ctx: CanvasRenderingContext2D, lit: boolean, flame: number) {
  joinRope(ctx, 58);
  if (lit) {
    const fire = ctx.createLinearGradient(0, 18, 0, 52);
    fire.addColorStop(0, "#ffe27a");
    fire.addColorStop(1, "#e27a26");
    ctx.fillStyle = fire;
    ctx.beginPath();
    ctx.moveTo(0, 52);
    ctx.quadraticCurveTo(-12, 36, 0, 16 - flame * 6);
    ctx.quadraticCurveTo(12, 36, 0, 52);
    ctx.fill();
  }
  const clay = ctx.createLinearGradient(0, 52, 0, 86);
  clay.addColorStop(0, "#be6c42");
  clay.addColorStop(1, "#863e28");
  ctx.fillStyle = clay;
  ctx.beginPath();
  ctx.moveTo(-26, 62);
  ctx.quadraticCurveTo(0, 92, 26, 62);
  ctx.closePath();
  ctx.fill();
  ctx.fillStyle = "#9e5432";
  ctx.fillRect(-26, 58, 52, 6);
}

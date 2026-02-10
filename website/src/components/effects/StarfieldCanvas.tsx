"use client";

import { useEffect, useRef } from "react";

interface Star {
  x: number;
  y: number;
  z: number;
  size: number;
  opacity: number;
  twinkleSpeed: number;
}

interface ShootingStar {
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
  maxLife: number;
  size: number;
}

interface Nebula {
  x: number;
  y: number;
  radius: number;
  r: number;
  g: number;
  b: number;
  opacity: number;
  drift: number;
}

export function StarfieldCanvas() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let animFrame: number;
    let stars: Star[] = [];
    let shootingStars: ShootingStar[] = [];
    let nebulae: Nebula[] = [];
    let mouseX = 0.5;
    let mouseY = 0.5;

    function resize() {
      canvas!.width = window.innerWidth;
      canvas!.height = window.innerHeight;
      initStars();
      initNebulae();
    }

    function initStars() {
      const count = Math.min(400, Math.floor((canvas!.width * canvas!.height) / 2500));
      stars = Array.from({ length: count }, () => ({
        x: Math.random() * canvas!.width,
        y: Math.random() * canvas!.height,
        z: Math.random(),
        size: Math.random() * 2 + 0.3,
        opacity: Math.random() * 0.7 + 0.15,
        twinkleSpeed: Math.random() * 2 + 0.5,
      }));
    }

    function initNebulae() {
      const w = canvas!.width;
      const h = canvas!.height;
      nebulae = [
        { x: w * 0.2, y: h * 0.3, radius: w * 0.25, r: 0, g: 80, b: 200, opacity: 0.012, drift: 0.15 },
        { x: w * 0.75, y: h * 0.6, radius: w * 0.2, r: 100, g: 0, b: 180, opacity: 0.01, drift: -0.1 },
        { x: w * 0.5, y: h * 0.8, radius: w * 0.18, r: 0, g: 150, b: 200, opacity: 0.008, drift: 0.08 },
      ];
    }

    function spawnShootingStar() {
      if (shootingStars.length >= 3) return;
      const side = Math.random();
      const speed = 4 + Math.random() * 6;
      const angle = -Math.PI / 6 + Math.random() * Math.PI / 8;
      shootingStars.push({
        x: side < 0.5 ? Math.random() * canvas!.width : canvas!.width * 0.8 + Math.random() * canvas!.width * 0.2,
        y: -10,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed + speed,
        life: 0,
        maxLife: 40 + Math.random() * 30,
        size: 1 + Math.random() * 1.5,
      });
    }

    function handleMouseMove(e: MouseEvent) {
      mouseX = e.clientX / window.innerWidth;
      mouseY = e.clientY / window.innerHeight;
    }

    function draw(time: number) {
      ctx!.clearRect(0, 0, canvas!.width, canvas!.height);

      // Parallax offset from mouse
      const px = (mouseX - 0.5) * 15;
      const py = (mouseY - 0.5) * 10;

      // Draw nebulae (soft background glow)
      for (const neb of nebulae) {
        const wobble = Math.sin(time * 0.0003 * neb.drift) * 20;
        const gradient = ctx!.createRadialGradient(
          neb.x + wobble + px * 0.5, neb.y + py * 0.5, 0,
          neb.x + wobble + px * 0.5, neb.y + py * 0.5, neb.radius
        );
        const pulse = 1 + Math.sin(time * 0.0005) * 0.15;
        gradient.addColorStop(0, `rgba(${neb.r}, ${neb.g}, ${neb.b}, ${neb.opacity * pulse})`);
        gradient.addColorStop(1, `rgba(${neb.r}, ${neb.g}, ${neb.b}, 0)`);
        ctx!.fillStyle = gradient;
        ctx!.fillRect(0, 0, canvas!.width, canvas!.height);
      }

      // Draw stars
      for (const star of stars) {
        const twinkle = Math.sin(time * 0.001 * star.twinkleSpeed + star.z * 100) * 0.25;
        const alpha = Math.max(0.05, star.opacity + twinkle);

        // Slow drift + parallax
        star.x += (star.z - 0.5) * 0.1;
        star.y += star.z * 0.05;

        const drawX = star.x + px * star.z * 0.8;
        const drawY = star.y + py * star.z * 0.8;

        // Wrap around
        if (star.x < -20) star.x = canvas!.width + 20;
        if (star.x > canvas!.width + 20) star.x = -20;
        if (star.y > canvas!.height + 10) {
          star.y = -10;
          star.x = Math.random() * canvas!.width;
        }

        const isCyan = star.z > 0.82;
        const isWarm = star.z < 0.15;
        const radius = star.size * (0.4 + star.z * 0.6);

        if (isCyan) {
          ctx!.fillStyle = `rgba(0, 200, 255, ${alpha * 0.9})`;
        } else if (isWarm) {
          ctx!.fillStyle = `rgba(255, 200, 150, ${alpha * 0.7})`;
        } else {
          ctx!.fillStyle = `rgba(176, 212, 232, ${alpha})`;
        }

        ctx!.beginPath();
        ctx!.arc(drawX, drawY, radius, 0, Math.PI * 2);
        ctx!.fill();

        // Cross flare for bright stars
        if (star.z > 0.75 && star.size > 1.2) {
          const flareAlpha = alpha * 0.15;
          const flareLen = radius * 4;
          ctx!.strokeStyle = isCyan
            ? `rgba(0, 200, 255, ${flareAlpha})`
            : `rgba(176, 212, 232, ${flareAlpha})`;
          ctx!.lineWidth = 0.5;
          ctx!.beginPath();
          ctx!.moveTo(drawX - flareLen, drawY);
          ctx!.lineTo(drawX + flareLen, drawY);
          ctx!.moveTo(drawX, drawY - flareLen);
          ctx!.lineTo(drawX, drawY + flareLen);
          ctx!.stroke();
        }

        // Glow halo for bright stars
        if (star.z > 0.7 && star.size > 1) {
          ctx!.fillStyle = isCyan
            ? `rgba(0, 200, 255, ${alpha * 0.06})`
            : `rgba(176, 212, 232, ${alpha * 0.05})`;
          ctx!.beginPath();
          ctx!.arc(drawX, drawY, star.size * 4, 0, Math.PI * 2);
          ctx!.fill();
        }
      }

      // Shooting stars
      if (Math.random() < 0.008) spawnShootingStar();

      for (let i = shootingStars.length - 1; i >= 0; i--) {
        const ss = shootingStars[i];
        ss.x += ss.vx;
        ss.y += ss.vy;
        ss.life++;

        const progress = ss.life / ss.maxLife;
        const fadeIn = Math.min(1, ss.life / 5);
        const fadeOut = 1 - progress;
        const alpha = fadeIn * fadeOut * 0.9;

        // Trail
        const trailLen = 25;
        const gradient = ctx!.createLinearGradient(
          ss.x, ss.y,
          ss.x - ss.vx * trailLen * 0.3, ss.y - ss.vy * trailLen * 0.3
        );
        gradient.addColorStop(0, `rgba(200, 230, 255, ${alpha})`);
        gradient.addColorStop(0.4, `rgba(0, 200, 255, ${alpha * 0.4})`);
        gradient.addColorStop(1, `rgba(0, 200, 255, 0)`);

        ctx!.strokeStyle = gradient;
        ctx!.lineWidth = ss.size;
        ctx!.lineCap = "round";
        ctx!.beginPath();
        ctx!.moveTo(ss.x, ss.y);
        ctx!.lineTo(ss.x - ss.vx * trailLen * 0.3, ss.y - ss.vy * trailLen * 0.3);
        ctx!.stroke();

        // Head glow
        ctx!.fillStyle = `rgba(255, 255, 255, ${alpha * 0.8})`;
        ctx!.beginPath();
        ctx!.arc(ss.x, ss.y, ss.size * 0.8, 0, Math.PI * 2);
        ctx!.fill();

        if (ss.life >= ss.maxLife || ss.x > canvas!.width + 50 || ss.y > canvas!.height + 50) {
          shootingStars.splice(i, 1);
        }
      }

      animFrame = requestAnimationFrame(draw);
    }

    resize();
    animFrame = requestAnimationFrame(draw);
    window.addEventListener("resize", resize);
    window.addEventListener("mousemove", handleMouseMove);

    return () => {
      cancelAnimationFrame(animFrame);
      window.removeEventListener("resize", resize);
      window.removeEventListener("mousemove", handleMouseMove);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      className="absolute inset-0 w-full h-full"
      style={{ pointerEvents: "none" }}
    />
  );
}

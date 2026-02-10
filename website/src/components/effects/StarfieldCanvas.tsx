"use client";

import { useEffect, useRef } from "react";

interface Star {
  x: number;
  y: number;
  z: number;
  size: number;
  opacity: number;
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

    function resize() {
      canvas!.width = window.innerWidth;
      canvas!.height = window.innerHeight;
      initStars();
    }

    function initStars() {
      const count = Math.min(250, Math.floor((canvas!.width * canvas!.height) / 4000));
      stars = Array.from({ length: count }, () => ({
        x: Math.random() * canvas!.width,
        y: Math.random() * canvas!.height,
        z: Math.random(),
        size: Math.random() * 1.5 + 0.5,
        opacity: Math.random() * 0.6 + 0.2,
      }));
    }

    function draw(time: number) {
      ctx!.clearRect(0, 0, canvas!.width, canvas!.height);

      for (const star of stars) {
        const twinkle = Math.sin(time * 0.001 + star.z * 100) * 0.15;
        const alpha = Math.max(0.05, star.opacity + twinkle);

        // Slow drift
        star.x += (star.z - 0.5) * 0.08;
        star.y += star.z * 0.04;

        // Wrap around
        if (star.x < 0) star.x = canvas!.width;
        if (star.x > canvas!.width) star.x = 0;
        if (star.y > canvas!.height) {
          star.y = 0;
          star.x = Math.random() * canvas!.width;
        }

        // Color: mostly white-blue, some cyan
        const isCyan = star.z > 0.85;
        if (isCyan) {
          ctx!.fillStyle = `rgba(0, 200, 255, ${alpha * 0.8})`;
        } else {
          ctx!.fillStyle = `rgba(176, 212, 232, ${alpha})`;
        }

        ctx!.beginPath();
        ctx!.arc(star.x, star.y, star.size * (0.5 + star.z * 0.5), 0, Math.PI * 2);
        ctx!.fill();

        // Glow for bright stars
        if (star.z > 0.7 && star.size > 1) {
          ctx!.fillStyle = isCyan
            ? `rgba(0, 200, 255, ${alpha * 0.1})`
            : `rgba(176, 212, 232, ${alpha * 0.08})`;
          ctx!.beginPath();
          ctx!.arc(star.x, star.y, star.size * 3, 0, Math.PI * 2);
          ctx!.fill();
        }
      }

      animFrame = requestAnimationFrame(draw);
    }

    resize();
    animFrame = requestAnimationFrame(draw);
    window.addEventListener("resize", resize);

    return () => {
      cancelAnimationFrame(animFrame);
      window.removeEventListener("resize", resize);
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

"use client";

import { useI18n } from "@/i18n";
import { Container } from "@/components/ui/Container";
import { Button } from "@/components/ui/Button";

export default function NotFound() {
  const { t } = useI18n();

  return (
    <div className="min-h-screen flex items-center justify-center">
      <Container className="text-center">
        <h1 className="text-8xl font-bold text-cyan/20 font-mono mb-4">{t.notFound.code}</h1>
        <h2 className="text-2xl font-bold uppercase tracking-wider text-text-primary mb-2">
          {t.notFound.title}
        </h2>
        <p className="text-text-secondary mb-8">
          {t.notFound.description}
        </p>
        <Button href="/">{t.notFound.backHome}</Button>
      </Container>
    </div>
  );
}

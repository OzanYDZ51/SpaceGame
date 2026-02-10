"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { formatDate } from "@/lib/utils";
import { Container } from "@/components/ui/Container";
import { SectionHeading } from "@/components/ui/SectionHeading";
import { Badge } from "@/components/ui/Badge";
import { ScrollReveal } from "@/components/effects/ScrollReveal";
import type { ChangelogEntry } from "@/types/api";

export function ChangelogSection() {
  const [entries, setEntries] = useState<ChangelogEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api
      .get<ChangelogEntry[]>("/api/v1/changelog/list?limit=5")
      .then(setEntries)
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []);

  return (
    <section id="changelog" className="py-24 sm:py-32 bg-bg-secondary/30">
      <Container>
        <ScrollReveal>
          <SectionHeading
            title="Changelog"
            subtitle="Les dernières mises à jour du jeu."
          />
        </ScrollReveal>

        {loading ? (
          <div className="text-center py-12">
            <div className="inline-block w-6 h-6 border-2 border-cyan/30 border-t-cyan rounded-full animate-spin" />
          </div>
        ) : entries.length === 0 ? (
          <p className="text-center text-text-secondary text-sm">
            Aucune entrée de changelog pour le moment.
          </p>
        ) : (
          <div className="max-w-2xl mx-auto">
            {/* Timeline */}
            <div className="relative border-l border-border-subtle pl-8 space-y-8">
              {entries.map((entry, i) => (
                <ScrollReveal key={entry.id} delay={i * 0.1}>
                  <div className="relative">
                    {/* Timeline dot */}
                    <div className="absolute -left-[2.35rem] top-1 w-2.5 h-2.5 rounded-full bg-cyan/60 ring-4 ring-bg-primary" />

                    <div className="flex items-center gap-3 mb-2">
                      <Badge
                        className={
                          entry.is_major
                            ? "border-accent/30 bg-accent/5 text-accent"
                            : undefined
                        }
                      >
                        v{entry.version}
                      </Badge>
                      <span className="text-xs text-text-muted font-mono">
                        {formatDate(entry.created_at)}
                      </span>
                    </div>

                    <p className="text-sm text-text-secondary leading-relaxed">
                      {entry.summary}
                    </p>
                  </div>
                </ScrollReveal>
              ))}
            </div>
          </div>
        )}
      </Container>
    </section>
  );
}

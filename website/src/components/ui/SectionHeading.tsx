import { cn } from "@/lib/utils";

export function SectionHeading({
  title,
  subtitle,
  className,
}: {
  title: string;
  subtitle?: string;
  className?: string;
}) {
  return (
    <div className={cn("text-center mb-16", className)}>
      <div className="flex items-center justify-center gap-4 mb-4">
        <div className="h-px w-12 bg-gradient-to-r from-transparent to-cyan/50" />
        <h2 className="text-3xl sm:text-4xl font-bold uppercase tracking-wider text-cyan text-glow-cyan-sm">
          {title}
        </h2>
        <div className="h-px w-12 bg-gradient-to-l from-transparent to-cyan/50" />
      </div>
      {subtitle && (
        <p className="text-text-secondary text-lg max-w-2xl mx-auto">
          {subtitle}
        </p>
      )}
    </div>
  );
}

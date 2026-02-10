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
    <div className={cn("text-center mb-10 sm:mb-16", className)}>
      <div className="flex items-center justify-center gap-3 sm:gap-4 mb-4">
        <div className="h-px w-8 sm:w-12 bg-gradient-to-r from-transparent to-cyan/50" />
        <h2 className="text-2xl sm:text-3xl md:text-4xl lg:text-5xl font-bold uppercase tracking-wider text-cyan text-glow-cyan-sm">
          {title}
        </h2>
        <div className="h-px w-8 sm:w-12 bg-gradient-to-l from-transparent to-cyan/50" />
      </div>
      {subtitle && (
        <p className="text-text-secondary text-sm sm:text-base md:text-lg max-w-2xl mx-auto px-2">
          {subtitle}
        </p>
      )}
    </div>
  );
}

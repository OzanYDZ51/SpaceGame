import { cn } from "@/lib/utils";

export function Card({
  className,
  children,
}: {
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div
      className={cn(
        "relative rounded border border-border-subtle bg-bg-card p-6 backdrop-blur-sm border-glow-hover",
        className
      )}
    >
      {children}
    </div>
  );
}

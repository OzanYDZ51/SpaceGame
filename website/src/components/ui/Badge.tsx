import { cn } from "@/lib/utils";

export function Badge({
  className,
  children,
}: {
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <span
      className={cn(
        "inline-block rounded border border-cyan/30 bg-cyan/5 px-3 py-1 text-xs uppercase tracking-[0.2em] text-cyan font-mono",
        className
      )}
    >
      {children}
    </span>
  );
}

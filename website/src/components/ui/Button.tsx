import { cn } from "@/lib/utils";
import { type ButtonHTMLAttributes } from "react";

type Variant = "primary" | "outline" | "ghost" | "danger";

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  href?: string;
}

const variants: Record<Variant, string> = {
  primary:
    "bg-cyan/10 border-cyan text-cyan hover:bg-cyan/20 hover:shadow-[0_0_20px_rgba(0,200,255,0.2)]",
  outline:
    "bg-transparent border-border-subtle text-text-primary hover:border-cyan hover:text-cyan",
  ghost:
    "bg-transparent border-transparent text-text-secondary hover:text-cyan hover:bg-cyan/5",
  danger:
    "bg-danger/10 border-danger text-danger hover:bg-danger/20",
};

export function Button({
  variant = "primary",
  className,
  href,
  children,
  ...props
}: ButtonProps) {
  const classes = cn(
    "inline-flex items-center justify-center gap-2 px-6 py-2.5 border rounded font-heading font-medium text-sm uppercase tracking-[0.15em] transition-all duration-200 cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed",
    variants[variant],
    className
  );

  if (href) {
    return (
      <a href={href} className={classes}>
        {children}
      </a>
    );
  }

  return (
    <button className={classes} {...props}>
      {children}
    </button>
  );
}

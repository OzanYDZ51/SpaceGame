import { cn } from "@/lib/utils";
import { type InputHTMLAttributes } from "react";

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
}

export function Input({ label, error, className, id, ...props }: InputProps) {
  return (
    <div className="space-y-1.5">
      {label && (
        <label
          htmlFor={id}
          className="block text-xs uppercase tracking-[0.2em] text-text-secondary font-mono"
        >
          {label}
        </label>
      )}
      <input
        id={id}
        className={cn(
          "w-full rounded border border-border-subtle bg-bg-secondary px-4 py-2.5 text-sm text-text-primary font-heading placeholder:text-text-muted outline-none transition-all duration-200 focus:border-cyan focus:shadow-[0_0_10px_rgba(0,200,255,0.15)]",
          error && "border-danger focus:border-danger focus:shadow-[0_0_10px_rgba(255,85,85,0.15)]",
          className
        )}
        {...props}
      />
      {error && (
        <p className="text-xs text-danger font-mono">{error}</p>
      )}
    </div>
  );
}

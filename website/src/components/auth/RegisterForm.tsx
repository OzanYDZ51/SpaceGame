"use client";

import { useState, type FormEvent } from "react";
import { useAuth } from "@/hooks/useAuth";
import { useI18n } from "@/i18n";
import { Input } from "@/components/ui/Input";
import { Button } from "@/components/ui/Button";

interface RegisterFormProps {
  onSwitch: () => void;
  onSuccess: () => void;
}

export function RegisterForm({ onSwitch, onSuccess }: RegisterFormProps) {
  const { register } = useAuth();
  const { t } = useI18n();
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError("");

    if (password !== confirmPassword) {
      setError(t.auth.errorPasswordMismatch);
      return;
    }
    if (password.length < 6) {
      setError(t.auth.errorPasswordLength);
      return;
    }

    setLoading(true);
    try {
      await register(username, email, password);
      onSuccess();
    } catch (err) {
      setError(err instanceof Error ? err.message : t.auth.errorRegister);
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <h3 className="text-xl font-bold uppercase tracking-wider text-cyan text-center text-glow-cyan-sm">
        {t.auth.registerTitle}
      </h3>

      {error && (
        <div className="rounded border border-danger/30 bg-danger/5 px-3 py-2 text-xs text-danger font-mono">
          {error}
        </div>
      )}

      <Input
        id="reg-username"
        label={t.auth.username}
        value={username}
        onChange={(e) => setUsername(e.target.value)}
        autoComplete="username"
        required
      />
      <Input
        id="reg-email"
        label={t.auth.email}
        type="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        autoComplete="email"
        required
      />
      <Input
        id="reg-password"
        label={t.auth.password}
        type="password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        autoComplete="new-password"
        required
      />
      <Input
        id="reg-confirm"
        label={t.auth.confirmPassword}
        type="password"
        value={confirmPassword}
        onChange={(e) => setConfirmPassword(e.target.value)}
        autoComplete="new-password"
        required
      />

      <Button type="submit" disabled={loading} className="w-full">
        {loading ? t.auth.registerLoading : t.auth.registerButton}
      </Button>

      <p className="text-center text-xs text-text-secondary">
        {t.auth.hasAccount}{" "}
        <button
          type="button"
          onClick={onSwitch}
          className="text-cyan hover:underline cursor-pointer"
        >
          {t.auth.switchToLogin}
        </button>
      </p>
    </form>
  );
}

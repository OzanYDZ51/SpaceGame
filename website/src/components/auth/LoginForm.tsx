"use client";

import { useState, type FormEvent } from "react";
import { useAuth } from "@/hooks/useAuth";
import { useI18n } from "@/i18n";
import { Input } from "@/components/ui/Input";
import { Button } from "@/components/ui/Button";

interface LoginFormProps {
  onSwitch: () => void;
  onSuccess: () => void;
}

export function LoginForm({ onSwitch, onSuccess }: LoginFormProps) {
  const { login } = useAuth();
  const { t } = useI18n();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await login(username, password);
      onSuccess();
    } catch (err) {
      setError(err instanceof Error ? err.message : t.auth.errorLogin);
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <h3 className="text-xl font-bold uppercase tracking-wider text-cyan text-center text-glow-cyan-sm">
        {t.auth.loginTitle}
      </h3>

      {error && (
        <div className="rounded border border-danger/30 bg-danger/5 px-3 py-2 text-xs text-danger font-mono">
          {error}
        </div>
      )}

      <Input
        id="login-username"
        label={t.auth.username}
        value={username}
        onChange={(e) => setUsername(e.target.value)}
        autoComplete="username"
        required
      />
      <Input
        id="login-password"
        label={t.auth.password}
        type="password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        autoComplete="current-password"
        required
      />

      <Button type="submit" disabled={loading} className="w-full">
        {loading ? t.auth.loginLoading : t.auth.loginButton}
      </Button>

      <p className="text-center text-xs text-text-secondary">
        {t.auth.noAccount}{" "}
        <button
          type="button"
          onClick={onSwitch}
          className="text-cyan hover:underline cursor-pointer"
        >
          {t.auth.createAccount}
        </button>
      </p>
    </form>
  );
}

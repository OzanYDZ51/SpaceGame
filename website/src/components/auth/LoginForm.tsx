"use client";

import { useState, type FormEvent } from "react";
import { useAuth } from "@/hooks/useAuth";
import { Input } from "@/components/ui/Input";
import { Button } from "@/components/ui/Button";

interface LoginFormProps {
  onSwitch: () => void;
  onSuccess: () => void;
}

export function LoginForm({ onSwitch, onSuccess }: LoginFormProps) {
  const { login } = useAuth();
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
      setError(err instanceof Error ? err.message : "Erreur de connexion");
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <h3 className="text-xl font-bold uppercase tracking-wider text-cyan text-center text-glow-cyan-sm">
        Connexion
      </h3>

      {error && (
        <div className="rounded border border-danger/30 bg-danger/5 px-3 py-2 text-xs text-danger font-mono">
          {error}
        </div>
      )}

      <Input
        id="login-username"
        label="Identifiant"
        value={username}
        onChange={(e) => setUsername(e.target.value)}
        autoComplete="username"
        required
      />
      <Input
        id="login-password"
        label="Mot de passe"
        type="password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        autoComplete="current-password"
        required
      />

      <Button type="submit" disabled={loading} className="w-full">
        {loading ? "Connexion..." : "Se connecter"}
      </Button>

      <p className="text-center text-xs text-text-secondary">
        Pas encore de compte ?{" "}
        <button
          type="button"
          onClick={onSwitch}
          className="text-cyan hover:underline cursor-pointer"
        >
          Créer un compte
        </button>
      </p>
    </form>
  );
}

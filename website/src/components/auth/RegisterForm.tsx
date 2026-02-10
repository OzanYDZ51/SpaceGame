"use client";

import { useState, type FormEvent } from "react";
import { useAuth } from "@/hooks/useAuth";
import { Input } from "@/components/ui/Input";
import { Button } from "@/components/ui/Button";

interface RegisterFormProps {
  onSwitch: () => void;
  onSuccess: () => void;
}

export function RegisterForm({ onSwitch, onSuccess }: RegisterFormProps) {
  const { register } = useAuth();
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
      setError("Les mots de passe ne correspondent pas");
      return;
    }
    if (password.length < 6) {
      setError("Le mot de passe doit faire au moins 6 caractères");
      return;
    }

    setLoading(true);
    try {
      await register(username, email, password);
      onSuccess();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur lors de l'inscription");
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <h3 className="text-xl font-bold uppercase tracking-wider text-cyan text-center text-glow-cyan-sm">
        Créer un compte
      </h3>

      {error && (
        <div className="rounded border border-danger/30 bg-danger/5 px-3 py-2 text-xs text-danger font-mono">
          {error}
        </div>
      )}

      <Input
        id="reg-username"
        label="Identifiant"
        value={username}
        onChange={(e) => setUsername(e.target.value)}
        autoComplete="username"
        required
      />
      <Input
        id="reg-email"
        label="Email"
        type="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        autoComplete="email"
        required
      />
      <Input
        id="reg-password"
        label="Mot de passe"
        type="password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        autoComplete="new-password"
        required
      />
      <Input
        id="reg-confirm"
        label="Confirmer"
        type="password"
        value={confirmPassword}
        onChange={(e) => setConfirmPassword(e.target.value)}
        autoComplete="new-password"
        required
      />

      <Button type="submit" disabled={loading} className="w-full">
        {loading ? "Création..." : "Créer le compte"}
      </Button>

      <p className="text-center text-xs text-text-secondary">
        Déjà un compte ?{" "}
        <button
          type="button"
          onClick={onSwitch}
          className="text-cyan hover:underline cursor-pointer"
        >
          Se connecter
        </button>
      </p>
    </form>
  );
}

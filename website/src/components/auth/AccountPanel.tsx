"use client";

import { useAuth } from "@/hooks/useAuth";
import { Button } from "@/components/ui/Button";

interface AccountPanelProps {
  onClose: () => void;
}

export function AccountPanel({ onClose }: AccountPanelProps) {
  const { user, logout } = useAuth();

  function handleLogout() {
    logout();
    onClose();
  }

  return (
    <div className="space-y-6 text-center">
      <h3 className="text-xl font-bold uppercase tracking-wider text-cyan text-glow-cyan-sm">
        Compte
      </h3>

      <div className="rounded border border-border-subtle bg-bg-primary/50 p-4">
        <p className="text-xs uppercase tracking-[0.2em] text-text-secondary font-mono mb-2">
          Identifiant
        </p>
        <p className="text-lg font-bold text-cyan">{user?.username}</p>
      </div>

      <p className="text-xs text-text-secondary">
        Utilisez le launcher pour jouer avec ce compte.
      </p>

      <div className="flex gap-3">
        <Button variant="outline" onClick={onClose} className="flex-1">
          Fermer
        </Button>
        <Button variant="danger" onClick={handleLogout} className="flex-1">
          Déconnexion
        </Button>
      </div>
    </div>
  );
}

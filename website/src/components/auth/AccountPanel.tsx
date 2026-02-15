"use client";

import { useAuth } from "@/hooks/useAuth";
import { useI18n } from "@/i18n";
import { Button } from "@/components/ui/Button";

interface AccountPanelProps {
  onClose: () => void;
}

export function AccountPanel({ onClose }: AccountPanelProps) {
  const { user, logout } = useAuth();
  const { t } = useI18n();

  function handleLogout() {
    logout();
    onClose();
  }

  return (
    <div className="space-y-6 text-center">
      <h3 className="text-xl font-bold uppercase tracking-wider text-cyan text-glow-cyan-sm">
        {t.auth.accountTitle}
      </h3>

      <div className="rounded border border-border-subtle bg-bg-primary/50 p-4">
        <p className="text-xs uppercase tracking-[0.2em] text-text-secondary font-mono mb-2">
          {t.auth.username}
        </p>
        <p className="text-lg font-bold text-cyan">{user?.username}</p>
      </div>

      <p className="text-xs text-text-secondary">
        {t.auth.launcherHint}
      </p>

      <div className="flex gap-3">
        <Button variant="outline" onClick={onClose} className="flex-1">
          {t.auth.closeButton}
        </Button>
        <Button variant="danger" onClick={handleLogout} className="flex-1">
          {t.auth.logoutButton}
        </Button>
      </div>
    </div>
  );
}

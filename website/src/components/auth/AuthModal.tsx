"use client";

import { useState } from "react";
import { useAuth } from "@/hooks/useAuth";
import { Modal } from "@/components/ui/Modal";
import { LoginForm } from "./LoginForm";
import { RegisterForm } from "./RegisterForm";
import { AccountPanel } from "./AccountPanel";

type View = "login" | "register" | "account";

interface AuthModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function AuthModal({ isOpen, onClose }: AuthModalProps) {
  const { isAuthenticated } = useAuth();
  const [view, setView] = useState<View>("login");

  const currentView = isAuthenticated ? "account" : view;

  return (
    <Modal isOpen={isOpen} onClose={onClose}>
      {currentView === "login" && (
        <LoginForm
          onSwitch={() => setView("register")}
          onSuccess={onClose}
        />
      )}
      {currentView === "register" && (
        <RegisterForm
          onSwitch={() => setView("login")}
          onSuccess={onClose}
        />
      )}
      {currentView === "account" && (
        <AccountPanel onClose={onClose} />
      )}
    </Modal>
  );
}

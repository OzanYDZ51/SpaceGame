"use client";

import {
  createContext,
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { api } from "./api";
import type { AuthResponse, RefreshResponse } from "@/types/api";
import React from "react";

interface User {
  id: string;
  username: string;
}

export interface AuthState {
  user: User | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  login: (username: string, password: string) => Promise<void>;
  register: (username: string, email: string, password: string) => Promise<void>;
  logout: () => void;
}

function decodeJwtPayload(token: string): { sub?: string; username?: string; exp?: number } {
  try {
    const payload = token.split(".")[1];
    return JSON.parse(atob(payload));
  } catch {
    return {};
  }
}

function getStoredUser(): User | null {
  if (typeof window === "undefined") return null;
  const token = localStorage.getItem("imperion_access_token");
  if (!token) return null;
  const payload = decodeJwtPayload(token);
  if (!payload.sub || !payload.username) return null;
  if (payload.exp && payload.exp * 1000 < Date.now()) return null;
  return { id: payload.sub, username: payload.username };
}

export const AuthContext = createContext<AuthState>({
  user: null,
  isLoading: true,
  isAuthenticated: false,
  login: async () => {},
  register: async () => {},
  logout: () => {},
});

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  // Hydrate on mount — try refresh if access token is expired
  useEffect(() => {
    const storedUser = getStoredUser();
    if (storedUser) {
      setUser(storedUser);
      setIsLoading(false);
      return;
    }

    const refreshToken = localStorage.getItem("imperion_refresh_token");
    if (!refreshToken) {
      setIsLoading(false);
      return;
    }

    api
      .post<RefreshResponse>("/api/v1/auth/refresh", { refresh_token: refreshToken })
      .then((res) => {
        localStorage.setItem("imperion_access_token", res.access_token);
        localStorage.setItem("imperion_refresh_token", res.refresh_token);
        const payload = decodeJwtPayload(res.access_token);
        if (payload.sub && payload.username) {
          setUser({ id: payload.sub, username: payload.username });
        }
      })
      .catch(() => {
        localStorage.removeItem("imperion_access_token");
        localStorage.removeItem("imperion_refresh_token");
      })
      .finally(() => setIsLoading(false));
  }, []);

  const login = useCallback(async (username: string, password: string) => {
    const res = await api.post<AuthResponse>("/api/v1/auth/login", {
      username,
      password,
    });
    localStorage.setItem("imperion_access_token", res.access_token);
    localStorage.setItem("imperion_refresh_token", res.refresh_token);
    setUser({ id: res.player.id, username: res.player.username });
  }, []);

  const register = useCallback(
    async (username: string, email: string, password: string) => {
      const res = await api.post<AuthResponse>("/api/v1/auth/register", {
        username,
        email,
        password,
      });
      localStorage.setItem("imperion_access_token", res.access_token);
      localStorage.setItem("imperion_refresh_token", res.refresh_token);
      setUser({ id: res.player.id, username: res.player.username });
    },
    []
  );

  const logout = useCallback(() => {
    const refreshToken = localStorage.getItem("imperion_refresh_token");
    if (refreshToken) {
      api.post("/api/v1/auth/logout", { refresh_token: refreshToken }).catch(() => {});
    }
    localStorage.removeItem("imperion_access_token");
    localStorage.removeItem("imperion_refresh_token");
    setUser(null);
  }, []);

  const value = useMemo<AuthState>(
    () => ({
      user,
      isLoading,
      isAuthenticated: !!user,
      login,
      register,
      logout,
    }),
    [user, isLoading, login, register, logout]
  );

  return React.createElement(AuthContext.Provider, { value }, children);
}

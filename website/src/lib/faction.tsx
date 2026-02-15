"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

export type FactionId = "nova_terra" | "kharsis";

export interface FactionState {
  faction: FactionId | null;
  setFaction: (f: FactionId) => void;
  clearFaction: () => void;
}

const STORAGE_KEY = "imperion_faction";

const FactionContext = createContext<FactionState>({
  faction: null,
  setFaction: () => {},
  clearFaction: () => {},
});

export function FactionProvider({ children }: { children: ReactNode }) {
  const [faction, setFactionState] = useState<FactionId | null>(null);
  const [hydrated, setHydrated] = useState(false);

  // Hydrate from localStorage
  useEffect(() => {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === "nova_terra" || stored === "kharsis") {
      setFactionState(stored);
      document.documentElement.setAttribute("data-faction", stored);
    }
    setHydrated(true);
  }, []);

  const setFaction = useCallback((f: FactionId) => {
    setFactionState(f);
    localStorage.setItem(STORAGE_KEY, f);
    document.documentElement.setAttribute("data-faction", f);
  }, []);

  const clearFaction = useCallback(() => {
    setFactionState(null);
    localStorage.removeItem(STORAGE_KEY);
    document.documentElement.removeAttribute("data-faction");
  }, []);

  const value = useMemo<FactionState>(
    () => ({ faction, setFaction, clearFaction }),
    [faction, setFaction, clearFaction]
  );

  // Avoid flash of wrong theme
  if (!hydrated) return null;

  return (
    <FactionContext.Provider value={value}>{children}</FactionContext.Provider>
  );
}

export function useFaction(): FactionState {
  return useContext(FactionContext);
}

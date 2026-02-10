"use client";

import { useContext } from "react";
import { AuthContext, type AuthState } from "@/lib/auth";

export function useAuth(): AuthState {
  return useContext(AuthContext);
}

import { API_URL } from "./constants";
import type { ApiError } from "@/types/api";

class ApiClient {
  private baseUrl: string;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
  }

  async fetch<T>(
    path: string,
    options: RequestInit = {}
  ): Promise<T> {
    const url = `${this.baseUrl}${path}`;
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      ...(options.headers as Record<string, string>),
    };

    const token =
      typeof window !== "undefined"
        ? localStorage.getItem("imperion_access_token")
        : null;
    if (token) {
      headers["Authorization"] = `Bearer ${token}`;
    }

    const res = await fetch(url, { ...options, headers });

    if (!res.ok) {
      const body: ApiError = await res.json().catch(() => ({
        error: `HTTP ${res.status}`,
      }));
      throw new Error(body.error);
    }

    return res.json();
  }

  get<T>(path: string) {
    return this.fetch<T>(path, { method: "GET" });
  }

  post<T>(path: string, body?: unknown) {
    return this.fetch<T>(path, {
      method: "POST",
      body: body ? JSON.stringify(body) : undefined,
    });
  }
}

export const api = new ApiClient(API_URL);

import axios, { type AxiosError, type InternalAxiosRequestConfig } from "axios";
import { useAuthStore } from "@/stores/auth";

// Requests go through the Vite dev proxy (see vite.config.ts) so this can
// stay relative in dev and be overridden per-environment in production.
export const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL ?? "/api/v1",
  timeout: 15_000,
});

// Attach the current access token (held in memory by the auth store, never
// localStorage — see stores/auth.ts for the reasoning).
api.interceptors.request.use((config) => {
  const auth = useAuthStore();
  if (auth.accessToken) {
    config.headers.Authorization = `Bearer ${auth.accessToken}`;
  }
  return config;
});

// --- 401 handling -----------------------------------------------------
// Multiple requests can fail with 401 at once (e.g. a page that fires
// several calls on mount after the access token has expired). Without
// coordination, each one would kick off its own refresh call, racing
// against the backend's refresh-token rotation. This queues concurrent
// 401s behind a single in-flight refresh and replays them once it
// resolves.
let refreshPromise: Promise<string> | null = null;

type RetryableConfig = InternalAxiosRequestConfig & { _retried?: boolean };

api.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const original = error.config as RetryableConfig | undefined;
    const status = error.response?.status;

    if (status !== 401 || !original || original._retried) {
      return Promise.reject(error);
    }

    const auth = useAuthStore();
    if (!auth.refreshToken) {
      auth.logout();
      return Promise.reject(error);
    }

    original._retried = true;

    try {
      if (!refreshPromise) {
        refreshPromise = auth.refreshAccessToken().finally(() => {
          refreshPromise = null;
        });
      }
      const newToken = await refreshPromise;
      original.headers.Authorization = `Bearer ${newToken}`;
      return api(original);
    } catch (refreshError) {
      auth.logout();
      return Promise.reject(refreshError);
    }
  },
);

export function extractErrorMessage(error: unknown): string {
  if (axios.isAxiosError(error)) {
    const detail = error.response?.data?.detail;
    if (typeof detail === "string") return detail;
    if (Array.isArray(detail) && detail[0]?.msg) return detail[0].msg;
    if (error.code === "ECONNABORTED")
      return "The request timed out. Please try again.";
    if (!error.response)
      return "Unable to reach the server. Check your connection.";
  }
  return "Something went wrong. Please try again.";
}

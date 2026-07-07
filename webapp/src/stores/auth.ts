import { defineStore } from "pinia";
import { api, extractErrorMessage } from "@/lib/api";
import type {
  LoginPayload,
  RegisterPayload,
  TokenPair,
  User,
} from "@/types/auth";

interface AuthState {
  user: User | null;
  accessToken: string | null;
  refreshToken: string | null;
  status: "idle" | "loading" | "error";
  error: string | null;
}

// Tokens live only in memory (this store's state), never localStorage or
// a plain cookie. Trade-off: a hard page refresh loses the session unless
// we re-hydrate via a refresh call on boot (see `bootstrap` below), which
// is the right cost for keeping tokens out of reach of any XSS-injected
// script that can read localStorage or non-httpOnly cookies.
export const useAuthStore = defineStore("auth", {
  state: (): AuthState => ({
    user: null,
    accessToken: null,
    refreshToken: null,
    status: "idle",
    error: null,
  }),

  getters: {
    isAuthenticated: (state) => Boolean(state.accessToken && state.user),
  },

  actions: {
    async login(payload: LoginPayload) {
      this.status = "loading";
      this.error = null;
      try {
        const { data } = await api.post<TokenPair>("/auth/login", payload);
        this.setTokens(data);
        await this.fetchCurrentUser();
        this.status = "idle";
      } catch (err) {
        this.status = "error";
        this.error = extractErrorMessage(err);
        throw err;
      }
    },

    async register(payload: RegisterPayload) {
      this.status = "loading";
      this.error = null;
      try {
        await api.post("/auth/register", payload);
        await this.login({ email: payload.email, password: payload.password });
      } catch (err) {
        this.status = "error";
        this.error = extractErrorMessage(err);
        throw err;
      }
    },

    async fetchCurrentUser() {
      const { data } = await api.get<User>("/users/me");
      this.user = data;
    },

    /** Called once on app boot. Because both tokens live only in this
     * store's in-memory state (see the note above), a hard page reload
     * currently clears the session and the user must log in again — an
     * intentional MVP trade-off for keeping tokens out of localStorage.
     * This is a no-op unless the store survived (e.g. a client-side route
     * change). If "stay logged in across reloads" becomes a hard
     * requirement, the fix belongs on the backend: issue the refresh
     * token as an httpOnly, Secure, SameSite cookie instead of a JSON
     * field, and have this method call /auth/refresh with
     * `withCredentials: true` and no body — the browser attaches the
     * cookie automatically and JS never touches the refresh token. */
    async bootstrap() {
      if (!this.refreshToken) return;
      try {
        await this.refreshAccessToken();
        await this.fetchCurrentUser();
      } catch {
        this.logout();
      }
    },

    async refreshAccessToken(): Promise<string> {
      if (!this.refreshToken) throw new Error("No refresh token available");
      const { data } = await api.post<TokenPair>("/auth/refresh", {
        refresh_token: this.refreshToken,
      });
      this.setTokens(data);
      return data.access_token;
    },

    setTokens(tokens: TokenPair) {
      this.accessToken = tokens.access_token;
      this.refreshToken = tokens.refresh_token;
    },

    logout() {
      this.user = null;
      this.accessToken = null;
      this.refreshToken = null;
    },
  },
});

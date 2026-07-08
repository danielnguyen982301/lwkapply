export interface User {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  avatar_url: string | null;
  role: string;
}

// The refresh token never appears here anymore — it lives only in the
// httpOnly cookie the backend sets on /auth/login and /auth/refresh.
export interface AccessTokenResponse {
  access_token: string;
  token_type: "bearer";
}

export interface LoginPayload {
  email: string;
  password: string;
}

export interface RegisterPayload {
  email: string;
  password: string;
  first_name: string;
  last_name: string;
}

export interface ApiError {
  detail:
    string | Array<{ loc: (string | number)[]; msg: string; type: string }>;
}

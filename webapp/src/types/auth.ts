export interface User {
  id: string
  email: string
  first_name: string
  last_name: string
  avatar_url: string | null
  role: string
}

// The refresh token never appears here anymore — it lives only in the
// httpOnly cookie the backend sets on /auth/login and /auth/refresh.
export interface AccessTokenResponse {
  access_token: string
  token_type: 'bearer'
}

export interface LoginPayload {
  email: string
  password: string
  timezone?: string
}

export interface RegisterPayload {
  email: string
  password: string
  first_name: string
  last_name: string
  timezone?: string
}

export interface ApiError {
  detail: string | Array<{ loc: (string | number)[]; msg: string; type: string }>
}

// Body for PATCH /users/me. `timezone: null` is an explicit "go back to
// auto-detect" (see app/schemas/user.py::UserProfileUpdate) — omit the key
// entirely to leave it untouched instead.
export interface ProfileUpdatePayload {
  first_name?: string
  last_name?: string
  timezone?: string | null
}

// Body for POST /users/me/password. Requires the current password even
// though the request is already bearer-authenticated (see
// PasswordChangeRequest in app/schemas/user.py).
export interface PasswordChangePayload {
  current_password: string
  new_password: string
}

// Body for DELETE /users/me — same re-prove-the-password reasoning as
// PasswordChangePayload above.
export interface AccountDeletePayload {
  password: string
}

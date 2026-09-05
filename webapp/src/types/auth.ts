export interface User {
  id: string
  email: string
  first_name: string
  last_name: string
  avatar_url: string | null
  role: string
  // NULL until the first register/login/refresh auto-detects one.
  // timezone_is_manual distinguishes "auto-detected" from "explicitly
  // set in Account Settings" (see ProfileUpdatePayload.timezone below).
  timezone: string | null
  timezone_is_manual: boolean
}

// The refresh token never appears here anymore — it lives only in the
// httpOnly cookie the backend sets on /auth/login and /auth/refresh.
export interface AccessTokenResponse {
  access_token: string
  token_type: 'bearer'
  // See backend TokenResponse.csrf_token's docstring — this is how the
  // frontend gets its copy now, rather than reading the csrf_token
  // cookie directly (which only works when frontend and backend share
  // an origin).
  csrf_token: string
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

// Body for POST /auth/password-reset/confirm (app/schemas/auth.py::
// PasswordResetConfirm). No equivalent payload type is needed for
// POST /auth/password-reset/request or POST /users/me/password-reset/
// request - the former takes just `{ email }` inline, the latter takes
// no body at all (the target user comes from the bearer token).
export interface PasswordResetConfirmPayload {
  token: string
  new_password: string
}

// Body for DELETE /users/me - deleting the account still requires
// re-proving the current password (unlike a password reset, this can't
// be replaced by an emailed link without adding a second confirmation
// step to an already-irreversible action).
export interface AccountDeletePayload {
  password: string
}

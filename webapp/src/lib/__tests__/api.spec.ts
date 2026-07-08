import { describe, expect, it } from 'vitest'
import axios from 'axios'
import { extractErrorMessage } from '../api'

describe('extractErrorMessage', () => {
  it('returns the string detail from a FastAPI error response', () => {
    const error = Object.assign(new Error(), {
      isAxiosError: true,
      response: { data: { detail: 'Incorrect email or password' } },
    })
    expect(extractErrorMessage(error)).toBe('Incorrect email or password')
  })

  it('returns the first validation message when detail is a list', () => {
    const error = Object.assign(new Error(), {
      isAxiosError: true,
      response: {
        data: {
          detail: [
            {
              loc: ['body', 'email'],
              msg: 'value is not a valid email address',
              type: 'value_error',
            },
          ],
        },
      },
    })
    expect(extractErrorMessage(error)).toBe('value is not a valid email address')
  })

  it('returns a network-specific message when there is no response at all', () => {
    const error = Object.assign(new Error(), { isAxiosError: true, response: undefined })
    expect(extractErrorMessage(error)).toBe('Unable to reach the server. Check your connection.')
  })

  it('falls back to a generic message for a non-axios error', () => {
    expect(extractErrorMessage(new Error('boom'))).toBe('Something went wrong. Please try again.')
  })
})

// Sanity check that axios.isAxiosError itself behaves as extractErrorMessage
// assumes — guards against a version bump changing that contract silently.
describe('axios.isAxiosError contract', () => {
  it('treats a plain object with isAxiosError:true as an axios error', () => {
    expect(axios.isAxiosError({ isAxiosError: true })).toBe(true)
  })
})

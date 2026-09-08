<script setup lang="ts">
import Button from 'primevue/button'

// Written primarily to satisfy Firefox AMO's data-collection
// disclosure requirement for the LwkApply Quick Capture browser
// extension (it logs in with an email/password and reads/transmits
// job-application data, both of which AMO requires a privacy policy
// URL for) - but it covers the webapp and mobile app too, since all
// three share one LwkApply account and backend.
const lastUpdated = 'September 8, 2026'
</script>

<template>
  <div class="min-h-screen bg-paper px-4 py-12">
    <div class="mx-auto max-w-2xl">
      <div class="mb-8 flex items-center justify-between">
        <p class="font-display text-xl font-bold text-ink">LwkApply</p>
        <Button label="Back to LwkApply" as="RouterLink" to="/" link />
      </div>

      <article class="space-y-8 text-sm leading-relaxed text-ink">
        <header class="space-y-1">
          <h1 class="font-display text-2xl font-bold text-ink">Privacy Policy</h1>
          <p class="text-slate">Last updated: {{ lastUpdated }}</p>
        </header>

        <p>
          LwkApply ("LwkApply", "we", "us") is a job application tracker built and operated by a
          single independent developer, not a company. This policy covers the LwkApply web app,
          mobile app, and the LwkApply Quick Capture browser extension, all of which share one
          LwkApply account and backend.
        </p>

        <section class="space-y-2">
          <h2 class="font-display text-lg font-semibold text-ink">Information we collect</h2>
          <ul class="ml-5 list-disc space-y-2">
            <li>
              <strong>Account credentials.</strong> When you log in — including from the browser
              extension — we receive the email and password you enter. Your password is used only to
              verify your identity with LwkApply's own backend and is never stored; we store only
              the resulting access and refresh tokens.
            </li>
            <li>
              <strong>Job posting details.</strong> The extension reads information already visible
              on a VietnamWorks job posting page you visit — company name, job title, location,
              salary, and VietnamWorks' own internal id for that posting — so it can fill in an
              application record for you.
            </li>
            <li>
              <strong>Your application activity on VietnamWorks.</strong> When you Save, Unsave, or
              Apply to a job on VietnamWorks, the extension recognizes this from the network
              requests your own browser already makes to VietnamWorks, and creates or updates the
              matching application in your LwkApply account. It does not read anything from any site
              other than VietnamWorks, and it never sees your VietnamWorks password or account.
            </li>
            <li>
              <strong>Application data you enter directly</strong> — company, position, location,
              salary, notes, and similar fields — whether typed into the extension's popup, the web
              app, or the mobile app.
            </li>
          </ul>
        </section>

        <section class="space-y-2">
          <h2 class="font-display text-lg font-semibold text-ink">What we don't collect</h2>
          <p>
            The extension does not collect your general browsing history, does not read or store
            your VietnamWorks credentials, does not collect payment information, and does not
            include any advertising or third-party analytics or tracking scripts.
          </p>
        </section>

        <section class="space-y-2">
          <h2 class="font-display text-lg font-semibold text-ink">How we use your information</h2>
          <p>
            Everything collected is used for one purpose: keeping your job applications organized in
            your own LwkApply account, so you can track applications you make across multiple job
            boards in one place. We do not use your data for advertising, and we do not sell or rent
            it to anyone.
          </p>
        </section>

        <section class="space-y-2">
          <h2 class="font-display text-lg font-semibold text-ink">
            How your information is stored
          </h2>
          <p>
            Application and account data is sent over HTTPS and stored in LwkApply's database. The
            extension caches your access and refresh tokens locally in your browser (via the
            browser's own extension storage) so you stay signed in — these tokens stay on your
            device and are sent only to LwkApply's backend to authenticate your requests.
          </p>
          <p>
            LwkApply's infrastructure runs on third-party hosting providers (currently Render for
            the backend and Supabase for the database). These providers can access data only as
            needed to host the service and do not use it for their own purposes.
          </p>
        </section>

        <section class="space-y-2">
          <h2 class="font-display text-lg font-semibold text-ink">
            Your choices and data retention
          </h2>
          <p>
            Application records are kept until you edit or delete them, or delete your LwkApply
            account, from the web or mobile app. Uninstalling the browser extension removes the
            locally cached sign-in token from your browser but does not delete your LwkApply account
            or its data — manage or delete that from the app itself.
          </p>
        </section>

        <section class="space-y-2">
          <h2 class="font-display text-lg font-semibold text-ink">Security</h2>
          <p>
            All communication between LwkApply's apps (including the extension) and its backend is
            encrypted over HTTPS, and requests are authenticated with a bearer token rather than a
            shared password.
          </p>
        </section>

        <section class="space-y-2">
          <h2 class="font-display text-lg font-semibold text-ink">Children's privacy</h2>
          <p>
            LwkApply is a job application tool not directed at children, and is not intended for use
            by anyone under 16.
          </p>
        </section>

        <section class="space-y-2">
          <h2 class="font-display text-lg font-semibold text-ink">Changes to this policy</h2>
          <p>
            If this policy changes, the update will be posted on this page with a revised "last
            updated" date above.
          </p>
        </section>

        <section class="space-y-2">
          <h2 class="font-display text-lg font-semibold text-ink">Contact</h2>
          <p>
            Questions about this policy or your data can be sent to
            <a class="text-teal underline" href="mailto:lwkapply@gmail.com">lwkapply@gmail.com</a>.
          </p>
        </section>
      </article>
    </div>
  </div>
</template>

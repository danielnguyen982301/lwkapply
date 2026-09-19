# Specialized Study Notes

These are notes I keep about the most challenging problems I came across
during the process of building this application.

---

## Automatic Application Handling

**Why is this a problem?**

Imagine applying for jobs across multiple job boards / platforms (VietnamWorks, Linkedin, Indeed, ITViec, etc.). We have to manually input the data for each application. It can be easy if we apply for one job a day. But what if we want to apply for 100 jobs a day? Without automatic filling, user experience just isn't that good.

So, in order to solve this problem, I have considered some approaches towards
scraping job data and how such data is handled back on LwkApply.

### Approach 1: Bookmarklet

No credentials from the job boards need to be stored. But it requires users to click the bookmark. And we can't Save / Unsave / Apply in sync with the same functions on the job boards. This is the simplest method, yet not very reliable.

### Approach 2: Server-side polling

The idea is to have a background job that runs on interval to access the job page, scrape data, and update the application to LwkApply. This seems to provide more convenience for users, but the downside is that credentials need to be stored on LwkApply's server (be it cookies or sessions). Thus, there is a risk: automatic traffic, access to a page with required credentials may violate the page's ToS.

### Approach 3: Userscript

No credentials from the job boards need to be stored. But requests that are not in the form of `fetch/XHR` may not work properly since a userscript can only observe what the page exposes to JavaScript.

### Approach 4: Email parsing

We can use some email API to read the users' inbox and parse the email contents and update the applications on LwkApply. But there's no guarantee that emails will be sent regarding the job application. And we can't identify which application it is just from the email alone since there is no guarantee such thing like `application_id` appears in the email in order to update the related application properly.

### Approach 5: API integration

The best overall option. Official, documented APIs from the job boards ensure the correctness of the job data without relying on scraping. The issue is whether the job board exposes their APIs to public. If there is none then we need to form a partnership, collaboration with said job board in order to make it happen, which is out of scope for this particular tiny study project.

### Approach 6: A browser extension

The best option that was selected within the scope of this study project.
(Currently scoped only to VietnamWorks)

**How to scrape job data:**

The current solution is walk the DOM tree, find the `<script>` tags which contain Linked Data in JSON format (`script[type="application/ld+json"]`), then parse the text content into relevant data.

**Auto save, unsave, apply:**

The expected behavior when we click those `Save`, `Unsave`, `Apply` buttons on a job board is that the application is saved / removed on LwkApply app. Here, I came up with solutions that may be able to handle this problem:

- After observing the DOM tree (through the Console tab on Chrome Devtools), I realized the `Apply`, `Save` button have their own class name, aria-label and button texts and toasts that indicate the completion of these actions. So the brute-force solution that I could think of was:
  - Walk the DOM tree
  - Find the element that matches said criteria
  - Attach an event listener to the element
  - After the event is fired, find texts that match the pattern of the texts on the toasts to confirm completion
  - Handle API calls to LwkApply

On the surface, the solution is simple, easy to understand and "should work". But the problems? Various questions come to mind:
  - What if the class names change?
  - What if the texts on button and toasts change due to multi-lingual feature?
  - What if the action isn't complete after clicking the button but opens modals which lead to a multi-step action?
  - What if we click `Save` twice on the same job post? How do we know that it is the same application that was saved on LwkApply and not a duplicate?

So the initial approach was wrong and not very reliable. Thus, I came up with another solution:

- After interacting with the UI and observing the Network tab on Chrome Devtools, I figured some requests are sent to API server of the job board regarding the actions. So what I would do next was:
  - Use service worker to listen to these requests
  - Use the request payload (which has a `jobId` field) in order to determine which application is going to be saved / unsaved without creating a duplicate
  - Use the response to determine whether the operation is a success or not (with status code in the range of 200)
  - Handle API calls to LwkApply

The second solution provides some improvements in terms of data handling and reliability: no 3rd-party credentials are stored, requests of any type can be observed. However, it still doesn't completely remove all the drawbacks:
  - Application status on LwkApply still can't automatically be synced when the application on the job board changes. In order to do this, we need a server-side polling to access the page and listen to the request that updates the status, which leads to the credential problem mentioned in Approach 2.
  - Users have to manually install the extension and have the browser actively open in order for the current auto-sync operation to happen
  - The job board's request and response shape may change anytime without notice so the extension needs to be monitored and updated accordingly.

**Conclusion:** API integration is still the best way to cope with this problem. But within the scope of this project, a browser extension is the best option around, though not entirely the best if we talk about real auto-sync features.

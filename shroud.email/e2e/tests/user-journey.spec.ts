import * as net from "node:net"
import {
  expect,
  test,
  type APIRequestContext
} from "@playwright/test"

const smtpHost = process.env.SMTP_HOST || "localhost"
const smtpPort = Number(process.env.SMTP_PORT || 4587)
const mailpitUrl = process.env.MAILPIT_URL || "http://localhost:8025"
const imageFixtureUrl =
  process.env.IMAGE_FIXTURE_URL || "http://localhost:4800/tracker.jpg"

type Email = {
  from: string
  to: string
  subject: string
}

type MailpitMessageSummary = {
  ID: string
  Subject: string
}

type MailpitMessages = {
  messages: MailpitMessageSummary[]
}

async function waitForApp(request: APIRequestContext) {
  await expect
    .poll(async () => {
      try {
        return (await request.get("/_health")).status()
      } catch (_error) {
        return 0
      }
    }, { timeout: 60_000, message: "production image did not become healthy" })
    .toBe(200)
}

function sendEmail({ from, to, subject }: Email) {
  return new Promise<void>((resolve, reject) => {
    const socket = net.createConnection({ host: smtpHost, port: smtpPort })
    let buffer = ""
    const commands = [
      "EHLO e2e.test\r\n",
      `MAIL FROM:<${from}>\r\n`,
      `RCPT TO:<${to}>\r\n`,
      "DATA\r\n",
      `From: Sender <${from}>\r\nTo: ${to}\r\nSubject: ${subject}\r\n\r\nForward me\r\n.\r\n`,
      "QUIT\r\n"
    ]
    let commandIndex = 0

    socket.setTimeout(10_000)
    socket.on("data", chunk => {
      buffer += chunk.toString()
      const lines = buffer.split("\r\n")
      buffer = lines.pop() || ""

      for (const line of lines) {
        if (!/^\d{3}[ -]/.test(line) || /^\d{3}-/.test(line)) continue
        const code = Number(line.slice(0, 3))
        if (code >= 400) {
          socket.destroy()
          reject(new Error(`SMTP rejected message: ${line}`))
          return
        }
        if (commandIndex < commands.length) socket.write(commands[commandIndex++])
      }
    })
    socket.on("timeout", () => socket.destroy(new Error("SMTP timeout")))
    socket.on("error", reject)
    socket.on("close", hadError => {
      if (!hadError && commandIndex === commands.length) resolve()
    })
  })
}

async function mailpitMessages(
  request: APIRequestContext
): Promise<MailpitMessages> {
  const response = await request.get(`${mailpitUrl}/api/v1/messages`)
  expect(response.ok()).toBeTruthy()
  return response.json()
}

async function waitForMail(request: APIRequestContext, subject: string) {
  let match: MailpitMessageSummary | undefined

  await expect
    .poll(async () => {
      const mailbox = await mailpitMessages(request)
      match = mailbox.messages.find(message => message.Subject === subject)
      return Boolean(match)
    }, { timeout: 30_000, message: `message not found in Mailpit: ${subject}` })
    .toBeTruthy()

  if (!match) throw new Error(`message not found in Mailpit: ${subject}`)

  const response = await request.get(`${mailpitUrl}/api/v1/message/${match.ID}`)
  expect(response.ok()).toBeTruthy()
  return response.json()
}

test("signup, login, alias lifecycle, and incoming forwarding", async ({ page, request }) => {
  await waitForApp(request)

  const unique = Date.now()
  const email = `e2e-${unique}@example.test`
  const password = "correct horse battery staple"

  await page.goto("/users/register")
  await page.locator("#user-registration-form input[type=email]").fill(email)
  await page.locator("#user-registration-form input[type=password]").fill(password)
  await page.getByRole("button", { name: "Sign up" }).click()
  await expect(page).toHaveURL(/\/users\/confirm$/)

  const confirmation = await waitForMail(request, "Confirmation instructions")
  const confirmationPath = JSON.stringify(confirmation).match(/\/users\/confirm\/[A-Za-z0-9_-]+/)?.[0]
  expect(confirmationPath).toBeDefined()
  if (!confirmationPath) throw new Error("confirmation path not found in email")

  await page.goto(confirmationPath)
  await page.getByRole("button", { name: "Confirm my account" }).click()
  await expect(page).toHaveURL(/\/$/)

  await page.locator("#user-menu-button").click()
  await page.getByRole("menuitem", { name: "Log out" }).click()
  await expect(page).toHaveURL(/\/users\/log_in/)

  await page.locator("#login-form input[type=email]").fill(email)
  await page.locator("#login-form input[type=password]").fill(password)
  await page.getByRole("button", { name: "Sign in" }).click()
  await expect(page).toHaveURL(/\/$/)

  await page.getByRole("button", { name: "New alias" }).click()
  await expect(page).toHaveURL(/\/alias\//)
  const alias = decodeURIComponent(new URL(page.url()).pathname.split("/").pop() || "")
  expect(alias).toMatch(/@aliases\.test$/)

  const subject = `E2E forwarding ${unique}`
  await sendEmail({ from: "sender@example.org", to: alias, subject })

  await expect
    .poll(async () => JSON.stringify(await mailpitMessages(request)), {
      timeout: 30_000,
      message: "forwarded message did not arrive in Mailpit"
    })
    .toContain(subject)
  expect(JSON.stringify(await mailpitMessages(request))).toContain(email)

  const toggle = page.getByRole("switch", { name: "Disable" })
  await expect(toggle).toBeVisible()
  await toggle.click()
  await expect(page.getByRole("switch", { name: "Enable" })).toBeVisible()

  const before = JSON.stringify(await mailpitMessages(request))
  await sendEmail({
    from: "sender@example.org",
    to: alias,
    subject: `Disabled alias ${unique}`
  })
  await page.waitForTimeout(2_000)
  expect(JSON.stringify(await mailpitMessages(request))).toBe(before)
})

test("image proxy returns an image from the running release", async ({ request }) => {
  await waitForApp(request)

  const response = await request.get("/proxy", {
    params: { url: imageFixtureUrl }
  })

  expect(response.status()).toBe(200)
  expect(response.headers()["content-type"]).toContain("image/jpeg")
  expect((await response.body()).length).toBeGreaterThan(1_000)
})

# Accounts to log back into

After recovery, work through this list. Have **Proton Pass** open — every credential should be in there.

## Essential — do first

- [ ] **Proton Pass** (sign in first, then everything else autofills) — extension in each browser
- [ ] **Proton Mail** desktop app
- [ ] **Proton Drive** desktop app (so SSH key backup is reachable)
- [ ] **Proton VPN** desktop app
- [ ] **GitHub** — sign in, verify SSH (`ssh -T git@github.com`), enable 2FA recovery if prompted
- [ ] **GitHub CLI** — `gh auth login` (uses your SSH key + token)

## Dev / cloud

- [ ] **Supabase** — sign in via browser, re-link any local CLI: `supabase login`
- [ ] **Docker Hub** — `docker login` (needed if you push images)
- [ ] **npm** — `npm login` if you publish packages

## Work / comms

- [ ] **Discord** — desktop app sign-in (2FA from Proton Pass)
- [ ] **Telegram** desktop — sign-in via QR code from your phone
- [ ] **Steam** — sign in, enable Steam Guard if it asks

## AI tools

- [ ] **Claude (claude.ai)** in browser, **Claude desktop**, and **Claude Code CLI**: `claude login`
- [ ] **ChatGPT desktop** (Codex requires sign-in to OpenAI)
- [ ] **Gemini** in browser

## Productivity

- [ ] **Notion** (if/when you migrate from .md files)
- [ ] **Microsoft 365** — see `manual-steps.md`

## Business

- [ ] **Gumroad** (Productivity OS launch)
- [ ] **Etsy** (Productivity OS launch)
- [ ] **Stripe** (if linked to Gumroad / your own checkout)
- [ ] **Linkarus Discord server** (Icarus modding community)
- [ ] **Domain registrar** (if you have one)
- [ ] **Hosting** (Vercel / Netlify / Cloudflare / etc., if applicable)

## Once you're done

Verify nothing on this list is in your password manager *only* with SMS 2FA. After a recovery, especially if you also lost your phone, SMS-only accounts are the ones that bite. Move them to TOTP (Proton Pass supports TOTP).

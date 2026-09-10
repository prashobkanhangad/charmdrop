# CharmDrop landing page

Astro 7, TypeScript, and Tailwind CSS 4. English, Hindi, and Spanish. The site
is mostly static; checkout and the download gate run on the Node adapter.

```bash
cd web
cp .env.example .env
# add Razorpay keys
npm install
npm run dev
```

Production:

```bash
npm run build
npm run preview
```

`dist/` is a Node standalone server, not a static-only folder.

## Payment

Two one-time INR licenses, charged at the offer price:

| Plan | Offer | Original | Macs |
|---|---|---|---|
| Personal | ₹101 | ₹401 | 1 |
| Household | ₹501 | ₹1201 | 5 |

Buy → Razorpay Checkout → verified payment → license cookie → DMG.

Required env vars:

- `RAZORPAY_KEY_ID` / `PUBLIC_RAZORPAY_KEY_ID`
- `RAZORPAY_KEY_SECRET`
- `LICENSE_SIGNING_SECRET` (falls back to the Razorpay secret if unset)

If the keys are missing, checkout returns 503. The site never pretends a
payment succeeded.

Put the paid build at `private/downloads/CharmDrop.dmg`, or set
`CHARMDROP_DMG_PATH`. The download is only served from `/api/download` after a
verified purchase.

The hero canvas is a small Verlet rope — grab, flick, and click to run a ritual.

# Between Us — two-player online compatibility game

A mobile-friendly web game with room codes, private slider answers, synchronized reveals, 15 original questions, and a final alignment recap. This is an independent, unofficial game, not affiliated with the publishers of *Are We Compatible?*.

## Setup (about 10 minutes)

1. Create a free Supabase project at https://supabase.com/dashboard.
2. In **Authentication → Providers → Anonymous**, enable anonymous sign-ins. (This is not the email provider.)
3. In **SQL Editor**, paste and run the entire `schema.sql` file.
4. In **Project Settings → API** (or **Connect**), copy the Project URL and **publishable / anon** key. Never use the service-role or secret key in a browser.
5. Copy `.env.example` to `.env` and replace both placeholders.
6. Run `npm install`, then `npm run dev`. Open the local URL.
7. For a public website, push this folder to GitHub and import it into https://vercel.com/new or https://app.netlify.com/. Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` as environment variables in the host, then deploy with build command `npm run build` and output directory `dist`.
8. Share your deployed site. Player 1 selects **Create a room**; Player 2 opens the invite link or enters the six-character room code.

## How synchronization works

Clients poll a Supabase server-side `game_state` function every 1.6 seconds. This is near-live synchronization without an extra paid service. The server-side function does not disclose another player's answer until **both** have submitted. The host controls advancing rounds. Answers are locked after submission.

## Security and privacy

Anonymous Supabase accounts identify players; no name or email is required. Room membership and game actions are checked server-side. This starter does not implement rate limits, abuse protection, room expiration, account recovery, or automated data cleanup. Anonymous identity is tied to the browser session; clearing browser storage can prevent rejoining an existing room. Do not use this project to collect sensitive personal information without further security work.

## Notes

- You must deploy and configure Supabase to enable real multiplayer. Opening `index.html` directly does not work.
- Room creation may fail if anonymous sign-in is disabled.
- Questions are original, not copied from the commercial game.
- Compatibility percentage is for fun, not a validated relationship metric.

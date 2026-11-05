# Between Us — two-player online compatibility game

A mobile-friendly web game with room codes, private slider answers, synchronized reveals, 115 questions with a randomized selection of 5-15 per game, and a final alignment recap. This is an independent, unofficial game, not affiliated with the publishers of *Are We Compatible?*.

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

## Slider update for existing Supabase projects

Answers now use a smooth 0?100 slider with no numeric steps shown. After both players submit, two vertical sliders rise side by side. Alignment is 100 minus the distance between answers.

For an existing database, run `migrations/001_continuous_slider.sql` **once** in Supabase SQL Editor before deploying this version. It converts old 1?5 answers to equivalent positions on the new scale. Deploy between games and have both players reload so old clients do not submit on the previous scale. For a new database, use `schema.sql` only.

## Question decks and rerolls

For existing databases, first apply migration 001 if you have not already, then run `migrations/002_question_decks.sql` once. Do not rerun migration 001. New projects use `schema.sql` only. Reload both browsers after updating.

The host chooses 5-15 questions before creating a room. Each room gets a shared random deck from 115 questions. Either player can reroll before anyone submits; replacements exclude all questions selected for the deck or previously skipped in that room. Question history does not carry across rooms. Rerolls do not consume a round. Existing rooms keep their original questions and 15-round length.

## Final answer recap

Run `migrations/003_answer_recap.sql` after migration 002, then refresh both browsers. The final page preserves the overall percentage and exact-match count, and adds every played question with both answers side by side. Recap answers are returned only after the game ends, from the requesting player's perspective. New databases use `schema.sql` only.

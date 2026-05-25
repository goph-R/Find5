# Music prompting for Find5

Reference prompts for the in-game and menu music, plus the reasoning
behind their phrasings. Aimed at music-generation AIs in the Suno family
(musicgeneratorai.com and similar).

## General principles

These hold across genres:

- **Name instruments concretely**, not categories. "Pizzicato strings"
  beats "strings". "French horn" beats "brass section". Vague prompts
  produce generic generic-sounding output.
- **Pick a BPM.** Even when the music isn't strictly metric, giving a
  tempo range steers the model away from its defaults (which are usually
  too fast). Always state it: `~95 BPM`, `~60 BPM`, etc.
- **Mood-via-setting beats mood-via-adjective.** "Like a Sunday-afternoon
  storybook" gives the model more to work with than "happy".
- **Use exclusion clauses.** `No drums, no synths, no vocals` is one of
  the highest-leverage tricks — most generators reach for those by
  default and they're usually wrong for game music.
- **Avoid the cliché words.** `Epic`, `powerful`, `intense`, `dramatic`
  pull the model toward modern Zimmer-brand bombast. For puzzle music
  that's the opposite of what you want.
- **Don't name composers/artists** — most generators block them or
  generate poorly. Reference the **era and style** instead.
- **Mention loopability** for in-game music: `loopable, no hard ending`.
- **Generate 3–4 variants per prompt.** These tools are stochastic;
  expect one usable take per several tries.

## Find5 is a focus game

Spot-the-difference means **the music has to be present but not
intrusive**. The player needs to concentrate on visual details, so
anything with a memorable hook fights the gameplay. Keep arrangements
sparse, melodies gentle, dynamics low.

## Ingame loop

```
Light, cheerful orchestral loop. Pizzicato strings carrying a gentle
melody, soft flute and oboe accents, harp arpeggios, occasional
glockenspiel sparkles. Major key, ~95 BPM. Cozy and focused — like a
warm afternoon spent solving a puzzle. Loopable, no hard ending, no
drums, no brass, no vocals.
```

### Why these phrasings

- **"Pizzicato / plucked strings"** keeps things light — full bowed
  strings sound too dramatic for puzzle music.
- **"~95 BPM"** is the sweet spot for focus (Layton, Animal Crossing
  menus, Cooking Mama all sit around there). Higher tempos make players
  feel rushed.
- **"Loopable, no hard ending"** is critical — many generators default
  to ~30–60s clips with a fade or final cadence; this hint pushes them
  toward seamless loops.
- **"No drums, no brass, no vocals"** — explicit excludes tend to be
  very effective on these models. Vocals especially distract during
  puzzling.

## Title / menu

Slightly more memorable since the player isn't focused on a task:

```
Warm, inviting light orchestral piece. Plucked strings, soft woodwinds
(flute, clarinet), gentle harp, occasional celesta. Major key, ~100 BPM.
Storybook charm — welcoming and curious. Clear hummable melody, gentle
swing. Loopable, no drums, no electronic elements, no vocals.
```

## Iteration notes

- If it feels **too saccharine**: add `slightly melancholic undertone,
  hint of nostalgia` — gives the cozy feeling more weight.
- If it feels **too busy**: `sparse arrangement, room to breathe`.
- For a future **last-10s timer-warning cue** (consistent palette,
  urgent): `urgent pizzicato, accelerating, tighter rhythm, minor chord
  touches, ~120 BPM, 15-second segment`.

## Retro variant

If you want the audio to match the Win98-era visual nostalgia, swap
"orchestral" for `MIDI-style early-90s game soundtrack, FM-synth
orchestral patches, SoundFont character` and bump tempo to ~110 BPM.
Gives a Lemmings / Castle of Dr. Brain vibe. Probably best to ship
modern, though — fights less with the bright color art.

## When this file is wrong

If a generated prompt stops working well, the model probably updated.
These prompts target current Suno-family behavior (early 2026). When
output starts feeling generic or won't respect exclusions, the first
thing to try is making the prompt **shorter** — newer models tend to
weight earlier tokens more, so the lead descriptor matters most.

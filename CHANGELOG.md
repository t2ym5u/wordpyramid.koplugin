# Changelog

## [1.1.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.1.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.1.0] - 2026-11-03

### Changed
- Riddles, names, themes, words and pyramids are remembered across games
  until every item of their kind has been played (the whole content, instead
  of the last 600 items), and as soon as they are dealt rather than at the
  end of a game. What was already remembered is carried over.

## [1.0.2] - 2026-11-02

### Changed
- Family-friendly content: replaced « crotte », « Le Dîner de cons »,
  « Enfoirés » (French) and "Damn with faint praise" (English).

## [1.0.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.0.0] - 2026-10-30

### Added
- First release: a word-guessing party game for four players (two teams of
  two), inspired by the classic French TV word game format; every one-word
  clue costs a brick.
- Riddles (6 offered, 2 per team, 5 words with 13 bricks, +1 for the answer,
  unused bricks as a bonus), ping-pong (5 words back and forth, 13 bricks,
  5 per word), against the clock (4 themes, 30 s, up to 7 words), proper names
  (6 themes of 4 names, brick bids to take a name over, sudden death on a tie).
- The Great Pyramid final: 6 expressions in 1 minute, all or nothing, drawn
  as a 3-2-1 pyramid; Final again.
- Settings: content language, round 2 (ping-pong, against the clock, or both),
  bricks per name (3/4/5), prizes (fake euros or points), player names.
- Hand-over screen before every turn; save/restore never on a visible word.
- French and English content written natively: 214/180 riddles, 116/120
  proper-name themes, 126/110 against-the-clock themes, 172/200 pyramid sets,
  891/858 ping-pong words.

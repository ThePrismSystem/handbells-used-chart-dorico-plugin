# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-26

The first version, for the first check on a Mac. It is not released yet: 1.0.0 follows that check.

### Added

- A Dorico 6 script plug-in, **Script > Handbells Used Chart**, ported from the Sibelius plugin (v1.3.1). It draws
  "handbells used" charts into a new flow at the start of the full score, which carries the title, and the music
  follows from page 2.
- Handbells, handchimes, SMBs, P&F handbells and Whitechapel handbells, each told apart by a notehead you choose
  from the ones the music uses, and each charted in its own section with its label and bell count.
- Charts in pitch order with both spellings of a shared bell stacked in one column, no natural signs, bells above
  C7 and below C3 stacked with their octave, and bells outside C2-C9 skipped with a warning. Grace notes are
  charted; cue notes aren't.
- Seven chart shapes or `(match notehead)`, stemless, and colour fields filled in from the music.
- One combined chart, or a separate chart for each instrument.
- An instrument table: tick the players to chart, and say whether each one's part is written for Dorico's Handbells
  instrument or at pitch (on a Piano or Organ staff, say), whose bells are then charted an octave higher. Both are
  remembered by player name across projects.
- Re-running replaces the chart; "Remove Existing Chart" takes it out. A chart the plug-in cannot positively
  identify is left alone, with the reason.
- The project is saved before anything is drawn, so File > Revert takes a run back.
- A results window listing the sections drawn and anything skipped, and a run log in the plug-in's data folder. A
  long list scrolls. When a run fails, the message says whether anything changed and, if it did, to use
  File > Revert.
- In a project with several flows, each music flow keeps its heading; only the chart's is hidden.
- Projects whose blocks Dorico has numbered out of step, such as some shared or downloaded files, are read and
  charted. Before, every note was reported unreadable.
- The dialog on Windows (PowerShell) and on a Mac (JavaScript for Automation, for Apple silicon and Intel). On the
  Mac, the colour fields take Cmd-C, Cmd-V and Cmd-A, and the results alert closes on Escape too.
- Any Dorico 6 build is accepted; other versions are refused, with nothing changed.
- `tools/install.py` installs into Dorico 6's Script Plug-ins folder on Windows and macOS, and `tools/package.py`
  builds the release zip.

[0.1.0]: https://github.com/ThePrismSystem/handbells-used-chart-dorico-plugin/releases/tag/v0.1.0

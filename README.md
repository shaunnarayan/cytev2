# Cyte

A background screen recorder for easy history search. There is an [optional companion app](https://github.com/shaunnarayan/cytev2-explore), which enables GPT features when running in background.

## Uses

### Train-of-thought recovery

Autosave isn’t always an option, in those cases you can easily recover your train of thought, a screenshot to use as a stencil, or extracted copy from memories recorded.

### Search across applications

A lot of research involves collating information from multiple sources; internal tools like confluence, websites like wikipedia, pdf and doc files etc; When searching for something we don’t always remember the source (or it's at the tip of your tongue)

## Features

> - Completely private, data is stored on disk only, no outside connections are made
> - Pause/Restart recording easily
> - Set applications that are not to be recorded (while taking keystrokes)
> - Chat your data; ask questions about work you've done

## Issues

- Searching does not show all intervals for results
- Bookmarking, episode closing and some other model state changes not causing the feed to update
- file change tracking hangs the UI (Need to move some memory functions off the main thread)
- Re-enable app sandbox which is disabled to allow file tracking; instead should request document permissions: https://stackoverflow.com/questions/70961951/how-to-get-permission-to-access-all-files-on-macos
- Windows matching Excluded bundles should be passed to exclusion list in ScreenCaptureKit
- OCR highlighting os slightly offset over videos
- Timeline slider not updating while video playing (timeJumped notification not sent until pause)

## Feature requests

- Automatically select first result for episode previews during search
- Easily copy code blocks in chat
- Keyword autoblacklist
- Filter incognito and chrome tabs from capture
- Investivate SQLite vs CoreData efficiency at scale
- Fallback to object recognition
- Generate and Save medium granularity features as MP4 metadata
    * Extract the main text from OCR results, embed/index it, and store the raw text as ranged meta
- Encryption e.g. Filevault?
- NL Embedding search 
- Search improvement: term expansion, stemming, verbs... 
- Audio support
